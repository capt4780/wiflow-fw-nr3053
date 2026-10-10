"""Executed host regressions: Portal mode polling must not undo WP disable.

These tests run the production POSIX shell reconciliation function with fake
UCI/firewall calls. They are not target NR3053 packet-flow verification.
"""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "package/wiflow-setup/files/usr/lib/wiflow/portal-mode-loop").read_text()
HEARTBEAT = (ROOT / "package/wiflow-setup/files/usr/lib/wiflow/heartbeat-loop").read_text()


def production_reconcile():
    start = SOURCE.index("portal_reconcile_local(){")
    end = SOURCE.index("\nwhile true; do", start)
    return SOURCE[start:end].replace(
        "/usr/lib/wiflow/portal-firewall", "firewall_test"
    ).replace("/usr/lib/wiflow/portal-sync", "sync_test")


class PortalEnabledOwnerTests(unittest.TestCase):
    def probe(self, enabled, snapshot=True, desired=27, firewall_ok=True):
        with tempfile.TemporaryDirectory(prefix="wiflow-portal-owner-") as temp:
            base = Path(temp)
            active = base / "active"
            active.mkdir()
            if snapshot:
                (active / "portal.json").write_text('{"revision":27}')
            log = base / "calls.log"
            script = (
                'PORTAL_ACTIVE="$TEST_ACTIVE"\n'
                'uci(){\n'
                ' if [ "$1" = -q ] && [ "$2" = get ]; then\n'
                '  case "$3" in\n'
                '   wiflow.core.portal_revision) echo 27;;\n'
                '   wiflow.core.portal_enabled) echo "$TEST_ENABLED";;\n'
                '  esac\n'
                ' else printf "uci:%s\\n" "$*" >> "$TEST_LOG"; fi\n'
                '}\n'
                'state_set(){ printf "state:%s=%s\\n" "$1" "$2" >> "$TEST_LOG"; }\n'
                'firewall_test(){ printf "firewall:%s\\n" "$1" >> "$TEST_LOG"; '
                '[ "$TEST_FW_OK" = 1 ]; }\n'
                'sync_test(){ printf "sync:%s\\n" "$1" >> "$TEST_LOG"; }\n'
                + production_reconcile()
                + '\nportal_reconcile_local "$TEST_DESIRED"\n'
            )
            result = subprocess.run(
                ["/bin/sh", "-c", script],
                env={**os.environ, "TEST_ACTIVE": str(active),
                     "TEST_LOG": str(log), "TEST_ENABLED": str(enabled),
                     "TEST_DESIRED": str(desired),
                     "TEST_FW_OK": "1" if firewall_ok else "0"},
                capture_output=True, text=True, timeout=5,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            return log.read_text().splitlines() if log.exists() else []

    def test_explicit_wp_disable_with_cached_snapshot_stays_disabled(self):
        self.assertEqual(self.probe(0), ["firewall:disable"])

    def test_disabled_portal_can_stage_new_revision_without_opening_wan(self):
        self.assertEqual(self.probe(0, desired=28),
                         ["sync:28", "firewall:disable"])

    def test_enabled_portal_preserves_cached_snapshot(self):
        self.assertEqual(self.probe(1), ["firewall:ensure"])

    def test_missing_snapshot_must_not_open_forwarding(self):
        self.assertEqual(self.probe(1, snapshot=False),
                         ["firewall:disable", "state:portal_error=snapshot_missing"])

    def test_ensure_failure_reports_error(self):
        self.assertEqual(self.probe(1, firewall_ok=False),
                         ["firewall:ensure",
                          "state:portal_error=captive_firewall_enable_failed"])

    def test_disabled_firewall_failure_reports_error_without_reenable(self):
        self.assertEqual(self.probe(0, firewall_ok=False),
                         ["firewall:disable",
                          "state:portal_error=captive_firewall_disable_failed"])

    def test_only_heartbeat_mutates_enabled_flag(self):
        body = production_reconcile()
        self.assertNotIn("uci set wiflow.core.portal_enabled", body)
        self.assertNotIn("uci commit wiflow", body)
        self.assertIn("portal_runtime_disable()", HEARTBEAT)
        self.assertIn("portal_runtime_set_enabled 0", HEARTBEAT)


if __name__ == "__main__":
    unittest.main()
