#!/usr/bin/env python3
"""Swap the rootfs inside an OpenWrt FIT sysupgrade image, nothing else.

The FIT header (device tree with external data) is edited in place: only the
rootfs-1 data-size and its crc32/sha1 hash values change, all of them fixed
length, so the header keeps its size and every other byte (kernel, device
tree, their hashes, the configuration) stays identical to the stock image.
The rootfs must be the last image in the file. The input must have had its
fwtool metadata trailer removed first (fwtool -t -i).

usage: fit-rootfs.py <stock.itb without trailer> <rootfs.squashfs> <out.itb>
"""
import hashlib
import struct
import sys
import zlib

src, rootfs_path, dst = sys.argv[1:4]
d = bytearray(open(src, "rb").read())
rootfs = open(rootfs_path, "rb").read()

magic, total, off_st, off_str = struct.unpack(">4I", d[:16])
assert magic == 0xD00DFEED, "not a FIT image"


def string(o):
    e = d.index(b"\0", off_str + o)
    return d[off_str + o:e].decode()


# walk the structure block and remember where each property value lives
props = {}  # path -> {name: (offset, length)}
p, path = off_st, []
while True:
    tok = struct.unpack(">I", d[p:p + 4])[0]
    p += 4
    if tok == 1:
        e = d.index(b"\0", p)
        path.append(d[p:e].decode())
        p = (e + 4) & ~3
        props["/".join(path)] = {}
    elif tok == 2:
        path.pop()
    elif tok == 3:
        ln, no = struct.unpack(">II", d[p:p + 8])
        p += 8
        props["/".join(path)][string(no)] = (p, ln)
        p = (p + ln + 3) & ~3
    elif tok == 4:
        continue
    elif tok == 9:
        break
    else:
        raise SystemExit(f"bad FDT token {tok}")


def u32(node, name):
    o, ln = props[node][name]
    assert ln == 4
    return struct.unpack(">I", d[o:o + 4])[0]


def put(node, name, value):
    o, ln = props[node][name]
    assert len(value) == ln, f"{node}/{name}: length {len(value)} != {ln}"
    d[o:o + ln] = value


IMG = "/images"
images = [k for k in props if k.startswith(IMG + "/") and k.count("/") == 2]
rf = "/images/rootfs-1"
assert rf in images, "no rootfs-1 image"
end = {k: u32(k, "data-position") + u32(k, "data-size") for k in images}
rpos = u32(rf, "data-position")
assert all(rpos >= end[k] for k in images if k != rf), "rootfs-1 is not the last image"
assert len(d) >= end[rf], "input truncated"
assert len(d) - end[rf] < 4096, "unexpected data after rootfs (remove the fwtool trailer first)"

for h in ("hash-1", "hash-2"):
    algo = bytes(d[props[f"{rf}/{h}"]["algo"][0]:][:props[f"{rf}/{h}"]["algo"][1]]).rstrip(b"\0").decode()
    if algo == "crc32":
        put(f"{rf}/{h}", "value", struct.pack(">I", zlib.crc32(rootfs) & 0xFFFFFFFF))
    elif algo == "sha1":
        put(f"{rf}/{h}", "value", hashlib.sha1(rootfs).digest())
    else:
        raise SystemExit(f"unsupported hash {algo}")
put(rf, "data-size", struct.pack(">I", len(rootfs)))

out = bytes(d[:rpos]) + rootfs
open(dst, "wb").write(out)

# self-check: everything before the rootfs, apart from the edited header
# values, is byte-identical to the input
orig = open(src, "rb").read()
assert out[total:rpos] == orig[total:rpos], "kernel/device tree bytes changed"
print(f"rootfs-1: {end[rf] - rpos} -> {len(rootfs)} bytes, image {len(orig)} -> {len(out)} bytes")
