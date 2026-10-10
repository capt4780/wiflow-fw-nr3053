"""Guest subnet may reach ONLY the gated management entrypoints.

Host regression test: verifies source configuration and the actual shared gate
verifier with a guest client address. This does NOT prove packet-level firewall
behavior on a physical NR3053.
"""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

from audit_nr3053_wiflow_image import audit_guest_gate_rootfs

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "package/wiflow-setup/files"
COMMON = SRC / "usr/lib/wiflow/common.sh"
PORTAL = SRC / "usr/lib/wiflow/portal-firewall"
BOOT = SRC / "usr/lib/wiflow/bootstrap"
LUCIGATE = SRC / "www-wiflow-luci-gate/cgi-bin/unlock"
SETUPGATE = SRC / "www-wiflow/cgi-bin/gate"
VERIFIER = SRC / "usr/lib/wiflow/gate-code.sh"
ENROLL = SRC / "www-wiflow/cgi-bin/enroll"
LUCINFT = SRC / "usr/share/nftables.d/chain-pre/input/25-wiflow-luci-gate.nft"


class GuestManagementGateTests(unittest.TestCase):
    def test_guest_allowed_to_both_gate_pages_only(self):
        net = COMMON.read_text()
        for setting in (
            "uci set firewall.wiflow_guest.input='REJECT'",
            "uci set firewall.wiflow_guest_setup.dest_ip='10.0.0.1'",
            "uci set firewall.wiflow_guest_setup.dest_port='80'",
            "uci set firewall.wiflow_guest_setup.target='ACCEPT'",
            "uci set firewall.wiflow_guest_gate.dest_ip='10.0.0.2'",
            "uci set firewall.wiflow_guest_gate.dest_port='80'",
            "uci set firewall.wiflow_guest_gate.target='ACCEPT'",
            "uci set firewall.wiflow_guest_setup.src='wiflow_guest'",
            "uci set firewall.wiflow_guest_gate.src='wiflow_guest'",
        ):
            with self.subTest(setting=setting):
                self.assertIn(setting, net)
        self.assertNotIn("uci set firewall.wiflow_guest_setup.dest_port='8081'", net)
        self.assertNotIn("uci set firewall.wiflow_guest_gate.dest_port='8081'", net)

    def test_guest_captive_redirect_excludes_gate_targets(self):
        captive = PORTAL.read_text()
        for dest in ("10.0.0.1", "10.0.0.2"):
            self.assertIn(f"ip saddr 10.10.10.0/24 ip daddr {dest} return", captive)
        self.assertIn("ip saddr 10.10.10.0/24 tcp dport 80 redirect to :2080", captive)

    def test_luci_true_backend_remains_guarded(self):
        nft = LUCINFT.read_text().splitlines()
        self.assertEqual(len(nft), 2, "unreviewed changes to LuCI input policy")
        self.assertEqual(nft[0],
            "ip daddr 10.0.0.2 tcp dport 8081 ip saddr @wiflow_luci_allowed4 accept")
        self.assertEqual(nft[1], "ip daddr 10.0.0.2 tcp dport 8081 drop")
        unlock = LUCIGATE.read_text()
        self.assertIn('wiflow_gate_code_allowed "$pin" "$want"', unlock)
        self.assertIn('nft add element inet fw4 wiflow_luci_allowed4', unlock)
        self.assertIn('timeout 20m', unlock)
        self.assertIn("redirect 'http://10.0.0.2:8081/cgi-bin/luci/'", unlock)
        boot = BOOT.read_text()
        self.assertIn("uci add_list uhttpd.main.listen_http='10.0.0.2:8081'", boot)
        self.assertIn("uci add_list uhttpd.wiflow_luci_gate.listen_http='10.0.0.2:80'", boot)
        self.assertIn("uci add_list uhttpd.wiflow.listen_http='10.0.0.1:80'", boot)
        self.assertIn("uci add_list uhttpd.wiflow_portal.listen_http='10.10.10.1:2080'", boot)

    def test_guest_device_pin_can_pass_shared_gate(self):
        verifier = VERIFIER.read_text()
        for ip in ("10.10.10.100", "10.10.10.249"):
            run = subprocess.run(
                ["sh", "-c", verifier + '\nwiflow_gate_code_allowed "$ENTERED" "$PIN"'],
                env={**os.environ, "REMOTE_ADDR": ip, "ENTERED": "221262", "PIN": "221262"},
                capture_output=True, text=True, timeout=5)
            self.assertEqual(run.returncode, 0, f"{ip}: {run.stderr}")
        self.assertIn("wiflow_gate_code_allowed", SETUPGATE.read_text())
        self.assertIn("wiflow_gate_code_allowed", LUCIGATE.read_text())

    def test_guest_emergency_code_passes_both_shared_gate_handlers(self):
        verifier = VERIFIER.read_text(encoding="utf-8")
        for ip in ("10.10.10.12", "10.10.10.100", "10.10.10.249"):
            for entered in ("WIFDIDNR3053", "221262"):
                with self.subTest(ip=ip, entered=entered):
                    r = subprocess.run(
                        ["sh", "-c",
                         verifier + '\nwiflow_gate_code_allowed "$ENTERED" "$PIN"'],
                        env={**os.environ, "REMOTE_ADDR": ip,
                             "ENTERED": entered, "PIN": "221262"},
                        capture_output=True, text=True, timeout=5,
                    )
                    self.assertEqual(r.returncode, 0, r.stderr)
        for handler in (SETUPGATE, LUCIGATE):
            script = handler.read_text(encoding="utf-8")
            self.assertIn('. /usr/lib/wiflow/gate-code.sh', script)
            self.assertIn('wiflow_gate_code_allowed "$pin" "$want"', script)
            self.assertIn('[ "${REQUEST_METHOD:-}" = POST ]', script)

    def test_public_emergency_does_not_expose_direct_luci_backend(self):
        self.test_luci_true_backend_remains_guarded()
        self.assertIn('check_gate_session', ENROLL.read_text(encoding="utf-8"))
        self.assertIn('setup_set_login', ENROLL.read_text(encoding="utf-8"))

    def test_guest_first_enrollment_keeps_gate_and_origin_protection(self):
        enroll = ENROLL.read_text()
        auth = 'check_gate_session >/dev/null 2>&1 || redirect \'/\''
        origin = '[ "${HTTP_ORIGIN:-}" = \'http://10.0.0.1\' ]'
        allow = next(
            line for line in enroll.splitlines()
            if 'case "${REMOTE_ADDR:-}" in' in line
        )
        self.assertIn('10.0.0.*|10.10.10.*)', allow)
        self.assertLess(enroll.index(auth), enroll.index(origin))
        self.assertLess(enroll.index(origin), enroll.index(allow))
        self.assertLess(enroll.index(allow), enroll.index('lock=/tmp/wiflow-setup-enrollment.lock'))
        self.assertIn('[ -z "$current" ] || redirect \'/login.html\'', enroll)
        self.assertIn('setup_set_login "$u" "$p"', enroll)
        for addr in ("10.0.0.2", "10.10.10.100", "10.10.10.249"):
            with self.subTest(client=addr):
                trial = subprocess.run(
                    ["sh", "-c", 'redirect(){ exit 55; }; ' + allow],
                    env={**os.environ, "REMOTE_ADDR": addr},
                    capture_output=True, text=True, timeout=5,
                )
                self.assertEqual(trial.returncode, 0, trial.stderr)
        for addr in ("192.168.1.10", "10.10.11.100", "8.8.8.8", ""):
            with self.subTest(client=addr):
                trial = subprocess.run(
                    ["sh", "-c", 'redirect(){ exit 55; }; ' + allow],
                    env={**os.environ, "REMOTE_ADDR": addr},
                    capture_output=True, text=True, timeout=5,
                )
                self.assertEqual(trial.returncode, 55, trial.stderr)

    def test_compiled_rootfs_audit_matches_current_guest_gate_source(self):
        self.assertEqual(audit_guest_gate_rootfs(SRC), [])

    def test_compiled_rootfs_audit_blocks_missing_guest_captive_exception(self):
        with tempfile.TemporaryDirectory(prefix="wiflow-guest-audit-") as tmp:
            fake = Path(tmp)
            source_paths = (
                "usr/lib/wiflow/common.sh",
                "usr/lib/wiflow/portal-firewall",
                "usr/lib/wiflow/bootstrap",
                "usr/share/nftables.d/chain-pre/input/25-wiflow-luci-gate.nft",
                "www-wiflow-luci-gate/cgi-bin/unlock",
                "www-wiflow/cgi-bin/gate",
            )
            for rel in source_paths:
                p = fake / rel
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_bytes((SRC / rel).read_bytes())
            captive = fake / "usr/lib/wiflow/portal-firewall"
            captive.write_text(captive.read_text().replace(
                "ip saddr 10.10.10.0/24 ip daddr 10.0.0.2 return", ""))
            issues = audit_guest_gate_rootfs(fake)
            self.assertTrue(any("redirect exception" in x for x in issues), issues)

    def test_rootfs_auditor_rejects_removed_orphan_nft_disable_check(self):
        with tempfile.TemporaryDirectory(prefix="wiflow-disable-rootfs-") as tmp:
            fake = Path(tmp)
            required = (
                "usr/lib/wiflow/common.sh",
                "usr/lib/wiflow/portal-firewall",
                "usr/lib/wiflow/bootstrap",
                "usr/share/nftables.d/chain-pre/input/25-wiflow-luci-gate.nft",
                "www-wiflow-luci-gate/cgi-bin/unlock",
                "www-wiflow/cgi-bin/gate",
            )
            for rel in required:
                path = fake / rel
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes((SRC / rel).read_bytes())
            self.assertEqual(audit_guest_gate_rootfs(fake), [])
            captive = fake / "usr/lib/wiflow/portal-firewall"
            source = captive.read_text()
            for token in ("if captive_nft_objects_present; then changed=1; fi",
                          "state_set portal_error 'captive_disable_stale_nft_state'"):
                with self.subTest(token=token):
                    captive.write_text(source.replace(token, ""))
                    issues = audit_guest_gate_rootfs(fake)
                    self.assertTrue(any("forwarding lifecycle" in issue for issue in issues),
                                    issues)
            captive.write_text(source)

    def test_guest_wan_default_is_fail_closed_without_snapshot(self):
        common = COMMON.read_text()
        scope = common[common.index("ensure_guest_network(){"):
                       common.index("ensure_uplink_network(){")]
        self.assertIn("uci -q delete firewall.wiflow_guest_wan", scope)
        self.assertNotIn("uci set firewall.wiflow_guest_wan='forwarding'", scope)
        self.assertIn("firewall.wiflow_guest_private_dns.dest_port='853'", scope)
        self.assertIn("firewall.wiflow_guest_setup.dest_ip='10.0.0.1'", scope)
        self.assertIn("firewall.wiflow_guest_gate.dest_ip='10.0.0.2'", scope)

    def test_captive_firewall_owns_guest_forwarding_lifecycle(self):
        captive = PORTAL.read_text()
        self.assertIn('[ -f "$PORTAL_ACTIVE/portal.json" ] || { state_set portal_error', captive)
        self.assertIn('uci set firewall.wiflow_guest_wan=\'forwarding\'', captive)
        self.assertIn('uci set firewall.wiflow_guest_wan.src=\'wiflow_guest\'', captive)
        self.assertIn('uci set firewall.wiflow_guest_wan.dest=\'wan\'', captive)
        self.assertIn('[ -f "$PORTAL_ACTIVE/portal.json" ] || { disable; return 1; }', captive)
        self.assertIn('uci -q delete firewall.wiflow_guest_wan', captive)
        self.assertIn('[ "$(uci -q get firewall.wiflow_guest_wan', captive)
        self.assertIn("state_set portal_error 'captive_reload_failed'", captive)
        self.assertIn("state_set portal_error 'captive_chains_missing'", captive)
        self.assertIn("disable || state_set portal_error 'captive_rollback_failed'", captive)
        self.assertIn("! /usr/sbin/nft list chain inet fw4 wiflow_portal_forward", captive)

    def test_no_standalone_ungated_luci_port_in_guest_firewall_rules(self):
        net = COMMON.read_text()
        scoped = net[net.index("ensure_guest_network(){"):net.index("ensure_uplink_network(){")]
        self.assertNotIn("dest_port='8081'", scoped)
        self.assertNotIn("dest_port='443'", scoped)


if __name__ == "__main__":
    unittest.main()
