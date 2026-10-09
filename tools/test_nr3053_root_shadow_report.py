"""Review-only root credential report for compiled NR3053 FIT SquashFS.

No plaintext/hash value is ever returned. This distinguishes Wiflow component
integrity from actual root credential safety; not a runtime login test.
"""
from pathlib import Path
import tempfile
import unittest

from audit_nr3053_wiflow_image import audit_root_shadow_field, root_shadow_static_errors

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


if __name__ == "__main__":
    unittest.main()
