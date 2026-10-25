#!/usr/bin/env python3
"""Strip the unpacked stock v2.3.6 rootfs down to the lean Wiflow ROM.

Starts from the packages in tools/lean-keep.txt, adds everything they depend
on (apk database D: lines resolved through P:/p: provides) and removes every
other package of the stock image: its files, directories it alone owned,
symlinks pointing at removed files, boot links of removed services, and its
records in the apk database (installed, triggers, scripts, world), so apk on
the router sees exactly what is on flash.

usage: lean-rootfs.py <rootfs> <keep-list> <report-dir>
"""
import io
import os
import re
import sys
import tarfile

root, keep_file, out = sys.argv[1:4]
DB = os.path.join(root, "lib/apk/db")


def die(msg):
    sys.exit("lean-rootfs: " + msg)


def parse_db(text):
    recs = []
    for rec in text.strip("\n").split("\n\n"):
        name = ver = csum = None
        deps, files, dirs, prov = [], [], [], []
        folder = ""
        for line in rec.splitlines():
            k, _, v = line.partition(":")
            if k == "P":
                name = v
            elif k == "V":
                ver = v
            elif k == "C":
                csum = v
            elif k == "D":
                deps += v.split()
            elif k == "p":
                prov += v.split()
            elif k == "F":
                folder = v
                dirs.append(v)
            elif k == "R":
                files.append(f"{folder}/{v}" if folder else v)
        if name:
            recs.append(dict(name=name, ver=ver, csum=csum, deps=deps, files=files,
                             dirs=dirs, prov=prov, text=rec))
    return recs


recs = parse_db(open(os.path.join(DB, "installed"), encoding="utf-8").read())
pkgs = {r["name"]: r for r in recs}
provides = {}
for r in recs:
    provides.setdefault(r["name"], r["name"])
    for p in r["prov"]:
        provides.setdefault(re.split(r"[=<>~]", p, maxsplit=1)[0], r["name"])

roots = []
for line in open(keep_file, encoding="utf-8"):
    line = line.split("#", 1)[0].strip()
    if line:
        roots.append(line)
missing = [r for r in roots if r not in pkgs]
if missing:
    die("keep-list names packages not in the stock image: " + " ".join(missing))

keep, stack, unresolved = set(), list(roots), set()
while stack:
    n = stack.pop()
    if n in keep:
        continue
    keep.add(n)
    for d in pkgs[n]["deps"]:
        if d.startswith("!"):
            continue
        r = provides.get(re.split(r"[=<>~]", d, maxsplit=1)[0])
        if r is None:
            unresolved.add(d)
        else:
            stack.append(r)
if unresolved:
    die("unresolved dependencies: " + " ".join(sorted(unresolved)))

remove = sorted(set(pkgs) - keep)
kept_files = {f for n in keep for f in pkgs[n]["files"]}
kept_dirs = {d for n in keep for d in pkgs[n]["dirs"]}
rm_files = sorted({f for n in remove for f in pkgs[n]["files"]} - kept_files)
rm_dirs = sorted({d for n in remove for d in pkgs[n]["dirs"]} - kept_dirs,
                 key=lambda p: -p.count("/"))

# --- files ---
gone = set()
for f in rm_files:
    p = os.path.join(root, f)
    if os.path.lexists(p):
        os.unlink(p)
        gone.add("/" + f)

# --- symlinks whose target was removed (alternatives, rc.d boot links) ---
dangling = []
for dp, dn, fn in os.walk(root):
    for f in fn + dn:
        p = os.path.join(dp, f)
        if not os.path.islink(p):
            continue
        t = os.readlink(p)
        rel = "/" + os.path.relpath(dp, root)
        target = os.path.normpath(t if t.startswith("/") else os.path.join(rel, t))
        if target in gone:
            os.unlink(p)
            dangling.append("/" + os.path.relpath(p, root))
            gone.add("/" + os.path.relpath(p, root))

# --- directories only the removed packages owned, when now empty ---
for d in rm_dirs:
    p = os.path.join(root, d)
    if os.path.isdir(p) and not os.path.islink(p) and not os.listdir(p):
        os.rmdir(p)

# --- apk database ---
keep_recs = [r for r in recs if r["name"] in keep]
open(os.path.join(DB, "installed"), "w", encoding="utf-8").write(
    "\n\n".join(r["text"] for r in keep_recs) + "\n\n")

rm_csums = {pkgs[n]["csum"] for n in remove if pkgs[n]["csum"]}
tp = os.path.join(DB, "triggers")
if os.path.exists(tp):
    lines = open(tp, encoding="utf-8").read().splitlines()
    lines = [l for l in lines if l.split(" ", 1)[0] not in rm_csums]
    open(tp, "w", encoding="utf-8").write("".join(l + "\n" for l in lines))

sp = os.path.join(DB, "scripts.tar.gz")
if os.path.exists(sp):
    prefixes = tuple(f"{n}-{pkgs[n]['ver']}." for n in remove)
    src = tarfile.open(sp, "r:gz")
    buf = io.BytesIO()
    dst = tarfile.open(fileobj=buf, mode="w:gz")
    for m in src.getmembers():
        if not m.name.startswith(prefixes):
            dst.addfile(m, src.extractfile(m) if m.isfile() else None)
    dst.close()
    open(sp, "wb").write(buf.getvalue())

wp = os.path.join(root, "etc/apk/world")
if os.path.exists(wp):
    world = open(wp, encoding="utf-8").read().split()
    world = [w for w in world if re.split(r"[=<>~]", w, maxsplit=1)[0] in keep]
    open(wp, "w", encoding="utf-8").write("\n".join(world) + "\n")

# --- report ---
os.makedirs(out, exist_ok=True)
open(os.path.join(out, "packages-kept.txt"), "w").write(
    "".join(f"{r['name']} {r['ver']}\n" for r in sorted(keep_recs, key=lambda r: r["name"])))
open(os.path.join(out, "packages-removed.txt"), "w").write(
    "".join(f"{n} {pkgs[n]['ver']}\n" for n in remove))
open(os.path.join(out, "files-removed.txt"), "w").write(
    "".join(f + "\n" for f in sorted(gone)))
print(f"kept {len(keep)} packages, removed {len(remove)} packages, "
      f"{len(gone)} files/links ({len(dangling)} dangling links)")
