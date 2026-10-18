# Minimal FIT (flattened device tree) reader: lists images and extracts their data.
import struct, sys, os
d = open(sys.argv[1], 'rb').read(); out = sys.argv[2]; os.makedirs(out, exist_ok=True)
magic, total, off_st, off_str, off_rsv, ver = struct.unpack('>6I', d[:24])
assert magic == 0xd00dfeed, hex(magic)
def s(o): e = d.index(b'\0', off_str + o); return d[off_str + o:e].decode()
p = off_st; path = []; nodes = {}
while True:
    tok = struct.unpack('>I', d[p:p+4])[0]; p += 4
    if tok == 1:
        e = d.index(b'\0', p); name = d[p:e].decode(); p = (e + 4) & ~3; path.append(name); nodes['/'.join(path)] = {}
    elif tok == 2: path.pop()
    elif tok == 3:
        ln, no = struct.unpack('>II', d[p:p+8]); p += 8; val = d[p:p+ln]; p = (p + ln + 3) & ~3
        nodes['/'.join(path)][s(no)] = val
    elif tok == 4: continue
    elif tok == 9: break
for k, v in nodes.items():
    props = {n: (x if n in ('data',) else x) for n, x in v.items()}
    info = {n: (x.rstrip(b'\0').decode(errors='replace') if n in ('description', 'type', 'arch', 'os', 'compression', 'compatible', 'kernel', 'fdt', 'loadables', 'default') else len(x)) for n, x in v.items() if n != 'data'}
    pos = None
    if 'data-position' in v: pos = struct.unpack('>I', v['data-position'])[0]
    elif 'data-offset' in v: pos = ((total + 3) & ~3) + struct.unpack('>I', v['data-offset'])[0]
    size = struct.unpack('>I', v['data-size'])[0] if 'data-size' in v else (len(v['data']) if 'data' in v else None)
    if size: info['size'] = size
    print(k or '/', info)
    blob = v['data'] if 'data' in v else (d[pos:pos+size] if pos is not None else None)
    if blob and size and size > 64: open(os.path.join(out, k.replace('/', '_') + '.bin'), 'wb').write(blob)
