"""Host shell test for short WPS press and stock long-press preservation.

No physical button or firmware runtime is tested.
"""
from pathlib import Path
import os
import subprocess
import unittest

BUTTON = Path(__file__).resolve().parents[1] / "package/wiflow-setup/files/etc/rc.wps/00-wiflow-first-owner"


class WpsRoutingTests(unittest.TestCase):
    def test_button_handler_only_claims_short_release_when_armed(self):
        source = BUTTON.read_text()
        self.assertIn('[ "$SEEN" -lt 3 ]', source)
        self.assertIn('case "$' + '{SEEN:-}"', source)
        simulated = source.replace(
            '[ -r /usr/lib/wiflow/owner-claim.sh ] || exit 1',
            ': # simulated source check',
        ).replace(
            '. /usr/lib/wiflow/owner-claim.sh',
            'owner_claim_wps(){ [ "$MOCK_APPROVED" = 1 ]; }',
        )
        self.assertNotIn('. /usr/lib/wiflow/owner-claim.sh', simulated)
        scenarios = (
            ("wps", "released", "0", "1", True),
            ("wps", "released", "2", "1", True),
            ("wps", "released", "2", "0", False),
            ("wps", "pressed", "1", "1", False),
            ("wps", "released", "3", "1", False),
            ("wps", "released", "8", "1", False),
            ("wps", "released", "", "1", False),
            ("wps", "released", "bad", "1", False),
            ("reset", "released", "1", "1", False),
        )
        for button, action, seen, approved, allowed in scenarios:
            with self.subTest(button=button, action=action,
                              seen=seen, approved=approved):
                run = subprocess.run(
                    ["sh", "-c", simulated],
                    env={**os.environ, "BUTTON": button, "ACTION": action,
                         "SEEN": seen, "MOCK_APPROVED": approved},
                    capture_output=True, text=True, timeout=5,
                )
                self.assertEqual(run.returncode == 0, allowed,
                                 run.stdout + run.stderr)


if __name__ == "__main__":
    unittest.main()
