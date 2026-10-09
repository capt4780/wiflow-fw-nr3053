#!/usr/bin/env python3
"""Read-only rootfs inventory for a real NR3053 FIT build.

This is a base-firmware gate, not a declaration that the Wiflow runtime exists.
No router access, no NAND operation, no credentials, no flashing.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from check_nr3053_fit_reference import fdt_nodes, read_image, u32


def inspect(path: Path):
    image = read_image(path)
    nodes = fdt_nodes(image)
    rootfs_node = nodes.get("/images/rootfs-1")
    if rootfs_node is None:
        raise ValueError("missing FIT rootfs-1")
    offset = u32(rootfs_node["data-position"])
    length = u32(rootfs_node["data-size"])
    if offset < 4096 or length < 4096 or offset + length > len(image):
        raise ValueError("invalid FIT rootfs data bounds")
    payload = image[offset:offset + length]
    if payload[:4] != b"hsqs":
        raise ValueError("missing SquashFS magic")

    with tempfile.TemporaryDirectory(prefix="nr3053-rootfs-") as td:
        td = Path(td)
        fs = td / "fs"
        squashfs = td / "image.squashfs"
        squashfs.write_bytes(payload)
        # Extract system trees only; avoid device-node creation as non-root.
        command = ["unsquashfs", "-no-progress", "-d", str(fs),
                   str(squashfs), "bin", "sbin", "etc", "lib", "usr", "www"]
        probe = subprocess.run(["unsquashfs", "-s", str(squashfs)],
                               capture_output=True, text=True, timeout=30)
        print("SQUASHFS_HEADER_PROBE=" + json.dumps({
            "exit": probe.returncode,
            "stdout": probe.stdout[-1500:],
            "stderr": probe.stderr[-1500:],
            "data_bytes": len(payload),
        }), flush=True)
        try:
            subprocess.run(command, check=True, text=True, stdout=subprocess.DEVNULL,
                           stderr=subprocess.PIPE, timeout=180)
        except subprocess.CalledProcessError as exc:
            raise ValueError("unsquashfs extraction failed: " +
                             (exc.stderr or "")[-2400:]) from exc

        # Initial audit is exploratory about base package paths, strict about
        # known destructive auto-writers and a functioning init/BusyBox.
        required = ["bin/busybox", "sbin/init"]
        missing = [p for p in required if not (fs / p).exists()]
        radio_writers = [
            "etc/hotplug.d/net/99-viettel-nr3053-throughwall",
            "etc/init.d/viettel-nr3053-throughwall",
            "etc/uci-defaults/99-viettel-nr3053-throughwall",
            "lib/viettel-nr3053-throughwall.sh",
        ]
        unexpected_radio = [p for p in radio_writers if (fs / p).exists()
                            or (fs / p).is_symlink()]
        feature_paths = {
            "dnsmasq_init": "etc/init.d/dnsmasq",
            "firewall_init": "etc/init.d/firewall",
            "uhttpd_init": "etc/init.d/uhttpd",
            "rpcd_init": "etc/init.d/rpcd",
            "luci_dispatcher": "www/cgi-bin/luci",
            "wireless_configuration": "etc/config/wireless",
            "firewall_configuration": "etc/config/firewall",
            "network_configuration": "etc/config/network",
            "apk_installed_db": "lib/apk/db/installed",
            "opkg_status_db": "usr/lib/opkg/status",
        }
        present = {name: (fs / rel).exists() for name, rel in feature_paths.items()}
        modules = sorted(
            str(p.relative_to(fs)) for p in (fs / "lib/modules").rglob("*")
            if p.is_file() and ("mt_wifi" in p.name.lower() or "mtwifi" in p.name.lower())
        ) if (fs / "lib/modules").is_dir() else []
        firmware = sorted(
            str(p.relative_to(fs)) for p in (fs / "lib/firmware").rglob("*")
            if p.is_file() and ("7981" in p.name or "mtwifi" in p.name.lower())
        ) if (fs / "lib/firmware").is_dir() else []
        distro = ""
        for rel in ("etc/openwrt_release", "etc/os-release"):
            if (fs / rel).is_file():
                distro = (fs / rel).read_text(errors="replace")[:2500]
                break
        installed_lines = []
        for rel in ("lib/apk/db/installed", "usr/lib/opkg/status"):
            p = fs / rel
            if p.is_file():
                data = p.read_text(errors="replace")
                installed_lines = [s[2:] for s in data.splitlines() if s.startswith("P:")]
                if not installed_lines:
                    installed_lines = [s[9:] for s in data.splitlines() if s.startswith("Package: ")]
                break
        # OpenWrt/ImmortalWrt often generates UCI network and wireless
        # configs on first boot. An absent config file is acceptable ONLY when
        # the generating scripts and exact NR3053 board mapping are present.
        # This checks on-disk source paths; it is NOT a runtime boot test.
        firstboot_paths = {
            "board_detect": "bin/board_detect",
            "config_generate": "bin/config_generate",
            "nr3053_board_network": "etc/board.d/02_network",
            "early_boot_script": "etc/init.d/boot",
            "wireless_cli": "sbin/wifi",
            "module_loader": "sbin/kmodloader",
            "network_service": "etc/init.d/network",
        }
        firstboot_files = {
            name: ((fs / rel).exists() or (fs / rel).is_symlink())
            for name, rel in firstboot_paths.items()
        }
        board_network = (fs / firstboot_paths["nr3053_board_network"])
        boot_script = (fs / firstboot_paths["early_boot_script"])
        config_generator = (fs / firstboot_paths["config_generate"])
        board_text = board_network.read_text(errors="replace") if board_network.is_file() else ""
        boot_text = boot_script.read_text(errors="replace") if boot_script.is_file() else ""
        generator_text = config_generator.read_text(errors="replace") if config_generator.is_file() else ""
        nr3053_board_mapping = (
            "viettel,nr3053)" in board_text
            and 'ucidef_set_interfaces_lan_wan "lan1 lan2 lan3" wan' in board_text
        )
        generated_network_path = (
            "generate_network" in generator_text
            and "/etc/config/network" in generator_text
            and "board_detect" in generator_text
        )
        wireless_boot_generation = (
            "/sbin/wifi config" in boot_text
            and "/sbin/kmodloader" in boot_text
            and boot_text.index("/sbin/wifi config") < boot_text.index("/sbin/kmodloader")
        )
        firstboot_errors = []
        if not all(firstboot_files.values()):
            firstboot_errors.append(
                "first-boot generator/service missing: " +
                ", ".join(sorted(k for k, v in firstboot_files.items() if not v))
            )
        if not nr3053_board_mapping:
            firstboot_errors.append("NR3053 LAN/WAN mapping missing or changed")
        if not generated_network_path:
            firstboot_errors.append("dynamic first-boot network configuration path missing")
        if not wireless_boot_generation:
            firstboot_errors.append("dynamic Wi-Fi config/driver boot sequence missing")
        firstboot = {
            "static_gate": "BLOCK" if firstboot_errors else "PASS",
            "firmware_on_device_tested": False,
            "wifi_2g_runtime_verified": False,
            "wifi_5g_runtime_verified": False,
            "first_boot_runtime_verified": False,
            "firstboot_paths_present": firstboot_files,
            "nr3053_board_lan_wan": nr3053_board_mapping,
            "dynamic_network_config_source": generated_network_path,
            "wireless_config_before_kmodloader": wireless_boot_generation,
            "observed_network_config_baked_in": present["network_configuration"],
            "observed_wireless_config_baked_in": present["wireless_configuration"],
            "errors": firstboot_errors,
        }
        portal_paths = [
            "usr/lib/wiflow",
            "etc/init.d/wiflow",
            "www/wiflow",
            "etc/config/wiflow",
        ]
        errors = []
        if missing:
            errors.append("missing basic init components: " + ", ".join(missing))
        if unexpected_radio:
            errors.append("unreviewed 5 GHz calibration writer(s): " +
                          ", ".join(unexpected_radio))
        if not modules:
            errors.append("no mt_wifi kernel module found in built rootfs")
        errors.extend(firstboot_errors)
        report = {
            "phase": "PUBLIC_NR3053_BASE_ONLY",
            "rootfs_audit": "BLOCK" if errors else "PASS",
            "flash_authorization": "BLOCK",
            "wiflow_portal_runtime_verified": False,
            "candidate_fit_sha256": hashlib.sha256(image).hexdigest(),
            "rootfs_sha256": hashlib.sha256(payload).hexdigest(),
            "rootfs_bytes": len(payload),
            "present": present,
            "firstboot_static": firstboot,
            "mtwifi_modules": modules,
            "firmware_files": firmware[:100],
            "observed_package_count": len(installed_lines),
            "key_packages": sorted(
                name for name in installed_lines
                if any(key in name.lower() for key in
                       ("mtwifi", "mt_wifi", "luci", "dnsmasq", "nft", "firewall", "uhttpd", "rpcd"))
            )[:100],
            "distro": distro,
            "unexpected_radio_writers": unexpected_radio,
            "wiflow_runtime_candidates": [p for p in portal_paths if (fs / p).exists()],
            "errors": errors,
        }
        return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        report = inspect(args.candidate)
    except (OSError, ValueError, KeyError, TimeoutError,
            subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        report = {"rootfs_audit": "BLOCK", "flash_authorization": "BLOCK",
                  "errors": [f"{type(exc).__name__}: {str(exc)[:600]}"]}
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps(report, sort_keys=True))
    return 0 if report["rootfs_audit"] == "PASS" else 2


if __name__ == "__main__":
    sys.exit(main())
