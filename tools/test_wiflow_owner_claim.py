"""Executed host regressions for WPS-bound first-owner claim.

Mocks only UCI device state; executes the actual POSIX shell claim functions.
This is not proof of a physical WPS event on the router.
"""
from pathlib import Path
import os
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "package/wiflow-setup/files"
CLAIM = BASE / "usr/lib/wiflow/owner-claim.sh"
ENROLL = BASE / "www-wiflow/cgi-bin/enroll"
ARM = BASE / "www-wiflow/cgi-bin/claim-arm"
BUTTON = BASE / "etc/rc.wps/00-wiflow-first-owner"
HTML = BASE / "www-wiflow/enroll.html"
GATE_TOKEN = "a" * 64
OTHER_TOKEN = "b" * 64


class PhysicalOwnerClaimTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="nr3053-owner-test-")
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / "claim"
        src = CLAIM.read_text()
        self.assertIn("OWNER_CLAIM_DIR=/tmp/wiflow-owner-claim", src)
        src = src.replace("OWNER_CLAIM_DIR=/tmp/wiflow-owner-claim",
                          "OWNER_CLAIM_DIR=" + str(self.path))
        self.script = Path(self.tmp.name) / "claim.sh"
        self.script.write_text(src)
        self.assertEqual(subprocess.run(["sh", "-n", str(self.script)]).returncode, 0)

    def operation(self, function, token=GATE_TOKEN, ip="10.10.10.101", claimed=False):
        # The same UCI section and setup_password_hash conditions as first boot.
        shell = r'''
uci(){
  if [ "$1" = -q ] && [ "$2" = get ] && [ "$3" = wiflow.core ]; then
    echo core
    return 0
  fi
  if [ "$1" = -q ] && [ "$2" = get ] && [ "$3" = wiflow.core.setup_password_hash ]; then
    if [ "$CLAIMED" = 1 ]; then echo existing; return 0; fi
    return 1
  fi
  return 1
}
. "$CLAIM_SCRIPT"
''' + function + '\n'
        return subprocess.run(
            ["sh", "-c", shell],
            env={**os.environ, "CLAIM_SCRIPT": str(self.script),
                 "CLAIMED": "1" if claimed else "0",
                 "TOKEN": token, "CLIENT_IP": ip},
            capture_output=True, text=True, timeout=5,
        )

    def test_physical_event_one_time_and_bound_to_session_and_ip(self):
        self.assertNotEqual(self.operation("owner_claim_consume \"$TOKEN\" \"$CLIENT_IP\"").returncode, 0)
        self.assertEqual(self.operation("owner_claim_arm \"$TOKEN\" \"$CLIENT_IP\"").returncode, 0)
        self.assertNotEqual(self.operation("owner_claim_consume \"$TOKEN\" \"$CLIENT_IP\"").returncode, 0)
        self.assertEqual(self.operation("owner_claim_wps").returncode, 0)
        self.assertNotEqual(self.operation("owner_claim_consume \"$TOKEN\" \"$CLIENT_IP\"",
                                            token=OTHER_TOKEN).returncode, 0)
        self.assertNotEqual(self.operation("owner_claim_consume \"$TOKEN\" \"$CLIENT_IP\"",
                                            ip="10.10.10.102").returncode, 0)
        self.assertEqual(self.operation("owner_claim_consume \"$TOKEN\" \"$CLIENT_IP\"").returncode, 0)
        self.assertNotEqual(self.operation("owner_claim_consume \"$TOKEN\" \"$CLIENT_IP\"").returncode, 0)

    def test_wps_does_nothing_without_armed_request(self):
        self.assertNotEqual(self.operation("owner_claim_wps").returncode, 0)
        self.assertFalse((self.path / "approved").exists())

    def test_only_one_pending_gate_session_and_device_must_be_unclaimed(self):
        self.assertEqual(self.operation("owner_claim_arm \"$TOKEN\" \"$CLIENT_IP\"").returncode, 0)
        self.assertNotEqual(self.operation("owner_claim_arm \"$TOKEN\" \"$CLIENT_IP\"",
                                            token=OTHER_TOKEN).returncode, 0)
        self.assertNotEqual(self.operation("owner_claim_arm \"$TOKEN\" \"$CLIENT_IP\"",
                                            claimed=True).returncode, 0)
        self.assertNotEqual(self.operation("owner_claim_wps", claimed=True).returncode, 0)

    def test_expired_request_cannot_be_authorized(self):
        self.path.mkdir()
        (self.path / "request").write_text(
            f"{GATE_TOKEN}|10.10.10.101|{int(time.time()) - 10}\n")
        self.assertNotEqual(self.operation("owner_claim_wps").returncode, 0)
        self.assertFalse((self.path / "approved").exists())

    def test_external_addresses_and_invalid_gate_tokens_denied(self):
        self.assertNotEqual(self.operation("owner_claim_arm \"$TOKEN\" \"$CLIENT_IP\"",
                                            ip="192.168.1.9").returncode, 0)
        self.assertNotEqual(self.operation("owner_claim_arm \"$TOKEN\" \"$CLIENT_IP\"",
                                            token="WIFDIDNR3053").returncode, 0)

    def test_endpoints_require_gate_and_wps_instead_of_shared_code_only(self):
        enroll, arm, button, html = (p.read_text() for p in
                                      (ENROLL, ARM, BUTTON, HTML))
        self.assertIn('claim_gate="$(check_gate_session', enroll)
        self.assertIn('owner_claim_consume "$claim_gate" "$REMOTE_ADDR"', enroll)
        self.assertLess(enroll.index('owner_claim_consume '),
                        enroll.index('setup_set_login "$u" "$p"'))
        self.assertIn('owner_claim_arm "$claim_gate" "$REMOTE_ADDR"', arm)
        self.assertIn("[ \"$HTTP_ORIGIN\" = 'http://10.0.0.1' ]", arm)
        self.assertIn('[ "${BUTTON:-}" = wps ]', button)
        self.assertIn('[ "${ACTION:-}" = released ]', button)
        self.assertIn('owner_claim_wps', button)
        self.assertNotIn("|| true", button)
        self.assertTrue(BUTTON.stat().st_mode & 0o100)
        self.assertIn('owner_claim_wps', button)
        self.assertIn("disabled>2. Sau khi nhấn WPS", html)
        self.assertNotIn("owner_claim_wps", enroll)


if __name__ == "__main__":
    unittest.main()
