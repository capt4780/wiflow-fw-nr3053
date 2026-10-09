"""Regression tests for the explicitly approved public device-source port.

Only static/source-level evidence. A passing test NEVER approves flashing.
"""
from pathlib import Path
import subprocess
import unittest

R = Path(__file__).resolve().parents[1]
F = R / "package/wiflow-setup/files"
REQUIRED = (
    "usr/lib/wiflow/common.sh",
    "usr/lib/wiflow/bootstrap",
    "usr/lib/wiflow/portal-sync",
    "usr/lib/wiflow/portal-firewall",
    "usr/lib/wiflow/portal-client",
    "www-wiflow/cgi-bin/api",
    "www-wiflow/cgi-bin/gate",
    "www-wiflow/cgi-bin/enroll",
    "www-wiflow-portal/template-website.html",
    "www-wiflow-portal/template-image.html",
    "www-wiflow-portal/template-video.html",
)


class SourcePortTests(unittest.TestCase):
    def test_all_required_runtime_components_present(self):
        for rel in REQUIRED:
            with self.subTest(rel=rel):
                self.assertTrue((F / rel).is_file(), rel)

    def test_nr3053_identity_and_fixed_wp_root(self):
        bootstrap = (F / "usr/lib/wiflow/bootstrap").read_text()
        api = (F / "www-wiflow/cgi-bin/api").read_text()
        common = (F / "usr/lib/wiflow/common.sh").read_text()
        self.assertIn("WIFDID-NR3053-", bootstrap)
        self.assertIn("Viettel NR3053", api)
        self.assertIn("https://projify.io.vn/wiflow/wp-json", common)
        self.assertIn("WIFLOW_DATA_GENERATION='4'", common)

    def test_emergency_access_limited_to_first_owner_claim(self):
        gate = (F / "www-wiflow/cgi-bin/gate").read_text()
        luci = (F / "www-wiflow-luci-gate/cgi-bin/unlock").read_text()
        common = (F / "usr/lib/wiflow/common.sh").read_text()
        entry = (F / "www-wiflow/index.html").read_text()
        self.assertNotIn("247365", gate + luci)
        self.assertNotIn("master=", gate + luci)
        self.assertIn('first_use_emergency_gate "$pin"', gate)
        self.assertIn('[ "$pin" = "$want" ]', gate)
        self.assertIn('"$pin" != "$want"', luci)
        self.assertIn("WIFLOW_FIRST_USE_GATE_CODE='WIFDIDNR3053'", common)
        self.assertIn('[ ! -e "$ROOT/setup-claimed" ]', common)
        self.assertIn('printf \'claimed\\n\' > "$ROOT/setup-claimed"', common)
        self.assertIn('pattern="([0-9]{6}|WIFDIDNR3053)"', entry)
        self.assertNotIn("WIFDIDNR3053", luci)

    def test_no_default_password_and_first_boot_enrollment(self):
        common = (F / "usr/lib/wiflow/common.sh").read_text()
        enroll = (F / "www-wiflow/cgi-bin/enroll").read_text()
        self.assertNotIn('[ "$p" = wiflow ]', common)
        self.assertIn('[ -n "$stored_hash" ] && [ -n "$stored_salt" ] || return 1', common)
        self.assertIn('[ "$plen" -ge 12 ]', common)
        self.assertIn('check_gate_session', enroll)
        self.assertIn('setup_set_login', enroll)
        self.assertIn('HTTP_ORIGIN', enroll)
        self.assertIn('wiflow-setup-enrollment.lock', enroll)

    def test_protocol_schema_and_atomic_switch_retained(self):
        sync = (F / "usr/lib/wiflow/portal-sync").read_text()
        self.assertIn('"$schema" = 2', sync)
        self.assertIn('"$manifest_generation" = "$WIFLOW_DATA_GENERATION"', sync)
        self.assertIn('sha256sum "$out"', sync)
        self.assertIn('mv -Tf "$LINK" "$PORTAL_ACTIVE"', sync)
        self.assertIn('revisions/rev-$REV', sync)

    def test_no_fonts_or_logo_binary_in_public_source(self):
        for p in F.rglob("*"):
            if p.is_file():
                with self.subTest(path=p.as_posix()):
                    self.assertNotIn(p.suffix.lower(), (".woff2", ".woff", ".png", ".webp", ".jpg", ".jpeg"))
                    self.assertNotIn(b"\x00", p.read_bytes())

    def test_shell_syntax_of_all_device_scripts(self):
        count = 0
        for p in F.rglob("*"):
            if p.is_file() and p.read_bytes().startswith(b"#!/bin/sh"):
                count += 1
                result = subprocess.run(["sh", "-n", str(p)], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, f"{p}: {result.stderr}")
        self.assertGreaterEqual(count, 25)


if __name__ == "__main__":
    unittest.main()
