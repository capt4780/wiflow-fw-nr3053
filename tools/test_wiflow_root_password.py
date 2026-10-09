"""Credential inspection for compiled NR3053 rootfs, not target runtime proof."""
from pathlib import Path
import tempfile
import unittest
from audit_nr3053_wiflow_image import audit_root_password_rootfs


class CompiledLuCIRootCredentialTests(unittest.TestCase):
    def test_empty_password_is_release_block(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "etc/shadow"
            p.parent.mkdir()
            p.write_text("root:::0:99999:7:::\n")
            self.assertTrue(any("empty password" in x for x in
                                audit_root_password_rootfs(Path(d))))

    def test_locked_account_without_provisioned_login_is_block(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "etc/shadow"
            p.parent.mkdir()
            p.write_text("root:!:0:0:99999:7:::\n")
            self.assertTrue(any("locked" in x for x in
                                audit_root_password_rootfs(Path(d))))

    def test_missing_shadow_is_block(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertTrue(audit_root_password_rootfs(Path(d)))

    def test_one_hash_passes_static_format_but_not_runtime_login(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "etc/shadow"
            p.parent.mkdir()
            p.write_text("root:$6$static-placeholder$hash:0:0:99999:7:::\n")
            self.assertEqual(audit_root_password_rootfs(Path(d)), [])

    def test_duplicate_root_entries_block(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "etc/shadow"
            p.parent.mkdir()
            p.write_text("root:$6$salt$hash:0:0:99999:7:::\nroot:::0:0:99999:7:::\n")
            self.assertTrue(audit_root_password_rootfs(Path(d)))


if __name__ == "__main__":
    unittest.main()
