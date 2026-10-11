"""Guard that expensive image jobs do not get pinned behind obsolete PR builds."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
WF = (ROOT / ".github/workflows/build-nr3053-wiflow.yml").read_text()


class FirmwareImageBuildQueueTests(unittest.TestCase):
    def test_independent_per_pr_build_lane(self):
        self.assertIn("group: nr3053-wiflow-public-experimental-${{ github.event.pull_request.number || github.ref }}", WF)
        self.assertIn("cancel-in-progress: ${{ github.event_name == 'pull_request' }}", WF)
        self.assertNotIn("group: nr3053-wiflow-public-experimental\n", WF)
        self.assertNotIn("cancel-in-progress: false", WF)

    def test_required_exact_image_audit_is_not_short_circuited(self):
        for expected in (
            'runs-on: ubuntu-24.04',
            'timeout-minutes: 330',
            'bash scripts/build-nr3053-base.sh',
            'python3 tools/check_nr3053_fit_reference.py',
            'python3 tools/audit_nr3053_rootfs.py',
            'python3 tools/audit_nr3053_wiflow_image.py',
            'WIFLOW_NR3053_APK_SOURCE_IMAGE_STATIC_INSPECTION_PASS_NO_FLASH',
            'nr3053-wiflow-experimental-NOT-FOR-FLASHING',
        ):
            self.assertIn(expected, WF)


if __name__ == "__main__":
    unittest.main()
