"""Run the actual POSIX device validator for Website pre-auth DNS exceptions."""
from pathlib import Path
import os
import subprocess
import unittest

PORTAL = Path(__file__).resolve().parents[1] / "package/wiflow-setup/files/usr/lib/wiflow/portal-firewall"


class WebsiteAddressTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = PORTAL.read_text()
        begin = cls.source.index("wiflow_public_ipv4(){")
        end = cls.source.index("\nresolve_website_ips(){", begin)
        cls.validator = cls.source[begin:end]

    def check(self, address):
        return subprocess.run(
            ["sh", "-c", self.validator + '\nwiflow_public_ipv4 "$CHECK_IP"'],
            env={**os.environ, "CHECK_IP": address},
            capture_output=True, text=True, timeout=5,
        )

    def test_public_unicast_allowed(self):
        for ip in ("1.1.1.1", "8.8.8.8", "9.9.9.9", "104.16.132.229", "172.32.0.1", "203.0.114.20"):
            with self.subTest(ip=ip):
                p = self.check(ip)
                self.assertEqual(p.returncode, 0, p.stderr)

    def test_private_reserved_and_malformed_denied(self):
        for ip in (
            "0.0.0.0", "10.0.0.1", "10.10.10.1", "100.64.0.1",
            "100.127.255.254", "127.0.0.1", "169.254.169.254",
            "172.16.1.1", "172.31.255.255", "192.0.0.9",
            "192.0.2.1", "192.88.99.1", "192.168.1.1",
            "198.18.0.1", "198.19.1.2", "198.51.100.1",
            "203.0.113.5", "224.0.0.1", "240.1.1.1",
            "255.255.255.255", "1.2.3.999", "1.2.3",
            "1.2.3.4.5", "1.2.3.-1", "1.2.3.4evil", "1.2.3.4444", "",
        ):
            with self.subTest(ip=ip):
                self.assertNotEqual(self.check(ip).returncode, 0, ip)

    def test_dns_results_validated_before_walled_garden(self):
        source = self.source
        self.assertIn('wiflow_public_ipv4 "$ip"', source)
        self.assertLess(source.index('wiflow_public_ipv4 "$ip"'),
                        source.index('cat "$tmp"; rm -f "$tmp"'))
        self.assertIn('[ -s "$tmp" ] || { rm -f "$tmp"; return 1; }', source)
        self.assertIn('state_set website_walled_garden 0', source)
        self.assertIn('flush set inet fw4 wiflow_portal_web4', source)


if __name__ == "__main__":
    unittest.main()
