#!/usr/bin/env python3
"""Check the lean NR3053 image manifest (package list built into the firmware).

Static evidence only: it proves which packages are in the image, not that the
image boots. flash_authorization is always BLOCK.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REQUIRED = (
    # boot / radio
    "kmod-mt_wifi", "mtwifi-cfg-ucode", "iwinfo-ucode", "wireless-tools", "wireless-regdb",
    # runtime that the separate wiflow-setup .apk depends on (must be in the base)
    "uhttpd", "firewall4", "dnsmasq-full", "nftables-json", "jsonfilter",
    "uclient-fetch", "ca-bundle", "libustream-openssl",
    # management UI
    "luci-base",
)
FORBIDDEN = (
    "wiflow-setup",  # Wiflow is installed separately from its own .apk
    "htop", "nano", "tcpdump", "luci-app-upnp", "miniupnpd", "luci-app-ddns",
    "luci-app-adblock", "luci-app-turboacc-mtk", "luci-app-eqos-mtk",
    "kmod-wireguard", "wireguard-tools", "luci-app-nr3053-throughwall",
    "luci-theme-aurora", "openssh-sftp-server", "kmod-tcp-bbr",
)


_VER = re.compile(r"^(.*?)-(\d[^\s]*)$")


def _name(line: str) -> str:
    """Package name from either manifest style.

    opkg style: "name - 1.0-r1"; apk style: "name-1.0-r1 arch {origin} ...".
    """
    parts = line.split()
    if len(parts) >= 2 and parts[1] == "-":
        return parts[0]
    m = _VER.match(parts[0])
    return m.group(1) if m else parts[0]


def parse(text: str) -> set[str]:
    names = set()
    for line in text.splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            names.add(_name(line))
    return names


def has(pkgs: set[str], want: str) -> bool:
    """Exact name, or name plus a library ABI suffix (libustream-openssl20201210)."""
    return want in pkgs or any(re.fullmatch(re.escape(want) + r"\d+", p) for p in pkgs)


def check(text: str) -> dict:
    pkgs = parse(text)
    missing = [p for p in REQUIRED if not has(pkgs, p)]
    present = [p for p in FORBIDDEN if p in pkgs]
    return {
        "package_count": len(pkgs),
        "missing_required": missing,
        "forbidden_present": present,
        "lean_gate": "PASS" if not missing and not present and pkgs else "FAIL",
        "flash_authorization": "BLOCK",
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("manifest", type=Path)
    ap.add_argument("--report", type=Path, required=True)
    a = ap.parse_args()
    report = check(a.manifest.read_text(encoding="utf-8"))
    a.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0 if report["lean_gate"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
