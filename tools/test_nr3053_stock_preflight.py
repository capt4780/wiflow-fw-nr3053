"""Host regressions for stock NR3053 S5-A passive inventory.

All checks run production shell script against synthetic files. No host
fixture is a hardware test or bootloader recovery/flash authorization.
"""
from pathlib import Path
import os
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools/nr3053-stock-preflight-readonly.sh"


class NR3053StockPreflightTests(unittest.TestCase):
    def evaluate(self, *, board="viettel,nr3053", compatible=True,
                 release=True, mtd=True, calibration=True, wiflow=False):
        with tempfile.TemporaryDirectory(prefix="nr3053-stock-preflight-") as temp:
            directory = Path(temp)
            root = directory / "stock"
            sysinfo = root / "tmp/sysinfo"
            sysinfo.mkdir(parents=True)
            if board is not None:
                (sysinfo / "board_name").write_text(board)
            device_tree = root / "proc/device-tree"
            device_tree.mkdir(parents=True)
            if compatible is not None:
                (device_tree / "compatible").write_bytes(
                    b"viettel,nr3053\x00mediatek,mt7981\x00" if compatible
                    else b"another,vendor\x00"
                )
            if release:
                osdir = root / "etc"
                osdir.mkdir(exist_ok=True)
                (osdir / "openwrt_release").write_text(
                    "DISTRIB_ID='ImmortalWrt'\n"
                )
            if mtd:
                partition_file = root / "proc/mtd"
                partition_file.parent.mkdir(parents=True, exist_ok=True)
                partition_file.write_text(
                    'dev:    size   erasesize  name\n'
                    'mtd0: 00100000 00020000 "BL2"\n'
                    + ('mtd1: 00080000 00020000 "factory"\n' if calibration
                       else 'mtd1: 00080000 00020000 "rootfs"\n')
                )
            if wiflow:
                wiflow_file = root / "usr/lib/wiflow/portal-client"
                wiflow_file.parent.mkdir(parents=True)
                wiflow_file.write_text("fixture, not real Wiflow")
            baseline = {
                str(p.relative_to(root)): p.read_bytes()
                for p in root.rglob("*") if p.is_file()
            }
            result = subprocess.run(
                ["sh", str(TOOL)],
                capture_output=True, text=True, timeout=8,
                env={**os.environ, "WIFLOW_STOCK_TEST_ROOT": str(root)},
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stderr, "")
            after = {
                str(p.relative_to(root)): p.read_bytes()
                for p in root.rglob("*") if p.is_file()
            }
            self.assertEqual(baseline, after)
            entries = {}
            for line in result.stdout.splitlines():
                name, status, detail = line.split("|")
                self.assertNotIn(name, entries)
                self.assertRegex(name, r"^[a-z][a-z0-9_]*$")
                self.assertRegex(detail, r"^[A-Za-z0-9_]+$")
                entries[name] = (status, detail)
            self.assertEqual(entries["context"], ("INFO", "HOST_FIXTURE_NOT_DEVICE"))
            self.assertEqual(entries["first_flash_approval"][0], "BLOCK")
            self.assertEqual(entries["bootloader_recovery"][0], "NOT_VERIFIED")
            self.assertEqual(entries["original_firmware_backup"][0], "NOT_VERIFIED")
            self.assertEqual(entries["wiflow_s5_runtime"][0], "NOT_TESTED")
            self.assertEqual(entries["release_s6"][0], "BLOCK")
            self.assertNotIn("factory", result.stdout)
            self.assertNotIn("BL2", result.stdout)
            self.assertNotIn("192.168", result.stdout)
            return entries

    def test_expected_stock_board_never_grants_flash_authorization(self):
        data = self.evaluate()
        for field in ("board_identity", "dt_compatible", "stock_os_metadata",
                      "flash_partition_inventory"):
            self.assertEqual(data[field][0], "PASS")
        self.assertEqual(data["calibration_partition_hint"][0], "INFO")
        self.assertEqual(data["wiflow_installation"][0], "INFO")
        self.assertEqual(data["stock_radio_2g"][0], "SKIP")
        self.assertEqual(data["stock_radio_5g"][0], "SKIP")

    def test_wrong_board_remains_blocked(self):
        data = self.evaluate(board="xiaomi,other", compatible=False)
        self.assertEqual(data["board_identity"][0], "BLOCK")
        self.assertEqual(data["dt_compatible"][0], "BLOCK")

    def test_expected_board_name_does_not_override_incompatible_device_tree(self):
        data = self.evaluate(board="viettel,nr3053", compatible=False)
        self.assertEqual(data["board_identity"][0], "PASS")
        self.assertEqual(data["dt_compatible"], ("BLOCK", "nr3053_compatible_mismatch"))
        self.assertEqual(data["first_flash_approval"][0], "BLOCK")

    def test_missing_board_mtd_and_os_are_explicitly_unknown(self):
        data = self.evaluate(board=None, compatible=None, release=False, mtd=False)
        for field in ("board_identity", "dt_compatible", "stock_os_metadata",
                      "flash_partition_inventory", "calibration_partition_hint"):
            self.assertEqual(data[field][0], "WARN")

    def test_missing_named_calibration_partition_is_warning(self):
        data = self.evaluate(calibration=False)
        self.assertEqual(data["flash_partition_inventory"][0], "PASS")
        self.assertEqual(data["calibration_partition_hint"][0], "WARN")

    def test_unexpected_wiflow_files_are_observed_not_executed(self):
        data = self.evaluate(wiflow=True)
        self.assertEqual(data["wiflow_installation"][0], "WARN")

    def test_source_has_no_flash_mutation_or_sensitive_dump(self):
        source = TOOL.read_text()
        self.assertIn("report first_flash_approval BLOCK", source)
        self.assertIn("report wiflow_s5_runtime NOT_TESTED", source)
        for pattern in (
            r"(?m)^\s*(sysupgrade|mtd|reboot|firstboot|passwd|dd|fw_setenv)\b",
            r"(?m)^\s*uci\s+(set|commit|delete)\b",
            r"(?m)^\s*nft\s+(add|delete|flush)\b",
            r"/etc/shadow", r"/etc/config/wireless", r"/etc/config/network",
            r"\bdevice_token\b", r"(?m)^\s*(curl|wget|ssh|telnet)\b",
        ):
            with self.subTest(pattern=pattern):
                self.assertIsNone(re.search(pattern, source))


if __name__ == "__main__":
    unittest.main()
