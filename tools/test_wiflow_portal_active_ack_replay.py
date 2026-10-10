"""Host-executed regressions for WordPress Portal ACK receipt and retry.

The production shell helper is exercised with fake HTTP transport, and the
production heartbeat reconciliation function is exercised with test-only path
substitutions. This does not assert a live WordPress/device E5 session.
"""
from pathlib import Path
import json
import os
import subprocess
import tempfile
import unittest

FILES = Path(__file__).resolve().parents[1] / "package/wiflow-setup/files"
SOURCE = (FILES / "usr/lib/wiflow/portal-sync").read_text(encoding="utf-8")
HEARTBEAT = (FILES / "usr/lib/wiflow/heartbeat-loop").read_text(encoding="utf-8")
COMMON = (FILES / "usr/lib/wiflow/common.sh").read_text(encoding="utf-8")


def production_ack_function():
    begin = SOURCE.index("ack_active_revision(){")
    end = SOURCE.index('\nRESP="/tmp/wiflow-portal-manifest.$$', begin)
    return SOURCE[begin:end]


def production_heartbeat_functions():
    begin = HEARTBEAT.index("portal_runtime_set_enabled(){")
    end = HEARTBEAT.index("\ndelay=20", begin)
    return HEARTBEAT[begin:end].replace(
        "/usr/lib/wiflow/portal-sync", "portal_sync_test"
    ).replace("/usr/lib/wiflow/portal-firewall", "portal_firewall_test")


class PortalActiveAckReplayTests(unittest.TestCase):
    def invoke(self, failure=False):
        with tempfile.TemporaryDirectory(prefix="wiflow-ack-test-") as temp:
            path = Path(temp) / "ack.log"
            log = Path(temp) / "error.log"
            marker = Path(temp) / "confirmed-revision"
            script = (
                "REV=27\n"
                "WIFLOW_DATA_GENERATION=4\n"
                "WIFLOW_PORTAL_API=https://example.invalid/wiflow/wp-json/portal\n"
                'PORTAL_ACK_CONFIRMED="$ACK_MARKER"\n'
                "wiflow_post(){ printf '%s|%s\\n' \"$2\" \"$3\" >> \"$ACK_OUTPUT\"; "
                '[ "$ACK_FAIL" = 0 ]; }\n'
                'logger(){ printf "%s\\n" "$*" >> "$ERROR_OUTPUT"; }\n'
                + production_ack_function()
                + "\nack_active_revision\nack_active_revision\n"
            )
            proc = subprocess.run(
                ["sh", "-c", script],
                capture_output=True, text=True, check=False, timeout=5,
                env={**os.environ, "ACK_OUTPUT": str(path),
                     "ERROR_OUTPUT": str(log), "ACK_MARKER": str(marker),
                     "ACK_FAIL": "1" if failure else "0"},
            )
            self.assertEqual(proc.stdout, "")
            self.assertEqual(proc.stderr, "")
            self.assertEqual(proc.returncode, 0)
            records = path.read_text().splitlines()
            self.assertEqual(len(records), 2)
            for record in records:
                url, payload = record.split("|", 1)
                self.assertEqual(url, "https://example.invalid/wiflow/wp-json/portal/ack")
                self.assertEqual(json.loads(payload), {
                    "revision": 27, "status": "active", "data_generation": 4,
                })
            if failure:
                self.assertFalse(marker.exists(), "a failed ACK must remain retryable")
            else:
                self.assertEqual(marker.read_text(), "27\n")
            return log.read_text().splitlines() if log.exists() else []

    def heartbeat_probe(self, starting_marker=None, wanted=1):
        with tempfile.TemporaryDirectory(prefix="wiflow-heartbeat-ack-") as temp:
            base = Path(temp)
            active = base / "active"
            active.mkdir()
            (active / "portal.json").write_text('{"revision":27}')
            marker = base / "confirmed-revision"
            calls = base / "sync.calls"
            if starting_marker is not None:
                marker.write_text(starting_marker)
            script = (
                'PORTAL_ACTIVE="$TEST_ACTIVE"\n'
                'PORTAL_ACK_CONFIRMED="$ACK_MARKER"\n'
                'uci(){ :; }\n'
                'state_set(){ :; }\n'
                'portal_firewall_test(){ :; }\n'
                'portal_sync_test(){ printf "sync:%s\\n" "$1" >> "$TEST_CALLS"; '
                'printf "%s\\n" "$1" > "$PORTAL_ACK_CONFIRMED"; }\n'
                + production_heartbeat_functions()
                + "\nportal_runtime_reconcile \"$WANTED\" 27 27\n"
                + "\nportal_runtime_reconcile \"$WANTED\" 27 27\n"
            )
            proc = subprocess.run(
                ["sh", "-c", script],
                capture_output=True, text=True, check=False, timeout=5,
                env={**os.environ, "TEST_ACTIVE": str(active),
                     "ACK_MARKER": str(marker), "TEST_CALLS": str(calls),
                     "WANTED": str(wanted)},
            )
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertEqual(proc.stdout, "")
            self.assertEqual(proc.stderr, "")
            return calls.read_text().splitlines() if calls.exists() else [], marker.exists()

    def test_same_revision_ack_replays_idempotently(self):
        self.assertEqual(self.invoke(), [])

    def test_failed_ack_remains_retryable_and_logs_only_status(self):
        messages = self.invoke(failure=True)
        self.assertEqual(len(messages), 2)
        for message in messages:
            self.assertIn("ack=retry_needed revision=27", message)
            self.assertNotIn("example.invalid", message)

    def test_existing_revision_fast_path_replays_ack_before_return(self):
        begin = SOURCE.index('if [ "$current" -eq "$REV" ]')
        end = SOURCE.index('\nmkdir -p "$PORTAL_REVISIONS"', begin)
        chunk = SOURCE[begin:end]
        self.assertIn("ack_active_revision", chunk)
        self.assertLess(chunk.index("ack_active_revision"), chunk.index('rm -f "$RESP"; exit 0'))

    def test_successful_atomic_activation_uses_the_same_ack_helper(self):
        begin = SOURCE.index('uci set "wiflow.core.portal_revision=$REV"')
        suffix = SOURCE[begin:]
        self.assertIn("ack_active_revision", suffix)
        self.assertIn("portal-firewall refresh", suffix)
        self.assertEqual(SOURCE.count("ack_active_revision()"), 1)
        self.assertEqual(SOURCE.count("\n  ack_active_revision\n"), 1)
        self.assertEqual(SOURCE.count("\nack_active_revision\n"), 1)

    def test_heartbeat_retries_missing_or_stale_ack_once(self):
        for starting_marker in (None, "26\n", ""):
            with self.subTest(starting_marker=starting_marker):
                calls, exists = self.heartbeat_probe(starting_marker)
                self.assertEqual(calls, ["sync:27"])
                self.assertTrue(exists)

    def test_heartbeat_skips_already_confirmed_revision(self):
        calls, exists = self.heartbeat_probe("27\n")
        self.assertEqual(calls, [])
        self.assertTrue(exists)

    def test_disabling_portal_invalidates_ack_receipt(self):
        calls, marker_exists = self.heartbeat_probe("27\n", wanted=0)
        self.assertEqual(calls, [])
        self.assertFalse(marker_exists)

    def test_heartbeat_uses_idempotent_captive_firewall_ensure(self):
        reconcile = HEARTBEAT[
            HEARTBEAT.index("portal_runtime_reconcile(){"):
            HEARTBEAT.index("\ndelay=20")
        ]
        self.assertIn("/usr/lib/wiflow/portal-firewall ensure", reconcile)
        self.assertNotIn("/usr/lib/wiflow/portal-firewall enable", reconcile)
        firewall = (FILES / "usr/lib/wiflow/portal-firewall").read_text()
        begin = firewall.index("ensure(){")
        end = firewall.index("\ndisable(){", begin)
        ensure = firewall[begin:end]
        self.assertIn("portal_nft_ready", ensure)
        self.assertIn("wiflow_portal_prerouting", ensure)
        self.assertIn("wiflow_portal_forward", ensure)
        self.assertIn("enable", ensure)

    def test_uci_state_committed_only_on_transition(self):
        # Execute the actual production state helper, not a Python emulator.
        with tempfile.TemporaryDirectory(prefix="wiflow-uci-no-flash-write-") as tmp:
            state = Path(tmp) / "state"
            writes = Path(tmp) / "writes"
            prefix = (
                'UCI_STATE="$TEST_UCI_STATE"\n'
                'UCI_WRITES="$TEST_UCI_WRITES"\n'
                'uci(){\n'
                ' case "$1" in\n'
                '  -q) cat "$UCI_STATE" 2>/dev/null || true;;\n'
                '  set) printf "%s\\n" "${2##*=}" > "$UCI_STATE"; '
                'printf "set:%s\\n" "$2" >> "$UCI_WRITES";;\n'
                '  commit) printf "commit:%s\\n" "$2" >> "$UCI_WRITES";;\n'
                ' esac\n'
                '}\n'
            )
            helper = production_heartbeat_functions()
            script = (prefix + helper +
                '\nportal_runtime_set_enabled 1\n'
                'portal_runtime_set_enabled 1\n'
                'portal_runtime_set_enabled 0\n'
                'portal_runtime_set_enabled 0\n')
            result = subprocess.run(
                ["sh", "-c", script], capture_output=True, text=True,
                env={**os.environ, "TEST_UCI_STATE": str(state),
                     "TEST_UCI_WRITES": str(writes)},
                timeout=5, check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(writes.read_text().splitlines(), [
                "set:wiflow.core.portal_enabled=1", "commit:wiflow",
                "set:wiflow.core.portal_enabled=0", "commit:wiflow",
            ])
            self.assertEqual(state.read_text(), "0\n")


    def test_firewall_disable_does_not_commit_when_already_disabled(self):
        firewall = (FILES / "usr/lib/wiflow/portal-firewall").read_text()
        begin = firewall.index("\ndisable(){")
        end = firewall.index('\ncase "$MODE" in', begin)
        actual_disable = firewall[begin:end].replace(
            "/etc/init.d/firewall", "firewall_reload_test"
        )
        with tempfile.TemporaryDirectory(prefix="wiflow-firewall-disabled-") as tmp:
            nft = Path(tmp) / "30-wiflow-captive.nft"
            log = Path(tmp) / "writes.log"
            script = (
                'NFT_FILE="$TEST_NFT_FILE"\n'
                'uci(){\n'
                ' case "$1" in\n'
                '  -q) return 1;;\n'
                '  commit) printf "commit:%s\n" "$2" >> "$TEST_LOG";;\n'
                ' esac\n'
                '}\n'
                'firewall_reload_test(){ printf "reload\n" >> "$TEST_LOG"; }\n'
                + actual_disable + "\ndisable\n"
            )
            env = {**os.environ, "TEST_NFT_FILE": str(nft), "TEST_LOG": str(log)}
            no_change = subprocess.run(
                ["sh", "-c", script], capture_output=True, text=True,
                env=env, timeout=5,
            )
            self.assertEqual(no_change.returncode, 0, no_change.stderr)
            self.assertFalse(log.exists(), "no UCI commit/reload on already-disabled Portal")
            tmp_nft = Path(str(nft) + ".tmp")
            tmp_nft.write_text("stale")
            repeat = subprocess.run(["sh", "-c", script], env=env, capture_output=True, text=True, timeout=5)
            self.assertEqual(repeat.returncode, 0, repeat.stderr)
            self.assertFalse(tmp_nft.exists(), "stale temporary rule must be cleaned")
            self.assertFalse(log.exists())
            nft.write_text("active")
            transition = subprocess.run(
                ["sh", "-c", script], capture_output=True, text=True,
                env=env, timeout=5,
            )
            self.assertEqual(transition.returncode, 0, transition.stderr)
            self.assertFalse(nft.exists())
            self.assertEqual(log.read_text().splitlines(), ["commit:firewall", "reload"])


    def test_wp_generation_mismatch_preserves_only_valid_local_portal(self):
        # Run the exact heartbeat mismatch branch with no real router/WP I/O.
        begin = HEARTBEAT.index('if [ "$generation" != "$WIFLOW_DATA_GENERATION" ]; then')
        end = HEARTBEAT.index("\n   else\n    state_set wp_online 1", begin)
        branch = HEARTBEAT[begin:end].replace(
            "/usr/lib/wiflow/portal-firewall", "portal_firewall_test"
        )
        for snapshot, enabled, firewall_ok, expect_disabled, expect_ensure in (
            (True, True, True, False, True),
            (True, True, False, True, True),
            (False, True, True, True, False),
            (True, False, True, True, False),
        ):
            with self.subTest(snapshot=snapshot, enabled=enabled, firewall_ok=firewall_ok):
                with tempfile.TemporaryDirectory(prefix="wiflow-wp-mismatch-") as tmp:
                    active = Path(tmp) / "active"
                    active.mkdir()
                    if snapshot:
                        (active / "portal.json").write_text('{"revision":27}')
                    states = Path(tmp) / "state.log"
                    fw_calls = Path(tmp) / "fw.log"
                    script = (
                        'PORTAL_ACTIVE="$TEST_ACTIVE"\n'
                        'generation=5\nWIFLOW_DATA_GENERATION=4\n'
                        'uci(){ [ "$TEST_ENABLED" = 1 ] && printf "1\n"; }\n'
                        'state_set(){ printf "%s=%s\n" "$1" "$2" >> "$TEST_STATES"; }\n'
                        'portal_runtime_disable(){ printf "disabled\n" >> "$TEST_STATES"; }\n'
                        'portal_firewall_test(){ printf "%s\n" "$1" >> "$TEST_FW"; '
                        '[ "$TEST_FIREWALL_OK" = 1 ]; }\n'
                        + branch + '\nfi\n'
                        + 'printf "delay=%s\n" "$delay" >> "$TEST_STATES"\n'
                    )
                    result = subprocess.run(
                        ["sh", "-c", script], capture_output=True, text=True,
                        timeout=5,
                        env={**os.environ, "TEST_ACTIVE": str(active),
                             "TEST_STATES": str(states), "TEST_FW": str(fw_calls),
                             "TEST_ENABLED": "1" if enabled else "0",
                             "TEST_FIREWALL_OK": "1" if firewall_ok else "0"},
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    events = states.read_text().splitlines()
                    self.assertIn("wp_online=0", events)
                    self.assertIn("api_error=generation_mismatch:5", events)
                    self.assertIn("delay=60", events)
                    self.assertEqual("disabled" in events, expect_disabled)
                    self.assertEqual(fw_calls.exists(), expect_ensure)
                    if expect_ensure:
                        self.assertEqual(fw_calls.read_text().splitlines(), ["ensure"])
                    if snapshot and enabled and not firewall_ok:
                        self.assertIn("portal_error=captive_firewall_ensure_failed", events)

    def test_marker_is_volatile_shared_and_does_not_write_flash_every_heartbeat(self):
        self.assertIn("PORTAL_ACK_CONFIRMED=/tmp/", COMMON)
        self.assertIn('cat "$PORTAL_ACK_CONFIRMED"', HEARTBEAT)
        self.assertIn('rm -f "$PORTAL_ACK_CONFIRMED"', HEARTBEAT)
        self.assertIn('mv "$PORTAL_ACK_CONFIRMED.$$" "$PORTAL_ACK_CONFIRMED"', SOURCE)
        self.assertIn('rm -f "$PORTAL_ACK_CONFIRMED"', SOURCE)


if __name__ == "__main__":
    unittest.main()
