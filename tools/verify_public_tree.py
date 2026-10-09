#!/usr/bin/env python3
"""Guard the public firmware repository from proprietary archives and credentials.

Security boundary: this protects *tracked Git files*. Never rely on it as the
only protection for a secret; use private build inputs and manual review.
"""
from __future__ import annotations

import argparse
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys

BLOCKED_SUFFIXES = (
    ".zip", ".7z", ".rar", ".tar", ".tgz", ".tar.gz", ".itb",
    ".ipk", ".apk", ".bin", ".img", ".sqlite", ".sqlite3",
    ".p12", ".pfx", ".pem", ".key", ".ovpn", ".enc",
)
BLOCKED_COMPONENTS = frozenset({
    "private", "secrets", "backups", "backup", "uploads", "output",
    "artifacts", "wp-content", "credentials", "site-backup",
    "device-media", "restore",
})
CREDENTIAL_PATTERNS = (
    ("private key", re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----")),
    ("GitHub access token", re.compile(rb"\b(?:ghp_|gho_|ghu_|ghs_|ghr_|github_pat_)[A-Za-z0-9_]{20,}\b")),
    ("authorization bearer token", re.compile(rb"\bAuthorization\s*:\s*Bearer\s+[A-Za-z0-9_.~+/=-]{20,}", re.I)),
    ("hardcoded credential", re.compile(
        rb"\b(?:api_key|api_secret|client_secret|wp_token|access_token|refresh_token|device_token|password)\b"
        rb"\s*[:=]\s*['\"]?[A-Za-z0-9+/._-]{24,}", re.I)),
)
MAX_TEXT_BYTES = 1_000_000


def check_entry(relative: str, data: bytes, *, symlink: bool = False) -> list[str]:
    issues: list[str] = []
    path = PurePosixPath(relative)
    basename = path.name.lower()
    if relative.startswith("/") or any(p in ("", ".", "..") for p in path.parts):
        issues.append("unsafe path")
    if symlink:
        issues.append("symlink is not approved for public source build")
    if basename == ".env" or basename.startswith(".env.") or basename.endswith(BLOCKED_SUFFIXES):
        issues.append("proprietary or binary archive extension prohibited")
    if any(component.lower() in BLOCKED_COMPONENTS for component in path.parts[:-1]):
        issues.append("private or generated directory not allowed")
    if b"\0" in data or len(data) > MAX_TEXT_BYTES:
        issues.append("non-text or oversized content cannot be reviewed in Git")
    else:
        for label, pattern in CREDENTIAL_PATTERNS:
            if pattern.search(data):
                issues.append("possible " + label)
    return issues


def audit(root: Path) -> list[str]:
    listed = subprocess.check_output(
        ["git", "-C", str(root), "ls-files", "-z", "--cached"],
        stderr=subprocess.STDOUT,
    ).split(b"\0")
    violations = []
    for raw in listed:
        if not raw:
            continue
        relative = raw.decode("utf-8", "surrogateescape")
        target = root / relative
        if not target.is_file() and not target.is_symlink():
            violations.append(f"{relative}: tracked item missing")
            continue
        data = target.read_bytes()
        for reason in check_entry(relative, data, symlink=target.is_symlink()):
            violations.append(f"{relative}: {reason}")
    return violations


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    try:
        problems = audit(args.repo)
    except (OSError, subprocess.CalledProcessError, UnicodeError) as exc:
        print("PUBLIC_SOURCE_AUDIT_BLOCK: " + str(exc), file=sys.stderr)
        return 2
    for p in problems:
        print("PUBLIC_SOURCE_AUDIT_BLOCK: " + p, file=sys.stderr)
    if problems:
        print("PUBLIC_SOURCE_BLOCKED_ITEMS=" + str(len(problems)), file=sys.stderr)
        return 2
    print("PUBLIC_SOURCE_SAFETY_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
