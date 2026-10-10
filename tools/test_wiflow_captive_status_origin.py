"""Execute production Captive Portal canonical-origin and status CGI handlers.

Host-shell behavior only; not a physical Wi-Fi or browser acceptance test.
"""
from pathlib import Path
import os
import subprocess
import unittest

PORTAL = Path(__file__).resolve().parents[1] / "package/wiflow-setup/files/www-wiflow-portal/cgi-bin/portal"
SOURCE = PORTAL.read_text(encoding="utf-8")


class CaptiveStatusAndOriginTests(unittest.TestCase):
    def call_status(self, enabled="1", authorized="1", session_valid="1"):
        start = SOURCE.index("\n status)\n")
        end = SOURCE.index("\n authorize)\n", start)
        code = r"""
action=status
headers(){ printf 'Content-Type: %s\n\n' "$1"; }
json_error(){ printf '{"ok":false,"error":"%s"}\n' "$1"; exit 0; }
param(){ printf '%s' 'abcdef1234567890abcdef12'; }
validate_session(){ [ "$TEST_SESSION_VALID" = 1 ]; }
uci(){ printf '%s' "$TEST_ENABLED"; }
mock_authorization(){ [ "$TEST_AUTH" = 1 ]; }
case "$action" in
""" + SOURCE[start:end].replace(
            "/usr/lib/wiflow/portal-client is-authorized", "mock_authorization"
        ) + "\n authorize) :;;\nesac\n"
        result = subprocess.run(
            ["sh", "-c", code], capture_output=True, text=True, timeout=5,
            env={**os.environ, "TEST_ENABLED": enabled,
                 "TEST_AUTH": authorized, "TEST_SESSION_VALID": session_valid},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        return result.stdout

    def origin(self, host, method="GET"):
        start = SOURCE.index('case "$' + '{HTTP_HOST:-}" in')
        end = SOURCE.index("\nevent_enqueue portal_view", start)
        script = SOURCE[start:end] + "\nprintf 'CONTINUE\\n'\n"
        result = subprocess.run(
            ["sh", "-c", script], capture_output=True, text=True, timeout=5,
            env={**os.environ, "HTTP_HOST": host, "REQUEST_METHOD": method},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        return result.stdout

    def test_verified_session_gets_authorized_true(self):
        output = self.call_status()
        self.assertIn("Content-Type: application/json", output)
        self.assertIn('{"ok":true,"authorized":true}', output)

    def test_nft_absent_or_portal_off_never_reports_authorized(self):
        for enabled, authorized in (("0", "1"), ("1", "0"), ("0", "0")):
            with self.subTest(enabled=enabled, authorized=authorized):
                output = self.call_status(enabled, authorized)
                self.assertIn('{"ok":true,"authorized":false}', output)
                self.assertNotIn('"authorized":true', output)

    def test_session_mismatch_never_leaks_authorization(self):
        output = self.call_status(session_valid="0")
        self.assertIn('"ok":false', output)
        self.assertNotIn('"authorized":true', output)

    def test_probe_foreign_host_redirects_to_fixed_local_origin(self):
        for host in ("connectivitycheck.gstatic.com", "example.org", ""):
            with self.subTest(host=host):
                output = self.origin(host)
                self.assertIn("Status: 302 Found", output)
                self.assertIn("Location: http://10.10.10.1:2080/cgi-bin/portal", output)
                self.assertNotIn("CONTINUE", output)
                if host:
                    self.assertNotIn(host, output)

    def test_canonical_host_or_non_get_not_redirected(self):
        for host in ("10.10.10.1:2080", "10.10.10.1"):
            self.assertEqual(self.origin(host), "CONTINUE\n")
        self.assertEqual(self.origin("connectivitycheck.gstatic.com", "POST"),
                         "CONTINUE\n")


if __name__ == "__main__":
    unittest.main()
