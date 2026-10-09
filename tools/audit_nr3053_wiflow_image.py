#!/usr/bin/env python3
"""Inspect EXPERIMENTAL Wiflow app files in a newly built NR3053 FIT image.

This is read-only offline inspection, not proof of boot, WiFi, security, or flashability.
"""
from pathlib import Path
import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile

from check_nr3053_fit_reference import fdt_nodes, read_image, u32

REQUIRED_FILES = (
    "usr/bin/iwinfo-ucode",
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
    "www-wiflow-luci-gate/cgi-bin/unlock",
    "www-wiflow-luci-gate/index.html",
    "usr/share/nftables.d/chain-pre/input/25-wiflow-luci-gate.nft",
    "usr/share/nftables.d/table-pre/25-wiflow-luci-gate-set.nft",
    "www-wiflow-portal/template-image.html",
    "www-wiflow-portal/template-video.html",
    "www-wiflow-portal/template-website.html",
    "www-wiflow-portal/cgi-bin/portal",
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
    # A Website DNS answer must never create pre-auth exceptions for RFC1918,
    # local management or special/reserved destinations. Verify the *image*,
    # not only the working tree.
    if 'wiflow_public_ipv4(){' not in captive_source or \
       'wiflow_public_ipv4 "$ip"' not in captive_source:
        problems.append("Website walled-garden public IPv4 gate missing from rootfs")
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


def audit_root_shadow_field(fs: Path) -> dict:
    """Classify ONLY the built root credential field, never disclose its value.

    A hash merely proves the field is populated. It does not prove that the
    password is strong or has been rotated; root credential RELEASE remains
    explicitly blocked pending real first-owner/runtime verification.
    """
    path = fs / "etc/shadow"
    state = "MISSING"
    if path.is_file():
        data = path.read_text(encoding="utf-8", errors="replace")
        lines = [line for line in data.splitlines()
                 if line.split(":", 1)[0] == "root"]
        if len(lines) != 1:
            state = "MISSING" if not lines else "DUPLICATE"
        else:
            fields = lines[0].split(":")
            if len(fields) != 9:
                state = "MALFORMED"
            else:
                password_field = fields[1]
                if not password_field:
                    state = "EMPTY"
                elif password_field.startswith(("!", "*")):
                    state = "LOCKED"
                elif re.fullmatch(
                    r"\$6\$(?:rounds=[1-9][0-9]*\$)?[A-Za-z0-9./]{1,16}\$[A-Za-z0-9./]{86}",
                    password_field,
                ):
                    state = "SHA512_CRYPT_HASH_PRESENT"
                elif password_field.startswith("$"):
                    state = "OTHER_OR_MALFORMED_HASH"
                else:
                    state = "UNSAFE_NONHASHED_FIELD"
    return {
        "root_password_field_state": state,
        "root_shadow_static_check": (
            "HASH_PRESENT_ONLY" if state == "SHA512_CRYPT_HASH_PRESENT"
            else "BLOCK"
        ),
        # Fixed public defaults or unchanged firstboot hashes aren't secure.
        "root_credential_release_gate": "BLOCK",
    }



def root_shadow_static_errors(root_audit: dict) -> list[str]:
    """Return only sanitized findings for image packaging (never credentials)."""
    if root_audit["root_shadow_static_check"] == "BLOCK":
        return ["built root credential field unsafe: "
                + root_audit["root_password_field_state"]]
    return []


def audit_captive_mutation_rootfs(fs: Path) -> list[str]:
    """Verify the built captive CGI enforces the reviewed HTTP mutation gate.

    This is static SquashFS policy evidence, NOT a live grant/packet test.
    """
    path = fs / "www-wiflow-portal/cgi-bin/portal"
    if not path.is_file():
        return ["captive authorization CGI missing from compiled rootfs"]
    source = path.read_text(encoding="utf-8", errors="replace")
    marker = 'case "$action" in\n authorize|event)'
    successor = '\ncase "$action" in\n authorize)'
    if source.count(marker) != 1 or successor not in source:
        return ["captive authorization action guard absent"]
    start = source.index(marker)
    end = source.index(successor, start)
    guard = source[start:end]
    required = (
        "authorize|event)",
        '[ "${REQUEST_METHOD:-}" != POST ]',
        "Status: 405 Method Not Allowed",
        '[ -z "$BODY" ]',
        "Status: 400 Bad Request",
    )
    if any(piece not in guard for piece in required):
        return ["captive authorization POST/body-only gate missing"]
    if 'authorize-session "$sid" "$cid"' not in source[end:]:
        return ["captive authorization backend flow changed unexpectedly"]
    return []



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
             "usr/bin/iwinfo-ucode", "usr/lib/wiflow", "usr/share/nftables.d", "etc/init.d/wiflow-setup", "etc/config/wiflow",
             "www-wiflow", "www-wiflow-luci-gate", "www-wiflow-portal", "etc/shadow"],
            capture_output=True, text=True, timeout=120,
        )
        if result.returncode:
            raise ValueError("SquashFS extraction failed: " + result.stderr[-800:])
        fs = root / "fs"
        root_audit = audit_root_shadow_field(fs)
        missing = [p for p in REQUIRED_FILES if not (fs / p).is_file()]
        issues = [f"missing Wiflow image file: {p}" for p in missing]
        # Fail-closed: 22/22 component success must not publish images with
        # empty, locked, malformed, duplicate or missing root shadow records.
        issues.extend(root_shadow_static_errors(root_audit))
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
            if 'check_gate_session >/dev/null 2>&1' not in guest_enroll:
                issues.append("Setup enrollment skips Gate cookie validation")
            luci_nft = (fs / "usr/share/nftables.d/chain-pre/input/25-wiflow-luci-gate.nft").read_text(errors="replace")
            if "tcp dport 8081 ip saddr @wiflow_luci_allowed4 accept" not in luci_nft:
                issues.append("LuCI gated-backend allowlist missing")
            if "tcp dport 8081 drop" not in luci_nft:
                issues.append("LuCI gated-backend deny missing")
            issues.extend(audit_guest_gate_rootfs(fs))
            issues.extend(audit_captive_mutation_rootfs(fs))
        return {
            "phase": "EXPERIMENTAL_APP_PACKAGE_OFFLINE_ROOTFS_AUDIT",
            "static_gate": "BLOCK" if issues else "PASS",
            "release_approval": "BLOCK",
            "device_wifi_tested": False,
            "portal_runtime_tested": False,
            "device_recovery_tested": False,
            "files_checked": len(REQUIRED_FILES),
            "found_files": len(REQUIRED_FILES) - len(missing),
            **root_audit,
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
                  "root_password_field_state": "NOT_INSPECTED",
                  "root_shadow_static_check": "BLOCK",
                  "root_credential_release_gate": "BLOCK",
                  "errors": [str(e)]}
    args.report.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(result, sort_keys=True))
    return 0 if result["static_gate"] == "PASS" else 2


if __name__ == "__main__":
    sys.exit(main())
