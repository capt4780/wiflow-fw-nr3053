"""Host-only execution tests for a read-only NR3053 sysupgrade validation.

These use a private disposable fixture + mocked sysupgrade; they do not access a
router or claim physical flash authorization.
"""
from pathlib import Path
import hashlib
import os
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools/nr3053-sysupgrade-test-readonly.sh"
GOLDEN_MTD = (
    'dev:    size   erasesize  name\n'
    'mtd0: 00100000 00020000 "BL2"\n'
    'mtd1: 00100000 00020000 "u-boot-env"\n'
    'mtd2: 00200000 00020000 "Factory"\n'
    'mtd3: 00200000 00020000 "FIP"\n'
    'mtd4: 0ea00000 00020000 "ubi"\n'
)


class StockDryRunTests(unittest.TestCase):
    def run_case(self, change=None, *, sysupgrade_ok=True, force_expected=None):
        with tempfile.TemporaryDirectory(prefix="wiflow-p47-stock-") as tmp:
            base = Path(tmp)
            board = base / "tmp/sysinfo/board_name"
            board.parent.mkdir(parents=True)
            board.write_text("viettel,nr3053\n")
            dt = base / "proc/device-tree/compatible"
            dt.parent.mkdir(parents=True)
            dt.write_bytes(b"viettel,nr3053\0mediatek,mt7981\0")
            mtd = base / "proc/mtd"
            mtd.write_text(GOLDEN_MTD)
            candidate = base / "tmp/wiflow.itb"
            candidate.write_bytes(b"FIT-demo-NOT-A-REAL-IMAGE" + bytes(1048576))
            digest = hashlib.sha256(candidate.read_bytes()).hexdigest()
            bindir = base / "mock-bin"
            bindir.mkdir()
            sysupgrade = bindir / "sysupgrade"
            sysupgrade.write_text(
                '#!/bin/sh\n'
                'printf "%s\\n" "$@" > "$SYSUPGRADE_CALL_FILE"\n'
                '[ "$SYSUPGRADE_OK" = 1 ]\n')
            sysupgrade.chmod(0o755)
            callfile = base / "sysupgrade-calls"
            if change is not None:
                digest = change(base, candidate, digest) or digest
            if force_expected is not None:
                digest = force_expected
            proc = subprocess.run(
                ["sh", str(SCRIPT), str(candidate), digest],
                env={**os.environ,
                     "PATH": str(bindir) + os.pathsep + os.environ["PATH"],
                     "WIFLOW_NR3053_TEST_ROOT": str(base),
                     "SYSUPGRADE_CALL_FILE": str(callfile),
                     "SYSUPGRADE_OK": "1" if sysupgrade_ok else "0"},
                capture_output=True, text=True, timeout=7, check=False)
            calls = callfile.read_text().splitlines() if callfile.exists() else []
            return proc.returncode, proc.stdout, proc.stderr, calls, str(candidate)

    def test_shell_syntax(self):
        p = subprocess.run(["sh", "-n", str(SCRIPT)], capture_output=True, timeout=3)
        self.assertEqual(p.returncode, 0, p.stderr)

    def test_valid_fixture_checks_candidate_only_no_flash(self):
        code, out, err, calls, candidate = self.run_case()
        self.assertEqual(code, 0, err)
        self.assertIn("context|INFO|HOST_FIXTURE_NOT_DEVICE", out)
        self.assertIn("board_identity|PASS|", out)
        self.assertIn("mtd_layout|PASS|", out)
        self.assertIn("image_sha256|PASS|", out)
        self.assertIn("sysupgrade_dryrun|PASS|", out)
        self.assertIn("first_flash_approval|BLOCK|", out)
        self.assertEqual(calls, ["-T", "-n", candidate])

    def test_wrong_board_blocks_before_sysupgrade(self):
        def change(base, candidate, digest):
            (base / "tmp/sysinfo/board_name").write_text("wrong,device\n")
        code, out, err, calls, _ = self.run_case(change)
        self.assertEqual(code, 2)
        self.assertIn("board_identity|BLOCK|wrong_board", out)
        self.assertEqual(calls, [])

    def test_soc_mismatch_blocks_before_sysupgrade(self):
        def change(base, candidate, digest):
            (base / "proc/device-tree/compatible").write_bytes(b"viettel,nr3053\0mediatek,mt7986\0")
        code, out, err, calls, _ = self.run_case(change)
        self.assertEqual(code, 2)
        self.assertIn("soc_compatible|BLOCK|", out)
        self.assertEqual(calls, [])

    def test_partition_size_mismatch_blocks(self):
        def change(base, candidate, digest):
            (base / "proc/mtd").write_text(GOLDEN_MTD.replace("00200000", "00100000"))
        code, out, err, calls, _ = self.run_case(change)
        self.assertEqual(code, 2)
        self.assertIn("mtd_layout|BLOCK|", out)
        self.assertEqual(calls, [])

    def test_sha_mismatch_blocks_before_sysupgrade(self):
        code, out, err, calls, _ = self.run_case(force_expected="0" * 64)
        self.assertEqual(code, 2)
        self.assertIn("image_sha256|BLOCK|mismatch", out)
        self.assertEqual(calls, [])

    def test_sysupgrade_rejection_is_blocked(self):
        code, out, err, calls, candidate = self.run_case(sysupgrade_ok=False)
        self.assertEqual(code, 2)
        self.assertIn("sysupgrade_dryrun|BLOCK|image_rejected", out)
        self.assertEqual(calls, ["-T", "-n", candidate])

    def test_candidate_symlink_is_rejected(self):
        def change(base, candidate, digest):
            other = base / "payload.bin"
            candidate.rename(other)
            candidate.symlink_to(other)
        code, out, err, calls, _ = self.run_case(change)
        self.assertEqual(code, 2)
        self.assertIn("image_location|BLOCK|", out)
        self.assertEqual(calls, [])

    def test_no_flash_or_force_path_in_source(self):
        text = SCRIPT.read_text()
        self.assertIn('sysupgrade -T -n "$candidate"', text)
        self.assertNotIn("sysupgrade -F ", text)
        self.assertNotIn("sysupgrade -f ", text)
        self.assertNotIn("mtd write", text)
        self.assertNotIn("ubus call system sysupgrade", text)
        self.assertNotIn("ubiupdatevol", text)


if __name__ == "__main__":
    unittest.main()
