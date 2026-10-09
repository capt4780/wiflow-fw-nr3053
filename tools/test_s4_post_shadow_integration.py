"""CI-only source integration tests for final PR #14 and PR #17 heads.
Mocks SquashFS extraction; no target runtime, no flash, no real credentials.
"""
from pathlib import Path
import unittest
from unittest.mock import patch

import test_nr3053_root_shadow_report as shadow_tests
from audit_nr3053_wiflow_image import audit_captive_mutation_rootfs


class CombinedSafetyGates(unittest.TestCase):
    def test_hash_shape_and_captive_post_guard_coexist(self):
        fixture = shadow_tests.BuiltRootShadowFieldTests()
        result = fixture.run_complete_audit_on_extracted_fixture(shadow_tests.GOOD)
        self.assertEqual(result["root_shadow_static_check"], "HASH_PRESENT_ONLY")
        self.assertEqual(result["root_credential_release_gate"], "BLOCK")
        self.assertFalse(any("captive authorization" in e for e in result["errors"]), result["errors"])

    def test_empty_root_blocks_even_with_captive_guard(self):
        fixture = shadow_tests.BuiltRootShadowFieldTests()
        result = fixture.run_complete_audit_on_extracted_fixture(
            "root::0:0:99999:7:::" + chr(10))
        self.assertEqual(result["root_password_field_state"], "EMPTY")
        self.assertEqual(result["static_gate"], "BLOCK")
        self.assertTrue(any("root credential field unsafe: EMPTY" in e
                            for e in result["errors"]), result["errors"])
        self.assertFalse(any("captive authorization" in e for e in result["errors"]), result["errors"])

    def test_missing_captive_guard_fails_image_audit(self):
        fixture = shadow_tests.BuiltRootShadowFieldTests()
        with patch("audit_nr3053_wiflow_image.audit_captive_mutation_rootfs",
                   return_value=["captive authorization POST/body-only gate missing"]) as guard:
            result = fixture.run_complete_audit_on_extracted_fixture(shadow_tests.GOOD)
        guard.assert_called_once()
        self.assertEqual(result["static_gate"], "BLOCK")
        self.assertIn("captive authorization POST/body-only gate missing",
                      result["errors"])

    def test_captive_guard_embedded_in_package_source(self):
        portal = (Path(__file__).resolve().parents[1] /
                  "package/wiflow-setup/files/www-wiflow-portal/cgi-bin/portal")
        self.assertTrue(portal.is_file())
        self.assertEqual(audit_captive_mutation_rootfs(portal.parents[2]), [])


if __name__ == "__main__":
    unittest.main()
