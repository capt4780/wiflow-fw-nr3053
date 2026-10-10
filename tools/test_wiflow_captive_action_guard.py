"""Execute the production captive mutation guard against positive/negative HTTP cases.

Evidence is host shell execution and source/contract review, not an NR3053
packet trace or proof that a human completed the advertisement.
"""
from pathlib import Path
import os
import tempfile
import subprocess
import unittest

BASE = Path(__file__).resolve().parents[1] / "package/wiflow-setup/files"
PORTAL = BASE / "www-wiflow-portal/cgi-bin/portal"
TEMPLATES = tuple(BASE / f"www-wiflow-portal/template-{name}.html"
                  for name in ("website", "image", "video"))


class CaptiveActionGuardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = PORTAL.read_text(encoding="utf-8")
        start = cls.source.index('case "$action" in\n authorize|event|status)')
        end = cls.source.index('\ncase "$action" in\n status)', start)
        cls.guard = cls.source[start:end]

    def run_guard(self, action, method, origin, body="action=authorize&session_id=test"):
        script = 'action="$TEST_ACTION"\nBODY="$TEST_BODY"\n' + self.guard + '\nprintf "GUARD_OK\\n"\n'
        return subprocess.run(
            ["sh", "-c", script],
            env={**os.environ, "TEST_ACTION": action, "REQUEST_METHOD": method,
                 "HTTP_ORIGIN": origin, "TEST_BODY": body},
            capture_output=True, text=True, timeout=5,
        )

    def test_all_local_mutations_accept_post_independent_of_origin(self):
        for action in ("authorize", "event", "status"):
            for origin in ("http://10.10.10.1:2080", "", "null",
                           "http://example.org"):
                with self.subTest(action=action, origin=origin):
                    result = self.run_guard(action, "POST", origin)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout, "GUARD_OK\n")

    def test_get_and_head_cannot_authorize_via_query_string(self):
        for method in ("GET", "HEAD", "DELETE", ""):
            with self.subTest(method=method):
                result = self.run_guard("authorize", method,
                                        "http://10.10.10.1:2080")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("405 Method Not Allowed", result.stdout)
                self.assertNotIn("GUARD_OK", result.stdout)
                self.assertIn("Allow: POST", result.stdout)

    def test_post_with_empty_body_fails_even_with_query_string(self):
        for action in ("authorize", "event", "status"):
            with self.subTest(action=action):
                result = self.run_guard(action, "POST", "", body="")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("400 Bad Request", result.stdout)
                self.assertNotIn("GUARD_OK", result.stdout)

    def test_preauth_portal_view_is_not_blocked(self):
        for action in ("", "other"):
            result = self.run_guard(action, "GET", "")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "GUARD_OK\n")

    def test_guard_precedes_session_authorization_and_event(self):
        source = self.source
        self.assertLess(source.index('case "$action" in\n authorize|event|status)'),
                        source.index('case "$action" in\n status)'))
        self.assertLess(source.index('case "$action" in\n authorize|event|status)'),
                        source.index('authorize-session "$sid" "$cid"'))
        self.assertLess(source.index('case "$action" in\n authorize|event|status)'),
                        source.index('event_enqueue "$ev"'))
        self.assertIn('validate_session "$sid"', source)
        self.assertIn('is-authorized "$sid"', source)

    def test_all_modes_use_same_origin_post_without_navigation(self):
        for path in TEMPLATES:
            with self.subTest(template=path.name):
                html = path.read_text(encoding="utf-8")
                self.assertIn("const commit=async()=>", html)
                self.assertIn("const response=await send('authorize')", html)
                self.assertIn("const status=await send('status')", html)
                self.assertIn("confirmed=response.status===204", html)
                self.assertIn("body:new URLSearchParams({action,session_id:sessionId}).toString()", html)
                self.assertIn("new URL(authorizeUrl,window.location.href).origin!==window.location.origin", html)
                self.assertIn("mode:'same-origin'", html)
                self.assertIn("redirect:'error'", html)
                self.assertNotIn("form.submit()", html)
                self.assertNotIn("window.location.assign(", html)
                self.assertIn('data-local-authorize-url="http://10.10.10.1:2080/cgi-bin/portal"', html)

    def test_exact_image_auditor_requires_compiled_guard(self):
        from audit_nr3053_wiflow_image import audit_captive_mutation_rootfs
        from shutil import copyfile
        with tempfile.TemporaryDirectory(prefix="wiflow-captive-audit-") as tmp:
            target = Path(tmp) / "www-wiflow-portal/cgi-bin/portal"
            target.parent.mkdir(parents=True)
            copyfile(PORTAL, target)
            self.assertEqual(audit_captive_mutation_rootfs(Path(tmp)), [])
            pristine = target.read_text(encoding="utf-8")
            for old in ('[ "${REQUEST_METHOD:-}" != POST ]',
                        '[ -z "$BODY" ]'):
                self.assertIn(old, pristine)
                target.write_text(pristine.replace(old, "# test mutation"), encoding="utf-8")
                result = audit_captive_mutation_rootfs(Path(tmp))
                self.assertTrue(result, old)
                target.write_text(pristine, encoding="utf-8")
            target.unlink()
            self.assertTrue(audit_captive_mutation_rootfs(Path(tmp)))




if __name__ == "__main__":
    unittest.main()
