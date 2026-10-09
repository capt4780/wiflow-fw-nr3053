"""Static extracted-rootfs audit tests for first-owner + autostart packaging."""
from pathlib import Path
import os
import shutil
import tempfile
import unittest

from audit_nr3053_wiflow_image import audit_first_owner_and_boot_rootfs

SRC = Path(__file__).resolve().parents[1] / "package/wiflow-setup/files"
PARTS = (
    "www-wiflow/cgi-bin/enroll", "www-wiflow/cgi-bin/claim-arm",
    "usr/lib/wiflow/owner-claim.sh",
    "etc/rc.wps/00-wiflow-first-owner",
    "etc/init.d/wiflow-setup",
    "www-wiflow/cgi-bin/gate", "www-wiflow-luci-gate/cgi-bin/unlock",
)


class FirstOwnerImageAuditTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="wiflow-rootfs-test-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for rel in PARTS:
            target = self.root / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(SRC / rel, target)
        rc = self.root / "etc/rc.d"
        rc.mkdir(parents=True, exist_ok=True)
        (rc / "S96wiflow-setup").symlink_to("../init.d/wiflow-setup")

    def test_selected_image_static_controls_pass(self):
        self.assertEqual(audit_first_owner_and_boot_rootfs(self.root), [])

    def test_missing_autostart_is_block(self):
        (self.root / "etc/rc.d/S96wiflow-setup").unlink()
        self.assertTrue(any("not enabled" in x for x in
                            audit_first_owner_and_boot_rootfs(self.root)))

    def test_non_executable_enrollment_is_block(self):
        (self.root / "www-wiflow/cgi-bin/enroll").chmod(0o644)
        self.assertTrue(any("executable" in x for x in
                            audit_first_owner_and_boot_rootfs(self.root)))

    def test_missing_physical_button_wiring_is_block(self):
        (self.root / "etc/rc.wps/00-wiflow-first-owner").unlink()
        self.assertTrue(any("rc.wps/00" in x for x in
                            audit_first_owner_and_boot_rootfs(self.root)))

    def test_non_executable_wps_handler_is_block(self):
        (self.root / "etc/rc.wps/00-wiflow-first-owner").chmod(0o644)
        self.assertTrue(any("executable" in x for x in
                            audit_first_owner_and_boot_rootfs(self.root)))

    def test_legacy_enrollment_without_one_use_claim_is_block(self):
        e = self.root / "www-wiflow/cgi-bin/enroll"
        e.write_text(e.read_text().replace(
            'owner_claim_consume "$claim_gate" "$REMOTE_ADDR"', "# removed"))
        self.assertTrue(any("owner_claim_consume" in x for x in
                            audit_first_owner_and_boot_rootfs(self.root)))


if __name__ == "__main__":
    unittest.main()
