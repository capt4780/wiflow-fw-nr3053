"""Uplink association must work on the MTWiFi (non-cfg80211) driver.

Executes the real shell functions against a fake sysfs tree; `iw dev` cannot
see mt_wifi.ko interfaces, so it must not be used for association.
"""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
COMMON = ROOT / "package/wiflow-setup/files/usr/lib/wiflow/common.sh"


def run(sysfs, l1, body):
    script = f'. "{COMMON}"; {body}'
    env = {"PATH": "/usr/bin:/bin", "WIFLOW_SYSFS_NET": str(sysfs),
           "WIFLOW_L1_PROFILE": str(l1)}
    return subprocess.run(["sh", "-c", script], env=env, capture_output=True,
                          text=True).returncode


class UplinkMtwifiTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.d = Path(self.tmp.name)
        self.sys = self.d / "net"
        self.sys.mkdir()
        self.l1 = self.d / "l1profile.dat"
        self.l1.write_text("Default\nINDEX0=MT7981\nINDEX0_apcli_ifname=apcli;apclix\n")

    def tearDown(self):
        self.tmp.cleanup()

    def vif(self, name, carrier):
        (self.sys / name).mkdir()
        (self.sys / name / "carrier").write_text(f"{carrier}\n")

    def test_function_does_not_use_nl80211_tools(self):
        src = COMMON.read_text()
        m = re.search(r"^wifi_uplink_associated\(\)\{.*?^\}", src, re.S | re.M)
        self.assertIsNotNone(m)
        self.assertNotIn("iw dev", m.group(0))
        self.assertNotIn("command -v iw ", m.group(0))

    def test_no_apcli_vif_is_not_associated(self):
        self.assertEqual(run(self.sys, self.l1, "wifi_uplink_associated"), 1)

    def test_vif_without_carrier_is_not_associated(self):
        self.vif("apcli0", 0)
        self.assertEqual(run(self.sys, self.l1, "wifi_uplink_associated"), 1)

    def test_carrier_2g_and_5g_vifs(self):
        self.vif("apcli0", 1)
        self.assertEqual(run(self.sys, self.l1, "wifi_uplink_associated"), 0)
        self.vif("apclix0", 1)
        (self.sys / "apcli0" / "carrier").write_text("0\n")
        self.assertEqual(run(self.sys, self.l1, "wifi_uplink_associated"), 0)

    def test_ssid_mismatch_and_match(self):
        self.vif("apcli0", 1)
        body = 'uplink_ssid_of(){ printf "Cafe"; }; wifi_uplink_associated %s'
        self.assertEqual(run(self.sys, self.l1, body % "Cafe"), 0)
        self.assertEqual(run(self.sys, self.l1, body % "Other"), 1)

    def test_unreported_ssid_falls_back_to_carrier(self):
        self.vif("apcli0", 1)
        body = 'uplink_ssid_of(){ :; }; wifi_uplink_associated Cafe'
        self.assertEqual(run(self.sys, self.l1, body), 0)

    def test_missing_l1_profile_uses_default_names(self):
        self.l1.unlink()
        self.vif("apclix0", 1)
        self.assertEqual(run(self.sys, self.l1, "wifi_uplink_associated"), 0)


if __name__ == "__main__":
    unittest.main()
