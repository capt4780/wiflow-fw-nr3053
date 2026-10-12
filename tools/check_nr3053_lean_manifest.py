#!/usr/bin/env python3
"""Check the lean NR3053 image manifest (package list built into the firmware).

Static evidence only: it proves which packages are in the image, not that the
image boots. flash_authorization is always BLOCK.
"""
from __future__ import annotations

import argparse
import json
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


def parse(text: str) -> set[str]:
    names = set()
    for line in text.splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            names.add(line.split()[0].rstrip(":"))
    return names


def check(text: str) -> dict:
    pkgs = parse(text)
    missing = [p for p in REQUIRED if p not in pkgs]
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
