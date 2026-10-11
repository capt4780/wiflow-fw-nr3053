"""Wi-Fi scan must work on MTWiFi: iwinfo takes ra0/rax0, not a UCI radio name.

Runs the real scan-wifi/common.sh against fake `uci` and fake iwinfo CLIs.
The fake CLI rejects anything that is not a network interface, exactly like
the shipped MTK iwinfo-ucode ("No such wireless device").
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "package/wiflow-setup/files/usr/lib/wiflow"

CELL = '''Cell 01 - Address: AA:BB:CC:DD:EE:01
          ESSID: "{ssid}"
          Mode: Master  Frequency: 2.437 GHz  Band: 2.4 GHz  Channel: 6
          Signal: -50 dBm  Quality: 60/70
          Encryption: {enc}

'''
FAKE_UCI = '''#!/bin/sh
case "$*" in
 "-q show wireless") printf 'wireless.MT7981_1_1=wifi-device\\nwireless.MT7981_1_2=wifi-device\\n';;
 "-q get wireless.MT7981_1_1.band") echo 2g;;
 "-q get wireless.MT7981_1_2.band") echo 5g;;
 *) exit 1;;
esac
'''
FAKE_IWINFO = '''#!/bin/sh
echo "$1 $2" >> "$WIFLOW_TEST_LOG"
case "$1" in
 ra0) printf '%s' "$WIFLOW_TEST_2G";;
 rax0) printf '%s' "$WIFLOW_TEST_5G";;
 *) echo "No such wireless device: $1" >&2; exit 1;;
esac
'''

SURVEY = """ra0       get_site_survey:
No  Ch  SSID                             BSSID               Security               Signal(%)W-Mode  ExtCH  NT WPS DPID
1   6   Quan Cafe 2G                     aa:bb:cc:dd:ee:10   WPA2PSK/AES            70       11b/g/n NONE   In YES
2   11  OpenNet                          aa:bb:cc:dd:ee:11   NONE                   40       11b/g/n NONE   In NO
3   1   Old                              aa:bb:cc:dd:ee:12   WPAPSK/TKIP            30       11b/g   NONE   In NO
4   3   Nha WPA3                         aa:bb:cc:dd:ee:13   WPA3PSK/AES            50       11b/g/n NONE   In NO
"""
FAKE_IWPRIV = '''#!/bin/sh
echo "iwpriv $*" >> "$WIFLOW_TEST_LOG"
[ "$2" = set ] && exit 0
[ "$2" = get_site_survey ] && { printf '%s' "$WIFLOW_TEST_SURVEY"; exit 0; }
exit 1
'''


class ScanMtwifiTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.d = Path(self.tmp.name)
        self.bin = self.d / "bin"
        self.bin.mkdir()
        (self.d / "uci").write_text(FAKE_UCI)
        shutil.copy(self.d / "uci", self.bin / "uci")
        (self.bin / "uci").chmod(0o755)
        self.log = self.d / "calls.log"
        self.l1 = self.d / "l1profile.dat"
        self.l1.write_text("Default\nINDEX0=MT7981\nINDEX0_main_ifname=ra0;rax0\n")
        self.common = self.d / "common.sh"
        self.common.write_text((LIB / "common.sh").read_text())
        self.scan = self.d / "scan-wifi"
        self.scan.write_text((LIB / "scan-wifi").read_text().replace(
            ". /usr/lib/wiflow/common.sh", f'. "{self.common}"'))

    def tearDown(self):
        self.tmp.cleanup()

    def install_cli(self, name):
        p = self.bin / name
        p.write_text(FAKE_IWINFO)
        p.chmod(0o755)

    def run_scan(self, band):
        out = Path("/tmp/wiflow-scan.out")
        out.unlink(missing_ok=True)
        env = {"PATH": f"{self.bin}:/usr/bin:/bin", "WIFLOW_BIN_DIR": str(self.bin),
               "WIFLOW_L1_PROFILE": str(self.l1), "WIFLOW_TEST_LOG": str(self.log),
               "WIFLOW_TEST_2G": CELL.format(ssid="Cafe2G", enc="WPA2 PSK (CCMP)"),
               "WIFLOW_TEST_5G": CELL.format(ssid="Cafe5G", enc="WPA3 SAE (CCMP)")}
        # DEVNULL: scan-wifi leaves a 7 s watchdog `sleep` behind that would
        # otherwise hold a captured pipe open.
        subprocess.run(["sh", str(self.scan), band], env=env, check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
        return out.read_text().splitlines() if out.exists() else []

    def calls(self):
        return self.log.read_text().split("\n")[:-1] if self.log.exists() else []

    def test_2g_scans_ra0_not_uci_radio_name(self):
        self.install_cli("iwinfo-ucode")
        rows = self.run_scan("2g")
        self.assertEqual(self.calls(), ["ra0 scan"])
        self.assertEqual(rows, ["MT7981_1_1\t2g\tCafe2G\tAA:BB:CC:DD:EE:01\tpsk2"])

    def test_5g_scans_rax0(self):
        self.install_cli("iwinfo-ucode")
        rows = self.run_scan("5g")
        self.assertEqual(self.calls(), ["rax0 scan"])
        self.assertEqual(rows, ["MT7981_1_2\t5g\tCafe5G\tAA:BB:CC:DD:EE:01\tsae-mixed"])

    def test_works_after_first_boot_rename_to_iwinfo(self):
        """99-replace-iwinfo moves iwinfo-ucode over iwinfo; only iwinfo remains."""
        self.install_cli("iwinfo")
        self.assertFalse((self.bin / "iwinfo-ucode").exists())
        rows = self.run_scan("2g")
        self.assertEqual(self.calls(), ["ra0 scan"])
        self.assertEqual(len(rows), 1)

    def test_interface_names_come_from_l1_profile(self):
        self.l1.write_text("INDEX0_main_ifname=ra1;rax1\n")
        self.install_cli("iwinfo-ucode")
        self.run_scan("5g")
        self.assertEqual(self.calls(), ["rax1 scan"])

    def test_missing_profile_falls_back_to_default_names(self):
        self.l1.unlink()
        self.install_cli("iwinfo-ucode")
        self.run_scan("5g")
        self.assertEqual(self.calls(), ["rax0 scan"])

    def test_no_cli_yields_empty_result_not_crash(self):
        self.assertEqual(self.run_scan("2g"), [])

    def test_iwpriv_site_survey_fallback_when_iwinfo_is_empty(self):
        self.install_cli("iwinfo")  # fake prints nothing for ra0 in this test
        p = self.bin / "iwpriv"
        p.write_text(FAKE_IWPRIV)
        p.chmod(0o755)
        out = Path("/tmp/wiflow-scan.out")
        out.unlink(missing_ok=True)
        env = {"PATH": f"{self.bin}:/usr/bin:/bin", "WIFLOW_BIN_DIR": str(self.bin),
               "WIFLOW_L1_PROFILE": str(self.l1), "WIFLOW_TEST_LOG": str(self.log),
               "WIFLOW_TEST_2G": "", "WIFLOW_TEST_5G": "", "WIFLOW_TEST_SURVEY": SURVEY,
               "WIFLOW_SURVEY_WAIT": "0"}
        subprocess.run(["sh", str(self.scan), "2g"], env=env, check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
        rows = out.read_text().splitlines()
        self.assertEqual(rows, [
            "MT7981_1_1\t2g\tQuan Cafe 2G\taa:bb:cc:dd:ee:10\tpsk2",
            "MT7981_1_1\t2g\tOpenNet\taa:bb:cc:dd:ee:11\tnone",
            "MT7981_1_1\t2g\tOld\taa:bb:cc:dd:ee:12\tpsk",
            "MT7981_1_1\t2g\tNha WPA3\taa:bb:cc:dd:ee:13\tsae-mixed"])
        self.assertIn("iwpriv ra0 set SiteSurvey=1", self.calls())
        dbg = Path("/tmp/wiflow-scan-debug.log").read_text()
        self.assertIn("ifname=ra0", dbg)
        self.assertIn("iwpriv get_site_survey", dbg)

    def test_debug_log_records_reason_when_nothing_works(self):
        self.run_scan("2g")
        self.assertIn("iwinfo: not installed", Path("/tmp/wiflow-scan-debug.log").read_text())


if __name__ == "__main__":
    unittest.main()
