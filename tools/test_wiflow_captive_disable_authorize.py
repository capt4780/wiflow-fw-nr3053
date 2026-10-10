"""S4 regression: stale Page 6 authorization must not reopen disabled Portal.

Source guard plus executed production shell branches; no device E5 claim.
"""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

FILES = Path(__file__).resolve().parents[1] / "package/wiflow-setup/files"
CLIENT = (FILES / "usr/lib/wiflow/portal-client").read_text()
CGI = (FILES / "www-wiflow-portal/cgi-bin/portal").read_text()


class CaptiveDisabledAuthorizationTests(unittest.TestCase):
    def test_backend_guard_precedes_any_nft_grant_to_authorization(self):
        start = CLIENT.index("\nauthorize-session)\n")
        end = CLIENT.index("\n    ;;\nrevoke-session)", start)
        body = CLIENT[start:end]
        enabled = body.index('uci -q get wiflow.core.portal_enabled')
        snapshot = body.index('[ -f "$PORTAL_ACTIVE/portal.json" ]')
        nft = body.index('portal_nft_add "$ip" "$mac"')
        self.assertLess(enabled, snapshot)
        self.assertLess(snapshot, nft)
        self.assertIn("portal_disabled", body)

    def test_cgi_authorize_guard_precedes_already_authorized_shortcut(self):
        start = CGI.index("\n authorize)\n")
        end = CGI.index("\n event)\n", start)
        body = CGI[start:end]
        self.assertLess(body.index('uci -q get wiflow.core.portal_enabled'),
                        body.index('portal-client is-authorized'))
        self.assertLess(body.index('[ -f "$PORTAL_ACTIVE/portal.json" ]'),
                        body.index('portal-client authorize-session'))
        self.assertIn("Status: 403 Forbidden", body)

    def test_actual_backend_gate_denies_disabled_and_snapshot_missing(self):
        body = CLIENT[CLIENT.index('    # Remote Portal disable is authoritative'):
                      CLIENT.index('    portal_nft_ready ||', CLIENT.index(
                          '    # Remote Portal disable is authoritative'))]
        for enabled, snapshot, expected in ((0, True, "portal_disabled"),
                                            (1, False, "snapshot_missing"),
                                            (1, True, "allowed")):
            with self.subTest(enabled=enabled, snapshot=snapshot):
                with tempfile.TemporaryDirectory() as temp:
                    base = Path(temp)
                    if snapshot:
                        (base / "portal.json").write_text("{}")
                    script = (
                        'PORTAL_ACTIVE="$ACTIVE"\n'
                        'sid=abcdefghijklmnop\n'
                        'uci(){ echo "$ENABLED"; }\n'
                        'log_client_event(){ printf "%s\\n" "$4" > "$EVENT_FILE"; }\n'
                        + body + '\nprintf "allowed\\n"\n'
                    )
                    proc = subprocess.run(["sh", "-c", script],
                        env={**os.environ, "ACTIVE": str(base), "ENABLED": str(enabled),
                             "EVENT_FILE": str(base / "event")},
                        capture_output=True, text=True, timeout=5)
                    if expected == "allowed":
                        self.assertEqual(proc.returncode, 0)
                        self.assertIn("allowed", proc.stdout)
                    else:
                        self.assertNotEqual(proc.returncode, 0)
                        self.assertIn(expected, proc.stdout + proc.stderr +
                                      (base / "event").read_text() if (base / "event").exists() else "")


if __name__ == "__main__":
    unittest.main()
