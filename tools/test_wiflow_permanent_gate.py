"""Executed regressions for the permanent NR3053 shared Gate verifier.

The verifier opens the first security Gate, not Setup/LuCI account login.
Emergency Gate is available on management or Wiflow guest IPs. Tests are E3 host
checks, NOT tests of NR3053 runtime or network filtering.
"""
import os
from pathlib import Path
import subprocess
import unittest

SOURCE = (Path(__file__).resolve().parents[1] /
          "package/wiflow-setup/files/usr/lib/wiflow/gate-code.sh")


class PermanentGateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.verifier = SOURCE.read_text(encoding="utf-8")

    def try_code(self, entered, expected="221262", remote="10.0.0.45", enrolled=False):
        script = self.verifier + '\nwiflow_gate_code_allowed "$WF_CODE" "$WF_DEVICE_PIN"\n'
        env = {**os.environ, "WF_CODE": entered, "WF_DEVICE_PIN": expected,
               "REMOTE_ADDR": remote, "SIM_ENROLLED": "1" if enrolled else "0"}
        run = subprocess.run(["sh", "-c", script], env=env, capture_output=True,
                             text=True, timeout=5)
        return run.returncode

    def test_normal_device_pin_before_and_after_enrollment(self):
        for enrolled in (False, True):
            self.assertEqual(self.try_code("221262", enrolled=enrolled), 0)
            self.assertNotEqual(self.try_code("221263", enrolled=enrolled), 0)

    def test_emergency_code_always_available_on_management_network(self):
        for enrolled in (False, True):
            self.assertEqual(self.try_code("WIFDIDNR3053", enrolled=enrolled), 0)

    def test_emergency_code_available_before_device_id_generated(self):
        self.assertEqual(self.try_code("WIFDIDNR3053", expected=""), 0)
        self.assertNotEqual(self.try_code("221262", expected=""), 0)

    def test_emergency_always_available_for_wiflow_guest(self):
        for ip in ("10.10.10.3", "10.10.10.17", "10.10.10.249"):
            for enrolled in (False, True):
                with self.subTest(ip=ip, enrolled=enrolled):
                    self.assertEqual(self.try_code("WIFDIDNR3053", remote=ip,
                                                   enrolled=enrolled), 0)

    def test_emergency_rejected_outside_management_and_guest(self):
        for addr in ("192.168.1.23", "172.16.0.4", "", "127.0.0.1",
                     "10.10.11.5", "8.8.8.8"):
            with self.subTest(address=addr):
                self.assertNotEqual(self.try_code("WIFDIDNR3053", remote=addr), 0)

    def test_incorrect_emergency_codes_are_rejected(self):
        for entered in ("247365", "WIFDIDNR3052", "WIFDIDNR3053 ",
                        "wifdidnr3053", "WIFDID-NR3053", ""):
            with self.subTest(code=entered):
                self.assertNotEqual(self.try_code(entered), 0)

    def test_only_one_canonical_emergency_function_exists(self):
        self.assertEqual(self.verifier.count("wiflow_gate_code_allowed(){"), 1)
        self.assertNotIn("setup-claimed", self.verifier)
        self.assertNotIn("setup_password_hash", self.verifier)
        self.assertNotIn("first_use", self.verifier)


if __name__ == "__main__":
    unittest.main()
