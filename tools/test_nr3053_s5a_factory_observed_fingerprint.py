"""Offline-only Factory checksum provenance tests; no real device bytes are used."""
from pathlib import Path
import hashlib
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools/nr3053-s5a-verify-factory-backup.py"
FACTORY_SIZE = 0x00200000


def fingerprint_text(digest: str) -> str:
    return (
        "NR3053 SOURCE FINGERPRINT — READ ONLY\n"
        "Generated: Wed Oct  7 08:17:19 ICT 2026\n"
        "===== FLASH / PARTITION LAYOUT =====\n"
        'mtd0: 00100000 00020000 "BL2"\n'
        'mtd1: 00100000 00020000 "u-boot-env"\n'
        'mtd2: 00200000 00020000 "Factory"\n'
        'mtd3: 00200000 00020000 "FIP"\n'
        'mtd4: 0ea00000 00020000 "ubi"\n'
        "===== FACTORY PARTITION FINGERPRINT — HASH ONLY =====\n"
        "Factory device=/dev/mtd2\n"
        + digest + "  /dev/mtd2\n"
        "===== APK / FEEDS / BUILD LINEAGE =====\n"
    )


class FactoryObservedFingerprintTests(unittest.TestCase):
    def run_case(self, *, mismatch=False, malformed=False, symlink=False):
        with tempfile.TemporaryDirectory(prefix="wiflow-p48-private-host-") as temp:
            root = Path(temp)
            raw = bytes(range(256)) * (FACTORY_SIZE // 256)
            a, b = root / "a.bin", root / "b.bin"
            a.write_bytes(raw)
            b.write_bytes(raw)
            digest = hashlib.sha256(raw).hexdigest()
            if mismatch:
                digest = hashlib.sha256(b"wrong-physical-device").hexdigest()
            fp = root / "fingerprint.txt"
            fp.write_text(fingerprint_text(digest if not malformed else "INVALID"))
            if symlink:
                real = root / "underlying.txt"
                fp.rename(real)
                fp.symlink_to(real)
            p = subprocess.run(
                ["python3", str(TOOL), "--factory-a", str(a),
                 "--factory-b", str(b), "--observed-fingerprint", str(fp)],
                capture_output=True, text=True, timeout=12,
            )
            self.assertNotIn(digest, p.stdout)
            self.assertNotIn(str(root), p.stdout)
            self.assertEqual(p.stderr, "")
            self.assertIn("first_flash_approval|BLOCK|", p.stdout)
            self.assertIn("uart_bootloader_recovery|NOT_VERIFIED|", p.stdout)
            return p

    def test_matches_private_observed_hash_but_still_no_flash(self):
        p = self.run_case()
        self.assertEqual(p.returncode, 0)
        self.assertIn("factory_copy_pair|PASS|", p.stdout)
        self.assertIn("factory_fingerprint_match|PASS|matching_observed_factory_hash", p.stdout)

    def test_wrong_device_dump_hash_blocked(self):
        p = self.run_case(mismatch=True)
        self.assertEqual(p.returncode, 2)
        self.assertIn("factory_fingerprint_match|BLOCK|observed_device_factory_hash_mismatch", p.stdout)

    def test_malformed_fingerprint_blocked(self):
        p = self.run_case(malformed=True)
        self.assertEqual(p.returncode, 2)
        self.assertIn("factory_fingerprint_match|BLOCK|private_fingerprint_invalid", p.stdout)

    def test_symlink_fingerprint_is_blocked(self):
        p = self.run_case(symlink=True)
        self.assertEqual(p.returncode, 2)
        self.assertIn("factory_fingerprint_match|BLOCK|private_fingerprint_invalid", p.stdout)


if __name__ == "__main__":
    unittest.main()
