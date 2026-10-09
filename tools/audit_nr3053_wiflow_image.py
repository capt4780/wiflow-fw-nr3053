#!/usr/bin/env python3
"""Inspect EXPERIMENTAL Wiflow app files in a newly built NR3053 FIT image.

This is read-only offline inspection, not proof of boot, WiFi, security, or flashability.
"""
from pathlib import Path
import argparse
import json
import os
import stat
import shutil
import subprocess
import sys
import tempfile

from check_nr3053_fit_reference import fdt_nodes, read_image, u32

REQUIRED_FILES = (
    "usr/lib/wiflow/bootstrap",
    "usr/lib/wiflow/common.sh",
    "usr/lib/wiflow/gate-code.sh",
    "usr/lib/wiflow/portal-sync",
    "usr/lib/wiflow/portal-firewall",
    "usr/lib/wiflow/portal-client",
    "usr/lib/wiflow/heartbeat-loop",
    "etc/init.d/wiflow-setup",
    "etc/config/wiflow",
    "www-wiflow/cgi-bin/api",
    "www-wiflow/cgi-bin/gate",
    "www-wiflow/cgi-bin/login",
    "www-wiflow/index.html",
    "www-wiflow/cgi-bin/enroll",
    "www-wiflow/cgi-bin/claim-arm",
    "www-wiflow/enroll.html",
    "usr/lib/wiflow/owner-claim.sh",
    "etc/hotplug.d/button/95-wiflow-first-owner",
    "www-wiflow-luci-gate/cgi-bin/unlock",
    "www-wiflow-luci-gate/index.html",
    "usr/share/nftables.d/chain-pre/input/25-wiflow-luci-gate.nft",
    "usr/share/nftables.d/table-pre/25-wiflow-luci-gate-set.nft",
    "www-wiflow-portal/template-image.html",
    "www-wiflow-portal/template-video.html",
    "www-wiflow-portal/template-website.html",
)



def audit_guest_gate_rootfs(fs: Path) -> list[str]:
    """Assert the BUILT SquashFS contains the declared guest management policy.

    This checks source files embedded in the firmware, not actual nft or
    network packet behavior on the target device.
    """
    files = {
        "network": "usr/lib/wiflow/common.sh",
        "captive": "usr/lib/wiflow/portal-firewall",
        "bootstrap": "usr/lib/wiflow/bootstrap",
        "luci_guard": "usr/share/nftables.d/chain-pre/input/25-wiflow-luci-gate.nft",
        "luci_gate": "www-wiflow-luci-gate/cgi-bin/unlock",
        "setup_gate": "www-wiflow/cgi-bin/gate",
    }
    texts = {}
    problems = []
    for name, rel in files.items():
        path = fs / rel
        if not path.is_file():
            problems.append(f"missing guest Gate component: {rel}")
        else:
            texts[name] = path.read_text(encoding="utf-8", errors="replace")
    if problems:
        return problems
    for expected in (
        "uci set firewall.wiflow_guest.input='REJECT'",
        "uci set firewall.wiflow_guest_setup.src='wiflow_guest'",
        "uci set firewall.wiflow_guest_setup.dest_ip='10.0.0.1'",
        "uci set firewall.wiflow_guest_setup.dest_port='80'",
        "uci set firewall.wiflow_guest_setup.target='ACCEPT'",
        "uci set firewall.wiflow_guest_gate.src='wiflow_guest'",
        "uci set firewall.wiflow_guest_gate.dest_ip='10.0.0.2'",
        "uci set firewall.wiflow_guest_gate.dest_port='80'",
        "uci set firewall.wiflow_guest_gate.target='ACCEPT'",
    ):
        if expected not in texts["network"]:
            problems.append(f"guest Gate firewall rule missing: {expected}")
    # Preserve fail-closed guest Internet, even if Portal has not synced yet.
    guest_source = texts["network"][texts["network"].index("ensure_guest_network(){"):
                                   texts["network"].index("ensure_uplink_network(){")]
    if "uci set firewall.wiflow_guest_wan='forwarding'" in guest_source:
        problems.append("guest WAN forwarding active without Portal snapshot")
    for required in (
        "uci -q delete firewall.wiflow_guest_wan",
        "firewall.wiflow_guest_private_dns.dest_port='853'",
    ):
        if required not in guest_source:
            problems.append(f"guest default forward/Private DNS safety missing: {required}")
    captive_source = texts["captive"]
    for required in (
        '[ -f "$PORTAL_ACTIVE/portal.json" ] || { state_set portal_error',
        "uci set firewall.wiflow_guest_wan='forwarding'",
        "uci -q delete firewall.wiflow_guest_wan",
        '[ -f "$PORTAL_ACTIVE/portal.json" ] || { disable; return 1; }',
        "state_set portal_error 'captive_reload_failed'",
        "state_set portal_error 'captive_chains_missing'",
        "disable || state_set portal_error 'captive_rollback_failed'",
    ):
        if required not in captive_source:
            problems.append(f"Portal-owned forwarding lifecycle missing: {required}")
    for target in ("10.0.0.1", "10.0.0.2"):
        expected = f"ip saddr 10.10.10.0/24 ip daddr {target} return"
        if expected not in texts["captive"]:
            problems.append(f"captive redirect exception missing: {target}")
    if "ip saddr 10.10.10.0/24 tcp dport 80 redirect to :2080" not in texts["captive"]:
        problems.append("guest captive fallback redirect missing")
    guard = texts["luci_guard"].splitlines()
    if guard != [
        "ip daddr 10.0.0.2 tcp dport 8081 ip saddr @wiflow_luci_allowed4 accept",
        "ip daddr 10.0.0.2 tcp dport 8081 drop",
    ]:
        problems.append("LuCI post-Gate input guard differs from reviewed policy")
    for key, token in (
        ("bootstrap", "uci add_list uhttpd.wiflow.listen_http='10.0.0.1:80'"),
        ("bootstrap", "uci add_list uhttpd.wiflow_luci_gate.listen_http='10.0.0.2:80'"),
        ("bootstrap", "uci add_list uhttpd.main.listen_http='10.0.0.2:8081'"),
        ("luci_gate", 'wiflow_gate_code_allowed "$pin" "$want"'),
        ("setup_gate", 'wiflow_gate_code_allowed "$pin" "$want"'),
        ("luci_gate", "nft add element inet fw4 wiflow_luci_allowed4"),
    ):
        if token not in texts[key]:
            problems.append(f"guest Gate web/gating path missing: {key}: {token}")
    return problems



def audit_first_owner_and_boot_rootfs(fs: Path) -> list[str]:
    """Check the built image's first-owner/WPS path and init autostart wiring.

    This is E2 STATIC evidence only; a GPIO/hostapd/booted-router test remains BLOCK.
    """
    problems = []
    paths = {
        "enroll": "www-wiflow/cgi-bin/enroll",
        "arm": "www-wiflow/cgi-bin/claim-arm",
        "claim": "usr/lib/wiflow/owner-claim.sh",
        "button": "etc/hotplug.d/button/95-wiflow-first-owner",
        "init": "etc/init.d/wiflow-setup",
    }
    texts = {}
    for name, rel in paths.items():
        p = fs / rel
        if not p.is_file():
            problems.append(f"missing first-owner/boot source: {rel}")
        else:
            texts[name] = p.read_text(encoding="utf-8", errors="replace")
    if problems:
        return problems
    required_tokens = {
        "enroll": (
            'claim_gate="$(check_gate_session 2>/dev/null || true)"',
            'owner_claim_consume "$claim_gate" "$REMOTE_ADDR"',
            'setup_set_login "$u" "$p"',
        ),
        "arm": (
            'check_gate_session',
            'owner_claim_arm "$claim_gate" "$REMOTE_ADDR"',
            "http://10.0.0.1",
        ),
        "claim": (
            "owner_unclaimed(){", "owner_claim_arm(){",
            "owner_claim_wps(){", "owner_claim_consume(){",
        ),
        "button": (
            '[ "$BUTTON" = wps ]',
            '[ "$ACTION" = pressed ]',
            "owner_claim_wps",
        ),
        "init": (
            "START=96",
            "/usr/lib/wiflow/bootstrap",
            "procd_open_instance heartbeat",
        ),
    }
    for name, tokens in required_tokens.items():
        for token in tokens:
            if token not in texts[name]:
                problems.append(f"first-owner/boot control missing: {name}: {token}")
    enroll = texts["enroll"]
    if "owner_claim_consume " in enroll and "setup_set_login " in enroll:
        if enroll.index("owner_claim_consume ") > enroll.index("setup_set_login "):
            problems.append("first-owner physical approval occurs after owner creation")
    for rel in ("www-wiflow/cgi-bin/enroll", "www-wiflow/cgi-bin/claim-arm",
                "www-wiflow/cgi-bin/gate", "www-wiflow-luci-gate/cgi-bin/unlock",
                "etc/init.d/wiflow-setup"):
        script = fs / rel
        if not script.is_file() or not (script.stat().st_mode & stat.S_IXUSR):
            problems.append(f"missing executable CGI/init permission: {rel}")
    startup = fs / "etc/rc.d/S96wiflow-setup"
    if not startup.is_symlink():
        problems.append("Wiflow init not enabled: missing rc.d/S96wiflow-setup symlink")
    elif not os.readlink(startup).endswith("init.d/wiflow-setup"):
        problems.append("Wiflow init rc.d symlink points to wrong service")
    return problems


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
             "usr/lib/wiflow", "usr/share/nftables.d", "etc/init.d/wiflow-setup", "etc/config/wiflow",
             "etc/rc.d", "etc/hotplug.d/button", "www-wiflow", "www-wiflow-luci-gate", "www-wiflow-portal"],
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
                    issues.append("legacy Gate code present in " + filename)
                if ". /usr/lib/wiflow/gate-code.sh" not in script:
                    issues.append("shared Gate verifier not sourced by " + filename)
                if 'wiflow_gate_code_allowed "$pin" "$want"' not in script:
                    issues.append("shared Gate verifier not enforced by " + filename)
            gate_source = (fs / "usr/lib/wiflow/gate-code.sh").read_text(errors="replace")
            if "WIFLOW_EMERGENCY_GATE_CODE='WIFDIDNR3053'" not in gate_source:
                issues.append("wrong permanent emergency Gate policy")
            setup_form = (fs / "www-wiflow/index.html").read_text(errors="replace")
            luci_form = (fs / "www-wiflow-luci-gate/index.html").read_text(errors="replace")
            for filename, form in (("Setup Gate", setup_form), ("LuCI Gate", luci_form)):
                if 'pattern="([0-9]{6}|WIFDIDNR3053)"' not in form:
                    issues.append(filename + " form does not accept both PIN formats")
            guest_enroll = (fs / "www-wiflow/cgi-bin/enroll").read_text(errors="replace")
            if '10.0.0.*|10.10.10.*)' not in guest_enroll:
                issues.append("post-Gate Setup enrollment blocks guest IPs")
            if 'claim_gate="$(check_gate_session 2>/dev/null || true)"' not in guest_enroll:
                issues.append("Setup enrollment skips the Gate-session-bound first-owner claim")
            luci_nft = (fs / "usr/share/nftables.d/chain-pre/input/25-wiflow-luci-gate.nft").read_text(errors="replace")
            if "tcp dport 8081 ip saddr @wiflow_luci_allowed4 accept" not in luci_nft:
                issues.append("LuCI gated-backend allowlist missing")
            if "tcp dport 8081 drop" not in luci_nft:
                issues.append("LuCI gated-backend deny missing")
            issues.extend(audit_guest_gate_rootfs(fs))
            issues.extend(audit_first_owner_and_boot_rootfs(fs))
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
