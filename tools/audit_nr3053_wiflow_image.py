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
from provision_nr3053_root_shadow import inspect_root_shadow

REQUIRED_FILES = (
    "usr/bin/iwinfo-ucode",
    "usr/lib/wiflow/bootstrap",
    "usr/lib/wiflow/common.sh",
    "usr/lib/wiflow/gate-code.sh",
    "usr/lib/wiflow/portal-sync",
    "usr/lib/wiflow/portal-firewall",
    "usr/lib/wiflow/portal-client",
    "usr/lib/wiflow/portal-mode-loop",
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


def audit_portal_disable_reporting_rootfs(fs: Path) -> list[str]:
    """Ensure explicit WP disable failures are reported, never swallowed."""
    file = fs / "usr/lib/wiflow/heartbeat-loop"
    if not file.is_file():
        return ["Portal heartbeat missing from compiled image"]
    source = file.read_text(encoding="utf-8", errors="replace")
    start = source.find("portal_runtime_disable(){")
    end = source.find("\nportal_runtime_reconcile(){", start)
    if start < 0 or end <= start:
        return ["Portal disable authoritative function missing"]
    body = source[start:end]
    required = (
        "if ! portal_runtime_set_enabled 0; then",
        "state_set portal_error 'portal_disable_state_commit_failed'",
        "if ! /usr/lib/wiflow/portal-firewall disable",
        "state_set portal_error 'captive_firewall_disable_failed'",
        '[ "$failed" = 0 ]',
    )
    if any(item not in body for item in required):
        return ["Portal disable can hide state or firewall failure"]
    reconcile = source[end:source.find("\ndelay=20", end)]
    if '  portal_runtime_disable\n  return $?' not in reconcile:
        return ["Portal remote disable reports unconditional success"]
    return []


def audit_portal_enable_owner_rootfs(fs: Path) -> list[str]:
    """Reject compiled images whose local poller overrides remote Portal disable."""
    path = fs / "usr/lib/wiflow/portal-mode-loop"
    if not path.is_file():
        return ["Portal mode owner missing from compiled rootfs"]
    source = path.read_text(encoding="utf-8", errors="replace")
    start = source.find("portal_reconcile_local(){")
    end = source.find("\nwhile true; do", start)
    if start < 0 or end <= start:
        return ["Portal mode reconciliation function missing"]
    body = source[start:end]
    required = (
        'enabled="$(uci -q get wiflow.core.portal_enabled',
        'if [ "$enabled" = 1 ] && [ -f "$PORTAL_ACTIVE/portal.json" ]; then',
        '/usr/lib/wiflow/portal-firewall ensure',
        '/usr/lib/wiflow/portal-firewall disable',
    )
    if any(piece not in body for piece in required):
        return ["Portal mode poller does not honor heartbeat-owned enable state"]
    if 'uci set wiflow.core.portal_enabled' in body or 'uci commit wiflow' in body:
        return ["Portal mode poller can override WordPress explicit disable"]
    return []


def audit_captive_mutation_rootfs(fs: Path) -> list[str]:
    """Verify the built captive CGI enforces the reviewed HTTP mutation gate.

    This is static SquashFS policy evidence, NOT a live grant/packet test.
    """
    path = fs / "www-wiflow-portal/cgi-bin/portal"
    if not path.is_file():
        return ["captive authorization CGI missing from compiled rootfs"]
    source = path.read_text(encoding="utf-8", errors="replace")
    marker = 'case "$action" in\n authorize|event|status)'
    successor = '\ncase "$action" in\n status)'
    if source.count(marker) != 1 or successor not in source:
        return ["captive authorization action guard absent"]
    start = source.index(marker)
    end = source.index(successor, start)
    guard = source[start:end]
    required = (
        "authorize|event|status)",
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


def audit_capport_tls_gate_rootfs(fs: Path) -> list[str]:
    """Never ship an invalid HTTP CAPPORT DHCP advertisement.

    Until TLS and per-client HTTPS CAPPORT are implemented/audited, no
    DHCP 114 URI may be advertised. HTTP fallback continues independently.
    """
    common = fs / "usr/lib/wiflow/common.sh"
    if not common.is_file():
        return ["CAPPORT DHCP configuration owner missing from rootfs"]
    text = common.read_text(encoding="utf-8", errors="replace")
    problems = []
    if "uci add_list dhcp.wiflow_guest.dhcp_option='114," in text:
        problems.append("DHCP Option 114 must remain OFF until audited CAPPORT HTTPS is ready")
    if "uci add_list dhcp.wiflow_guest.dhcp_option='6,10.10.10.1'" not in text:
        problems.append("fallback guest DNS DHCP option missing")
    if (fs / "www-wiflow-portal/cgi-bin/captive-api").exists():
        problems.append("obsolete insecure HTTP CAPPORT CGI must not be installed")
    return problems


def audit_captive_noredirect_rootfs(fs: Path) -> list[str]:
    """Block images missing a safe, navigation-free captive confirmation.

    The HTTPS CAPPORT endpoint is a separate gated feature. This gate only
    verifies the HTTP-fallback Portal has a same-origin POST and status check.
    """
    problems = []
    for mode in ("website", "image", "video"):
        path = fs / f"www-wiflow-portal/template-{mode}.html"
        if not path.is_file():
            problems.append(f"no-redirect captive template missing: {mode}")
            continue
        content = path.read_text(encoding="utf-8", errors="replace")
        required = (
            "const commit=async()=>",
            "const response=await send('authorize')",
            "const status=await send('status')",
            "confirmed=response.status===204",
            "new URL(authorizeUrl,window.location.href).origin!==window.location.origin",
            "mode:'same-origin'",
            "redirect:'error'",
            "body:new URLSearchParams({action,session_id:sessionId}).toString()",
            "state='authorized'",
        )
        if any(piece not in content for piece in required) or "form.submit()" in content:
            problems.append(f"captive mode {mode} lost safe non-navigation confirmation")
    cgi = fs / "www-wiflow-portal/cgi-bin/portal"
    if not cgi.is_file():
        problems.append("read-back status CGI missing")
    else:
        src = cgi.read_text(encoding="utf-8", errors="replace")
        for piece in (
            " authorize|event|status)",
            " status)",
            'validate_session "$sid"',
            'is-authorized "$sid"',
            'Location: http://10.10.10.1:2080/cgi-bin/portal',
        ):
            if piece not in src:
                problems.append(f"captive CGI status/canonical-origin gate missing: {piece}")
    return problems


def audit_captive_disabled_authorization_rootfs(fs: Path) -> list[str]:
    """Require a fresh Portal enable+snapshot guard in both authorize owners."""
    paths = (
        ("www-wiflow-portal/cgi-bin/portal", "\n authorize)\n", "\n event)\n"),
        ("usr/lib/wiflow/portal-client", "\nauthorize-session)\n", "\n    ;;\nrevoke-session)"),
    )
    issues = []
    for path, start_mark, end_mark in paths:
        file = fs / path
        if not file.is_file():
            issues.append("Portal disabled authorize owner missing: " + path)
            continue
        content = file.read_text(encoding="utf-8", errors="replace")
        start, end = content.find(start_mark), content.find(end_mark)
        if start < 0 or end <= start:
            issues.append("Portal disabled authorize branch missing: " + path)
            continue
        branch = content[start:end]
        enabled = branch.find("uci -q get wiflow.core.portal_enabled")
        snapshot = branch.find('[ -f "$PORTAL_ACTIVE/portal.json" ]')
        downstream = (branch.find("portal-client is-authorized")
                      if path.startswith("www-") else branch.find('portal_nft_add "$ip" "$mac"'))
        if min(enabled, snapshot, downstream) < 0 or enabled >= downstream or snapshot >= downstream:
            issues.append("Portal disabled can authorize stale session: " + path)
    return issues


def audit_captive_commit_rootfs(fs: Path) -> list[str]:
    """Enforce fail-closed Page 6 transaction ordering in the BUILT rootfs.

    Static implementation gate only; external IP/MAC packet testing remains S5.
    """
    path = fs / "usr/lib/wiflow/portal-client"
    if not path.is_file():
        return ["captive transaction implementation missing from compiled rootfs"]
    source = path.read_text(encoding="utf-8", errors="replace")
    start = source.find("\nauthorize-session)\n")
    end = source.find("\n    ;;\nrevoke-session)", start)
    if start == -1 or end <= start:
        return ["captive authorization transaction branch missing"]
    body = source[start:end]
    required = (
        'portal_nft_pair_granted "$ip" "$mac"',
        'portal_nft_add "$ip" "$mac"',
        'if ! portal_nft_pair_authorized "$ip" "$mac"; then',
        'if ! client_session_write "$f"',
        'portal_nft_del "$ip" "$mac"',
        '/usr/lib/wiflow/portal-firewall disable',
        'portal_nft_grant_del "$ip" "$mac"',
    )
    if any(x not in body for x in required):
        return ["captive authorization rollback/commit guard missing"]
    if not (body.index('portal_nft_add "$ip" "$mac"') <
            body.index('if ! client_session_write "$f"') <
            body.index('portal_nft_grant_del "$ip" "$mac"')):
        return ["captive grant consumed before authorized session persisted"]
    failure = body[body.index('if ! client_session_write "$f"'):
                   body.index('portal_nft_grant_del "$ip" "$mac"')]
    if 'portal_nft_del "$ip" "$mac"' not in failure or "exit 7" not in failure:
        return ["captive session write failure can leave a live nft authorization"]
    return []


def audit_wp_ack_receipt_rootfs(fs: Path) -> list[str]:
    """Do not mark WP active ACK on HTTP transport alone."""
    path = fs / "usr/lib/wiflow/portal-sync"
    if not path.is_file():
        return ["Portal ACK replay implementation missing from compiled rootfs"]
    source = path.read_text(encoding="utf-8", errors="replace")
    start = source.find("ack_active_revision(){")
    end = source.find("\nRESP=", start)
    if start == -1 or end <= start:
        return ["Portal ACK replay helper missing"]
    body = source[start:end]
    required = (
        'wiflow_post "$ack" "$WIFLOW_PORTAL_API/ack"',
        'jsonfilter -i "$ack" -e \'@.ok\'',
        '[ "$ack_ok" = true ] || [ "$ack_ok" = 1 ]',
        'mv "$PORTAL_ACK_CONFIRMED.$$" "$PORTAL_ACK_CONFIRMED"',
        'rm -f "$PORTAL_ACK_CONFIRMED"',
    )
    if any(x not in body for x in required):
        return ["Portal ACK receipt can be marked without a confirmed WP response"]
    return []


def audit_captive_rebind_rootfs(fs: Path) -> list[str]:
    """Static gate: DHCP IP changes cannot bypass session persistence."""
    client = fs / "usr/lib/wiflow/portal-client"
    loop = fs / "usr/lib/wiflow/portal-session-loop"
    if not client.is_file() or not loop.is_file():
        return ["guest DHCP rebind runtime missing from compiled rootfs"]
    a = client.read_text(encoding="utf-8", errors="replace")
    b = loop.read_text(encoding="utf-8", errors="replace")
    ai = a.find("# On DHCP IP rebind, never authorize a new IP")
    bi = b.find('if [ "$newip" != "$ip" ]; then')
    if ai < 0 or bi < 0:
        return ["guest DHCP IP rebind fail-closed guard missing"]
    a = a[ai:a.find("\n    fi\n\n    # Stage 3", ai)]
    b = b[bi:b.find('\n        else\n            [ "$absent"', bi)]
    # Neither path may use the stored authorized flag to skip old-pair
    # revocation: a stale nft entry could outlive an unauthorized record.
    if 'if [ -n "$oldip" ] && [ "$oldip" != "$ip" ]; then' not in a:
        return ["client DHCP rebind skips stale unauthorized nft authorization"]
    old_loop = b[b.find("had_grant=0"):b.find('if ! client_session_write "$f"')]
    required_unconditional = (
        'portal_nft_del "$ip" "$mac"',
        'if ! portal_nft_pair_revoked "$ip" "$mac"; then',
        'if [ "${authorized:-0}" = 0 ] && portal_nft_pair_granted',
    )
    if not old_loop.startswith('had_grant=0') or any(
        token not in old_loop for token in required_unconditional
    ):
        return ["session-loop DHCP rebind skips stale unauthorized nft authorization"]
    if 'if [ "${authorized:-0}" != 0 ]; then' in old_loop:
        return ["session-loop old nft revoke guarded by local authorization flag"]
    if not (
        old_loop.index(required_unconditional[0]) <
        old_loop.index(required_unconditional[1]) <
        old_loop.index(required_unconditional[2])
    ):
        return ["session-loop DHCP revoke not verified before grant migration"]
    required_a = (
        'portal_nft_del "$oldip" "$mac"',
        'if ! client_session_write "$f"',
        'portal_nft_add "$ip" "$mac"',
        'if ! portal_nft_pair_revoked "$oldip" "$mac"; then',
        '/usr/lib/wiflow/portal-firewall disable',
    )
    required_b = (
        'portal_nft_del "$ip" "$mac"',
        'if ! portal_nft_pair_revoked "$ip" "$mac"; then',
        '/usr/lib/wiflow/portal-firewall disable',
        'if ! client_session_write "$f"',
        'portal_nft_add "$newip" "$mac"',
        'portal_nft_grant_add "$newip" "$mac"',
    )
    if any(x not in a for x in required_a) or any(x not in b for x in required_b):
        return ["guest DHCP rebind transaction guard incomplete"]
    if not (a.index('portal_nft_del "$oldip" "$mac"') <
            a.index('if ! portal_nft_pair_revoked "$oldip" "$mac"; then') <
            a.index('/usr/lib/wiflow/portal-firewall disable') <
            a.index('if ! client_session_write "$f"') <
            a.index('portal_nft_add "$ip" "$mac"')):
        return ["guest IP restore precedes local session persistence"]
    if not (b.index('portal_nft_del "$ip" "$mac"') <
            b.index('if ! portal_nft_pair_revoked "$ip" "$mac"; then') <
            b.index('/usr/lib/wiflow/portal-firewall disable') <
            b.index('if ! client_session_write "$f"') <
            b.index('portal_nft_add "$newip" "$mac"')):
        return ["session loop reauthorizes changed IP before persisting new session"]
    if b.index('if ! client_session_write "$f"') > b.index(
            'portal_nft_grant_add "$newip" "$mac"'):
        return ["session loop grants changed IP before persisting new session"]
    return []



def audit_captive_revoke_rootfs(fs: Path) -> list[str]:
    """Compiled image must verify guest authorization removal before retiring sessions."""
    client = fs / "usr/lib/wiflow/portal-client"
    loop = fs / "usr/lib/wiflow/portal-session-loop"
    common = fs / "usr/lib/wiflow/common.sh"
    if not client.is_file() or not loop.is_file() or not common.is_file():
        return ["captive revoke runtime missing from compiled rootfs"]
    a = client.read_text(encoding="utf-8", errors="replace")
    b = loop.read_text(encoding="utf-8", errors="replace")
    c = common.read_text(encoding="utf-8", errors="replace")
    helper = c[c.find("portal_nft_pair_revoked(){"):c.find("\nportal_nft_add(){")]
    if not all(x in helper for x in (
        'dump="$(/usr/sbin/nft list set inet fw4 wiflow_portal_authed',
        '|| return 1',
        '! printf',
        'grep -Fiq "$ipx . $mac"',
    )):
        return ["nft readback errors must never count as a successful guest revoke"]
    ai = a.find("\nrevoke-session)\n")
    ae = a.find("\n    ;;\nis-authorized)", ai)
    bi = b.find('if [ "$elapsed" -ge "$DISCONNECT_GRACE" ]; then')
    be = b.find('\n            else\n                client_session_write', bi)
    if min(ai, ae, bi, be) < 0 or ae <= ai or be <= bi:
        return ["captive revoke/disconnect branch missing"]
    a = a[ai:ae]
    b = b[bi:be]
    required_a = (
        'portal_nft_del "$ip" "$mac"',
        'if ! portal_nft_pair_revoked "$ip" "$mac"; then',
        '/usr/lib/wiflow/portal-firewall disable',
        "state_set portal_error 'client_revoke_unverified'",
        'if ! client_session_write "$f"',
        "state_set portal_error 'client_revoke_persist_failed'",
    )
    required_b = (
        'portal_nft_del "$ip" "$mac"',
        'if ! portal_nft_pair_revoked "$ip" "$mac"; then',
        '/usr/lib/wiflow/portal-firewall disable',
        "state_set portal_error 'client_disconnect_revoke_unverified'",
        'continue',
        'rm -f "$f"',
    )
    if any(x not in a for x in required_a) or any(x not in b for x in required_b):
        return ["guest revocation must fail closed on nft verify/persistence failure"]
    if not (a.index('portal_nft_del "$ip" "$mac"') <
            a.index('if ! portal_nft_pair_revoked') <
            a.index('portal_nft_grant_del "$ip" "$mac"') <
            a.index('log_client_event revoked "$sid" verified')):
        return ["guest revoke marks success before verifying nft removal"]
    if not (b.index('portal_nft_del "$ip" "$mac"') <
            b.index('if ! portal_nft_pair_revoked') <
            b.index('portal_nft_grant_del "$ip" "$mac"') <
            b.index('rm -f "$f"')):
        return ["guest disconnect retires session before verifying nft removal"]
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
        missing = [p for p in REQUIRED_FILES if not (fs / p).is_file()]
        issues = [f"missing Wiflow image file: {p}" for p in missing]
        # This is an image-level root credential check, not a login test.
        # A source package audit cannot attest the actual built /etc/shadow.
        shadow = fs / "etc/shadow"
        if not shadow.is_file():
            issues.append("root account shadow missing from built image")
        else:
            shadow_gate, reason = inspect_root_shadow(shadow.read_text(errors="replace"))
            if shadow_gate != "PASS":
                issues.append("root shadow unsafe: " + reason)
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
            issues.extend(audit_portal_enable_owner_rootfs(fs))
            issues.extend(audit_portal_disable_reporting_rootfs(fs))
            issues.extend(audit_captive_mutation_rootfs(fs))
            issues.extend(audit_captive_noredirect_rootfs(fs))
            issues.extend(audit_capport_tls_gate_rootfs(fs))
            issues.extend(audit_captive_disabled_authorization_rootfs(fs))
            issues.extend(audit_captive_commit_rootfs(fs))
            issues.extend(audit_wp_ack_receipt_rootfs(fs))
            issues.extend(audit_captive_rebind_rootfs(fs))
            issues.extend(audit_captive_revoke_rootfs(fs))
        return {
            "phase": "EXPERIMENTAL_APP_PACKAGE_OFFLINE_ROOTFS_AUDIT",
            "static_gate": "BLOCK" if issues else "PASS",
            "release_approval": "BLOCK",
            "device_wifi_tested": False,
            "portal_runtime_tested": False,
            "device_recovery_tested": False,
            "files_checked": len(REQUIRED_FILES),
            "found_files": len(REQUIRED_FILES) - len(missing),
            "root_shadow_gate": (
                inspect_root_shadow(shadow.read_text(errors="replace"))[0]
                if shadow.is_file() else "BLOCK"
            ),
            "root_login_tested": False,
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
