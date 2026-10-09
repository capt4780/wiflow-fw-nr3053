"""CI-only guard against losing either S3/S4 FIT rootfs check on merge.

This is host static integration evidence, not hardware/runtime verification.
"""
from pathlib import Path
from shutil import copyfile
import tempfile
import unittest

from audit_nr3053_wiflow_image import (
    audit_captive_mutation_rootfs,
    audit_root_shadow_field,
    root_shadow_static_errors,
)

ROOT = Path(__file__).resolve().parents[1]
AUDITOR = ROOT / "tools/audit_nr3053_wiflow_image.py"


class S3S4CombinedImageGuardTests(unittest.TestCase):
    def test_missing_captive_and_empty_root_both_fail_independently(self):
        with tempfile.TemporaryDirectory(prefix="wiflow-combined-guard-") as tmp:
            fs = Path(tmp)
            shadow = fs / "etc/shadow"
            shadow.parent.mkdir(parents=True)
            shadow.write_text("root::0:0:99999:7:::\n")
            root = audit_root_shadow_field(fs)
            self.assertEqual(root["root_password_field_state"], "EMPTY")
            self.assertTrue(root_shadow_static_errors(root))
            self.assertTrue(audit_captive_mutation_rootfs(fs))

    def test_symlinked_shadow_blocks_while_captive_post_guard_passes(self):
        with tempfile.TemporaryDirectory(prefix="wiflow-combined-link-") as tmp:
            fs = Path(tmp) / "rootfs"
            outside = Path(tmp) / "outside"
            fs.mkdir()
            outside.mkdir()
            (outside / "shadow").write_text(
                "root:$6$salt1234$" + ("A" * 86) + ":0:0:99999:7:::\n",
                encoding="utf-8",
            )
            (fs / "etc").symlink_to(outside, target_is_directory=True)
            portal = fs / "www-wiflow-portal/cgi-bin/portal"
            portal.parent.mkdir(parents=True)
            copyfile(ROOT / "package/wiflow-setup/files/www-wiflow-portal/cgi-bin/portal", portal)
            finding = audit_root_shadow_field(fs)
            self.assertEqual(finding["root_password_field_state"],
                             "SYMLINK_OR_OUTSIDE_ROOTFS")
            self.assertTrue(root_shadow_static_errors(finding))
            self.assertEqual(audit_captive_mutation_rootfs(fs), [])

    def test_final_image_static_gate_includes_both_checks(self):
        s = AUDITOR.read_text(encoding="utf-8")
        self.assertIn("root_audit = audit_root_shadow_field(fs)", s)
        self.assertIn("issues.extend(root_shadow_static_errors(root_audit))", s)
        self.assertIn("issues.extend(audit_captive_mutation_rootfs(fs))", s)
        self.assertIn('"static_gate": "BLOCK" if issues else "PASS"', s)
        self.assertIn('"release_approval": "BLOCK"', s)


if __name__ == "__main__":
    unittest.main()
