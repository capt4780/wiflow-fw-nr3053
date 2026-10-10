"""Execute production Portal authorize-session branch under host nft/session mocks.

These regressions are not actual NR3053 network/packet evidence.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SOURCE = (
    Path(__file__).resolve().parents[1]
    / "package/wiflow-setup/files/usr/lib/wiflow/portal-client"
).read_text(encoding="utf-8")


def production_authorize_branch():
    # Exercise the production rollback helper AND its three actual call sites.
    helper_start = SOURCE.index("rollback_authorization_pair(){")
    helper_end = SOURCE.index('\ncase "$mode" in', helper_start)
    start = SOURCE.index("\nauthorize-session)\n") + len("\nauthorize-session)\n")
    stop = SOURCE.index("\n    ;;\nrevoke-session)", start)
    return (SOURCE[helper_start:helper_end] + "\n" + SOURCE[start:stop]).replace(
        "/usr/lib/wiflow/portal-firewall disable", "fail_closed_disable"
    )


class PortalAuthPersistenceTests(unittest.TestCase):
    def exercise(self, *, persist=True, verify=True, deletion=True, readback=True, add_ok=True, firewall_ok=True):
        with tempfile.TemporaryDirectory(prefix="wiflow-auth-rollback-") as tmp:
            root = Path(tmp)
            session = root / "session"
            session.write_text("02:11:22:33:44:55|client1|abcdef1234567890abcdef12|10.10.10.101|10|0|20|0\n")
            (root / "portal.json").write_text('{"revision":27}\n')
            script = r"""
value=abcdef1234567890abcdef12
expected_client=client1
HEARTBEAT_KICK="$TEST_ROOT/kick"
EVENT_LOG="$TEST_ROOT/events"
PAIR_FILE="$TEST_ROOT/authorized"
TEST_SESSION="$TEST_ROOT/session"
PORTAL_ACTIVE="$TEST_ROOT"
LOG="$TEST_ROOT/log"
uci(){ echo 1; }
log_client_event(){ printf "log:%s\n" "$3" >> "$LOG"; }
acquire_session_lock(){ return 0; }
release_session_lock(){ :; }
client_find_file_by_session(){ printf '%s\n' "$TEST_SESSION"; }
valid_guest_ip(){ [ "$1" = 10.10.10.101 ]; }
portal_nft_ready(){ return 0; }
portal_nft_pair_granted(){ return 0; }
portal_nft_add(){
 printf "nft_add\n" >> "$LOG"
 : > "$PAIR_FILE"
 [ "$TEST_ADD_OK" = 1 ]
}
portal_nft_pair_revoked(){
 [ "$TEST_READBACK" = 1 ] && [ ! -f "$PAIR_FILE" ]
}
state_set(){ printf "state:%s\n" "$2" >> "$LOG"; }
portal_nft_del(){
 printf "nft_del\n" >> "$LOG"
 [ "$TEST_DELETE" = 0 ] || rm -f "$PAIR_FILE"
}
portal_nft_pair_authorized(){
 if [ "$TEST_VERIFY" = 0 ]; then return 1; fi
 [ -f "$PAIR_FILE" ]
}
portal_nft_grant_del(){ printf "grant_consumed\n" >> "$LOG"; }
client_session_write(){
 printf "persist_attempt\n" >> "$LOG"
 [ "$TEST_PERSIST" = 1 ] || return 1
 printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" > "$1"
}
event_enqueue(){ printf "event\n" >> "$EVENT_LOG"; }
flush_captive_conntrack(){ printf "conntrack\n" >> "$LOG"; }
fail_closed_disable(){
 printf "firewall_disabled\n" >> "$LOG"
 [ "$TEST_FW_OK" = 1 ] || return 1
 rm -f "$PAIR_FILE"
}
""" + production_authorize_branch()
            proc = subprocess.run(
                ["sh", "-c", script], capture_output=True, text=True,
                env={**os.environ, "TEST_ROOT": str(root),
                     "TEST_PERSIST": "1" if persist else "0",
                     "TEST_VERIFY": "1" if verify else "0",
                     "TEST_DELETE": "1" if deletion else "0",
                     "TEST_READBACK": "1" if readback else "0",
                     "TEST_ADD_OK": "1" if add_ok else "0",
                     "TEST_FW_OK": "1" if firewall_ok else "0"},
                timeout=8,
            )
            self.assertEqual(proc.stdout, "")
            self.assertEqual(proc.stderr, "")
            log = (root / "log").read_text().splitlines()
            authed = (root / "authorized").exists()
            event = (root / "events").exists()
            return proc.returncode, log, authed, event

    def test_success_persists_before_consuming_grant_and_flush(self):
        code, log, authed, event = self.exercise()
        self.assertEqual(code, 0)
        self.assertTrue(authed)
        self.assertTrue(event)
        for name in ("nft_add", "persist_attempt", "grant_consumed", "conntrack"):
            self.assertIn(name, log)
        self.assertLess(log.index("nft_add"), log.index("persist_attempt"))
        self.assertLess(log.index("persist_attempt"), log.index("grant_consumed"))
        self.assertLess(log.index("grant_consumed"), log.index("conntrack"))

    def test_session_write_failure_rolls_back_without_consuming_grant(self):
        code, log, authed, event = self.exercise(persist=False)
        self.assertEqual(code, 7)
        self.assertEqual(log, [
            "nft_add", "persist_attempt", "nft_del", "log:persist",
        ])
        self.assertFalse(authed)
        self.assertFalse(event)

    def test_nft_verify_failure_attempts_rollback_before_persistence(self):
        code, log, authed, event = self.exercise(verify=False)
        self.assertEqual(code, 5)
        self.assertIn("nft_del", log)
        self.assertIn("log:policy_verify", log)
        self.assertNotIn("persist_attempt", log)
        self.assertNotIn("grant_consumed", log)
        self.assertFalse(authed)
        self.assertFalse(event)

    def test_failed_nft_deletion_forces_firewall_closed(self):
        code, log, authed, event = self.exercise(persist=False, deletion=False)
        self.assertEqual(code, 7)
        self.assertIn("firewall_disabled", log)
        self.assertIn("log:rollback_unverified", log)
        self.assertFalse(authed)
        self.assertFalse(event)

    def test_nft_readback_error_after_persistence_failure_is_fail_closed(self):
        code, log, authed, event = self.exercise(persist=False, readback=False)
        self.assertEqual(code, 7)
        self.assertIn("firewall_disabled", log)
        self.assertIn("state:client_authorize_rollback_unverified", log)
        self.assertIn("log:rollback_unverified", log)
        self.assertNotIn("grant_consumed", log)
        self.assertFalse(authed)
        self.assertFalse(event)

    def test_nft_add_partial_failure_always_attempts_verified_rollback(self):
        code, log, authed, event = self.exercise(add_ok=False)
        self.assertEqual(code, 5)
        self.assertIn("nft_add", log)
        self.assertIn("nft_del", log)
        self.assertIn("log:policy_apply", log)
        self.assertNotIn("persist_attempt", log)
        self.assertFalse(authed)
        self.assertFalse(event)

    def test_nft_readback_failure_after_add_blocks_persistence(self):
        code, log, authed, event = self.exercise(verify=False, readback=False)
        self.assertEqual(code, 5)
        self.assertIn("nft_del", log)
        self.assertIn("firewall_disabled", log)
        self.assertIn("log:rollback_unverified", log)
        self.assertNotIn("persist_attempt", log)
        self.assertFalse(authed)
        self.assertFalse(event)

    def test_rollback_readback_and_firewall_failure_is_explicit(self):
        code, log, authed, event = self.exercise(persist=False, readback=False,
                                                  firewall_ok=False)
        self.assertEqual(code, 7)
        self.assertIn("state:client_authorize_rollback_firewall_disable_failed", log)
        self.assertIn("log:rollback_unverified", log)
        self.assertFalse(event)
        # No E5 claim: if nft readback and firewall disable both fail, the
        # actual forwarding state is UNKNOWN and must be treated as BLOCK.

    def test_immutable_captive_post_session_and_grant_checks(self):
        s = production_authorize_branch()
        self.assertLess(s.index("acquire_session_lock"), s.index("portal_nft_add"))
        self.assertLess(s.index('portal_nft_pair_granted "$ip" "$mac"'),
                        s.index("portal_nft_add"))
        self.assertLess(s.index("client_session_write"), s.index("portal_nft_grant_del"))
        self.assertIn("valid_guest_ip", s)
        self.assertIn("expected_client", s)
        self.assertIn("portal_nft_pair_authorized", s)


    def test_compiled_rootfs_auditor_blocks_regressed_authorize_transaction(self):
        from audit_nr3053_wiflow_image import audit_captive_commit_rootfs
        with tempfile.TemporaryDirectory(prefix="wiflow-captive-image-") as temp:
            root = Path(temp)
            file = root / "usr/lib/wiflow/portal-client"
            file.parent.mkdir(parents=True)
            file.write_text(SOURCE)
            self.assertEqual(audit_captive_commit_rootfs(root), [])
            for damaged in (
                'if ! client_session_write "$f"',
                'portal_nft_del "$rb_ip" "$rb_mac"',
                'if ! portal_nft_pair_revoked "$rb_ip" "$rb_mac"; then',
                '/usr/lib/wiflow/portal-firewall disable',
            ):
                with self.subTest(damaged=damaged):
                    file.write_text(SOURCE.replace(damaged, "# stripped for negative test"))
                    self.assertTrue(audit_captive_commit_rootfs(root))
            file.unlink()
            self.assertTrue(audit_captive_commit_rootfs(root))

    def test_compiled_rootfs_auditor_requires_wp_ack_business_success(self):
        from audit_nr3053_wiflow_image import audit_wp_ack_receipt_rootfs
        source = (
            Path(__file__).resolve().parents[1]
            / "package/wiflow-setup/files/usr/lib/wiflow/portal-sync"
        ).read_text()
        with tempfile.TemporaryDirectory(prefix="wiflow-ack-image-") as temp:
            root = Path(temp)
            file = root / "usr/lib/wiflow/portal-sync"
            file.parent.mkdir(parents=True)
            file.write_text(source)
            self.assertEqual(audit_wp_ack_receipt_rootfs(root), [])
            file.write_text(source.replace(
                'jsonfilter -i "$ack" -e \'@.ok\'', "echo true"))
            self.assertTrue(audit_wp_ack_receipt_rootfs(root))
            file.unlink()
            self.assertTrue(audit_wp_ack_receipt_rootfs(root))


if __name__ == "__main__":
    unittest.main()
