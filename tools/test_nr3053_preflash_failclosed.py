"""One-pass host regression for firstboot radio and interrupted-uplink rollback.

Runs production shell fragments against disposable host fixtures.
Never connects to serial/router, writes MTD, or invokes sysupgrade.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "package/wiflow-setup/files/usr/lib/wiflow"
COMMON = (BASE / "common.sh").read_text()
BOOT = (BASE / "bootstrap").read_text()
RADIO = (BASE / "radio-policy").read_text()


def function(src, name):
    start = src.index(name + "(){")
    end = src.index("\n}", start) + 2
    return src[start:end]


class PreflashFailClosedTests(unittest.TestCase):
    def run_recover(self, *, missing=None, fail_cp=False):
        with tempfile.TemporaryDirectory(prefix="wiflow-nr3053-restore-") as d:
            base = Path(d)
            cfg = base / "config"
            cfg.mkdir()
            transaction = base / "transaction"
            transaction.mkdir()
            (transaction / ".pending").write_text("")
            for name in ("wireless", "network", "wiflow"):
                (cfg / name).write_text("current-" + name)
                if missing != name:
                    (transaction / name).write_text("saved-" + name)
            owner = function(COMMON, "recover_uplink_transaction").replace(
                '"/etc/config/$f"', '"$TEST_CONFIG/$f"')
            script = (
                "set -u\n"
                'ROOT="$TEST_ROOT"\nUPLINK_TXN="$TEST_ROOT/transaction"\n'
                'TEST_CONFIG="$TEST_ROOT/config"\n'
                'secure_configs(){ return 0; }\n'
                'command_result_set(){ return 0; }\n'
                'cp(){\n'
                ' case "$1" in *wireless) [ "$FAIL_COPY" = 1 ] && return 1;; esac\n'
                ' command cp "$@"\n'
                '}\n'
                + owner + "\nrecover_uplink_transaction\n"
            )
            r = subprocess.run(
                ["sh", "-c", script], capture_output=True, text=True, timeout=5,
                env={**os.environ, "TEST_ROOT": d, "FAIL_COPY": "1" if fail_cp else "0"},
            )
            return r.returncode, transaction.exists(), {
                f: (cfg / f).read_text() for f in ("wireless", "network", "wiflow")
            }, r.stderr

    def test_complete_uplink_rollback_removes_transaction(self):
        code, remains, values, err = self.run_recover()
        self.assertEqual(code, 0, err)
        self.assertFalse(remains)
        for n in values:
            self.assertEqual(values[n], "saved-" + n)

    def test_missing_backup_never_discards_rollback(self):
        for missing in ("wireless", "network", "wiflow"):
            with self.subTest(missing=missing):
                code, remains, values, err = self.run_recover(missing=missing)
                self.assertNotEqual(code, 0, err)
                self.assertTrue(remains)
                self.assertEqual(values, {x: "current-" + x for x in values})

    def test_failed_copy_preserves_transaction(self):
        code, remains, values, err = self.run_recover(fail_cp=True)
        self.assertNotEqual(code, 0, err)
        self.assertTrue(remains)
        self.assertEqual(values["wireless"], "current-wireless")

    def test_boot_blocks_on_interrupted_uplink_restore(self):
        self.assertIn("recover_uplink_transaction || bootstrap_fail 'uplink rollback transaction incomplete'", BOOT)
        self.assertNotIn("recover_uplink_transaction && log 'Recovered interrupted uplink transaction' || true", BOOT)

    def run_radio(self, *, fail_call="NEVER", lost_band=False):
        setup = r'''
set -u
radio_for_band(){
 if [ "$1" = 2g ]; then echo radio2
 elif [ "$LOST_BAND" != 1 ]; then echo radio5
 fi
}
uci(){
 [ "$*" = "$FAIL_CALL" ] && return 1
 if [ "$1" = -q ] && [ "$2" = get ] && [ "$3" = wiflow.core.guest_ssid ]; then
  echo Wiflow
 fi
 return 0
}
'''
        body = RADIO.replace(". /usr/lib/wiflow/common.sh", setup)
        r = subprocess.run(
            ["sh", "-c", body], capture_output=True, text=True, timeout=5,
            env={**os.environ, "FAIL_CALL": fail_call, "LOST_BAND": "1" if lost_band else "0"},
        )
        return r.returncode, r.stderr

    def test_normal_dual_band_radio_policy_succeeds(self):
        code, err = self.run_radio()
        self.assertEqual(code, 0, err)

    def test_radio_uci_write_and_commit_fail_closed(self):
        for cmd in (
            "set wireless.radio2.country=VN",
            "set wireless.wiflow_guest_2g.network=wiflow_guest",
            "set wireless.wiflow_guest_5g.encryption=none",
            "commit wireless",
        ):
            with self.subTest(cmd=cmd):
                code, err = self.run_radio(fail_call=cmd)
                self.assertNotEqual(code, 0, err)

    def test_missing_second_radio_blocks_success(self):
        code, err = self.run_radio(lost_band=True)
        self.assertNotEqual(code, 0, err)

    def test_boot_waits_for_wifi_success_before_management_complete(self):
        self.assertIn("bootstrap_fail 'initial WiFi radio policy failed'", BOOT)
        self.assertIn("bootstrap_fail 'saved WiFi radio policy failed'", BOOT)
        self.assertIn("bootstrap_fail 'WiFi radio reload failed'", BOOT)
        self.assertNotIn("wifi reload >/dev/null 2>&1 || true", BOOT)

    def test_production_files_shell_parse(self):
        for script in (BOOT, COMMON, RADIO):
            p = subprocess.run(["sh", "-n"], input=script, capture_output=True, text=True)
            self.assertEqual(p.returncode, 0, p.stderr)


if __name__ == "__main__":
    unittest.main()
