"""Execute actual NR3053 firstboot Portal state owner under host UCI/firewall mocks.

Evidence is production shell fragment behavior, not physical NR3053 or nft E5.
"""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

from audit_nr3053_wiflow_image import audit_bootstrap_remote_disable_rootfs

ROOT = Path(__file__).resolve().parents[1]
BOOTSTRAP = (ROOT / "package/wiflow-setup/files/usr/lib/wiflow/bootstrap").read_text()


def production_boot_portal():
    begin = BOOTSTRAP.index('saved_portal_enabled="$(uci -q get wiflow.core.portal_enabled')
    end = BOOTSTRAP.index("\nuplink_radio=", begin)
    return BOOTSTRAP[begin:end].replace("/usr/lib/wiflow/portal-firewall", "firewall_test")


class BootPortalRemoteEnableTests(unittest.TestCase):
    def run_case(self, *, flag, snapshot=True, firewall_ok=True, commit_ok=True):
        with tempfile.TemporaryDirectory(prefix="wiflow-bootstrap-owner-") as tmp:
            root = Path(tmp)
            active = root / "active"
            active.mkdir()
            if snapshot:
                (active / "portal.json").write_text('{"schema":2,"revision":27}')
            (root / "state").write_text(str(flag))
            script = r'''
PORTAL_ACTIVE="$TEST_ROOT/active"
uci(){
 case "$1" in
  -q) [ "$2" = get ] && { cat "$TEST_ROOT/state"; return 0; } ;;
  set) printf "%s\n" "$2" | sed 's/^[^=]*=//' | tr -d "'" > "$TEST_ROOT/state"
       printf "set:%s\n" "$2" >> "$TEST_ROOT/log"; return 0 ;;
  commit) printf "commit:%s\n" "$2" >> "$TEST_ROOT/log"
          [ "$COMMIT_OK" = 1 ]; return ;;
 esac
 return 1
}
firewall_test(){ printf "firewall:%s\n" "$1" >> "$TEST_ROOT/log"
                 [ "$FIREWALL_OK" = 1 ]; }
log(){ printf "log:%s\n" "$1" >> "$TEST_ROOT/log"; }
''' + production_boot_portal()
            result = subprocess.run(
                ["sh", "-c", script], capture_output=True, text=True, timeout=6,
                env={**os.environ, "TEST_ROOT": str(root),
                     "FIREWALL_OK": "1" if firewall_ok else "0",
                     "COMMIT_OK": "1" if commit_ok else "0"},
            )
            self.assertEqual(result.stderr, "")
            calls = (root / "log").read_text().splitlines() if (root / "log").exists() else []
            return result.returncode, (root / "state").read_text().strip(), calls

    def test_disabled_with_cached_snapshot_remains_disabled_after_boot(self):
        code, flag, calls = self.run_case(flag=0, snapshot=True)
        self.assertEqual(code, 0)
        self.assertEqual(flag, "0")
        self.assertEqual(calls, ["firewall:disable"])

    def test_enabled_with_cached_snapshot_keeps_local_portal_while_wp_offline(self):
        code, flag, calls = self.run_case(flag=1, snapshot=True)
        self.assertEqual(code, 0)
        self.assertEqual(flag, "1")
        self.assertEqual(calls, ["firewall:ensure"])

    def test_missing_snapshot_with_stale_enable_is_persistently_closed(self):
        code, flag, calls = self.run_case(flag=1, snapshot=False)
        self.assertEqual(code, 0)
        self.assertEqual(flag, "0")
        self.assertEqual(calls, ["set:wiflow.core.portal_enabled=0",
                                 "commit:wiflow", "firewall:disable"])

    def test_already_disabled_without_snapshot_does_not_rewrite_flash(self):
        code, flag, calls = self.run_case(flag=0, snapshot=False)
        self.assertEqual(code, 0)
        self.assertEqual(flag, "0")
        self.assertEqual(calls, ["firewall:disable"])

    def test_unset_portal_flag_is_not_implicitly_enabled_by_cached_snapshot(self):
        code, flag, calls = self.run_case(flag="", snapshot=True)
        self.assertEqual(code, 0)
        self.assertEqual(flag, "0")
        self.assertEqual(calls, ["set:wiflow.core.portal_enabled=0",
                                 "commit:wiflow", "firewall:disable"])

    def test_disabled_firewall_failure_is_visible_to_bootstrap_log(self):
        code, flag, calls = self.run_case(flag=0, snapshot=True, firewall_ok=False)
        self.assertEqual(code, 0)
        self.assertEqual(flag, "0")
        self.assertIn("log:Captive portal firewall could not be disabled", calls)

    def test_exact_image_auditor_accepts_current_bootstrap(self):
        with tempfile.TemporaryDirectory(prefix="wiflow-image-bootstrap-") as tmp:
            file = Path(tmp) / "usr/lib/wiflow/bootstrap"
            file.parent.mkdir(parents=True)
            file.write_text(BOOTSTRAP)
            self.assertEqual(audit_bootstrap_remote_disable_rootfs(Path(tmp)), [])

    def test_compiled_rootfs_audit_blocks_reenabled_cached_snapshot(self):
        with tempfile.TemporaryDirectory(prefix="wiflow-image-bootstrap-") as tmp:
            file = Path(tmp) / "usr/lib/wiflow/bootstrap"
            file.parent.mkdir(parents=True)
            file.write_text(BOOTSTRAP)
            damaged = BOOTSTRAP.replace(
                'saved_portal_enabled="$(uci -q get wiflow.core.portal_enabled 2>/dev/null || true)"',
                "saved_portal_enabled=1",
            )
            self.assertNotEqual(damaged, BOOTSTRAP)
            file.write_text(damaged)
            self.assertTrue(audit_bootstrap_remote_disable_rootfs(Path(tmp)))

    def test_compiled_rootfs_audit_blocks_unconditional_boot_enable(self):
        with tempfile.TemporaryDirectory(prefix="wiflow-image-bootstrap-") as tmp:
            file = Path(tmp) / "usr/lib/wiflow/bootstrap"
            file.parent.mkdir(parents=True)
            damaged = BOOTSTRAP.replace(
                'if [ "$saved_portal_enabled" = 1 ] && [ -f "$PORTAL_ACTIVE/portal.json" ]; then',
                'if [ -f "$PORTAL_ACTIVE/portal.json" ]; then',
            )
            file.write_text(damaged)
            self.assertTrue(audit_bootstrap_remote_disable_rootfs(Path(tmp)))


if __name__ == "__main__":
    unittest.main()
