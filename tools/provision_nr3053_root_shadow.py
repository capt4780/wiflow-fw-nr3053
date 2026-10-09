#!/usr/bin/env python3
"""Provision and audit Wiflow's explicit root/1234 default in build-only rootfs.

This is an intentionally WEAK, user-specified fixed default; hashing prevents
the *empty* password vulnerability, not credential guessing or interception.
Never interpret a valid hash as proof of a secure or flash-ready device.
"""
from pathlib import Path
import argparse
import re
import subprocess
import sys

# Previously approved NR3053 default, not a secret. Requires changing after
# private first-owner setup before any deployment can be considered secure.
DEFAULT_USER_PASSWORD = "1234"
HASH_SALT = "WiflowNR3053"
ROOT_LINE = "root:::0:99999:7:::"


def inspect_root_shadow(text: str) -> tuple[str, str]:
    roots = [line for line in text.splitlines() if line.startswith("root:")]
    if len(roots) != 1:
        return "BLOCK", "root entry absent or duplicated"
    fields = roots[0].split(":")
    if len(fields) != 9:
        return "BLOCK", "root shadow field count invalid"
    encoded = fields[1]
    # Explicit audited SHA-512 crypt policy. Accept only a populated crypt
    # digest; do not count empty, !-locked, '*' or plaintext root as PASS.
    if not re.fullmatch(r"\$6\$[A-Za-z0-9./]{1,16}\$[A-Za-z0-9./]{86}", encoded):
        return "BLOCK", "root password empty, disabled or not SHA-512 crypt"
    # The user's specified factory login is root/1234. Validate the hash
    # *against that actual contract*, not merely the digest's regex shape.
    salt = encoded.split("$")[2]
    try:
        expected = subprocess.run(
            ["openssl", "passwd", "-6", "-salt", salt, DEFAULT_USER_PASSWORD],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "BLOCK", "cannot validate factory default root crypt digest"
    if encoded != expected:
        return "BLOCK", "root hash does not match declared factory default"
    return "PASS", "root/1234 SHA-512 crypt verified (weak public default)"


def provision(upstream: Path, output: Path) -> None:
    # Fail if upstream shadow changes: never silently replace user accounts.
    source = upstream.read_text()
    lines = source.splitlines(keepends=True)
    root_positions = [i for i, line in enumerate(lines) if line.startswith("root:")]
    if len(root_positions) != 1 or lines[root_positions[0]].rstrip("\r\n") != ROOT_LINE:
        raise ValueError("pinned upstream root entry drifted; refusing password override")
    result = subprocess.run(
        ["openssl", "passwd", "-6", "-salt", HASH_SALT, DEFAULT_USER_PASSWORD],
        check=True, capture_output=True, text=True,
    )
    password_hash = result.stdout.strip()
    replacement = ROOT_LINE.replace("root::", f"root:{password_hash}:", 1)
    lines[root_positions[0]] = replacement + "\n"
    transformed = "".join(lines)
    gate, reason = inspect_root_shadow(transformed)
    if gate != "PASS":
        raise ValueError("generated root credential failed policy: " + reason)
    if "".join(line for i, line in enumerate(lines) if i != root_positions[0]) != "".join(
        line for i, line in enumerate(source.splitlines(keepends=True)) if i != root_positions[0]
    ):
        raise ValueError("non-root shadow accounts changed unexpectedly")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(transformed)
    output.chmod(0o600)
    print("NR3053_WIFLOW_ROOT_SHADOW_HASH_STAGED_NO_FLASH")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pinned_upstream_shadow", type=Path)
    parser.add_argument("overlay_output", type=Path)
    args = parser.parse_args()
    try:
        provision(args.pinned_upstream_shadow, args.overlay_output)
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print("NR3053_ROOT_PROVISION_BLOCK: " + str(exc)[:300], file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
