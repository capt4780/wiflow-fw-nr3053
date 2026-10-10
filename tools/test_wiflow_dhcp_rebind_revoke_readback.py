#!/usr/bin/env python3
"""Guard both DHCP IP rebind paths against unverified nft revocation."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1] / "package/wiflow-setup/files/usr/lib/wiflow"


class DhcpRebindRevokeReadback(unittest.TestCase):
    def test_rebind_paths_require_positive_absence_proof(self):
        for file_name, old_ip in (("portal-client", "oldip"), ("portal-session-loop", "ip")):
            with self.subTest(file=file_name):
                source = (ROOT / file_name).read_text()
                rebind_start = source.index("if [ \"\u0024{authorized:-0}\" != 0 ]") if file_name == "portal-client" else source.index("if [ \"\u0024{authorized:-0}\" != 0 ]; then", source.index("if [ \"\u0024newip\" != \"\u0024ip\" ]"))
                section = source[rebind_start:rebind_start + 520]
                self.assertIn(f'portal_nft_del "\u0024{old_ip}" "\u0024mac"', section)
                self.assertIn(f'if ! portal_nft_pair_revoked "\u0024{old_ip}" "\u0024mac"; then', section)
                self.assertNotIn(f'if portal_nft_pair_authorized "\u0024{old_ip}" "\u0024mac"; then', section)

    def test_revoke_helper_rejects_failed_read(self):
        source = (ROOT / "common.sh").read_text()
        section = source.split("portal_nft_pair_revoked(){", 1)[1].split("\n}", 1)[0]
        self.assertIn("nft list set inet fw4 wiflow_portal_authed", section)
        self.assertIn("|| return 1", section)
        self.assertIn("! printf", section)


if __name__ == "__main__":
    unittest.main()
