"""P54 integration checks: P51 survey safety, P52 evidence, P53 rollback."""
from pathlib import Path
import ast
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "scripts/build-nr3053-base.sh"
API = ROOT / "package/wiflow-setup/files/www-wiflow/cgi-bin/api"
UPLINK = ROOT / "package/wiflow-setup/files/usr/lib/wiflow/apply-uplink"
DIAG = ROOT / "package/wiflow-setup/files/usr/lib/wiflow/network-diagnostics"


class P54IntegrationTests(unittest.TestCase):
    def test_build_guard_rejects_corrupt_mt_wifi_survey(self):
        script = BUILD.read_text()
        self.assertIn('!strstr(pos, "BSSID ")', script)
        self.assertIn('!strstr(pos, "SSID_Len")', script)
        self.assertIn('(size_t)ssid_len > sizeof(e->ssid)', script)
        self.assertIn('MTK SiteSurvey column mapping changed', script)
        self.assertIn('MTK SiteSurvey SSID length parse changed', script)
        here = script.split("python3 - <<'PY'\n", 1)[1].split("\nPY", 1)[0]
        ast.parse(here)

    def test_p51_p52_p53_present_together(self):
        self.assertIn('code":"WIFI_SCAN_FAILED"', API.read_text())
        self.assertIn("diagnostics)", API.read_text())
        self.assertIn("network-diagnostics", API.read_text())
        self.assertTrue(DIAG.is_file())
        self.assertIn('code=rollback_failed', UPLINK.read_text())
        self.assertIn('[ ! -e "$UPLINK_TXN/.pending" ]', UPLINK.read_text())
        for script in (API, UPLINK, DIAG):
            with self.subTest(script=script.name):
                check = subprocess.run(["sh", "-n", str(script)], capture_output=True, text=True)
                self.assertEqual(check.returncode, 0, check.stderr)


if __name__ == "__main__":
    unittest.main()
