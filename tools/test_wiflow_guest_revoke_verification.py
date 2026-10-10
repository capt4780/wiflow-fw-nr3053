"""Exercise the exact production guest revocation and disconnect fragments under host mocks.

This verifies failure ordering only, not real NR3053 nft/packet behavior.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

BASE = Path(__file__).resolve().parents[1]
FILES = BASE / "package/wiflow-setup/files/usr/lib/wiflow"
CLIENT = (FILES / "portal-client").read_text(encoding="utf-8")
LOOP = (FILES / "portal-session-loop").read_text(encoding="utf-8")
COMMON = (FILES / "common.sh").read_text(encoding="utf-8")
SID = "abcdef1234567890abcdef12"


def revoke_branch():
    start = CLIENT.index("\nrevoke-session)\n") + len("\nrevoke-session)\n")
    end = CLIENT.index("\n    ;;\nis-authorized)", start)
    return CLIENT[start:end].replace(
        "/usr/lib/wiflow/portal-firewall disable", "fail_closed_disable"
    )


def disconnect_branch():
    start = LOOP.index('if [ "$elapsed" -ge "$DISCONNECT_GRACE" ]; then')
    begin = LOOP.index('                portal_nft_del "$ip" "$mac"', start)
    end = LOOP.index('\n            else\n                client_session_write', begin)
    return LOOP[begin:end].replace(
        "/usr/lib/wiflow/portal-firewall disable", "fail_closed_disable"
    )


def nft_readback_helper():
    begin = COMMON.index("portal_nft_pair_revoked(){")
    end = COMMON.index("\nportal_nft_add(){", begin)
    return COMMON[begin:end].replace("/usr/sbin/nft", "nft_mock")


MOCK = r"""
LOG="$TEST_ROOT/log"
f="$TEST_ROOT/session"
HEARTBEAT_KICK="$TEST_ROOT/kick"
mac=02:11:22:33:44:55
cid=client1
sid=abcdef1234567890abcdef12
value="$sid"
ip=10.10.10.101
connected=10
authorized=20
last=30
absent=60
now=100
acquire_session_lock(){ return 0; }
release_session_lock(){ :; }
client_find_file_by_session(){ printf '%s\n' "$f"; }
portal_nft_del(){
  echo nft_del >> "$LOG"
  [ "$TEST_DELETE" = 1 ] && rm -f "$TEST_ROOT/pair"
  return 0
}
portal_nft_pair_revoked(){ [ "$TEST_READY" = 1 ] && [ ! -f "$TEST_ROOT/pair" ]; }
portal_nft_grant_del(){ echo grant_del >> "$LOG"; }
client_session_write(){
  echo persist >> "$LOG"
  [ "$TEST_PERSIST" = 1 ] || return 1
  printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" > "$1"
}
fail_closed_disable(){
  echo firewall_disable >> "$LOG"
  rm -f "$TEST_ROOT/pair"
}
state_set(){ printf 'state:%s\n' "$2" >> "$LOG"; }
log_client_event(){ printf 'event:%s:%s\n' "$1" "$3" >> "$LOG"; }
event_enqueue(){ echo disconnected_event >> "$LOG"; }
"""


class GuestRevokeVerificationTests(unittest.TestCase):
    def execute(self, *, kind="revoke", delete=True, ready=True, persist=True):
        with tempfile.TemporaryDirectory(prefix="wiflow-guest-revoke-") as tmp:
            root = Path(tmp)
            session = root / "session"
            session.write_text(
                f"02:11:22:33:44:55|client1|{SID}|10.10.10.101|10|20|30|60\n"
            )
            (root / "pair").touch()
            if kind == "revoke":
                script = MOCK + "\n" + revoke_branch()
            else:
                script = MOCK + "\nfor once in 1; do\n" + disconnect_branch() + "\nbreak\ndone\n"
            proc = subprocess.run(
                ["sh", "-c", script], text=True, capture_output=True, timeout=8,
                env={**os.environ, "TEST_ROOT": str(root),
                     "TEST_DELETE": "1" if delete else "0",
                     "TEST_READY": "1" if ready else "0",
                     "TEST_PERSIST": "1" if persist else "0"},
            )
            log = (root / "log").read_text().splitlines()
            state = session.read_text() if session.exists() else None
            self.assertFalse(proc.stderr, proc.stderr)
            return proc.returncode, log, (root / "pair").exists(), state

    def test_revoke_success_requires_nft_readback_before_persisting(self):
        code, log, pair, state = self.execute()
        self.assertEqual(code, 0)
        self.assertFalse(pair)
        self.assertIn("|0|", state)
        self.assertLess(log.index("nft_del"), log.index("grant_del"))
        self.assertLess(log.index("grant_del"), log.index("persist"))
        self.assertIn("event:revoked:verified", log)
        self.assertNotIn("firewall_disable", log)

    def test_revoke_nft_delete_failure_disables_firewall(self):
        code, log, pair, state = self.execute(delete=False)
        self.assertEqual(code, 5)
        self.assertFalse(pair)
        self.assertIn("|0|", state)
        self.assertIn("firewall_disable", log)
        self.assertIn("state:client_revoke_unverified", log)
        self.assertNotIn("grant_del", log)
        self.assertNotIn("event:revoked:verified", log)

    def test_revoke_nft_unavailable_is_not_treated_as_verified(self):
        code, log, pair, state = self.execute(ready=False)
        self.assertEqual(code, 5)
        self.assertFalse(pair)
        self.assertIn("|0|", state)
        self.assertIn("firewall_disable", log)

    def test_revoke_session_persist_failure_must_not_restore_access(self):
        code, log, pair, state = self.execute(persist=False)
        self.assertEqual(code, 7)
        self.assertFalse(pair)
        self.assertIsNone(state)
        self.assertIn("firewall_disable", log)
        self.assertIn("state:client_revoke_persist_failed", log)
        self.assertNotIn("event:revoked:verified", log)

    def test_disconnect_success_clears_session_only_after_nft_readback(self):
        code, log, pair, state = self.execute(kind="disconnect")
        self.assertEqual(code, 0)
        self.assertFalse(pair)
        self.assertIsNone(state)
        self.assertLess(log.index("nft_del"), log.index("grant_del"))
        self.assertIn("disconnected_event", log)
        self.assertNotIn("firewall_disable", log)

    def test_disconnect_nft_delete_failure_keeps_session_and_fails_closed(self):
        code, log, pair, state = self.execute(kind="disconnect", delete=False)
        self.assertEqual(code, 0)
        self.assertFalse(pair)
        self.assertIsNotNone(state)
        self.assertIn("firewall_disable", log)
        self.assertIn("state:client_disconnect_revoke_unverified", log)
        self.assertNotIn("disconnected_event", log)
        self.assertNotIn("grant_del", log)

    def test_disconnect_nft_unavailable_keeps_session(self):
        code, log, pair, state = self.execute(kind="disconnect", ready=False)
        self.assertEqual(code, 0)
        self.assertFalse(pair)
        self.assertIsNotNone(state)
        self.assertIn("firewall_disable", log)
        self.assertNotIn("disconnected_event", log)

    def test_actual_nft_readback_does_not_confuse_command_failure_with_absence(self):
        source = nft_readback_helper()
        for read_ok, present, expected in (
            (True, False, 0), (True, True, 1), (False, False, 1),
        ):
            with self.subTest(read_ok=read_ok, present=present):
                with tempfile.TemporaryDirectory(prefix="wiflow-nft-readback-") as temp:
                    p = Path(temp)
                    pair = "10.10.10.101 . 02:11:22:33:44:55"
                    (p / "dump").write_text(
                        ("elements = { " + pair + " }\n") if present else "elements = { }\n"
                    )
                    script = (
                        'nft_mock(){ [ "$TEST_READ_OK" = 1 ] || return 1; cat "$TEST_ROOT/dump"; }\n'
                        + source
                        + '\nportal_nft_pair_revoked 10.10.10.101 02:11:22:33:44:55\n'
                    )
                    proc = subprocess.run(
                        ["sh", "-c", script], capture_output=True, text=True,
                        env={**os.environ, "TEST_ROOT": str(p),
                             "TEST_READ_OK": "1" if read_ok else "0"}, timeout=5,
                    )
                    self.assertEqual(proc.returncode, expected)
                    self.assertEqual(proc.stderr, "")

    def test_compiled_rootfs_auditor_blocks_missing_revoke_guards(self):
        from audit_nr3053_wiflow_image import audit_captive_revoke_rootfs
        with tempfile.TemporaryDirectory(prefix="wiflow-revoke-image-") as temp:
            root = Path(temp)
            a = root / "usr/lib/wiflow/portal-client"
            b = root / "usr/lib/wiflow/portal-session-loop"
            a.parent.mkdir(parents=True)
            a.write_text(CLIENT)
            b.write_text(LOOP)
            self.assertEqual(audit_captive_revoke_rootfs(root), [])
            a.write_text(CLIENT.replace(
                "state_set portal_error 'client_revoke_unverified'",
                "echo bypassed"))
            self.assertTrue(audit_captive_revoke_rootfs(root))
            a.write_text(CLIENT)
            b.write_text(LOOP.replace(
                "state_set portal_error 'client_disconnect_revoke_unverified'",
                "echo bypassed"))
            self.assertTrue(audit_captive_revoke_rootfs(root))
            b.unlink()
            self.assertTrue(audit_captive_revoke_rootfs(root))


if __name__ == "__main__":
    unittest.main()
