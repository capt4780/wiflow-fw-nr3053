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
        start = cls.source.index('case "$action" in\n authorize|event)')
        end = cls.source.index('\ncase "$action" in\n authorize)', start)
        cls.guard = cls.source[start:end]

    def run_guard(self, action, method, origin):
        script = 'action="$TEST_ACTION"\n' + self.guard + '\nprintf "GUARD_OK\\n"\n'
        return subprocess.run(
            ["sh", "-c", script],
            env={**os.environ, "TEST_ACTION": action, "REQUEST_METHOD": method,
                 "HTTP_ORIGIN": origin},
            capture_output=True, text=True, timeout=5,
        )

    def test_all_local_mutations_accept_only_origin_verified_post(self):
        for action in ("authorize", "event"):
            with self.subTest(action=action):
                result = self.run_guard(action, "POST", "http://10.10.10.1:2080")
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

    def test_cross_origin_post_and_missing_origin_fail_closed(self):
        for origin in ("", "null", "https://10.10.10.1:2080",
                       "http://10.10.10.1", "http://10.10.10.1:2081",
                       "http://10.10.10.1:2080.evil.invalid",
                       "http://10.0.0.1", "http://example.org"):
            with self.subTest(origin=origin):
                result = self.run_guard("authorize", "POST", origin)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("403 Forbidden", result.stdout)
                self.assertNotIn("GUARD_OK", result.stdout)

    def test_preauth_portal_view_is_not_blocked(self):
        for action in ("", "other"):
            result = self.run_guard(action, "GET", "")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "GUARD_OK\n")

    def test_guard_precedes_session_authorization_and_event(self):
        source = self.source
        self.assertLess(source.index('case "$action" in\n authorize|event)'),
                        source.index('case "$action" in\n authorize)'))
        self.assertLess(source.index('case "$action" in\n authorize|event)'),
                        source.index('authorize-session "$sid" "$cid"'))
        self.assertLess(source.index('case "$action" in\n authorize|event)'),
                        source.index('event_enqueue "$ev"'))
        self.assertIn('validate_session "$sid"', source)
        self.assertIn('is-authorized "$sid"', source)

    def test_existing_templates_use_post_confirm_without_ui_rewrite(self):
        for path in TEMPLATES:
            with self.subTest(template=path.name):
                html = path.read_text(encoding="utf-8")
                self.assertIn("form.method='post'", html)
                self.assertIn("action.value='authorize'", html)
                self.assertIn("sid.name='session_id'", html)
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
                        '[ "${HTTP_ORIGIN:-}" != \'http://10.10.10.1:2080\' ]'):
                self.assertIn(old, pristine)
                target.write_text(pristine.replace(old, "# test mutation"), encoding="utf-8")
                result = audit_captive_mutation_rootfs(Path(tmp))
                self.assertTrue(result, old)
                target.write_text(pristine, encoding="utf-8")
            target.unlink()
            self.assertTrue(audit_captive_mutation_rootfs(Path(tmp)))




if __name__ == "__main__":
    unittest.main()
