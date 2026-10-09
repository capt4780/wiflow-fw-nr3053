"""Prevent a Kconfig-clean Wiflow image with an unusable Wi-Fi scanner."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
SCAN=(ROOT/"package/wiflow-setup/files/usr/lib/wiflow/scan-wifi").read_text()
AUDIT=(ROOT/"tools/audit_nr3053_wiflow_image.py").read_text()
PKG=(ROOT/"package/wiflow-setup/Makefile").read_text()


class WiFiScannerUcodeTests(unittest.TestCase):
    def test_scanner_invokes_pinned_upstream_ucode_cli(self):
        self.assertIn('/usr/bin/iwinfo-ucode "$r" scan', SCAN)
        self.assertNotIn('( iwinfo "$r" scan', SCAN)
        self.assertIn('ESSID: ', SCAN)
        self.assertIn('Encryption: ', SCAN)

    def test_built_rootfs_must_contain_required_cli(self):
        self.assertIn('"usr/bin/iwinfo-ucode"', AUDIT)
        self.assertIn('"usr/bin/iwinfo-ucode", "usr/lib/wiflow"', AUDIT)

    def test_mtwifi_backend_owns_cli_selection(self):
        deps=next(s for s in PKG.splitlines() if "DEPENDS:=" in s)
        self.assertIn("+mtwifi-cfg-ucode", deps)
        self.assertNotIn("+iwinfo ", deps)
        self.assertNotIn("+iwinfo-ucode", deps)


if __name__=="__main__":
    unittest.main()
