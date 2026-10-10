"""Synthetic UART evidence checks; no NR3053 connected or UART accessed."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools/nr3053-uart-bootmenu-evidence-offline.py"
CONTRACT = ROOT / "reference/nr3053-bootloader-source-recovery-contract.json"

EXAMPLE = """
U-Boot 2026 experimental source build: NOT A PHYSICAL DEVICE
 1: Boot system via TFTP.
 2: Boot production system from NAND.
 3: Boot recovery system from NAND.
 4: Load production system via TFTP then write to NAND.
 5: Load recovery system via TFTP then write to NAND.
 6: Load BL31+U-Boot FIP via TFTP then write to NAND.
 7: Load BL2 preloader via TFTP then write to NAND.
 9: Reset all settings to factory defaults.
WIFI_SECRET=REDACTED_PRIVATE_SENTINEL
"""


class UartBootmenuSourceEvidenceTests(unittest.TestCase):
    def invoke(self, text: str = EXAMPLE, *, symlink: bool = False):
        with tempfile.TemporaryDirectory(prefix="wiflow-p49-uart-host-") as folder:
            root = Path(folder)
            log = root / "uart.txt"
            if symlink:
                actual = root / "real.txt"
                actual.write_text(text)
                log.symlink_to(actual)
            else:
                log.write_text(text)
            result = subprocess.run(
                ["python3", str(SCRIPT), "--uart-transcript", str(log)],
                capture_output=True, text=True, timeout=5,
            )
            self.assertEqual(result.stderr, "")
            self.assertNotIn("WIFI_SECRET", result.stdout)
            self.assertNotIn("REDACTED_PRIVATE_SENTINEL", result.stdout)
            self.assertNotIn(str(log), result.stdout)
            self.assertIn("first_flash_approval|BLOCK|", result.stdout)
            self.assertIn("physical_uart_connection|NOT_VERIFIED|", result.stdout)
            self.assertIn("original_nand_restore_test|NOT_TESTED|", result.stdout)
            return result

    def test_source_menu_shape_only_never_approves_flash(self):
        result = self.invoke()
        self.assertEqual(result.returncode, 0)
        self.assertIn("boot_menu_text|PASS|matches_pinned_text_not_authenticated", result.stdout)

    def test_missing_tftp_ram_boot_label_blocks(self):
        result = self.invoke(EXAMPLE.replace("Boot system via TFTP.", "Other menu action."))
        self.assertEqual(result.returncode, 2)
        self.assertIn("boot_menu_text|BLOCK|", result.stdout)

    def test_only_ram_boot_label_not_enough(self):
        result = self.invoke("Boot system via TFTP.\n")
        self.assertEqual(result.returncode, 2)

    def test_missing_destructive_menu_control_blocks(self):
        result = self.invoke(
            EXAMPLE.replace("Load production system via TFTP then write to NAND.", "X")
                   .replace("Load recovery system via TFTP then write to NAND.", "Y")
        )
        self.assertEqual(result.returncode, 2)

    def test_symlink_and_empty_transcripts_are_rejected(self):
        self.assertEqual(self.invoke(symlink=True).returncode, 2)
        self.assertEqual(self.invoke("").returncode, 2)

    def test_contract_differentiates_read_only_vs_mutating(self):
        data = json.loads(CONTRACT.read_text())
        allowed = {x["id"] for x in data["potentially_nonwriting_menu_items"]}
        modifying = {x["id"] for x in data["destructive_or_mutating_menu_items"]}
        self.assertEqual(allowed, {"1", "2", "3"})
        self.assertEqual(modifying, {"0", "4", "5", "6", "7", "9"})
        self.assertFalse(allowed & modifying)
        self.assertEqual(data["first_flash_approval"], "BLOCK")
        self.assertIs(data["provenance"]["physical_bootloader_verified"], False)
        self.assertIs(data["on_device_ramboot_tested"], False)

    def test_offline_tool_contains_no_write_flash_or_uart_controls(self):
        source = SCRIPT.read_text()
        for forbidden in ("serial.Serial", "pyserial", "tftpboot ", "mtd erase ",
                          "ubus call system sysupgrade", "os.system(", "socket.socket("):
            self.assertNotIn(forbidden, source)
        self.assertIn('verdict("first_flash_approval", "BLOCK"', source)


if __name__ == "__main__":
    unittest.main()
