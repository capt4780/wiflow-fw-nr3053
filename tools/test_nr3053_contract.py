"""Contract regression tests for non-secret Wiflow NR3053 baseline facts.

These checks prove contract consistency only; they do not test hardware runtime.
"""
import json
from pathlib import Path
import re
import unittest

ROOT=Path(__file__).resolve().parents[1]
CONTRACT=ROOT/"reference/wiflow-nr3053-contract.json"


class BaselineContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.c=json.loads(CONTRACT.read_text(encoding="utf-8"))

    def test_public_contract_has_no_raw_private_baseline(self):
        self.assertEqual(self.c["baseline"]["private_baseline_uploaded_to_repo"],False)
        for key in ("sha256","wordpress_sha256","device_ipk_sha256"):
            self.assertRegex(self.c["baseline"][key],r"^[a-f0-9]{64}$")

    def test_wp_api_matches_embedded_agent_generation(self):
        c=self.c
        self.assertEqual(c["remote"]["data_generation"],4)
        self.assertEqual(c["remote"]["api_version"],1)
        self.assertEqual(c["remote"]["portal_snapshot_schema"],2)
        base=c["remote"]["rest_root"]
        self.assertEqual(base,"https://projify.io.vn/wiflow/wp-json")
        self.assertEqual(c["remote"]["devices_api"],base+"/devices")
        self.assertEqual(c["remote"]["portal_api"],base+"/portal")
        self.assertEqual(c["remote"]["device_methods"],{"pair":"POST","heartbeat":"POST","sync":"GET","unpair":"POST"})
        self.assertEqual(c["remote"]["portal_methods"],{"manifest":"GET","media":"GET","ack":"POST"})

    def test_nr3053_identity_not_cr6609(self):
        self.assertEqual(self.c["device"]["board"],"viettel,nr3053")
        self.assertEqual(self.c["device"]["identity_prefix"],"WIFDID-NR3053-")
        self.assertNotEqual(self.c["device"]["identity_prefix"],self.c["porting"]["source_identity_old_prefix"])
        self.assertEqual(self.c["device"]["identity_prefix"],self.c["porting"]["source_identity_target_prefix"])

    def test_local_network_boundaries_are_explicit(self):
        d=self.c["device"]
        self.assertEqual((d["setup_address"],d["luci_gate_address"],d["guest_gateway"]),("10.0.0.1","10.0.0.2","10.10.10.1"))
        self.assertEqual(d["guest_subnet"],"10.10.10.0/24")
        self.assertEqual(d["mode_values"],["website","image","video"])
        self.assertEqual(len(d["primary_media_roles"]),4)
        self.assertEqual(len(d["popup_roles"]),5)

    def test_atomic_media_contract_and_dns_pre_auth(self):
        d=self.c["device"]
        self.assertIn("atomic activation",d["portal_media_policy"])
        self.assertIn("TCP/853",d["private_dns_pre_auth"])
        self.assertIn("otherwise-blocked guest Internet",d["private_dns_pre_auth"])

    def test_never_mark_unverified_firmware_as_flash_ready(self):
        self.assertEqual(self.c["device"]["package_manager"],"apk")
        self.assertEqual(self.c["porting"]["new_package_format"],"ImmortalWrt 25.12 APK-native source package")
        self.assertTrue(self.c["release_gates"])
        for gate,status in self.c["release_gates"].items():
            self.assertEqual(status,"BLOCK",gate)


if __name__=="__main__":
    unittest.main()
