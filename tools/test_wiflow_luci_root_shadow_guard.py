"""Host-level tests for the experimental LuCI root shadow pre-grant guard.

No real credential, root hash, device access, or runtime E5 claim is involved.
"""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

SOURCE = (
    Path(__file__).resolve().parents[1]
    / "package/wiflow-setup/files/www-wiflow-luci-gate/cgi-bin/unlock"
)


class LuciShadowGuardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.script = SOURCE.read_text(encoding="utf-8")
        match = re.search(
            r"(?ms)^wiflow_root_shadow_hash_present\(\)\{\n.*?^\}",
            cls.script,
        )
        assert match is not None, "LuCI shadow guard missing"
        cls.guard = match.group(0)

    def probe(self, lines=None, symlink=False):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "shadow"
            if lines is not None:
                if symlink:
                    external = Path(tmp) / "target"
                    external.write_text(lines, encoding="utf-8")
                    path.symlink_to(external)
                else:
                    path.write_text(lines, encoding="utf-8")
            result = subprocess.run(
                ["sh", "-c", self.guard + '\nwiflow_root_shadow_hash_present "$1"', "shadow-test", str(path)],
                capture_output=True,
                text=True,
                check=False,
                timeout=3,
            )
            # No raw hash or shadow file content may reach logs/stdout.
            self.assertEqual(result.stdout, "")
            self.assertEqual(result.stderr, "")
            return result.returncode

    @staticmethod
    def entry(field):
        return "root:" + field + ":19800:0:99999:7:::\n"

    def test_gate_denies_unusable_root_fields(self):
        for field in ("", "!", "*", "plaintext", "$1$old$hash", "$6$bad"):
            with self.subTest(field_class="missing" if not field else field[:2]):
                self.assertNotEqual(self.probe(self.entry(field)), 0)

    def test_gate_denies_missing_duplicate_and_symlink_shadow(self):
        self.assertNotEqual(self.probe(), 0)
        good = "$6$abcdefghijklmnop$" + "A" * 86
        self.assertNotEqual(self.probe(self.entry(good) * 2), 0)
        self.assertNotEqual(self.probe(self.entry(good), symlink=True), 0)

    def test_only_sha512_crypt_shaped_root_field_passes_shape_guard(self):
        good = "$6$abcdefghijklmnop$" + "A" * 86
        self.assertEqual(self.probe(self.entry(good)), 0)
        self.assertEqual(
            self.probe(self.entry("$6$rounds=10000$abcdefghijklmnop$" + "A" * 86)),
            0,
        )

    def test_no_nft_grant_precedes_credential_check(self):
        self.assertIn("wiflow_root_shadow_hash_present /etc/shadow", self.script)
        self.assertLess(
            self.script.index("wiflow_root_shadow_hash_present /etc/shadow"),
            self.script.index("nft list set inet fw4 wiflow_luci_allowed4"),
        )
        self.assertLess(
            self.script.index("wiflow_root_shadow_hash_present /etc/shadow"),
            self.script.index("nft add element inet fw4 wiflow_luci_allowed4"),
        )
        self.assertIn("redirect '/?error=1'", self.script)
        self.assertIn('wiflow_gate_code_allowed "$pin" "$want"', self.script)


if __name__ == "__main__":
    unittest.main()
