"""Review-only root credential report for compiled NR3053 FIT SquashFS.

No plaintext/hash value is ever returned. This distinguishes Wiflow component
integrity from actual root credential safety; not a runtime login test.
"""
from pathlib import Path
import tempfile
import unittest
import shutil
import subprocess
from unittest.mock import patch

from audit_nr3053_wiflow_image import audit, audit_root_shadow_field, root_shadow_static_errors

GOOD = "root:$6$salt1234$" + ("A" * 86) + ":0:0:99999:7:::\n"
BAD = "root:1234:0:0:99999:7:::\n"


class BuiltRootShadowFieldTests(unittest.TestCase):
    def inspect(self, body=None):
        with tempfile.TemporaryDirectory(prefix="nr3053-shadow-audit-") as t:
            fs = Path(t)
            if body is not None:
                f = fs / "etc/shadow"
                f.parent.mkdir(parents=True)
                f.write_text(body, encoding="utf-8")
            return audit_root_shadow_field(fs)

    def test_missing_empty_locked_are_blocked(self):
        for body, expected in (
            (None, "MISSING"),
            ("root::0:0:99999:7:::\n", "EMPTY"),
            ("root:!:0:0:99999:7:::\n", "LOCKED"),
            ("root:*:0:0:99999:7:::\n", "LOCKED"),
            ("root:!$6$salt$secret:0:0:99999:7:::\n", "LOCKED"),
        ):
            with self.subTest(state=expected, body=body):
                result = self.inspect(body)
                self.assertEqual(result["root_password_field_state"], expected)
                self.assertEqual(result["root_shadow_static_check"], "BLOCK")
                self.assertEqual(result["root_credential_release_gate"], "BLOCK")
                self.assertEqual(root_shadow_static_errors(result),
                                 [f"built root credential field unsafe: {expected}"])

    def test_one_supported_hash_is_presence_only_not_release_approval(self):
        result = self.inspect(GOOD)
        self.assertEqual(result["root_password_field_state"],
                         "SHA512_CRYPT_HASH_PRESENT")
        self.assertEqual(result["root_shadow_static_check"], "HASH_PRESENT_ONLY")
        self.assertEqual(result["root_credential_release_gate"], "BLOCK")
        self.assertNotIn("$6$", str(result))
        self.assertEqual(root_shadow_static_errors(result), [])

    def test_duplicate_malformed_plaintext_and_other_hash_rejected(self):
        for body, expected in (
            (GOOD + GOOD, "DUPLICATE"),
            ("root:too:few:fields\n", "MALFORMED"),
            (BAD, "UNSAFE_NONHASHED_FIELD"),
            ("root:$2a$unexpected:0:0:99999:7:::\n", "OTHER_OR_MALFORMED_HASH"),
        ):
            with self.subTest(expected=expected):
                result = self.inspect(body)
                self.assertEqual(result["root_password_field_state"], expected)
                self.assertEqual(result["root_shadow_static_check"], "BLOCK")
                self.assertEqual(result["root_credential_release_gate"], "BLOCK")
                self.assertEqual(root_shadow_static_errors(result),
                                 [f"built root credential field unsafe: {expected}"])
                self.assertNotIn("1234", str(result))
                self.assertNotIn("secret", str(result))

    def test_symlinked_shadow_or_parent_escape_is_blocked(self):
        # These links can otherwise trick an extracted-image audit into
        # inspecting the CI host's credential file rather than FIT contents.
        with tempfile.TemporaryDirectory(prefix="nr3053-shadow-link-") as temp:
            fs = Path(temp) / "rootfs"
            outside = Path(temp) / "outside"
            fs.mkdir()
            outside.mkdir()
            (outside / "shadow").write_text(GOOD, encoding="utf-8")
            etc = fs / "etc"
            etc.mkdir()
            shadow = etc / "shadow"
            shadow.symlink_to(outside / "shadow")
            for location in ("shadow symlink", "etc directory escape"):
                with self.subTest(location=location):
                    result = audit_root_shadow_field(fs)
                    self.assertEqual(result["root_password_field_state"],
                                     "SYMLINK_OR_OUTSIDE_ROOTFS")
                    self.assertEqual(result["root_shadow_static_check"], "BLOCK")
                    self.assertEqual(result["root_credential_release_gate"], "BLOCK")
                    self.assertEqual(root_shadow_static_errors(result),
                                     ["built root credential field unsafe: "
                                      "SYMLINK_OR_OUTSIDE_ROOTFS"])
                    self.assertNotIn("$6$", str(result))
                if location == "shadow symlink":
                    shadow.unlink()
                    etc.rmdir()
                    etc.symlink_to(outside, target_is_directory=True)

    def test_extra_accounts_do_not_change_root_classification(self):
        result = self.inspect("daemon:*:0:0:99999:7:::\n" + GOOD)
        self.assertEqual(result["root_password_field_state"],
                         "SHA512_CRYPT_HASH_PRESENT")

    def test_image_auditor_extracts_actual_etc_shadow_not_source_only(self):
        source = (Path(__file__).resolve().parents[1] /
                  "tools/audit_nr3053_wiflow_image.py").read_text()
        self.assertIn('"www-wiflow-portal", "etc/shadow"', source)
        self.assertIn("root_audit = audit_root_shadow_field(fs)", source)
        self.assertIn("**root_audit,", source)
        self.assertIn("issues.extend(root_shadow_static_errors(root_audit))", source)
        self.assertIn('"static_gate": "BLOCK" if issues else "PASS"', source)
        self.assertIn('"release_approval": "BLOCK"', source)


    def run_complete_audit_on_extracted_fixture(self, shadow):
        """Exercise the REAL FIT audit flow with mock extraction, no binary image.

        This tests that the finished audit result fails even with all 22
        Wiflow files present. The SquashFS extractor itself is mocked; this
        remains host evidence, not a real-image/NR3053 validation.
        """
        source = (Path(__file__).resolve().parents[1] /
                  "package/wiflow-setup/files")
        payload = b"\x00" * 4096 + b"hsqs" + b"\x00" * 8192
        node = {
            "/images/rootfs-1": {
                "data-position": (4096).to_bytes(4, "big"),
                "data-size": (8196).to_bytes(4, "big"),
            }
        }
        def fake_unsquashfs(command, **_kwargs):
            self.assertEqual(command[0], "unsquashfs")
            self.assertIn("etc/shadow", command)
            dest = Path(command[command.index("-d") + 1])
            shutil.copytree(source, dest, dirs_exist_ok=True)
            iw = dest / "usr/bin/iwinfo-ucode"
            iw.parent.mkdir(parents=True, exist_ok=True)
            iw.write_text("host-test-placeholder", encoding="ascii")
            file = dest / "etc/shadow"
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text(shadow, encoding="utf-8")
            return subprocess.CompletedProcess(command, 0, "", "")

        with patch("audit_nr3053_wiflow_image.read_image", return_value=payload), \
             patch("audit_nr3053_wiflow_image.fdt_nodes", return_value=node), \
             patch("audit_nr3053_wiflow_image.shutil.which",
                   return_value="/usr/bin/unsquashfs"), \
             patch("audit_nr3053_wiflow_image.subprocess.run",
                   side_effect=fake_unsquashfs):
            return audit(Path("/never-read-mocked-image.itb"))

    def test_full_image_report_rejects_empty_root_even_if_all_files_exist(self):
        result = self.run_complete_audit_on_extracted_fixture(
            "root::0:0:99999:7:::\n")
        self.assertEqual(result["root_password_field_state"], "EMPTY")
        self.assertEqual(result["static_gate"], "BLOCK")
        self.assertEqual(result["files_checked"], result["found_files"])
        self.assertTrue(any("root credential field unsafe: EMPTY" in e
                            for e in result["errors"]), result["errors"])
        self.assertEqual(result["release_approval"], "BLOCK")

    def test_full_image_report_accepts_hash_shape_but_never_release(self):
        result = self.run_complete_audit_on_extracted_fixture(GOOD)
        self.assertEqual(result["root_shadow_static_check"], "HASH_PRESENT_ONLY")
        self.assertEqual(result["files_checked"], result["found_files"])
        self.assertFalse(any("root credential field unsafe" in e
                             for e in result["errors"]))
        self.assertEqual(result["root_credential_release_gate"], "BLOCK")
        self.assertEqual(result["release_approval"], "BLOCK")
        self.assertNotIn("$6$", str(result))


if __name__ == "__main__":
    unittest.main()
