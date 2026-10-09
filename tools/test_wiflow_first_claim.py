"""Execute the actual first-owner emergency-gate shell function with stubbed UCI.

This tests only the helper's local authorization predicate, not on-device
network isolation, uhttpd, LuCI or full firmware boot.
"""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


COMMON = (Path(__file__).resolve().parents[1] /
          "package/wiflow-setup/files/usr/lib/wiflow/common.sh")


class FirstOwnerEmergencyGateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = COMMON.read_text(encoding="utf-8")
        match = re.search(
            r"(?ms)^first_use_emergency_gate\(\)\{\n.*?^\}\n", source
        )
        if not match:
            raise AssertionError("authoritative first-use gate missing")
        cls.function = match.group()

    def run_case(self, code="WIFDIDNR3053", remote="10.0.0.51",
                 password_hash="", password_salt="", claimed=False):
        with tempfile.TemporaryDirectory(prefix="wiflow-first-claim-") as folder:
            root = Path(folder)
            if claimed:
                (root / "setup-claimed").write_text("claimed\n")
            script = """#!/bin/sh
ROOT="$1"
REMOTE_ADDR="$2"
WIFLOW_FIRST_USE_GATE_CODE='WIFDIDNR3053'
uci() {
    case "$3" in
        wiflow.core.setup_password_hash) printf '%s' "$SIM_PASSWORD_HASH";;
        wiflow.core.setup_password_salt) printf '%s' "$SIM_PASSWORD_SALT";;
        *) return 1;;
    esac
}
""" + self.function + "\nfirst_use_emergency_gate \"$3\"\n"
            res = subprocess.run(
                ["sh", "-c", script, "sh", str(root), remote, code],
                capture_output=True, text=True, timeout=5,
                env={**os.environ, "SIM_PASSWORD_HASH": password_hash,
                     "SIM_PASSWORD_SALT": password_salt},
            )
            return res.returncode

    def test_first_use_on_management_lan_works(self):
        self.assertEqual(self.run_case(), 0)

    def test_other_codes_blocked(self):
        for value in ("247365", "WIFDIDNR3052", "WIFDIDNR3053 ", "123456"):
            with self.subTest(value=value):
                self.assertNotEqual(self.run_case(code=value), 0)

    def test_outside_management_lan_blocked(self):
        for addr in ("192.168.1.3", "10.10.10.9", "", "1.2.3.4"):
            with self.subTest(addr=addr):
                self.assertNotEqual(self.run_case(remote=addr), 0)

    def test_claimed_device_blocked_even_without_password_config(self):
        self.assertNotEqual(self.run_case(claimed=True), 0)

    def test_provisioned_password_blocks_emergency(self):
        self.assertNotEqual(self.run_case(password_hash="deadbeef"), 0)
        self.assertNotEqual(self.run_case(password_salt="f00dbabe"), 0)


if __name__ == "__main__":
    unittest.main()
