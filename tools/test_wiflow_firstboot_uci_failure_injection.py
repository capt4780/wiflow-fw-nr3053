"""P46: execute production UCI network and listener functions with failure injection.

Uses disposable host fixtures/mocks. Not a device E5, no real /etc/config
writes, no live router, no firmware flashing.
"""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
COMMON = (ROOT / "package/wiflow-setup/files/usr/lib/wiflow/common.sh").read_text()
BOOT = (ROOT / "package/wiflow-setup/files/usr/lib/wiflow/bootstrap").read_text()
SCOPE_NAMES = ("ensure_guest_network", "ensure_uplink_network", "tune_wiflow_runtime")


def function(text: str, name: str) -> str:
    start = text.index(name + "(){")
    end = text.index("\n}", start) + 2
    return text[start:end]


MOCK = r"""
uci(){
    printf '%s\n' "$*" >> "$TEST_DIR/calls"
    if [ "$1" = '-q' ]; then
        case "$2" in
            get)
                case "$3" in
                    firewall.wiflow_guest_wan) [ "$STALE_WAN" = '1' ]; return ;;
                    uhttpd.main) return 0 ;;
                    uhttpd.main.listen_http) [ "$STALE_HTTP" = '1' ]; return ;;
                    uhttpd.main.listen_https) [ "$STALE_HTTPS" = '1' ]; return ;;
                    *) return 0 ;;
                esac ;;
            delete) return 0 ;;
            del_list) return 0 ;;
        esac
    fi
    [ "$*" = "$FAIL_CALL" ] && return 1
    return 0
}
wan_zone(){ printf 'wan'; }
tcp_listening(){ return 0; }
test_service(){ printf 'service %s\n' "$*" >> "$TEST_DIR/calls"; return 0; }
"""


class FirstbootUciFailureTests(unittest.TestCase):
    def run_shell(self, body: str, operation: str, *, fail_call="NOT_CALLED",
                  stale_wan=False, stale_http=False, stale_https=False):
        with tempfile.TemporaryDirectory(prefix="wiflow-p46-uci-") as d:
            p = Path(d)
            (p / "uhttpd").write_text("fixture\n")
            (p / "stock").mkdir()
            script = (
                "#!/bin/sh\nset -u\n"
                'TEST_UHTTPD_FILE="$TEST_DIR/uhttpd"\n'
                'ROOT="$TEST_DIR/stock"\n'
                + MOCK + "\n" + body + "\n" + operation + "\n"
            )
            result = subprocess.run(
                ["sh", "-c", script],
                env={**os.environ, "TEST_DIR": d, "FAIL_CALL": fail_call,
                     "STALE_WAN": "1" if stale_wan else "0",
                     "STALE_HTTP": "1" if stale_http else "0",
                     "STALE_HTTPS": "1" if stale_https else "0"},
                capture_output=True, text=True, timeout=5,
            )
            calls = (p / "calls").read_text().splitlines() if (p / "calls").exists() else []
            return result.returncode, calls, result.stderr

    def test_network_guest_all_stages_succeed(self):
        code, calls, err = self.run_shell(
            function(COMMON, "ensure_guest_network"), "ensure_guest_network")
        self.assertEqual(code, 0, err)
        self.assertIn("commit network", calls)
        self.assertIn("commit dhcp", calls)
        self.assertIn("commit firewall", calls)

    def test_guest_critical_uci_failures_stop_immediately(self):
        for command in (
            "set network.wiflow_guest.ipaddr=10.10.10.1",
            "set network.wiflow_guest_dev.name=br-wiflow",
            "commit network",
            "set dhcp.wiflow_guest.limit=150",
            "commit dhcp",
            "set firewall.wiflow_guest.forward=REJECT",
            "add_list firewall.wiflow_guest_private_dns.proto=tcp",
            "set firewall.wiflow_guest_gate.target=ACCEPT",
            "commit firewall",
        ):
            with self.subTest(command=command):
                code, calls, err = self.run_shell(
                    function(COMMON, "ensure_guest_network"),
                    "ensure_guest_network", fail_call=command)
                self.assertNotEqual(code, 0, err)
                self.assertIn(command, calls)

    def test_existing_guest_wan_forward_rule_blocks_even_if_delete_returns_success(self):
        code, calls, err = self.run_shell(
            function(COMMON, "ensure_guest_network"), "ensure_guest_network", stale_wan=True)
        self.assertNotEqual(code, 0, err)
        self.assertIn("-q get firewall.wiflow_guest_wan", calls)
        self.assertNotIn("commit firewall", calls)

    def test_uplink_and_runtime_uci_failures_propagate(self):
        for name, failed in (
            ("ensure_uplink_network", "set network.wiflow_wwan.metric=10"),
            ("ensure_uplink_network", "commit firewall"),
            ("tune_wiflow_runtime", "commit network"),
            ("tune_wiflow_runtime", "commit dhcp"),
        ):
            with self.subTest(function=name, failure=failed):
                code, calls, err = self.run_shell(
                    function(COMMON, name), name, fail_call=failed)
                self.assertNotEqual(code, 0, err)
                self.assertIn(failed, calls)

    def test_bootstrap_chains_every_uci_owner_to_failure_handler(self):
        for name in SCOPE_NAMES:
            self.assertIn(name + " || bootstrap_fail", BOOT)

    def test_web_listener_deletion_guard(self):
        web = function(BOOT, "configure_web").replace(
            "/etc/config/uhttpd", '"$TEST_UHTTPD_FILE"')
        web = web.replace("/etc/init.d/uhttpd", "test_service uhttpd")
        web = web.replace("/etc/init.d/firewall", "test_service firewall")
        for flags in ({}, {"stale_http": True}, {"stale_https": True}):
            with self.subTest(flags=flags):
                code, calls, err = self.run_shell(web, "configure_web", **flags)
                self.assertEqual(code == 0, not bool(flags), err)
                if flags:
                    self.assertNotIn("commit uhttpd", calls)
                else:
                    self.assertIn("commit uhttpd", calls)
        self.assertIn("uci -q get uhttpd.main.listen_http >/dev/null 2>&1 && return 1", BOOT)
        self.assertIn("uci -q get uhttpd.main.listen_https >/dev/null 2>&1 && return 1", BOOT)

    def test_web_uci_partial_write_blocks(self):
        web = function(BOOT, "configure_web").replace(
            "/etc/config/uhttpd", '"$TEST_UHTTPD_FILE"')
        for command in (
            "add_list uhttpd.main.listen_http=10.0.0.2:8081",
            "set uhttpd.wiflow_luci_gate.home=/www-wiflow-luci-gate",
            "set uhttpd.wiflow_portal.home=/www-wiflow-portal",
            "commit uhttpd",
        ):
            with self.subTest(command=command):
                code, calls, err = self.run_shell(web, "configure_web", fail_call=command)
                self.assertNotEqual(code, 0, err)
                self.assertIn(command, calls)


if __name__ == "__main__":
    unittest.main()
