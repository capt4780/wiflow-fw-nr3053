"""Regression tests for the pinned NR3053 image package profile.

The legacy MTWiFi LuCI app has missing build-host dependencies in this
upstream/feeds combination. Preserve the actual radio driver and ucode backend.
"""
from pathlib import Path
import re
import unittest

SRC = (Path(__file__).resolve().parents[1] / "scripts/build-nr3053-base.sh").read_text()


class NR3053MtwifiProfileTests(unittest.TestCase):
    def test_unbuildable_gui_not_selected(self):
        m = re.search(r'DEVICE_PACKAGES := ([^\n]+)', SRC)
        self.assertIsNotNone(m)
        parts = m.group(1).split()
        self.assertIn("luci-ssl", parts)
        self.assertIn("luci-app-firewall", parts)
        self.assertIn("kmod-mt_wifi", parts)
        self.assertNotIn("luci-app-mtwifi-cfg", parts)

    def test_explicitly_disable_old_gui_after_source_config(self):
        self.assertIn('"luci-app-mtwifi-cfg", "luci-i18n-mtwifi-cfg-vi",', SRC)
        self.assertIn('for pkg in ("luci-app-mtwifi-cfg",', SRC)
        self.assertIn('"CONFIG_PACKAGE_" + name + " is not set"', SRC)

    def test_radio_driver_and_ucode_remain_required(self):
        self.assertEqual(SRC.count('"CONFIG_PACKAGE_kmod-mt_wifi=y"'), 2)
        self.assertEqual(SRC.count('"CONFIG_PACKAGE_mtwifi-cfg-ucode=y"'), 2)
        self.assertIn('"CONFIG_MTK_MT_WIFI_DRIVER_VERSION_7673=y"', SRC)
        self.assertIn("CONFIG_MTK_MT_WIFI_FIRMWARE_PATH_MT7981=", SRC)


if __name__ == "__main__":
    unittest.main()
