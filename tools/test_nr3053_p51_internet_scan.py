"""P51 WiFi source scan and WAN reporting regression tests (host fixtures only)."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCAN = ROOT / "package/wiflow-setup/files/usr/lib/wiflow/scan-wifi"
API = ROOT / "package/wiflow-setup/files/www-wiflow/cgi-bin/api"
JS = ROOT / "package/wiflow-setup/files/www-wiflow/assets/setup-v1.js"
UPLINK = ROOT / "package/wiflow-setup/files/usr/lib/wiflow/apply-uplink"
BUILD = ROOT / "scripts/build-nr3053-base.sh"


class P51Regression(unittest.TestCase):
    def test_upstream_mtk_pointer_size_guarded_repair(self):
        t = BUILD.read_text()
        self.assertIn('mtk_get_scanlist_dump(ifname, index, data, sizeof(data))', t)
        self.assertIn('mtk_get_scanlist_dump(ifname, index, data, data_len)', t)
        self.assertIn('P51_MTK_SURVEY_BUFFER_FIX_STAGED', t)
        self.assertIn('assert s.count(bad) == 1', t)

    def test_no_silent_scanner_success(self):
        t = SCAN.read_text()
        self.assertIn('if ! wait "$p"; then', t)
        self.assertIn('exit 4', t)
        self.assertIn('[ "$found_radio" -eq 1 ] || exit 3', t)
        self.assertIn('cat "$out.uniq"', t)
        self.assertNotIn('/tmp/wiflow-scan.out', t)

    def test_scanner_errors_reach_ui(self):
        self.assertIn('if ! /usr/lib/wiflow/scan-wifi "$band" > "$scan_tmp"; then', API.read_text())
        self.assertIn('"code":"WIFI_SCAN_FAILED"', API.read_text())
        self.assertIn("if(r.ok!==true)throw new Error", JS.read_text())
        self.assertIn("api('scan',{band},26000)", JS.read_text())

    def test_wan_carrier_and_dhcp_messages(self):
        t = UPLINK.read_text()
        self.assertIn('"/sys/class/net/$wan_dev/carrier"', t)
        self.assertIn('wan_no_carrier', t)
        self.assertIn("fail dhcp_failed 'Cổng WAN có thể đã kết nối", t)

    def test_production_shell_parses(self):
        for p in (SCAN, API, UPLINK):
            with self.subTest(path=p.name):
                r = subprocess.run(["sh", "-n", str(p)], capture_output=True, text=True)
                self.assertEqual(r.returncode, 0, r.stderr)

    def test_scanner_executes_success_and_failure_cases(self):
        with tempfile.TemporaryDirectory(prefix="nr3053-p51-") as d:
            base = Path(d)
            exe = base / "fake-iwinfo"
            exe.write_text(
                "#!/bin/sh\n"
                "echo 'Cell 01 - Address: 02:00:00:00:00:01'\n"
                "echo '          ESSID: \"Example2G\"'\n"
                "echo '          Encryption: WPA2 PSK (CCMP)'\n")
            exe.chmod(0o755)
            t = SCAN.read_text().replace(
                ". /usr/lib/wiflow/common.sh",
                "radio_band(){ echo 2g; }\n"
                "uci(){ echo 'wireless.radio0=wifi-device'; }\n"
            ).replace('/usr/bin/iwinfo-ucode', str(exe))
            script = base / "scan.sh"
            script.write_text(t)
            good = subprocess.run(["sh", str(script), "2g"],
                                  capture_output=True, text=True, timeout=20)
            self.assertEqual(good.returncode, 0, good.stderr)
            self.assertIn("Example2G", good.stdout)
            exe.write_text("#!/bin/sh\nexit 1\n")
            bad = subprocess.run(["sh", str(script), "2g"],
                                 capture_output=True, text=True, timeout=20)
            self.assertNotEqual(bad.returncode, 0)


if __name__ == "__main__":
    unittest.main()
