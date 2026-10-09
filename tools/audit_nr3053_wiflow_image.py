#!/usr/bin/env python3
"""Inspect EXPERIMENTAL Wiflow app files in a newly built NR3053 FIT image.

This is read-only offline inspection, not proof of boot, WiFi, security, or flashability.
"""
from pathlib import Path
import argparse
import json
import shutil
import subprocess
import sys
import tempfile

from check_nr3053_fit_reference import fdt_nodes, read_image, u32

REQUIRED_FILES = (
    "usr/lib/wiflow/bootstrap",
    "usr/lib/wiflow/common.sh",
    "usr/lib/wiflow/portal-sync",
    "usr/lib/wiflow/portal-firewall",
    "usr/lib/wiflow/portal-client",
    "usr/lib/wiflow/heartbeat-loop",
    "etc/init.d/wiflow-setup",
    "etc/config/wiflow",
    "www-wiflow/cgi-bin/api",
    "www-wiflow/cgi-bin/gate",
    "www-wiflow/cgi-bin/enroll",
    "www-wiflow-luci-gate/cgi-bin/unlock",
    "www-wiflow-portal/template-image.html",
    "www-wiflow-portal/template-video.html",
    "www-wiflow-portal/template-website.html",
)


def audit(path: Path) -> dict:
    image = read_image(path)
    tree = fdt_nodes(image)
    node = tree.get("/images/rootfs-1")
    if not node:
        raise ValueError("FIT missing rootfs-1")
    offset, length = u32(node["data-position"]), u32(node["data-size"])
    if offset < 4096 or length < 4096 or offset + length > len(image):
        raise ValueError("invalid FIT rootfs bounds")
    payload = image[offset:offset + length]
    if payload[:4] != b"hsqs":
        raise ValueError("rootfs is not SquashFS")
    with tempfile.TemporaryDirectory(prefix="nr3053-wiflow-") as temp:
        root = Path(temp)
        blob = root / "rootfs.squashfs"
        blob.write_bytes(payload)
        if not shutil.which("unsquashfs"):
            raise ValueError("unsquashfs missing from audit runner")
        result = subprocess.run(
            ["unsquashfs", "-no-progress", "-d", str(root / "fs"), str(blob),
             "usr/lib/wiflow", "etc/init.d/wiflow-setup", "etc/config/wiflow",
             "www-wiflow", "www-wiflow-luci-gate", "www-wiflow-portal"],
            capture_output=True, text=True, timeout=120,
        )
        if result.returncode:
            raise ValueError("SquashFS extraction failed: " + result.stderr[-800:])
        fs = root / "fs"
        missing = [p for p in REQUIRED_FILES if not (fs / p).is_file()]
        issues = [f"missing Wiflow image file: {p}" for p in missing]
        if not missing:
            login = (fs / "usr/lib/wiflow/common.sh").read_text(errors="replace")
            gate = (fs / "www-wiflow/cgi-bin/gate").read_text(errors="replace")
            unlock = (fs / "www-wiflow-luci-gate/cgi-bin/unlock").read_text(errors="replace")
            if "WIFLOW_DATA_GENERATION='4'" not in login:
                issues.append("unexpected Wiflow data generation")
            if '[ "$p" = wiflow ]' in login:
                issues.append("insecure default Wiflow setup password present")
            for filename, script in (("Setup Gate", gate), ("LuCI Gate", unlock)):
                if "247365" in script or "master=" in script:
                    issues.append("static web recovery backdoor in " + filename)
        return {
            "phase": "EXPERIMENTAL_APP_PACKAGE_OFFLINE_ROOTFS_AUDIT",
            "static_gate": "BLOCK" if issues else "PASS",
            "release_approval": "BLOCK",
            "device_wifi_tested": False,
            "portal_runtime_tested": False,
            "device_recovery_tested": False,
            "files_checked": len(REQUIRED_FILES),
            "found_files": len(REQUIRED_FILES) - len(missing),
            "errors": issues,
        }


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("fit_image", type=Path)
    p.add_argument("--report", type=Path, required=True)
    args = p.parse_args()
    try:
        result = audit(args.fit_image)
    except (OSError, ValueError, KeyError, subprocess.TimeoutExpired) as e:
        result = {"static_gate": "BLOCK", "release_approval": "BLOCK",
                  "errors": [str(e)]}
    args.report.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(result, sort_keys=True))
    return 0 if result["static_gate"] == "PASS" else 2


if __name__ == "__main__":
    sys.exit(main())
