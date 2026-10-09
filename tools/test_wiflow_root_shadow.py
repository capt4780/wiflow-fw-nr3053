"""Executed root shadow provisioning and exact-built-image audit regressions."""
from pathlib import Path
import os
import stat
import subprocess
import tempfile
import unittest

from provision_nr3053_root_shadow import inspect_root_shadow, provision, ROOT_LINE

ROOT = Path(__file__).resolve().parents[1]
BUILD = (ROOT / "scripts/build-nr3053-base.sh").read_text()
AUDIT = (ROOT / "tools/audit_nr3053_wiflow_image.py").read_text()
EXTRA = "daemon:*:0:0:99999:7:::\nftp:*:0:0:99999:7:::\n"


class RootShadowProvisioningTests(unittest.TestCase):
    def test_missing_empty_duplicate_locked_plaintext_rejected(self):
        for content in ("", "daemon:*:0:0:99999:7:::\n", ROOT_LINE + "\n",
                        "root:!:0:99999:7:::\n", "root:*:0:99999:7:::\n",
                        "root:1234:0:99999:7:::\n", ROOT_LINE + "\n" + ROOT_LINE + "\n"):
            with self.subTest(content=content[:25]):
                self.assertEqual(inspect_root_shadow(content)[0], "BLOCK")

    def test_provision_preserves_other_accounts_and_makes_root_hashed(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "upstream"
            overlay = Path(tmp) / "files/etc/shadow"
            source.write_text(ROOT_LINE + "\n" + EXTRA)
            provision(source, overlay)
            actual = overlay.read_text()
            self.assertEqual(inspect_root_shadow(actual)[0], "PASS")
            self.assertEqual(actual.splitlines()[1:], EXTRA.splitlines())
            self.assertTrue(actual.splitlines()[0].startswith("root:$6$"))
            self.assertEqual(stat.S_IMODE(overlay.stat().st_mode), 0o600)
            self.assertNotIn("root:::", actual)
            self.assertNotIn("root:1234:", actual)

    def test_upstream_drift_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            upstream = Path(tmp) / "upstream"
            overlay = Path(tmp) / "overlay"
            upstream.write_text("root:$6$existing$hash:0:99999:7:::\n" + EXTRA)
            with self.assertRaisesRegex(ValueError, "drifted"):
                provision(upstream, overlay)
            self.assertFalse(overlay.exists())

    def test_actual_firmware_build_stages_and_audits_hash(self):
        self.assertIn("tools/provision_nr3053_root_shadow.py", BUILD)
        self.assertIn("package/base-files/files/etc/shadow files/etc/shadow", BUILD)
        self.assertLess(BUILD.index("provision_nr3053_root_shadow.py"),
                        BUILD.index("./scripts/feeds update -a"))
        self.assertIn('"etc/shadow"', AUDIT)
        self.assertIn('inspect_root_shadow(shadow.read_text(errors="replace"))', AUDIT)
        self.assertIn('"root_shadow_gate"', AUDIT)
        self.assertIn('"root_login_tested": False', AUDIT)


if __name__ == "__main__":
    unittest.main()
