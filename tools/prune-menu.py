#!/usr/bin/env python3
"""LuCI menu: only what a Wiflow router needs.

  prune-menu.py <menu.d dir> [<extra menu json> ...]

Everything else in the menu files of luci-base / luci-mod-* is dropped. The
extra files are menu copies that the router writes over menu.d on its first
boot (luci-app-mtwifi-cfg: /usr/share/luci-app-mtwifi-cfg/luci-mod-status.json);
they get the same treatment, otherwise the dropped pages come back after the
first boot.
"""
import glob, json, os, sys

KEEP = {"admin", "admin/status", "admin/status/overview", "admin/status/logs", "admin/status/logs/syslog",
        "admin/system", "admin/system/system", "admin/system/admin", "admin/system/admin/password", "admin/system/admin/dropbear",
        "admin/system/package-manager", "admin/system/flash", "admin/system/reboot",
        "admin/network", "admin/network/network", "admin/network/wireless", "admin/network/dhcp", "admin/network/remote_addr/*",
        "admin/wiflow"}
TECH = {"translations", "ubus", "uci", "logout", "menu"}


def keep(m):
    out = {}
    for k, v in m.items():
        top = k.split("/")[1] if "/" in k else ""
        if k in KEEP or top in TECH:
            out[k] = v
    return out


d, extra = sys.argv[1], sys.argv[2:]
seen = set()
for f in sorted(glob.glob(d + "/*.json")):
    out = keep(json.load(open(f)))
    seen.update(out)
    if out:
        open(f, "w").write(json.dumps(out, indent="\t") + "\n")
    else:
        os.remove(f)
missing = KEEP - seen
if missing:
    sys.exit("menu pages missing: %s" % sorted(missing))
for f in extra:
    out = keep(json.load(open(f)))
    open(f, "w").write(json.dumps(out, indent="\t") + "\n")
