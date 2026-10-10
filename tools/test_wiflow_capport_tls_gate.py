"""CAPPORT RFC 8908/8910 pre-advertisement safety gate.

No router currently runs Wiflow. This verifies source and synthetic SquashFS
only; it is not evidence of a TLS certificate or real Android CAPPORT support.
"""
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "package/wiflow-setup/files"
COMMON = PACKAGE / "usr/lib/wiflow/common.sh"
LEGACY_API = PACKAGE / "www-wiflow-portal/cgi-bin/captive-api"


class CAPPORTTLSGateTests(unittest.TestCase):
    def test_no_insecure_option_114_advertisement(self):
        text = COMMON.read_text()
        self.assertNotIn("dhcp.wiflow_guest.dhcp_option='114,", text)
        self.assertIn("dhcp.wiflow_guest.dhcp_option='6,10.10.10.1'", text)
        self.assertIn("uci -q delete dhcp.wiflow_guest.dhcp_option", text)
        self.assertNotIn("http://10.10.10.1:2080/cgi-bin/captive-api", text)

    def test_http_capport_stub_is_not_shipped(self):
        self.assertFalse(LEGACY_API.exists())

    def test_built_squashfs_audit_rejects_invalid_capport(self):
        from audit_nr3053_wiflow_image import audit_capport_tls_gate_rootfs
        with tempfile.TemporaryDirectory(prefix="wiflow-capport-gate-") as temp:
            root = Path(temp)
            common = root / "usr/lib/wiflow/common.sh"
            common.parent.mkdir(parents=True)
            baseline = COMMON.read_text()
            common.write_text(baseline)
            self.assertEqual(audit_capport_tls_gate_rootfs(root), [])
            common.write_text(
                baseline + "\nuci add_list dhcp.wiflow_guest.dhcp_option="
                "'114,http://10.10.10.1:2080/cgi-bin/captive-api'\n"
            )
            self.assertTrue(audit_capport_tls_gate_rootfs(root))
            common.write_text(baseline)
            legacy = root / "www-wiflow-portal/cgi-bin/captive-api"
            legacy.parent.mkdir(parents=True)
            legacy.write_text("obsolete")
            self.assertTrue(audit_capport_tls_gate_rootfs(root))
            legacy.unlink()
            common.write_text(baseline.replace(
                "dhcp.wiflow_guest.dhcp_option='6,10.10.10.1'",
                "dhcp.wiflow_guest.dhcp_option='6,8.8.8.8'"))
            self.assertTrue(audit_capport_tls_gate_rootfs(root))


if __name__ == "__main__":
    unittest.main()
