"""Executed host regressions for local Portal active-revision ACK replay.

E3 source/host evidence only; does not assert a live WordPress ACK.
"""
from pathlib import Path
import json
import os
import subprocess
import tempfile
import unittest

SOURCE = (
    Path(__file__).resolve().parents[1]
    / "package/wiflow-setup/files/usr/lib/wiflow/portal-sync"
).read_text(encoding="utf-8")


def production_ack_function():
    begin = SOURCE.index("ack_active_revision(){")
    end = SOURCE.index('\nRESP="/tmp/wiflow-portal-manifest.$$', begin)
    return SOURCE[begin:end]


class PortalActiveAckReplayTests(unittest.TestCase):
    def invoke(self, failure=False):
        with tempfile.TemporaryDirectory(prefix="wiflow-ack-test-") as temp:
            path = Path(temp) / "ack.log"
            log = Path(temp) / "error.log"
            script = (
                "REV=27\n"
                "WIFLOW_DATA_GENERATION=4\n"
                "WIFLOW_PORTAL_API=https://example.invalid/wiflow/wp-json/portal\n"
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
                     "ERROR_OUTPUT": str(log), "ACK_FAIL": "1" if failure else "0"},
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
            return log.read_text().splitlines() if log.exists() else []

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


if __name__ == "__main__":
    unittest.main()
