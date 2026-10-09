"""Fast public-repository data-loss prevention checks (stdlib only)."""
import unittest
from verify_public_tree import check_entry


class PublicSourceGateTests(unittest.TestCase):
    def test_normal_source_allowed(self):
        self.assertEqual(check_entry("tools/module.py", b"print('hello')\n"), [])

    def test_do_not_publish_reference_firmware(self):
        self.assertTrue(check_entry("reference/stable-nr3053.itb", b"123456"))

    def test_do_not_publish_private_wordpress_zip(self):
        self.assertTrue(check_entry("Wiflow-BASELINE-FULL.zip", b"test"))

    def test_do_not_publish_private_media_or_env(self):
        self.assertTrue(check_entry("wp-content/mu-plugins/portal.php", b"test"))
        self.assertTrue(check_entry(".env", b"KEY=test"))

    def test_do_not_publish_hardcoded_auth(self):
        fake_token = b"ghp_" + b"A" * 30
        self.assertTrue(check_entry("tools/config.txt", b"token=" + fake_token))

    def test_do_not_publish_private_key(self):
        fake_private_key = b"-----BEGIN " + b"PRIVATE KEY-----"
        self.assertTrue(check_entry("tools/config.txt", fake_private_key))

    def test_symlink_and_non_text_blocked(self):
        self.assertTrue(check_entry("tools/link", b"README.md", symlink=True))
        self.assertTrue(check_entry("sample.txt", b"abc" + bytes([0]) + b"def"))

    def test_oversized_text_blocked(self):
        self.assertTrue(check_entry("README.md", b"0" * 1_000_001))


if __name__ == "__main__":
    unittest.main()
