#!/usr/bin/env python3
"""Offline NR3053 UART boot-menu transcript classification (NO FLASH).

No serial port access. Never prints UART logs, MACs, device serials, IPs,
calibration bytes, credentials, user paths or environment contents. The tool
NEVER infers physical recovery, and cannot authorize a first flash.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import stat

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = ROOT / "reference/nr3053-bootloader-source-recovery-contract.json"
MAX_BYTES = 2 * 1024 * 1024
CSI = re.compile(r"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1b\\))")


def verdict(key: str, status: str, detail: str) -> None:
    print(f"{key}|{status}|{detail}")


def inspect_console(path: Path) -> str | None:
    """Read one local regular log with no symlink or path disclosure."""
    try:
        before = path.lstat()
        if not stat.S_ISREG(before.st_mode) or not (100 <= before.st_size <= MAX_BYTES):
            return None
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
        try:
            opened = os.fstat(fd)
            if not stat.S_ISREG(opened.st_mode) or (
                    opened.st_dev, opened.st_ino) != (before.st_dev, before.st_ino):
                return None
            chunks = bytearray()
            while len(chunks) <= MAX_BYTES:
                piece = os.read(fd, 64 * 1024)
                if not piece:
                    break
                chunks.extend(piece)
            after = os.fstat(fd)
            if (len(chunks) != opened.st_size or len(chunks) > MAX_BYTES
                    or (opened.st_size, opened.st_mtime_ns, opened.st_ctime_ns) !=
                    (after.st_size, after.st_mtime_ns, after.st_ctime_ns)):
                return None
        finally:
            os.close(fd)
        return CSI.sub("", chunks.decode("utf-8", "replace")).replace("\r", "\n")
    except (OSError, ValueError):
        return None


def inspect_reference() -> dict | None:
    try:
        data = json.loads(REFERENCE.read_text(encoding="utf-8"))
    except (OSError, ValueError, TypeError):
        return None
    if data.get("schema") != "wiflow.nr3053.bootloader-source-capability.v1":
        return None
    if data.get("first_flash_approval") != "BLOCK":
        return None
    if data.get("provenance", {}).get("physical_bootloader_verified") is not False:
        return None
    items = data.get("potentially_nonwriting_menu_items", [])
    destructive = data.get("destructive_or_mutating_menu_items", [])
    if {item.get("id") for item in items} != {"1", "2", "3"}:
        return None
    if {item.get("id") for item in destructive} != {"0", "4", "5", "6", "7", "9"}:
        return None
    return data


def run(path: Path) -> int:
    verdict("stage", "INFO", "S5A_BOOTLOADER_TEXT_CLASSIFICATION_ONLY")
    verdict("context", "INFO", "OFFLINE_UNTRUSTED_TEXT_NOT_PHYSICAL_EVIDENCE")
    reference = inspect_reference()
    if reference is None:
        verdict("upstream_bootloader_source", "BLOCK", "source_contract_invalid")
        good = False
    else:
        verdict("upstream_bootloader_source", "PASS", "pinned_source_menu_contract_loaded")
        log = inspect_console(path)
        if log is None:
            verdict("boot_menu_text", "BLOCK", "local_transcript_unreadable_or_invalid")
            good = False
        else:
            required = reference["potentially_nonwriting_menu_items"]
            labels_present = all(
                item["label"] in log and item["classification"].startswith("BOOT_ONLY")
                or item["label"] in log and item["classification"].startswith("RAM_BOOT_")
                for item in required
            )
            # The transcript must also display a NAND write option to show the
            # classification is distinguishing boot from write actions.
            marker = any(
                item["label"] in log
                for item in reference["destructive_or_mutating_menu_items"]
                if item["classification"] == "NAND_WRITE"
            )
            good = labels_present and marker
            verdict("boot_menu_text", "PASS" if good else "BLOCK",
                    "matches_pinned_text_not_authenticated" if good
                    else "different_or_incomplete_menu_text")
    verdict("physical_uart_connection", "NOT_VERIFIED", "technician_and_physical_device_required")
    verdict("ram_tftp_boot_test", "NOT_TESTED", "nonwriting_ram_boot_not_observed")
    verdict("original_nand_restore_test", "NOT_TESTED", "independent_restore_not_demonstrated")
    verdict("first_flash_approval", "BLOCK", "physical_rescue_not_proven")
    verdict("release_s6", "BLOCK", "device_e5_and_recovery_not_proven")
    return 0 if good else 2


def main() -> int:
    parser = argparse.ArgumentParser(description="Classify private UART transcript safely (NO FLASH)")
    parser.add_argument("--uart-transcript", type=Path, required=True)
    args = parser.parse_args()
    return run(args.uart_transcript)


if __name__ == "__main__":
    raise SystemExit(main())
