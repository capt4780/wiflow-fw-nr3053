"""Static guards: sync loop backs off when WordPress is unreachable; no unused iw dependency."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
LOOP = (ROOT / "package/wiflow-setup/files/usr/lib/wiflow/portal-mode-loop").read_text()
MK = (ROOT / "package/wiflow-setup/Makefile").read_text()


class SyncBackoffTests(unittest.TestCase):
    def test_backoff_present_and_capped(self):
        self.assertIn("delay=2", LOOP)
        self.assertIn("delay=$((delay * 2))", LOOP)
        self.assertIn('[ "$delay" -le 30 ] || delay=30', LOOP)
        self.assertIn('sleep "$delay"', LOOP)

    def test_success_resets_delay(self):
        self.assertIn('/sync" >/dev/null 2>&1; then\n   delay=2', LOOP)

    def test_iw_dependency_removed(self):
        dep = [l for l in MK.splitlines() if "DEPENDS:=" in l][0]
        self.assertNotIn("+iw ", dep + " ")
        self.assertIn("+mtwifi-cfg-ucode", dep)


if __name__ == "__main__":
    unittest.main()
