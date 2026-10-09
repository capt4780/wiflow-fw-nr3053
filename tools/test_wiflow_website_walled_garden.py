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


    def test_resolver_excludes_private_answers_end_to_end(self):
        # Execute BOTH source functions with a fake busybox-style nslookup;
        # no DNS network or router access. Protects against a wiring regression.
        from tempfile import TemporaryDirectory
        from pathlib import Path
        src = self.source
        start = src.index("wiflow_public_ipv4(){")
        end = src.index("\nrefresh(){", start)
        actual = src[start:end]
        stubs = r'''
portal_active_config(){ printf '/tmp/test-portal'; }
uci(){ printf 'website'; }
jsonfilter(){ printf 'https://promo.example/offer'; }
website_url_valid(){ case "$1" in https://*) return 0;; *) return 1;; esac; }
website_host_from_url(){ printf 'promo.example'; }
nslookup(){ cat "$DNS_RESPONSES"; }
'''
        with TemporaryDirectory(prefix="wiflow-web-dns-test-") as d:
            answer = Path(d) / "answers"
            for answers, expected_success, expected_ips in (
                (("192.168.1.1", "10.0.0.1", "8.8.8.8", "1.1.1.1"), True, {"1.1.1.1", "8.8.8.8"}),
                (("127.0.0.1", "192.168.2.1", "100.64.2.3"), False, set()),
                (("104.16.132.229",), True, {"104.16.132.229"}),
            ):
                answer.write_text("Name: promo.example\n" + "".join(
                    f"Address {i+1}: {ip}\n" for i, ip in enumerate(answers)))
                run = subprocess.run(
                    ["sh", "-c", stubs + actual + "\nresolve_website_ips"],
                    env={**os.environ, "DNS_RESPONSES": str(answer)},
                    capture_output=True, text=True, timeout=5)
                self.assertEqual(run.returncode == 0, expected_success, run.stderr)
                self.assertEqual(set(run.stdout.splitlines()), expected_ips)

if __name__ == "__main__":
    unittest.main()
