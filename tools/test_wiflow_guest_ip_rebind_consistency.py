"""Actual shell execution for DHCP IP-rebind authorization transaction safety.

Host mocks only; IP/MAC traffic on NR3053 requires independent S5 evidence.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

FILES = Path(__file__).resolve().parents[1] / "package/wiflow-setup/files/usr/lib/wiflow"
CLIENT = (FILES / "portal-client").read_text()
LOOP = (FILES / "portal-session-loop").read_text()


def client_rebind():
    marker = "        # On DHCP IP rebind, never authorize a new IP"
    begin = CLIENT.index(marker)
    end = CLIENT.index("\n    fi\n\n    # Stage 3", begin)
    return CLIENT[begin:end].replace(
        "/usr/lib/wiflow/portal-firewall disable", "fail_closed_disable"
    )


def session_loop_rebind():
    begin = LOOP.index('            if [ "$newip" != "$ip" ]; then')
    end = LOOP.index("\n        else\n            [ \"$absent\"", begin)
    return LOOP[begin:end].replace(
        "/usr/lib/wiflow/portal-firewall disable", "fail_closed_disable"
    )


BASE_MOCKS = r"""
LOG="$TEST_ROOT/log"
oldip=10.10.10.101
ip=10.10.10.102
newip=10.10.10.102
mac=02:11:22:33:44:55
f="$TEST_ROOT/session"
cid=client1
sid=abcdef1234567890abcdef12
connected=100
authorized=120
now=140
portal_nft_del(){
 printf "old_revoke\n" >> "$LOG"
 [ "$TEST_REVOKE_OK" = 0 ] || rm -f "$TEST_ROOT/old"
}
portal_nft_pair_authorized(){ [ -f "$TEST_ROOT/old" ]; }
portal_nft_pair_revoked(){ [ "$TEST_NFT_READ_OK" = 1 ] && [ ! -f "$TEST_ROOT/old" ]; }
portal_nft_pair_granted(){ [ "$TEST_GRANT" = 1 ]; }
portal_nft_grant_del(){ printf "old_grant_del\n" >> "$LOG"; }
portal_nft_grant_add(){ printf "new_grant_add\n" >> "$LOG"; }
portal_nft_add(){ printf "new_authorize\n" >> "$LOG"; }
client_session_write(){
 printf "session_write\n" >> "$LOG"
 [ "$TEST_WRITE_OK" = 1 ]
}
state_set(){ printf "state_error:%s\n" "$2" >> "$LOG"; }
log_client_event(){ printf "log:%s\n" "$3" >> "$LOG"; }
fail_closed_disable(){ printf "firewall_disable\n" >> "$LOG"; rm -f "$TEST_ROOT/old"; }
"""


class GuestIPRebindConsistencyTests(unittest.TestCase):
    def invoke(self, kind="client", *, write_ok=True, revoke_ok=True,
               authorized=True, had_grant=False, nft_read_ok=True):
        with tempfile.TemporaryDirectory(prefix="wiflow-rebind-") as temp:
            base = Path(temp)
            (base / "old").touch()
            script = BASE_MOCKS + ("authorized=0\n" if not authorized else "")
            if kind == "client":
                # Real fragment from production portal-client's existing-session branch.
                script += client_rebind()
            else:
                script += "\nip=10.10.10.101\nfor test_iteration in once; do\n" + session_loop_rebind() + "\n break\ndone\n"
            proc = subprocess.run(
                ["sh", "-c", script],
                capture_output=True, text=True, timeout=6,
                env={**os.environ, "TEST_ROOT": str(base),
                     "TEST_WRITE_OK": "1" if write_ok else "0",
                     "TEST_REVOKE_OK": "1" if revoke_ok else "0",
                     "TEST_GRANT": "1" if had_grant else "0",
                     "TEST_NFT_READ_OK": "1" if nft_read_ok else "0"},
            )
            log = (base / "log").read_text().splitlines() if (base / "log").exists() else []
            self.assertEqual(proc.stderr, "", proc.stderr)
            return proc.returncode, log

    def test_client_existing_authorized_ip_restores_only_after_persist(self):
        code, events = self.invoke("client")
        self.assertEqual(code, 0)
        self.assertEqual(events, ["old_revoke", "session_write", "new_authorize"])

    def test_client_failed_session_write_must_not_authorize_new_ip(self):
        code, events = self.invoke("client", write_ok=False)
        self.assertEqual(code, 1)
        self.assertEqual(events, ["old_revoke", "session_write", "log:session_persist"])

    def test_client_old_pair_revoke_failure_triggers_fail_closed(self):
        code, events = self.invoke("client", revoke_ok=False)
        self.assertEqual(code, 1)
        self.assertEqual(events, ["old_revoke", "firewall_disable", "log:old_ip_revoke"])

    def test_client_nft_read_error_must_fail_closed_even_after_delete(self):
        code, events = self.invoke("client", nft_read_ok=False)
        self.assertEqual(code, 1)
        self.assertEqual(events, ["old_revoke", "firewall_disable", "log:old_ip_revoke"])
        self.assertNotIn("new_authorize", events)

    def test_client_read_error_with_old_pair_present_must_fail_closed(self):
        code, events = self.invoke("client", revoke_ok=False, nft_read_ok=False)
        self.assertEqual(code, 1)
        self.assertEqual(events, ["old_revoke", "firewall_disable", "log:old_ip_revoke"])
        self.assertNotIn("session_write", events)

    def test_session_loop_success_rebind_commits_before_nft_add(self):
        code, events = self.invoke("loop")
        self.assertEqual(code, 0)
        self.assertEqual(events, ["old_revoke", "session_write", "new_authorize"])

    def test_session_loop_failed_state_write_does_not_open_new_ip(self):
        code, events = self.invoke("loop", write_ok=False)
        self.assertEqual(code, 0)
        self.assertEqual(events, ["old_revoke", "session_write",
                                  "state_error:client_ip_state_write_failed"])

    def test_session_loop_nft_read_error_must_fail_closed(self):
        code, events = self.invoke("loop", nft_read_ok=False)
        self.assertEqual(code, 0)
        self.assertEqual(events, ["old_revoke", "firewall_disable",
                                  "state_error:client_ip_old_authorization_revoke_failed"])
        self.assertNotIn("new_authorize", events)
        self.assertNotIn("session_write", events)

    def test_session_loop_stale_pair_and_read_error_must_fail_closed(self):
        code, events = self.invoke("loop", revoke_ok=False, nft_read_ok=False)
        self.assertEqual(code, 0)
        self.assertEqual(events, ["old_revoke", "firewall_disable",
                                  "state_error:client_ip_old_authorization_revoke_failed"])
        self.assertNotIn("new_authorize", events)

    def test_session_loop_preauthorization_grant_rebind_is_also_ordered(self):
        code, events = self.invoke("loop", authorized=False, had_grant=True)
        self.assertEqual(code, 0)
        self.assertEqual(events, ["old_grant_del", "session_write", "new_grant_add"])

    def test_session_loop_preauthorization_failed_write_does_not_grant(self):
        code, events = self.invoke("loop", authorized=False, had_grant=True,
                                   write_ok=False)
        self.assertEqual(code, 0)
        self.assertEqual(events, ["old_grant_del", "session_write",
                                  "state_error:client_ip_state_write_failed"])


    def test_built_rootfs_audit_rejects_unordered_ip_rebind(self):
        from audit_nr3053_wiflow_image import audit_captive_rebind_rootfs
        with tempfile.TemporaryDirectory(prefix="wiflow-rebind-rootfs-") as tmp:
            root = Path(tmp)
            client = root / "usr/lib/wiflow/portal-client"
            loop = root / "usr/lib/wiflow/portal-session-loop"
            client.parent.mkdir(parents=True)
            client.write_text(CLIENT)
            loop.write_text(LOOP)
            self.assertEqual(audit_captive_rebind_rootfs(root), [])
            client.write_text(CLIENT.replace(
                'portal_nft_add "$ip" "$mac"',
                'test_no_authorized_restore "$ip" "$mac"'))
            self.assertTrue(audit_captive_rebind_rootfs(root))
            client.write_text(CLIENT.replace(
                'if ! portal_nft_pair_revoked "$oldip" "$mac"; then',
                'if portal_nft_pair_authorized "$oldip" "$mac"; then'))
            self.assertTrue(audit_captive_rebind_rootfs(root))
            client.write_text(CLIENT)
            loop.write_text(LOOP.replace(
                'if ! portal_nft_pair_revoked "$ip" "$mac"; then',
                'if portal_nft_pair_authorized "$ip" "$mac"; then'))
            self.assertTrue(audit_captive_rebind_rootfs(root))
            client.write_text(CLIENT)
            loop.write_text(LOOP.replace(
                'if ! client_session_write "$f"',
                'if ! test_no_session_write "$f"'))
            self.assertTrue(audit_captive_rebind_rootfs(root))
            loop.unlink()
            self.assertTrue(audit_captive_rebind_rootfs(root))


if __name__ == "__main__":
    unittest.main()
