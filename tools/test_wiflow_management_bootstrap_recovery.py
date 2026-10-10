"""P46 host execution tests for Wiflow first-boot management rollback.

Production shell functions are executed against disposable /etc/config fixtures.
No target router, flash, credentials or calibration data are accessed.
"""
from pathlib import Path
from audit_nr3053_wiflow_image import audit_management_recovery_rootfs
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BOOT = (ROOT / "package/wiflow-setup/files/usr/lib/wiflow/bootstrap").read_text()
INIT = (ROOT / "package/wiflow-setup/files/etc/init.d/wiflow-setup").read_text()
CONFIGS = ("network", "wireless", "firewall", "dhcp", "uhttpd")


def isolated_production_functions() -> str:
    first = BOOT.index("backup_stock_configs(){")
    end = BOOT.index("ensure_management_network(){", first)
    src = BOOT[first:end]
    src = src.replace('"/etc/config/', '"$TEST_CONFIG/')
    for service in ("network", "dnsmasq", "firewall", "uhttpd"):
        src = src.replace("/etc/init.d/" + service, "test_service " + service)
    src = src.replace("wifi reload", "test_service wifi reload")
    src = src.replace("/usr/lib/wiflow/portal-firewall", "test_portal_firewall")
    return src


class ManagementBootstrapRollbackTests(unittest.TestCase):
    def run_case(self, action, missing=None, tamper=None, service_ok=True):
        with tempfile.TemporaryDirectory(prefix="wiflow-p46-") as tmp:
            root = Path(tmp)
            cfg = root / "etc" / "config"
            cfg.mkdir(parents=True)
            for name in CONFIGS:
                if name != missing:
                    (cfg / name).write_text("original:" + name, encoding="utf-8")
            shell = """#!/bin/sh
set -u
ROOT="$TEST_ROOT/wiflow"
TEST_CONFIG="$TEST_ROOT/etc/config"
mkdir -p "$ROOT"
test_service(){ printf 'svc:%s\\n' "$*" >> "$TEST_ROOT/trace"; [ "$SERVICE_OK" = 1 ]; }
test_portal_firewall(){ printf 'fw:%s\\n' "$*" >> "$TEST_ROOT/trace"; }
log(){ printf 'log:%s\\n' "$*" >> "$TEST_ROOT/trace"; }
""" + isolated_production_functions() + "\n" + action + "\n"
            proc = subprocess.run(
                ["sh", "-c", shell], capture_output=True, text=True, timeout=10,
                env={**os.environ, "TEST_ROOT": str(root),
                     "SERVICE_OK": "1" if service_ok else "0"},
            )
            trace = (root / "trace").read_text().splitlines() if (root / "trace").exists() else []
            config = {n: (cfg / n).read_text() if (cfg / n).exists() else None for n in CONFIGS}
            marker = (root / "wiflow" / "stock" / ".complete").exists()
            return proc, trace, config, marker

    def test_real_shell_syntax(self):
        for p in (BOOT, INIT):
            proc = subprocess.run(["sh", "-n"], input=p, text=True,
                                  capture_output=True, timeout=4)
            self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_successful_backup_mutation_and_rollback(self):
        action = """backup_stock_configs || exit 20
for f in network wireless firewall dhcp uhttpd; do
    printf 'changed:%s' "$f" > "$TEST_CONFIG/$f"
done
rollback_stock_configs || exit 30
"""
        proc, trace, config, complete = self.run_case(action)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertTrue(complete)
        self.assertEqual(config, {n: "original:" + n for n in CONFIGS})
        self.assertEqual(trace, ["svc:network reload", "svc:dnsmasq restart",
                                 "svc:firewall reload", "svc:uhttpd restart",
                                 "svc:wifi reload"])

    def test_missing_config_never_marks_complete(self):
        proc, trace, config, complete = self.run_case(
            "backup_stock_configs", missing="firewall")
        self.assertNotEqual(proc.returncode, 0)
        self.assertFalse(complete)

    def test_incomplete_backup_prevents_rollback_without_overwrite(self):
        action = """backup_stock_configs || exit 20
rm -f "$ROOT/stock/network"
printf 'current-config' > "$TEST_CONFIG/uhttpd"
rollback_stock_configs
"""
        proc, trace, config, complete = self.run_case(action)
        self.assertNotEqual(proc.returncode, 0)
        self.assertEqual(config["uhttpd"], "current-config")

    def test_service_failure_is_not_reported_as_success(self):
        proc, trace, config, complete = self.run_case(
            "backup_stock_configs && rollback_stock_configs", service_ok=False)
        self.assertNotEqual(proc.returncode, 0)
        self.assertEqual(trace, ["svc:network reload"])

    def test_compiled_image_guard_rejects_regression(self):
        with tempfile.TemporaryDirectory(prefix="wiflow-p46-rootfs-audit-") as tmp:
            fs = Path(tmp)
            for rel, body in (("usr/lib/wiflow/bootstrap", BOOT),
                              ("etc/init.d/wiflow-setup", INIT)):
                dest = fs / rel
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_text(body, encoding="utf-8")
            self.assertEqual(audit_management_recovery_rootfs(fs), [])
            (fs / "etc/init.d/wiflow-setup").write_text(
                INIT.replace("return 1", "return 0"), encoding="utf-8")
            self.assertTrue(audit_management_recovery_rootfs(fs))
            (fs / "etc/init.d/wiflow-setup").write_text(INIT, encoding="utf-8")
            (fs / "usr/lib/wiflow/bootstrap").write_text(
                BOOT.replace("rollback_stock_configs(){", "no_rollback(){"),
                encoding="utf-8")
            self.assertTrue(audit_management_recovery_rootfs(fs))

    def test_bootstrap_failure_stops_portal_start(self):
        self.assertNotIn("/usr/lib/wiflow/bootstrap >/tmp/wiflow-bootstrap.log 2>&1 || true", INIT)
        self.assertIn("if ! /usr/lib/wiflow/bootstrap", INIT)
        self.assertLess(INIT.index("return 1"), INIT.index("procd_open_instance heartbeat"))
        for reason in (
            "management LAN configuration failed",
            "network reload failed",
            "management IP 10.0.0.1 not confirmed",
            "LuCI IP 10.0.0.2/32 not confirmed",
            "guest IP 10.10.10.1 not confirmed",
            "dnsmasq restart failed",
            "firewall reload failed",
            "management web listeners not confirmed",
        ):
            self.assertIn("bootstrap_fail '" + reason + "'", BOOT)
        self.assertLess(BOOT.index("backup_stock_configs ||"), BOOT.index("ensure_management_network ||"))
        self.assertLess(BOOT.index("configure_web || bootstrap_fail"),
                        BOOT.index("/usr/lib/wiflow/minimal-profile"))
        self.assertLess(BOOT.index("configure_web || bootstrap_fail"),
                        BOOT.index("\ncleanup_legacy_management_ips\n"))
        self.assertLess(BOOT.index("\ncleanup_legacy_management_ips\n"),
                        BOOT.index('command_result_set "$cid" "$act" success'))

    def test_failed_bootstrap_rolls_back_with_nonzero_exit(self):
        action = """backup_stock_configs || exit 20
printf 'broken' > "$TEST_CONFIG/network"
bootstrap_fail 'injected management error'
"""
        proc, trace, config, complete = self.run_case(action)
        self.assertEqual(proc.returncode, 1)
        self.assertEqual(config["network"], "original:network")
        self.assertIn("fw:disable", trace)
        self.assertTrue(any("BOOTSTRAP_ROLLBACK: configuration restored" in s for s in trace))


if __name__ == "__main__":
    unittest.main()
