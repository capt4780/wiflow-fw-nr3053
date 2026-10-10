"""Host-only regressions for the private/offline NR3053 Factory copy checker."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools/nr3053-s5a-verify-factory-backup.py"
EXPECTED_FACTORY_BYTES = 0x00200000


class S5AFactoryBackupCheckerTests(unittest.TestCase):
    def invoke(self, a: Path, b: Path):
        p = subprocess.run(
            ["python3", str(SCRIPT), "--factory-a", str(a), "--factory-b", str(b)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=12,
        )
        self.assertEqual(p.stderr, "")
        self.assertNotIn(str(a), p.stdout)
        self.assertNotIn(str(b), p.stdout)
        self.assertNotIn("sha256:", p.stdout)
        self.assertIn("first_flash_approval|BLOCK|", p.stdout)
        self.assertIn("release_s6|BLOCK|", p.stdout)
        self.assertIn("backup_device_origin|NOT_VERIFIED|", p.stdout)
        self.assertIn("uart_bootloader_recovery|NOT_VERIFIED|", p.stdout)
        fields = dict((line.split("|")[0], line.split("|")[1:]) for line in p.stdout.splitlines())
        return p, fields

    def test_two_distinct_identical_golden_size_copies_pass_only_integrity(self):
        with tempfile.TemporaryDirectory() as d:
            a, b = Path(d)/"a.bin", Path(d)/"b.bin"
            a.write_bytes(b"A" * EXPECTED_FACTORY_BYTES)
            b.write_bytes(b"A" * EXPECTED_FACTORY_BYTES)
            p, fields = self.invoke(a, b)
            self.assertEqual(p.returncode, 0)
            self.assertEqual(fields["golden_factory_reference"][0], "PASS")
            self.assertEqual(fields["factory_copy_pair"], ["PASS", "distinct_files_equal_sha256"])
            self.assertEqual(fields["first_flash_approval"][0], "BLOCK")

    def test_all_erased_ff_factory_copies_are_not_consistency_pass(self):
        with tempfile.TemporaryDirectory() as d:
            a, b = Path(d)/"erased-a", Path(d)/"erased-b"
            a.write_bytes(b"\xff" * EXPECTED_FACTORY_BYTES)
            b.write_bytes(b"\xff" * EXPECTED_FACTORY_BYTES)
            p, fields = self.invoke(a, b)
            self.assertEqual(p.returncode, 2)
            self.assertEqual(fields["factory_copy_a"],
                             ["BLOCK", "blank_factory_copy_no_calibration_evidence"])
            self.assertEqual(fields["factory_copy_b"][0], "BLOCK")
            self.assertEqual(fields["factory_copy_pair"][0], "NOT_TESTED")

    def test_all_zero_factory_copies_are_not_consistency_pass(self):
        with tempfile.TemporaryDirectory() as d:
            a, b = Path(d)/"zero-a", Path(d)/"zero-b"
            a.write_bytes(b"\x00" * EXPECTED_FACTORY_BYTES)
            b.write_bytes(b"\x00" * EXPECTED_FACTORY_BYTES)
            p, fields = self.invoke(a, b)
            self.assertEqual(p.returncode, 2)
            self.assertEqual(fields["factory_copy_a"],
                             ["BLOCK", "blank_factory_copy_no_calibration_evidence"])
            self.assertEqual(fields["factory_copy_pair"][0], "NOT_TESTED")

    def test_same_size_but_different_content_is_blocked(self):
        with tempfile.TemporaryDirectory() as d:
            a, b = Path(d)/"a", Path(d)/"b"
            a.write_bytes(b"A" * EXPECTED_FACTORY_BYTES)
            b.write_bytes(b"B" * EXPECTED_FACTORY_BYTES)
            p, fields = self.invoke(a, b)
            self.assertEqual(p.returncode, 2)
            self.assertEqual(fields["factory_copy_pair"], ["BLOCK", "sha256_content_mismatch"])

    def test_observed_wrong_golden_size_is_blocked(self):
        with tempfile.TemporaryDirectory() as d:
            a, b = Path(d)/"a", Path(d)/"b"
            a.write_bytes(b"A" * 100)
            b.write_bytes(b"B" * EXPECTED_FACTORY_BYTES)
            p, fields = self.invoke(a, b)
            self.assertEqual(p.returncode, 2)
            self.assertEqual(fields["factory_copy_a"][0], "BLOCK")
            self.assertEqual(fields["factory_copy_pair"][0], "NOT_TESTED")

    def test_same_inode_and_hardlink_are_not_two_copies(self):
        with tempfile.TemporaryDirectory() as d:
            a, b = Path(d)/"a", Path(d)/"b"
            a.write_bytes(b"A" * EXPECTED_FACTORY_BYTES)
            os.link(a, b)
            for dest in (a, b):
                p, fields = self.invoke(a, dest)
                self.assertEqual(p.returncode, 2)
                self.assertEqual(fields["factory_copy_pair"], ["BLOCK", "same_file_or_hardlink"])

    def test_symlink_is_not_accepted_as_independent_backup(self):
        with tempfile.TemporaryDirectory() as d:
            a, b = Path(d)/"a", Path(d)/"b"
            a.write_bytes(b"A" * EXPECTED_FACTORY_BYTES)
            b.symlink_to(a)
            p, fields = self.invoke(a, b)
            self.assertEqual(p.returncode, 2)
            self.assertEqual(fields["factory_copy_b"], ["BLOCK", "not_regular_file"])

    def test_missing_copy_is_warning_not_implicit_success(self):
        with tempfile.TemporaryDirectory() as d:
            a, b = Path(d)/"a", Path(d)/"not-found"
            a.write_bytes(b"A" * EXPECTED_FACTORY_BYTES)
            p, fields = self.invoke(a, b)
            self.assertEqual(p.returncode, 2)
            self.assertEqual(fields["factory_copy_b"], ["WARN", "file_unavailable_or_unreadable"])

    def test_tool_and_test_source_reject_sensitive_and_flash_actions(self):
        source = SCRIPT.read_text()
        self.assertNotIn("sysupgrade", source)
        self.assertNotIn("mtd write", source)
        self.assertNotIn("subprocess", source)
        self.assertIn('report("first_flash_approval", "BLOCK"', source)
        self.assertIn('report("backup_device_origin", "NOT_VERIFIED"', source)


if __name__ == "__main__":
    unittest.main()
