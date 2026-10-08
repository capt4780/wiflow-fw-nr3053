#!/usr/bin/env python3
"""Compare a *built* NR3053 FIT image against the pinned stable reference.

Stdlib-only, read-only and fail-closed for structural mismatches.
PASS/WARN here never authorizes a flash or claims a working Wiflow portal.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import sys
import zlib

MAGIC = 0xD00DFEED


def u32(value):
    if len(value) != 4:
        raise ValueError("invalid FIT 32-bit property")
    return struct.unpack(">I", value)[0]


def string(value):
    return value.rstrip(b"\0").decode("utf-8", "strict")


def fdt_nodes(blob):
    if len(blob) < 40:
        raise ValueError("FDT header missing")
    hdr = struct.unpack_from(">10I", blob)
    if hdr[0] != MAGIC or hdr[1] < 40 or hdr[1] > len(blob):
        raise ValueError("FDT magic or total size invalid")
    so, st, sl, ss = hdr[2], hdr[3], hdr[9], hdr[8]
    if so + sl > hdr[1] or st + ss > hdr[1]:
        raise ValueError("FDT offsets exceed header bounds")
    strings = blob[st:st + ss]
    cursor = so
    end = so + sl
    names = []
    nodes = {}
    while cursor + 4 <= end:
        tag = struct.unpack_from(">I", blob, cursor)[0]
        cursor += 4
        if tag == 1:
            stop = blob.find(b"\0", cursor, end)
            if stop < 0:
                raise ValueError("unterminated FDT node")
            names.append(blob[cursor:stop].decode("utf-8", "strict"))
            cursor = (stop + 4) & ~3
            key = "/" + "/".join(p for p in names if p)
            if key in nodes:
                raise ValueError("duplicate FDT node")
            nodes[key] = {}
        elif tag == 2:
            if not names:
                raise ValueError("invalid FDT end-node")
            names.pop()
        elif tag == 3:
            if cursor + 8 > end or not names:
                raise ValueError("invalid FDT property header")
            length, noff = struct.unpack_from(">II", blob, cursor)
            cursor += 8
            if cursor + length > end or noff >= len(strings):
                raise ValueError("invalid FDT property length or name")
            stop = strings.find(b"\0", noff)
            if stop < 0:
                raise ValueError("unterminated FDT property name")
            pname = strings[noff:stop].decode("utf-8", "strict")
            key = "/" + "/".join(p for p in names if p)
            if pname in nodes[key]:
                raise ValueError("duplicate FDT property")
            nodes[key][pname] = blob[cursor:cursor + length]
            cursor = (cursor + length + 3) & ~3
        elif tag == 4:
            continue
        elif tag == 9:
            if names:
                raise ValueError("unclosed FDT nodes")
            return nodes
        else:
            raise ValueError("unknown FDT token")
    raise ValueError("FDT missing terminal token")


def read_image(path):
    if not path.is_file() or path.is_symlink() or not 4096 <= path.stat().st_size <= 268435456:
        raise ValueError("missing, linked, or implausible FIT image")
    return path.read_bytes()


def evaluate(image, reference):
    warnings = []
    errors = []
    main = fdt_nodes(image)
    config = main.get("/configurations/config-1", {})
    images = {}
    for part in ("kernel-1", "fdt-1", "rootfs-1"):
        node = main.get("/images/" + part)
        if not node:
            raise ValueError("missing FIT component " + part)
        pos = u32(node["data-position"])
        size = u32(node["data-size"])
        if pos < 4096 or size < 64 or pos + size > len(image):
            raise ValueError("invalid FIT component bounds: " + part)
        data = image[pos:pos + size]
        hashes = (
            main["/images/" + part + "/hash-1"],
            main["/images/" + part + "/hash-2"],
        )
        if (string(hashes[0]["algo"]) != "crc32"
                or hashes[0]["value"] != struct.pack(">I", zlib.crc32(data))
                or string(hashes[1]["algo"]) != "sha1"
                or hashes[1]["value"] != hashlib.sha1(data).digest()):
            errors.append("FIT hash failure: " + part)
        images[part] = data

    if string(main["/configurations"]["default"]) != "config-1":
        errors.append("different default FIT configuration")
    if [string(config[k]) for k in ("kernel", "fdt", "loadables")] != [
        "kernel-1", "fdt-1", "rootfs-1"
    ]:
        errors.append("different FIT kernel/FDT/rootfs mapping")
    kernel_desc = string(main["/images/kernel-1"]["description"])
    if not kernel_desc.startswith("ARM64 OpenWrt Linux-6."):
        errors.append("unexpected kernel architecture/family")
    elif kernel_desc != reference["fit"]["components"]["kernel"]["description"]:
        warnings.append("kernel version differs: " + kernel_desc)
    if string(main["/images/kernel-1"]["compression"]) != "gzip":
        errors.append("unexpected FIT kernel compression")
    dt = fdt_nodes(images["fdt-1"])
    root = dt.get("/", {})
    if string(root.get("model", b"")) != reference["dtb"]["model"]:
        errors.append("different hardware DTB model")
    compatible = string(root.get("compatible", b"")).split("\0")
    required = reference["dtb"]["compatible"]
    if any(c not in compatible for c in required):
        errors.append("missing NR3053/MT7981 DTB compatible")

    expected_parts = {p["name"]: (int(p["offset"], 16), int(p["size"], 16))
                      for p in reference["dtb"]["spi_nand_partition_layout"]}
    parts = {}
    for key, node in dt.items():
        if "/partitions/partition@" in key and "/nvmem-layout/" not in key:
            if "label" in node and "reg" in node:
                r = node["reg"]
                if len(r) == 8:
                    reg = struct.unpack(">2I", r)
                    parts[string(node["label"])] = reg
    if parts != expected_parts:
        errors.append("partition layout differs from stable NR3053 DTB")
    wifi = [node for key, node in dt.items() if "/wifi@" in key]
    if not any(string(n.get("status", b"")) == "okay"
               and string(n.get("nvmem-cell-names", b"")).split("\0") == ["eeprom"]
               for n in wifi):
        errors.append("working WiFi / Factory EEPROM DTB mapping missing")

    rootfs = images["rootfs-1"]
    if rootfs[:4] != b"hsqs":
        errors.append("rootfs does not contain SquashFS")
    else:
        compression_id = struct.unpack_from("<H", rootfs, 20)[0]
        expected_id = reference["fit"]["components"]["rootfs"]["squashfs_compression_id"]
        if compression_id != expected_id:
            warnings.append("SquashFS compression differs from stable firmware")

    trailer = image[-4096:]
    found = re.search(rb'\{\s*"metadata_version"\s*:', trailer)
    if not found:
        errors.append("missing OpenWrt device metadata")
        metadata = {}
    else:
        try:
            metadata = json.JSONDecoder().raw_decode(
                trailer[found.start():].decode("utf-8", "replace")
            )[0]
        except (ValueError, UnicodeDecodeError):
            errors.append("invalid OpenWrt image metadata")
            metadata = {}
    if metadata:
        if metadata.get("supported_devices") != reference["metadata"]["supported_devices"]:
            errors.append("NR3053 supported_devices tag mismatch")
        for key in ("target", "board", "dist"):
            if metadata.get("version", {}).get(key) != reference["metadata"]["version"][key]:
                errors.append("OpenWrt image version mismatch: " + key)
        if metadata.get("compat_version") != reference["metadata"]["compat_version"]:
            errors.append("OpenWrt compatibility version mismatch")
    sha = hashlib.sha256(image).hexdigest()
    if sha != reference["sha256"]:
        warnings.append("candidate SHA-256 differs (expected for new builds)")
    return {
        "structural_gate": "BLOCK" if errors else ("WARN" if warnings else "PASS"),
        "flash_authorization": "BLOCK",
        "wiflow_features_verified": False,
        "candidate_sha256": sha,
        "reference_sha256": reference["sha256"],
        "errors": errors,
        "warnings": warnings,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--reference", type=Path,
                        default=Path(__file__).resolve().parents[1] /
                                "reference/nr3053-golden.json")
    args = parser.parse_args()
    try:
        ref = json.loads(args.reference.read_text(encoding="utf-8"))
        result = evaluate(read_image(args.candidate), ref)
    except (OSError, ValueError, KeyError, IndexError, TypeError, struct.error) as exc:
        result = {"structural_gate": "BLOCK", "flash_authorization": "BLOCK",
                  "errors": [str(exc)]}
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 2 if result["structural_gate"] == "BLOCK" else 0


if __name__ == "__main__":
    sys.exit(main())
