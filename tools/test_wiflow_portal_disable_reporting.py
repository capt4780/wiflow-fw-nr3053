"""Host-executed regression for explicit remote Portal disable failure reporting.

Exercises production heartbeat functions with fake UCI/firewall. Not target E5.
"""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

from audit_nr3053_wiflow_image import audit_portal_disable_reporting_rootfs

ROOT = Path(__file__).resolve().parents[1]
HEARTBEAT = (ROOT / "package/wiflow-setup/files/usr/lib/wiflow/heartbeat-loop").read_text()
FIREWALL = (ROOT / "package/wiflow-setup/files/usr/lib/wiflow/portal-firewall").read_text()


def production_firewall_disable():
    start = FIREWALL.index("captive_nft_objects_present(){")
    end = FIREWALL.index("\ncase \"$MODE\" in", start)
    return FIREWALL[start:end].replace("/usr/sbin/nft", "nft_test").replace(
        "/etc/init.d/firewall reload", "firewall_reload_test"
    )



def production_functions():
    start = HEARTBEAT.index("portal_runtime_set_enabled(){")
    end = HEARTBEAT.index("\ndelay=20", start)
    return HEARTBEAT[start:end].replace(
        "/usr/lib/wiflow/portal-firewall", "firewall_test"
    ).replace("/usr/lib/wiflow/portal-sync", "sync_test")


class ExplicitPortalDisableReportingTests(unittest.TestCase):
    def probe(self, *, initial=1, fail_commit=False, fail_firewall=False):
        with tempfile.TemporaryDirectory(prefix="wiflow-disable-state-") as tmp:
            root = Path(tmp)
            state = root / "enabled"
            state.write_text(str(initial))
            marker = root / "ack"
            marker.write_text("27")
            log = root / "events"
            script = (
                'PORTAL_ACK_CONFIRMED="$TEST_MARKER"\n'
                'uci(){\n'
                ' case "$1" in\n'
                '  -q) if [ "$2" = get ]; then cat "$TEST_STATE"; fi;;\n'
                '  set) printf "%s\\n" "${2##*=}" > "$TEST_STATE"; '
                'printf "uci_set\\n" >> "$TEST_LOG";;\n'
                '  commit) [ "$FAIL_COMMIT" = 0 ];;\n'
                ' esac\n'
                '}\n'
                'state_set(){ printf "error:%s\\n" "$2" >> "$TEST_LOG"; }\n'
                'firewall_test(){ printf "firewall:%s\\n" "$1" >> "$TEST_LOG"; '
                '[ "$FAIL_FIREWALL" = 0 ]; }\n'
                'sync_test(){ return 0; }\n'
                + production_functions()
                + '\nportal_runtime_reconcile 0 0 27\n'
            )
            result = subprocess.run(
                ["sh", "-c", script], capture_output=True, text=True,
                timeout=5, env={**os.environ, "TEST_STATE": str(state),
                                "TEST_MARKER": str(marker), "TEST_LOG": str(log),
                                "FAIL_COMMIT": "1" if fail_commit else "0",
                                "FAIL_FIREWALL": "1" if fail_firewall else "0"},
            )
            self.assertEqual(result.stderr, "")
            self.assertFalse(marker.exists(), "remote disable must invalidate ACK")
            return result.returncode, state.read_text(), (
                log.read_text().splitlines() if log.exists() else [])

    def test_remote_disable_success_is_reported_success(self):
        code, value, log = self.probe()
        self.assertEqual(code, 0)
        self.assertEqual(value, "0\n")
        self.assertEqual(log, ["uci_set", "firewall:disable"])

    def test_firewall_disable_failure_is_not_silent_success(self):
        code, value, log = self.probe(fail_firewall=True)
        self.assertNotEqual(code, 0)
        self.assertEqual(value, "0\n")
        self.assertIn("error:captive_firewall_disable_failed", log)

    def test_state_persistence_failure_is_not_silent_success(self):
        code, _, log = self.probe(fail_commit=True)
        self.assertNotEqual(code, 0)
        self.assertIn("error:portal_disable_state_commit_failed", log)
        self.assertIn("firewall:disable", log)

    def test_both_failures_are_observable(self):
        code, _, log = self.probe(fail_commit=True, fail_firewall=True)
        self.assertNotEqual(code, 0)
        self.assertIn("error:portal_disable_state_commit_failed", log)
        self.assertIn("error:captive_firewall_disable_failed", log)

    def test_already_disabled_does_not_rewrite_flash(self):
        code, value, log = self.probe(initial=0)
        self.assertEqual(code, 0)
        self.assertEqual(value, "0")
        self.assertEqual(log, ["firewall:disable"])

    def exercise_firewall_disable(self, *, orphan=False, rules=False,
                                  table_ok=True, reload_ok=True, stale_after_reload=False):
        with tempfile.TemporaryDirectory(prefix="wiflow-firewall-disable-") as tmp:
            base = Path(tmp)
            if orphan:
                (base / "orphan").touch()
            if rules:
                (base / "captive.nft").write_text("test")
            script = r'''
NFT_FILE="$TEST_ROOT/captive.nft"
uci(){
 case "$1" in
 -q) return 1 ;;
 commit) echo commit >> "$TEST_ROOT/log"; return 0 ;;
 esac
 return 0
}
nft_test(){
 if [ "$1" = list ] && [ "$2" = table ]; then
  [ "$TABLE_OK" = 1 ]; return
 fi
 [ -f "$TEST_ROOT/orphan" ]
}
firewall_reload_test(){
 echo reload >> "$TEST_ROOT/log"
 [ "$RELOAD_OK" = 1 ] || return 1
 [ "$STALE" = 1 ] || rm -f "$TEST_ROOT/orphan"
 return 0
}
state_set(){ echo "error:$2" >> "$TEST_ROOT/log"; }
''' + production_firewall_disable() + '\ndisable\n'
            result = subprocess.run(
                ["sh", "-c", script], capture_output=True, text=True, timeout=8,
                env={**os.environ, "TEST_ROOT": str(base),
                     "TABLE_OK": "1" if table_ok else "0",
                     "RELOAD_OK": "1" if reload_ok else "0",
                     "STALE": "1" if stale_after_reload else "0"},
            )
            log = (base / "log").read_text().splitlines() if (base / "log").exists() else []
            self.assertEqual(result.stderr, "")
            return result.returncode, log

    def test_disable_clean_kernel_and_config_avoids_reloads(self):
        code, log = self.exercise_firewall_disable()
        self.assertEqual(code, 0)
        self.assertEqual(log, [])

    def test_disable_detects_orphaned_live_nft_state_after_config_deletion(self):
        code, log = self.exercise_firewall_disable(orphan=True)
        self.assertEqual(code, 0)
        self.assertEqual(log, ["commit", "reload"])

    def test_disable_live_rule_unchanged_by_reload_is_not_reported_success(self):
        code, log = self.exercise_firewall_disable(orphan=True, stale_after_reload=True)
        self.assertNotEqual(code, 0)
        self.assertIn("error:captive_disable_stale_nft_state", log)

    def test_disable_unqueryable_nft_state_is_not_reported_success(self):
        code, log = self.exercise_firewall_disable(table_ok=False)
        self.assertNotEqual(code, 0)
        self.assertIn("error:captive_disable_nft_unavailable", log)

    def test_disable_firewall_reload_failure_propagates(self):
        code, log = self.exercise_firewall_disable(orphan=True, reload_ok=False)
        self.assertNotEqual(code, 0)
        self.assertIn("error:captive_disable_reload_failed", log)

    def test_disable_config_deletion_requires_firewall_reload(self):
        code, log = self.exercise_firewall_disable(rules=True)
        self.assertEqual(code, 0)
        self.assertEqual(log, ["commit", "reload"])

    def test_exact_image_audit_rejects_swallowed_failure(self):
        with tempfile.TemporaryDirectory(prefix="wiflow-disable-image-") as tmp:
            path = Path(tmp) / "usr/lib/wiflow/heartbeat-loop"
            path.parent.mkdir(parents=True)
            path.write_text(HEARTBEAT)
            self.assertEqual(audit_portal_disable_reporting_rootfs(Path(tmp)), [])
            path.write_text(HEARTBEAT.replace(
                "state_set portal_error 'captive_firewall_disable_failed'",
                ": # swallowed firewall disable failure", 1))
            self.assertTrue(audit_portal_disable_reporting_rootfs(Path(tmp)))
            path.write_text(HEARTBEAT.replace(
                '  portal_runtime_disable\n  return $?',
                '  portal_runtime_disable\n  return 0', 1))
            self.assertTrue(audit_portal_disable_reporting_rootfs(Path(tmp)))


if __name__ == "__main__":
    unittest.main()
