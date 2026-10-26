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
# One intended change: mtwifi's country table maps VN to A-band region 7
# (36-64, 100-140, 149-165) instead of 0; everything else byte-identical.
PATCHED = {"/usr/share/schema/mtwifi/dat-defs.json": (b'"VN": [ 1, 7 ]', b'"VN": [ 1, 0 ]')}
def sha_stock(p):
    b = open(F + p, "rb").read()
    if p in PATCHED:
        new, old = PATCHED[p]
        if b.count(new) != 1:
            return None
        b = b.replace(new, old)
    return hashlib.sha256(b).hexdigest()
diff = [p for p, h in golden["must_match"].items()
        if not os.path.isfile(F + p) or sha_stock(p) != h]
diff += [p for p, h in golden["info"].items()
         if not os.path.isfile(F + p) or sha_stock(p) != h]
n = len(golden["must_match"]) + len(golden["info"])
if diff:
    fail("differs from v2.3.6: " + ", ".join(diff))
else:
    ok(f"WiFi driver, firmware, profiles, board and upgrade files: {n} files identical to v2.3.6 (country table: only VN -> region 7)")


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
        "/www/luci-static/wiflow/ui.css", "/www/luci-static/resources/view/wiflow/account.js",
        "/etc/init.d/wiflow", "/etc/rc.d/S96wiflow", "/usr/libexec/wiflow/agent", "/usr/libexec/wiflow/job", "/usr/libexec/wiflow/provision",
        "/usr/share/ucode/wiflow/setup.uc", "/usr/share/ucode/wiflow/stats.uc", "/usr/share/rpcd/ucode/wiflow", "/usr/share/rpcd/acl.d/luci-app-wiflow.json",
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
    "LuCI menu: Wiflow App, Status, Network (incl. Firewall, Diagnostics), System only (no Services, VPN, NAS)":
        sorted(k for f in glob.glob(F + "/usr/share/luci/menu.d/*.json") for k in json.load(open(f)) if k.count("/") == 1 and k not in ("admin/logout", "admin/ubus", "admin/uci", "admin/menu"))
        == ["admin/network", "admin/status", "admin/system", "admin/wiflow"]
        and all(any(k in json.load(open(f)) for f in glob.glob(F + "/usr/share/luci/menu.d/*.json"))
                for k in ("admin/network/firewall/zones", "admin/network/firewall/rules", "admin/network/diagnostics")),
    "PPPoE available (pppd, netifd proto, LuCI protocol page)":
        all(os.path.exists(F + x) for x in ["/usr/sbin/pppd", "/lib/netifd/proto/ppp.sh", "/www/luci-static/resources/protocol/ppp.js"]),
    "stability: guest WiFi isolation, stable channels, DNS cache with fallback servers, tiered uplink recovery":
        "isolate_guests" in open(F + "/usr/libexec/wiflow/guest-net").read()
        and all(x in open(F + "/etc/uci-defaults/98-wiflow-base").read() for x in ["htmode='HE80'", "htmode='HE20'", "cachesize='1000'", "1.1.1.1 8.8.8.8"])
        and all(x in open(F + "/usr/libexec/wiflow/agent").read() for x in ["ifup wan", "wifi reload", "auto_recovery", "REC_MAX"]),
    "Vietnamese is the default LuCI language, English selectable":
        "set luci.main.lang='vi'" in open(F + "/etc/uci-defaults/98-wiflow-base").read()
        and glob.glob(F + "/usr/lib/lua/luci/i18n/base.vi.lmo") and glob.glob(F + "/usr/lib/lua/luci/i18n/firewall.vi.lmo"),
    "LuCI menu copy that the first boot writes over menu.d is pruned too (dropped pages must not come back)":
        sorted(json.load(open(F + "/usr/share/luci-app-mtwifi-cfg/luci-mod-status.json")))
        == ["admin/status/logs", "admin/status/logs/syslog", "admin/status/overview"],
    "guest portal: scripts executable, valid shell, web pages, service starts the loops":
        all(os.access(F + x, os.X_OK) for x in ["/usr/lib/wiflow/portal-client", "/usr/lib/wiflow/portal-firewall", "/usr/lib/wiflow/portal-sync",
            "/usr/lib/wiflow/portal-mode-loop", "/usr/lib/wiflow/portal-session-loop", "/usr/lib/wiflow/portal-hb", "/usr/lib/wiflow/portal-boot",
            "/usr/libexec/wiflow/guests", "/www-wiflow-portal/cgi-bin/portal", "/www-wiflow-portal/cgi-bin/captive-api",
            "/etc/hotplug.d/iface/60-wiflow-portal"])
        and all(subprocess.run(["sh", "-n", F + x]).returncode == 0 for x in ["/usr/lib/wiflow/common.sh", "/usr/lib/wiflow/portal-client",
            "/usr/lib/wiflow/portal-firewall", "/usr/lib/wiflow/portal-sync", "/usr/lib/wiflow/portal-mode-loop", "/usr/lib/wiflow/portal-session-loop",
            "/usr/lib/wiflow/portal-hb", "/usr/lib/wiflow/portal-boot", "/www-wiflow-portal/cgi-bin/portal", "/www-wiflow-portal/cgi-bin/captive-api"])
        and all(os.path.isfile(F + "/www-wiflow-portal/" + x) for x in ["template-website.html", "template-image.html", "template-video.html",
            "connected.html", "runtime/assets/bg-landscape.webp", "runtime/assets/fonts/lexend.woff"])
        and "portal-mode-loop" in open(F + "/etc/init.d/wiflow").read() and "portal-session-loop" in open(F + "/etc/init.d/wiflow").read(),
    "guest portal: no WiFi-driver access (no iwinfo/iwpriv/hostapd/wifi calls in the portal and agent)":
        not any(re.search(r"\b(iwinfo|iwpriv|iwconfig|hostapd|wifi (up|down|reload))\b", open(F + x).read())
                for x in ["/usr/lib/wiflow/common.sh", "/usr/lib/wiflow/portal-client", "/usr/lib/wiflow/portal-firewall", "/usr/lib/wiflow/portal-sync",
                          "/usr/lib/wiflow/portal-mode-loop", "/usr/lib/wiflow/portal-session-loop", "/usr/lib/wiflow/portal-hb", "/usr/lib/wiflow/portal-boot",
                          "/usr/libexec/wiflow/agent", "/usr/libexec/wiflow/guests", "/usr/share/ucode/wiflow/setup.uc"])
        # the only driver question: the source WiFi signal, one call, only while the Wiflow App page is open
        and not re.search(r"iwpriv|iwconfig|hostapd|wifi (up|down|reload)", open(F + "/usr/share/ucode/wiflow/stats.uc").read())
        and open(F + "/usr/share/ucode/wiflow/stats.uc").read().count("call iwinfo") == 1
        and "viewed" in open(F + "/usr/share/ucode/wiflow/stats.uc").read(),
    "guest network: WiFi on wiflow_guest (10.10.10.1/24), DHCP, firewall zone, portal web server on :2080":
        all(x in open(F + "/etc/uci-defaults/98-wiflow-base").read() + open(F + "/usr/libexec/wiflow/guest-net").read() for x in ["wireless.$ifc.network='wiflow_guest'", "ipaddr='10.10.10.1'",
            "firewall.wiflow_guest.name='wiflow_guest'", "listen_http='10.10.10.1:2080'", "dest_port='2080'"]),
    "Wiflow App is part of the firmware (service enabled, native LuCI page, no standalone web app)":
        os.path.islink(F + "/etc/rc.d/S96wiflow") and not os.path.exists(F + "/www/wiflow")
        and json.load(open(F + "/usr/share/luci/menu.d/luci-app-wiflow.json"))["admin/wiflow"]["title"] == "Wiflow App",
    "Wiflow UI: solid buttons (no gradient fill on buttons)":
        "linear-gradient" not in open(F + "/www/luci-static/wiflow/ui.css").read(),
    "LuCI package upload accepts an unsigned package file":
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
        "/www/luci-static/resources/view/firewall/ipsets.js", "/www/luci-static/resources/view/firewall/custom.js",
        "/www/luci-static/resources/view/status/processes.js"]
left = [p for p in deny if os.path.lexists(F + p)]
zh = glob.glob(F + "/usr/lib/lua/luci/i18n/*.zh*.lmo")
if left or zh:
    fail("removed features still present: " + ", ".join(left + zh))
else:
    ok("removed: Tailscale, WireGuard, Adblock, DDNS, UPnP, TurboACC/HNAT tools, EQoS, IPv6 DHCP/RA, "
       "zram, iptables, debug tools, Aurora/Bootstrap themes, Chinese translations")

sys.exit(bad)
