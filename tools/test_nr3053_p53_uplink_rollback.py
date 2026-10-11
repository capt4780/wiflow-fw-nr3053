"""P53: safeguard recovery on the user's single NR3053 router (host only)."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
UPLINK = ROOT / "package/wiflow-setup/files/usr/lib/wiflow/apply-uplink"


class UplinkRollbackSafetyTests(unittest.TestCase):
    def test_pending_backup_is_never_overwritten(self):
        text = UPLINK.read_text()
        self.assertIn('[ ! -e "$UPLINK_TXN/.pending" ]', text)
        with tempfile.TemporaryDirectory(prefix="wiflow-p53-") as tmp:
            backup = Path(tmp) / "txn"
            backup.mkdir()
            (backup / ".pending").write_text("")
            (backup / "network").write_text("original configuration\n")
            function = text[text.index("backup_configs(){"):text.index("cleanup_backups(){")]
            script = (
                f'UPLINK_TXN="{backup}"\n'
                'command_id=""\ncommand_action=""\n'
                'cp(){ return 99; }\n'  # must not even be reached
                + function + '\n'
                + 'backup_configs\n'
            )
            proc = subprocess.run(["sh"], input=script, text=True, capture_output=True)
            self.assertNotEqual(proc.returncode, 0)
            self.assertEqual((backup / "network").read_text(), "original configuration\n")
            self.assertTrue((backup / ".pending").exists())

    def test_failed_restore_keeps_all_backups_and_reports_failure(self):
        text = UPLINK.read_text()
        self.assertIn('if restore_configs; then\n        cleanup_backups\n    else', text)
        self.assertIn('code=rollback_failed', text)
        with tempfile.TemporaryDirectory(prefix="wiflow-p53-") as tmp:
            backup = Path(tmp) / "txn"
            backup.mkdir()
            for name in ("wireless", "wiflow", "network", ".pending"):
                (backup / name).write_text(f"saved {name}\n")
            functions = text[text.index("cleanup_backups(){"):text.index("succeed(){")]
            script = (
                f'UPLINK_TXN="{backup}"\n'
                'req="/nonexistent/request"\nold_radio=""\nradio=""\n'
                'cp(){ return 1; }\n'
                + functions + '\n'
                + 'cleanup_request(){ :; }\n'
                + 'state_set(){ printf "%s=%s\\n" "$1" "$2"; }\n'
                + 'finish_command(){ :; }\n'
                + 'fail original_error "original failure"\n'
            )
            proc = subprocess.run(["sh"], input=script, text=True, capture_output=True)
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn("job_error=rollback_failed", proc.stdout)
            self.assertIn("Không khôi phục được", proc.stdout)
            for name in ("wireless", "wiflow", "network", ".pending"):
                self.assertTrue((backup / name).exists(), name)

    def test_shell_parses_and_network_reload_must_succeed(self):
        text = UPLINK.read_text()
        self.assertIn(
            '/etc/init.d/network reload >/dev/null 2>&1 || return 1', text
        )
        proc = subprocess.run(["sh", "-n", str(UPLINK)], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)


if __name__ == "__main__":
    unittest.main()
