"""Build graph regression: the two iwinfo variants are mutually exclusive.

This host guard alone is NOT Kconfig proof. The PR workflow executes the
pinned upstream's real make defconfig with the full feeds installed.
"""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
PACKAGE=(ROOT/"package/wiflow-setup/Makefile").read_text()
BUILD=(ROOT/"scripts/build-nr3053-base.sh").read_text()
WF=(ROOT/".github/workflows/nr3053-kconfig-preflight.yml").read_text()


class RealKconfigPreflightTests(unittest.TestCase):
    def test_do_not_select_legacy_iwinfo_against_ucode(self):
        deps=next(s for s in PACKAGE.splitlines() if "DEPENDS:=" in s).split("DEPENDS:=",1)[1].split()
        self.assertIn("+mtwifi-cfg-ucode", deps)
        self.assertNotIn("+iwinfo", deps)
        self.assertNotIn("+iwinfo-ucode", deps)  # owner is MTWiFi package

    def test_preflight_checks_resolved_ucode_config_not_just_requested(self):
        self.assertIn('"CONFIG_PACKAGE_mtwifi-cfg-ucode=y"', BUILD)
        self.assertIn('"CONFIG_PACKAGE_kmod-mt_wifi=y"', BUILD)
        self.assertIn('"CONFIG_PACKAGE_iwinfo-ucode=y" in config', BUILD)
        self.assertIn('"CONFIG_PACKAGE_iwinfo=y" not in config', BUILD)

    def test_preflight_exits_after_full_feeds_real_defconfig(self):
        self.assertIn('make defconfig', BUILD)
        self.assertIn('NR3053_PINNED_KCONFIG_PREFLIGHT_PASS_NO_IMAGE_NO_FLASH', BUILD)
        self.assertLess(BUILD.index('make defconfig'), BUILD.index('WIFLOW_KCONFIG_ONLY:-0'))
        self.assertLess(BUILD.index('WIFLOW_KCONFIG_ONLY:-0'), BUILD.index('make download -j4'))
        self.assertIn('WIFLOW_KCONFIG_ONLY: "1"', WF)
        self.assertIn('WIFLOW_SOURCE_BUILD: "1"', WF)
        self.assertIn('pull_request:', WF)
        self.assertNotIn('actions/upload-artifact', WF)


if __name__=="__main__":
    unittest.main()
