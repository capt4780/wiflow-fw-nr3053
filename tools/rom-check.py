#!/usr/bin/env python3
"""Checks the lean rootfs before it is packed. Fails the build on any FAIL.

  - WiFi firmware, profiles, driver scripts, board/upgrade files and WiFi
    kernel modules byte-identical to v2.3.6 (tools/nr3053-golden.json)
  - every ELF program/library finds the shared libraries it needs
  - every kernel module finds the modules it depends on (no new gaps vs stock)
  - boot links, init scripts and symlinks resolve
  - Wiflow defaults, theme and base files present; removed features absent

usage: rom-check.py <lean rootfs> <stock rootfs.squashfs> <unsquashfs>
"""
import glob
import hashlib
import json
import os
import re
import struct
import subprocess
import sys
import tempfile

F, stock_sqfs, unsquashfs = sys.argv[1:4]
HERE = os.path.dirname(os.path.abspath(__file__))
golden = json.load(open(os.path.join(HERE, "nr3053-golden.json")))
bad = 0


def ok(msg):
    print("PASS", msg)


def fail(msg):
    global bad
    bad = 1
    print("FAIL", msg)


def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()


# --- WiFi stack identical to v2.3.6 ---
diff = [p for p, h in golden["must_match"].items()
        if not os.path.isfile(F + p) or sha(F + p) != h]
diff += [p for p, h in golden["info"].items()
         if not os.path.isfile(F + p) or sha(F + p) != h]
n = len(golden["must_match"]) + len(golden["info"])
if diff:
    fail("differs from v2.3.6: " + ", ".join(diff))
else:
    ok(f"WiFi driver, firmware, profiles, board and upgrade files: {n} files identical to v2.3.6")


# --- shared libraries ---
def elf_needed(path):
    try:
        with open(path, "rb") as fh:
            b = fh.read()
    except OSError:
        return None
    if b[:4] != b"\x7fELF" or b[4] != 2:
        return None
    shoff, = struct.unpack_from("<Q", b, 0x28)
    shentsize, shnum = struct.unpack_from("<HH", b, 0x3A)
    secs = [struct.unpack_from("<IIQQQQIIQQ", b, shoff + i * shentsize) for i in range(shnum)]
    dyn = [s for s in secs if s[1] == 6]  # SHT_DYNAMIC
    if not dyn:
        return []
    s = dyn[0]
    strtab = secs[s[6]]
    out = []
    for o in range(s[4], s[4] + s[5], 16):
        tag, val = struct.unpack_from("<qQ", b, o)
        if tag == 0:
            break
        if tag == 1:  # DT_NEEDED
            e = b.index(b"\0", strtab[4] + val)
            out.append(b[strtab[4] + val:e].decode())
    return out


libdirs = ["lib", "usr/lib"]
libs = set()
for d in libdirs:
    for p in glob.glob(os.path.join(F, d, "*")):
        libs.add(os.path.basename(p))
missing = []
checked = 0
for dp, dn, fn in os.walk(F):
    if "/lib/modules" in dp:
        continue
    for f in fn:
        p = os.path.join(dp, f)
        if os.path.islink(p) or not os.path.isfile(p):
            continue
        need = elf_needed(p)
        if need is None:
            continue
        checked += 1
        for lib in need:
            if lib not in libs:
                missing.append(f"/{os.path.relpath(p, F)} -> {lib}")
if missing:
    fail("missing shared libraries: " + "; ".join(missing[:20]))
else:
    ok(f"shared libraries: {checked} ELF files, all needed libraries present")


# --- kernel modules ---
def module_gaps(root):
    d = glob.glob(os.path.join(root, "lib/modules/*"))[0]
    names = {f[:-3].replace("-", "_") for f in os.listdir(d) if f.endswith(".ko")}
    builtin = {os.path.basename(l.strip())[:-3].replace("-", "_")
               for l in open(os.path.join(d, "modules.builtin"))}
    gaps = set()
    for f in os.listdir(d):
        if not f.endswith(".ko"):
            continue
        b = open(os.path.join(d, f), "rb").read()
        m = re.search(rb"depends=([^\0]*)\0", b)
        for x in (m.group(1).decode().split(",") if m else []):
            x = x.replace("-", "_")
            if x and x not in names and x not in builtin:
                gaps.add(f"{f} -> {x}")
    for f in os.listdir(os.path.join(root, "etc/modules.d")):
        for line in open(os.path.join(root, "etc/modules.d", f)):
            w = line.split()
            if not w or not re.match(r"^[A-Za-z_][\w-]*$", w[0]):
                continue
            x = w[0].replace("-", "_")
            if x not in names and x not in builtin:
                gaps.add(f"modules.d/{f} -> {x}")
    return gaps, len(names)


with tempfile.TemporaryDirectory() as t:
    subprocess.run([unsquashfs, "-q", "-no-progress", "-d", t + "/s", stock_sqfs,
                    "lib/modules", "etc/modules.d"], check=True, stdout=subprocess.DEVNULL)
    stock_gaps, _ = module_gaps(t + "/s")
gaps, nmods = module_gaps(F)
new = sorted(gaps - stock_gaps)
if new:
    fail("kernel module dependencies missing: " + "; ".join(new))
else:
    ok(f"kernel modules: {nmods} modules, no dependency missing (same as v2.3.6)")


# --- links and services ---
runtime = ("/tmp", "/var", "/proc", "/sys", "/dev", "/run")
dangling = []
for dp, dn, fn in os.walk(F):
    for f in fn + dn:
        p = os.path.join(dp, f)
        if not os.path.islink(p):
            continue
        t = os.readlink(p)
        rel = "/" + os.path.relpath(dp, F)
        target = os.path.normpath(t if t.startswith("/") else os.path.join(rel, t))
        if target.startswith(runtime):
            continue
        if not os.path.lexists(F + target):
            dangling.append(f"/{os.path.relpath(p, F)} -> {t}")
if dangling:
    fail("broken links: " + "; ".join(dangling))
else:
    ok("all symlinks and boot links resolve")

for s in sorted(os.listdir(F + "/etc/init.d")):
    first = open(F + "/etc/init.d/" + s, "rb").readline().decode(errors="replace").strip()
    interp = first[2:].split()[0] if first.startswith("#!") else ""
    if not interp or not os.path.exists(F + interp):
        fail(f"init script {s}: interpreter {interp!r} missing")
ok("services: " + " ".join(sorted(os.listdir(F + "/etc/init.d"))))

# --- Wiflow defaults and theme ---
need = ["/etc/uci-defaults/98-wiflow-base", "/etc/init.d/wiflow-hnat-off", "/etc/rc.d/S21wiflow-hnat-off",
        "/usr/share/ucode/luci/template/themes/wiflow/header.ut",
        "/usr/share/ucode/luci/template/themes/wiflow/footer.ut",
        "/usr/share/ucode/luci/template/themes/wiflow/sysauth.ut",
        "/www/luci-static/wiflow/wiflow.css", "/www/luci-static/wiflow/cascade.css",
        "/www/luci-static/wiflow/wiflow-logo.png", "/www/luci-static/wiflow/favicon.png", "/www/favicon.ico", "/etc/wiflow_release", "/www/luci-static/wiflow/fonts/inter-400.woff2",
        "/www/luci-static/resources/menu-wiflow.js", "/www/luci-static/resources/view/wiflow/sysauth.js",
        "/usr/sbin/uhttpd", "/usr/sbin/dnsmasq", "/sbin/fw4", "/usr/sbin/dropbear",
        "/usr/sbin/hostapd", "/usr/sbin/iwpriv", "/usr/bin/curl", "/bin/uclient-fetch", "/usr/bin/jsonfilter",
        "/sbin/ip", "/usr/bin/awk", "/usr/bin/sort", "/usr/bin/apk", "/sbin/sysupgrade",
        "/www/luci-static/resources/view/package-manager.js",
        "/usr/share/luci-app-mtwifi-cfg/wireless-mtk.js"]
lost = [p for p in need if not os.path.lexists(F + p)]
if lost:
    fail("missing: " + ", ".join(lost))
else:
    ok(f"Wiflow base, theme, LuCI, WiFi and Internet tools: {len(need)} files present")

cg = open(F + "/bin/config_generate").read()
sh = open(F + "/etc/shadow").read()
checks = {
    "LAN default 10.0.0.1": 'ipad=${ipaddr:-"10.0.0.1"}' in cg,
    "root password set": re.search(r"^root:\$1\$[^:]+:", sh, re.M) is not None,
    "Wiflow release name": "Wiflow" in open(F + "/etc/openwrt_release").read(),
    # stock WiFi first-boot fixes only run when DISTRIB_RELEASE >= 25.12
    "DISTRIB_RELEASE kept as v2.3.6 (25.12-SNAPSHOT)":
        "DISTRIB_RELEASE='25.12-SNAPSHOT'" in open(F + "/etc/openwrt_release").read(),
    "hostname default Wiflow": "hostname='Wiflow'" in cg,
    "web login wiflow added, root kept": "option username 'wiflow'" in open(F + "/etc/config/rpcd").read()
        and "option username 'root'" in open(F + "/etc/config/rpcd").read(),
    "access gate: module, codes, dispatcher check":
        os.path.isfile(F + "/usr/share/ucode/wiflow/gate.uc")
        and "WIFDIDNR3053" in open(F + "/etc/config/wiflow_gate").read()
        and "wiflow_gate_passed(http)" in open(F + "/usr/share/ucode/luci/dispatcher.uc").read(),
    "LuCI package upload accepts the unsigned Wiflow Setup apk":
        '--allow-untrusted --no-network --repositories-file /dev/null' in open(F + "/usr/libexec/package-manager-call").read(),
    "LuCI pages are not offered for machine translation":
        'translate="no"' in open(F + "/usr/share/ucode/luci/template/themes/wiflow/header.ut").read(),
    "phone/tablet layout by viewport width (tables become cards up to 900 px)":
        "max-device-width" not in open(F + "/www/luci-static/wiflow/mobile.css").read()
        and "(max-width: 854px)" in open(F + "/usr/share/ucode/luci/template/themes/wiflow/header.ut").read(),
    "5 GHz scans and uses channels 100-140 (country VN, A-band region 7)":
        json.load(open(F + "/usr/share/schema/mtwifi/dat-defs.json"))["COUNTRY_REGIONS"]["VN"] == [1, 7]
        and "country='VN'" in open(F + "/etc/uci-defaults/98-wiflow-base").read(),
    "anonymous ubus cannot call session.login":
        "login" not in json.load(open(F + "/usr/share/rpcd/acl.d/unauthenticated.json"))["unauthenticated"]["read"]["ubus"]["session"],
}
for k, v in checks.items():
    (ok if v else fail)(k)

deny = ["/usr/sbin/tailscaled", "/etc/init.d/adblock", "/etc/init.d/ddns", "/etc/init.d/miniupnpd",
        "/etc/init.d/turboacc", "/etc/init.d/eqos", "/etc/init.d/mtkhqos", "/usr/bin/wg", "/etc/init.d/zram",
        "/usr/sbin/odhcpd", "/usr/sbin/odhcp6c", "/usr/sbin/tcpdump", "/usr/bin/htop", "/usr/bin/nano",
        "/www/luci-static/aurora", "/www/luci-static/bootstrap", "/etc/hotplug.d/iface/99-hnat-detect",
        "/etc/init.d/viettel-apk-mirror", "/usr/sbin/iptables", "/etc/init.d/blockd",
        "/usr/sbin/pppd", "/lib/netifd/proto/ppp.sh"]
left = [p for p in deny if os.path.lexists(F + p)]
zh = glob.glob(F + "/usr/lib/lua/luci/i18n/*.lmo") + glob.glob(F + "/usr/share/luci/i18n/*")
if left or zh:
    fail("removed features still present: " + ", ".join(left + zh))
else:
    ok("removed: Tailscale, WireGuard, Adblock, DDNS, UPnP, TurboACC/HNAT tools, EQoS, IPv6 DHCP/RA, "
       "PPPoE, zram, iptables, debug tools, Aurora/Bootstrap themes, translations (English only)")

sys.exit(bad)
