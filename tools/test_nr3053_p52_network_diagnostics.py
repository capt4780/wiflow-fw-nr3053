"""P52 read-only network diagnosis: host fixtures, no device or radio writes."""
from pathlib import Path
import json
import os
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
DIAG = ROOT / "package/wiflow-setup/files/usr/lib/wiflow/network-diagnostics"
API = ROOT / "package/wiflow-setup/files/www-wiflow/cgi-bin/api"


class NetworkDiagnosticsTests(unittest.TestCase):
    def test_diagnostics_read_only_and_authenticated(self):
        t = DIAG.read_text()
        # Never let a user-facing troubleshooting endpoint change the sole router.
        for forbidden in (
            r"\buci\s+(?:set|commit|delete|add|add_list)\b",
            r"\b(?:ifup|ifdown|reboot|sysupgrade|wifi\s+reload|wifi\s+up)\b",
            r"\b(?:opkg|apk)\s+(?:add|remove|upgrade|install)\b",
        ):
            self.assertIsNone(re.search(forbidden, t), forbidden)
        a = API.read_text()
        self.assertLess(a.index("require_session"), a.index("diagnostics)"))
        self.assertIn('sh /usr/lib/wiflow/network-diagnostics', a)
        self.assertIn("read_only", t)

    def test_port_link_fixture_separates_wan_from_lan(self):
        with tempfile.TemporaryDirectory(prefix="wiflow-p52-") as tmp:
            root = Path(tmp)
            net = root / "net"
            net.mkdir()
            for dev, carrier, state in (
                ("wan", "0", "down"),
                ("lan1", "1", "up"),
                ("lan2", "0", "down"),
            ):
                p = net / dev
                p.mkdir()
                (p / "carrier").write_text(carrier + "\n")
                (p / "operstate").write_text(state + "\n")
            bindir = root / "bin"
            bindir.mkdir()
            uci = bindir / "uci"
            uci.write_text(
                "#!/bin/sh\n"
                'case "$*" in\n'
                '  "-q get network.wan.device") echo wan;;\n'
                '  "-q get network.wan.proto") echo dhcp;;\n'
                "esac\n"
            )
            uci.chmod(0o755)
            env = {
                **os.environ,
                "NET_SYS_ROOT": str(net),
                "PATH": str(bindir) + os.pathsep + os.environ.get("PATH", ""),
            }
            p = subprocess.run(
                ["sh", str(DIAG)],
                env=env, capture_output=True, text=True, timeout=5, check=True
            )
            data = json.loads(p.stdout)
            self.assertTrue(data["ok"])
            self.assertTrue(data["read_only"])
            self.assertEqual(data["wan_device"], "wan")
            self.assertEqual(data["wan_protocol"], "dhcp")
            self.assertEqual(data["ports"]["wan"]["carrier"], "0")
            self.assertEqual(data["ports"]["lan1"]["carrier"], "1")
            self.assertFalse(data["ports"]["lan3"]["present"])

    def test_production_shell_syntax(self):
        for path in (DIAG, API):
            with self.subTest(path=path.name):
                r = subprocess.run(["sh", "-n", str(path)], capture_output=True, text=True)
                self.assertEqual(r.returncode, 0, r.stderr)


if __name__ == "__main__":
    unittest.main()
