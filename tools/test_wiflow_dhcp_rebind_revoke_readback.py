#!/usr/bin/env python3
"""Prevent DHCP rebind from authorizing a new IP without proved nft revocation."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1] / "package/wiflow-setup/files/usr/lib/wiflow"


class DhcpRebindRevokeReadback(unittest.TestCase):
    def test_both_paths_require_positive_revocation_readback(self):
        for name, old_ip in (("portal-client", "oldip"), ("portal-session-loop", "ip")):
            with self.subTest(path=name):
                source = (ROOT / name).read_text()
                if name == "portal-client":
                    start = source.index("# On DHCP IP rebind")
                    end = source.index("\n    fi\n\n    # Stage 3", start)
                else:
                    start = source.index('if [ "$newip" != "$ip" ]; then')
                    end = source.index('\n        else\n            [ "$absent"', start)
                section = source[start:end]
                revoke = f'if ! portal_nft_pair_revoked "${old_ip}" "$mac"; then'
                self.assertIn(revoke, section)
                self.assertNotIn(f'if portal_nft_pair_authorized "${old_ip}" "$mac"; then', section)
                self.assertLess(section.index(f'portal_nft_del "${old_ip}" "$mac"'),
                                section.index(revoke))
                self.assertLess(section.index(revoke),
                                section.index('if ! client_session_write "$f"'))
                self.assertLess(section.index('if ! client_session_write "$f"'),
                                section.index(f'portal_nft_add "${"ip" if name == "portal-client" else "newip"}" "$mac"'))

    def test_revoke_helper_proves_read_success(self):
        source = (ROOT / "common.sh").read_text()
        section = source.split("portal_nft_pair_revoked(){", 1)[1].split("\n}", 1)[0]
        self.assertIn("nft list set inet fw4 wiflow_portal_authed", section)
        self.assertIn("|| return 1", section)
        self.assertIn("! printf", section)


if __name__ == "__main__":
    unittest.main()
