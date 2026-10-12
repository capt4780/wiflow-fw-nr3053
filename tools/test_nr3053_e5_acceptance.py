"""The E5 acceptance script must exist, parse, and never change router state."""
from pathlib import Path
import re
import subprocess
import unittest

SCRIPT = Path(__file__).resolve().parent / "nr3053-e5-acceptance.sh"
FORBIDDEN = [r"\buci (set|add|add_list|del_list|delete|commit)\b", r"\bnft (add|delete|flush|-f)\b",
             r"\bifup\b", r"\bifdown\b", r"\bwifi (reload|up|down)\b", r"/etc/init\.d/",
             r"\breboot\b", r"\brm -rf\b", r"\bsysupgrade\b", r"\bmtd\b", r">\s*/etc/"]


class E5AcceptanceTests(unittest.TestCase):
    def test_syntax(self):
        self.assertEqual(subprocess.run(["sh", "-n", str(SCRIPT)]).returncode, 0)

    def test_read_only(self):
        text = SCRIPT.read_text()
        for pat in FORBIDDEN:
            self.assertIsNone(re.search(pat, text), pat)

    def test_covers_three_goals_and_is_not_flash_approval(self):
        text = SCRIPT.read_text()
        for needle in ("== 1. Uplink ==", "== 2. WordPress API ==", "== 3. Captive portal ==",
                       "NOT FLASH APPROVAL", "wiflow_portal_prerouting", "$WIFLOW_DEVICE_API/health",
                       "wifi_uplink_associated", "radio_scan_ifname"):
            self.assertIn(needle, text)

    def test_exit_status_reflects_failures(self):
        self.assertIn('[ "$fail" -eq 0 ]', SCRIPT.read_text().rstrip().splitlines()[-1])


if __name__ == "__main__":
    unittest.main()
