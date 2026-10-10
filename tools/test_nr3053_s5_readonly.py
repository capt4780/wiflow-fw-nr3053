"""Host-fixture coverage of the actual non-mutating NR3053 S5 evidence script.

Never treats host fixtures as E5 device verification or release permission.
"""
from pathlib import Path
import os
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools/nr3053-s5-readonly.sh"

MOCKS = {
    "ip": r"""#!/bin/sh
case "$*" in
 *br-lan*) echo '7: br-lan inet 10.0.0.1/24 brd 10.0.0.255'; echo '7: br-lan inet 10.0.0.2/32';;
 *br-wiflow*) [ "$MOCK_GUEST_MISSING" = 1 ] || echo '9: br-wiflow inet 10.10.10.1/24';;
esac
""",
    "uci": r"""#!/bin/sh
case "$*" in
 *wiflow.core.portal_enabled*) printf '%s\n' "$MOCK_ENABLED";;
 *) exit 1;;
esac
""",
    "nft": r"""#!/bin/sh
case "$*" in
 *wiflow_portal_forward*)
  echo 'ip saddr . ether saddr @wiflow_portal_authed return'
  echo 'ip saddr 10.10.10.0/24 tcp dport 853 accept'
  [ "$MOCK_NFT_BAD" = 1 ] || echo 'ip saddr 10.10.10.0/24 reject';;
 *wiflow_portal_prerouting*)
  echo 'ip saddr 10.10.10.0/24 ip daddr 10.0.0.1 return'
  echo 'ip saddr 10.10.10.0/24 ip daddr 10.0.0.2 return'
  echo 'ip saddr 10.10.10.0/24 tcp dport 80 redirect to :2080';;
 *wiflow_portal_authed*|*wiflow_portal_granted*) exit 0;;
 *) exit 1;;
esac
""",
    "iw": r"""#!/bin/sh
echo 'Interface phy0-ap0'
echo 'channel 6 (2437 MHz), width: 20 MHz'
if [ "$MOCK_NO_5G" != 1 ]; then
 echo 'Interface phy1-ap0'
 echo 'channel 36 (5180 MHz), width: 80 MHz'
fi
""",
    "jsonfilter": r"""#!/bin/sh
case "$*" in
 *'@.schema'*) echo 2;;
 *'@.data_generation'*) echo 4;;
 *'@.revision'*) echo 7;;
 *'@.mode'*) echo image;;
 *'@.board_name'*) echo 'viettel,nr3053';;
 *) exit 1;;
esac
""",
}


class S5ReadonlyEvidenceTests(unittest.TestCase):
    def fixture(self, *, enabled="1", board="viettel,nr3053", snapshot=True,
                nft_bad=False, no_5g=False, guest_missing=False):
        with tempfile.TemporaryDirectory(prefix="wiflow-nr3053-s5-") as temp:
            home = Path(temp)
            root = home / "root"
            bindir = home / "mockbin"
            bindir.mkdir()
            board_dir = root / "tmp/sysinfo"
            board_dir.mkdir(parents=True)
            (board_dir / "board_name").write_text(board)
            for filename, data in MOCKS.items():
                stub = bindir / filename
                stub.write_text(data)
                stub.chmod(0o755)
            for p in ("www-wiflow/cgi-bin/gate",
                      "www-wiflow-luci-gate/cgi-bin/unlock",
                      "www-wiflow-portal/cgi-bin/portal"):
                target = root / p
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text("fixture")
            if snapshot:
                portal = root / "www-wiflow-portal/runtime"
                rev = portal / "revisions/rev-7"
                rev.mkdir(parents=True)
                (rev / "portal.json").write_text(
                    '{"schema":2,"data_generation":4,"revision":7,"mode":"image"}'
                )
                (portal / "active").symlink_to("revisions/rev-7")
            before = sorted(str(p.relative_to(root)) for p in root.rglob("*"))
            proc = subprocess.run(
                ["sh", str(SCRIPT)],
                cwd=temp, capture_output=True, text=True, timeout=8,
                env={**os.environ, "PATH": str(bindir) + ":/usr/bin:/bin",
                     "WIFLOW_S5_TEST_ROOT": str(root),
                     "MOCK_ENABLED": enabled,
                     "MOCK_NFT_BAD": "1" if nft_bad else "0",
                     "MOCK_NO_5G": "1" if no_5g else "0",
                     "MOCK_GUEST_MISSING": "1" if guest_missing else "0"},
            )
            after = sorted(str(p.relative_to(root)) for p in root.rglob("*"))
            self.assertEqual(before, after, "read-only collector mutated fixture")
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertEqual(proc.stderr, "")
            report = {}
            for record in proc.stdout.splitlines():
                key, status, detail = record.split("|")
                self.assertNotIn(key, report, "duplicate report row")
                self.assertRegex(key, r"^[a-z][a-z0-9_]*$")
                self.assertRegex(detail, r"^[A-Za-z0-9_]+$")
                report[key] = status
            self.assertEqual(report["context"], "INFO")
            self.assertIn("HOST_FIXTURE_NOT_DEVICE", proc.stdout)
            self.assertEqual(report["e5_complete"], "BLOCK")
            self.assertEqual(report["flash_authorization"], "BLOCK")
            self.assertEqual(report["physical_recovery"], "NOT_VERIFIED")
            for secret in ("WIFDIDNR3053", "root:1234", "SECRET_TEST_TOKEN",
                           "XX:AA:11:00:00:00"):
                self.assertNotIn(secret, proc.stdout)
            return report

    def test_complete_host_fixture_never_becomes_e5_or_flash_pass(self):
        x = self.fixture()
        for key in ("target_board", "setup_address", "luci_gate_address",
                    "guest_gateway", "setup_gate", "luci_gate",
                    "portal_handler", "portal_snapshot", "captive_forward",
                    "captive_redirect", "captive_sets", "private_dns_rule",
                    "radio_2g_channel", "radio_5g_channel"):
            with self.subTest(key=key):
                self.assertEqual(x[key], "PASS")
        self.assertEqual(x["wordpress_sync_roundtrip"], "NOT_TESTED")
        self.assertEqual(x["guest_pre_post_authorization"], "NOT_TESTED")

    def test_wrong_board_never_passes_board_gate(self):
        self.assertEqual(self.fixture(board="other,board")["target_board"], "BLOCK")

    def test_missing_captive_snapshot_is_blocked_when_enabled(self):
        self.assertEqual(self.fixture(snapshot=False)["portal_snapshot"], "BLOCK")

    def test_disabled_portal_skips_active_firewall_introspection(self):
        x = self.fixture(enabled="0", snapshot=False, nft_bad=True)
        for key in ("captive_forward", "captive_redirect",
                    "captive_sets", "private_dns_rule"):
            self.assertEqual(x[key], "SKIP")

    def test_guest_forward_deny_rule_is_required(self):
        self.assertEqual(self.fixture(nft_bad=True)["captive_forward"], "BLOCK")

    def test_missing_guest_gateway_and_5ghz_are_not_falsely_passed(self):
        x = self.fixture(no_5g=True, guest_missing=True)
        self.assertEqual(x["radio_2g_channel"], "PASS")
        self.assertEqual(x["radio_5g_channel"], "WARN")
        self.assertEqual(x["guest_gateway"], "WARN")

    def test_only_allowed_device_read_apis_and_no_credential_access(self):
        source = SCRIPT.read_text()
        for pattern in (
            r"(?m)^\s*(?:sysupgrade|mtd|reboot|firstboot|passwd)\b",
            r"(?m)^\s*uci\s+(?:set|commit|delete)\b",
            r"(?m)^\s*nft\s+(?:add|delete|flush|insert)\b",
            r"/etc/shadow", r"device_token", r"X-Wiflow-Device-Token",
            r"(?m)^\s*(?:curl|wget|uclient-fetch|ssh|telnet)\b",
        ):
            with self.subTest(pattern=pattern):
                self.assertIsNone(re.search(pattern, source))
        self.assertIn("report flash_authorization BLOCK", source)
        self.assertIn("report running_firmware_provenance NOT_ATTESTED", source)


if __name__ == "__main__":
    unittest.main()
