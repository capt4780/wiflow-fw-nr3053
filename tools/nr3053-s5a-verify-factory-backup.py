#!/usr/bin/env python3
"""Local/offline Factory backup copy check; never authorizes NR3053 flashing.

Run on a trusted workstation with two purported Factory backup copies. The
script never contacts the router/network, writes to backup files, or prints
paths, hashes, MACs, EEPROM, tokens, serial numbers or backup contents.
Matching file hashes cannot prove that either copy came from the device.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import stat

GOLDEN = Path(__file__).resolve().parents[1] / "reference/nr3053-golden.json"
CHUNK = 128 * 1024


def report(name: str, status: str, reason: str) -> None:
    print(f"{name}|{status}|{reason}")


def factory_expected_size() -> int:
    data = json.loads(GOLDEN.read_text(encoding="utf-8"))
    partitions = data["dtb"]["spi_nand_partition_layout"]
    factory = [p for p in partitions if p.get("name") == "Factory"]
    if data.get("schema") != "wiflow.nr3053.golden-reference.v1" or len(factory) != 1:
        raise ValueError("invalid golden schema")
    size = int(factory[0]["size"], 16)
    if not (0 < size <= 16 * 1024 * 1024):
        raise ValueError("out of range")
    return size


def inspect(path: Path, expected: int) -> tuple[str, str, tuple[int, int] | None, bytes | None]:
    """Read regular, non-symlink file using O_NOFOLLOW and report only verdicts."""
    try:
        before = path.lstat()
        if not stat.S_ISREG(before.st_mode):
            return "BLOCK", "not_regular_file", None, None
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0))
        try:
            opened = os.fstat(fd)
            if not stat.S_ISREG(opened.st_mode) or (opened.st_dev, opened.st_ino) != (before.st_dev, before.st_ino):
                return "BLOCK", "file_changed_during_open", None, None
            if opened.st_size != expected:
                return "BLOCK", "wrong_golden_factory_size", None, None
            digest = hashlib.sha256()
            total = 0
            all_zero = True
            all_erased = True
            while True:
                piece = os.read(fd, CHUNK)
                if not piece:
                    break
                total += len(piece)
                if total > expected:
                    return "BLOCK", "file_changed_during_read", None, None
                digest.update(piece)
                # Two equal dumps of blank NAND are not usable calibration evidence.
                # Check in-stream without exposing any content or adding an extra read.
                all_zero = all_zero and piece.count(0) == len(piece)
                all_erased = all_erased and piece.count(255) == len(piece)
            after = os.fstat(fd)
            if total != expected or (opened.st_size, opened.st_mtime_ns, opened.st_ctime_ns, opened.st_ino, opened.st_dev) != (after.st_size, after.st_mtime_ns, after.st_ctime_ns, after.st_ino, after.st_dev):
                return "BLOCK", "file_changed_during_read", None, None
            if all_zero or all_erased:
                return "BLOCK", "blank_factory_copy_no_calibration_evidence", None, None
            return "PASS", "golden_size_and_read_complete", (opened.st_dev, opened.st_ino), digest.digest()
        finally:
            os.close(fd)
    except (OSError, ValueError):
        return "WARN", "file_unavailable_or_unreadable", None, None


def run(first: Path, second: Path) -> int:
    report("stage", "INFO", "S5_A_PRIVATE_OFFLINE_FACTORY_BACKUP_CHECK")
    try:
        expected = factory_expected_size()
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError):
        report("golden_factory_reference", "BLOCK", "missing_or_invalid_golden")
        report("factory_copy_pair", "NOT_TESTED", "golden_reference_unavailable")
        status = 2
    else:
        report("golden_factory_reference", "PASS", "pinned_size_loaded")
        a = inspect(first, expected)
        b = inspect(second, expected)
        report("factory_copy_a", a[0], a[1])
        report("factory_copy_b", b[0], b[1])
        if a[0] != "PASS" or b[0] != "PASS":
            report("factory_copy_pair", "NOT_TESTED", "both_valid_regular_copies_required")
            status = 2
        elif a[2] == b[2]:
            report("factory_copy_pair", "BLOCK", "same_file_or_hardlink")
            status = 2
        elif a[3] != b[3]:
            report("factory_copy_pair", "BLOCK", "sha256_content_mismatch")
            status = 2
        else:
            report("factory_copy_pair", "PASS", "distinct_files_equal_sha256")
            status = 0
    # Always keep the high-risk approval gates blocked. File copies can be forged.
    report("backup_device_origin", "NOT_VERIFIED", "technician_device_export_evidence_required")
    report("backup_restore_test", "NOT_VERIFIED", "independent_restore_evidence_required")
    report("uart_bootloader_recovery", "NOT_VERIFIED", "physical_lab_demonstration_required")
    report("first_flash_approval", "BLOCK", "independent_hardware_recovery_not_proven")
    report("release_s6", "BLOCK", "device_e5_and_recovery_not_proven")
    return status


def main() -> int:
    parser = argparse.ArgumentParser(description="NR3053 offline Factory backup copy integrity check (NO FLASH)")
    parser.add_argument("--factory-a", type=Path, required=True, help="Private Factory dump copy A")
    parser.add_argument("--factory-b", type=Path, required=True, help="Private Factory dump copy B")
    args = parser.parse_args()
    return run(args.factory_a, args.factory_b)


if __name__ == "__main__":
    raise SystemExit(main())
