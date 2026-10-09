"""Execute the exact production Portal revision activation shell sequence.

Evidence: host POSIX shell filesystem regressions. This does not replace an
actual NR3053 flash-storage/power-loss test or a live WordPress sync test.
"""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SYNC = ROOT / "package/wiflow-setup/files/usr/lib/wiflow/portal-sync"
SOURCE = SYNC.read_text(encoding="utf-8")


def activation_code():
    start = SOURCE.index('DEST="$PORTAL_REVISIONS/rev-$REV-$$"')
    end = SOURCE.index('\nuci set "wiflow.core.portal_revision=', start)
    return SOURCE[start:end]


class AtomicPortalRevisionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="wiflow-portal-atomic-")
        self.addCleanup(self.temp.cleanup)
        self.runtime = Path(self.temp.name) / "runtime"
        self.revisions = self.runtime / "revisions"
        self.revisions.mkdir(parents=True)
        self.active = self.runtime / "active"
        self.stage = self.runtime / ".staging-test"
        self.stage.mkdir()
        (self.stage / "portal.json").write_text("new")
        self.rev = 7

    def existing_active(self, name="rev-7"):
        prev = self.revisions / name
        prev.mkdir()
        (prev / "portal.json").write_text("old")
        self.active.symlink_to(f"revisions/{name}")
        return prev

    def shell(self, prelude="", verify_before_swap=False):
        start = '''
set -eu
PORTAL_RUNTIME="$TEST_RUNTIME"
PORTAL_REVISIONS="$PORTAL_RUNTIME/revisions"
PORTAL_ACTIVE="$PORTAL_RUNTIME/active"
STAGE="$TEST_STAGE"
REV=7
fail(){ printf "FAILED:%s\\n" "$1" >&2; [ -z "$STAGE" ] || rm -rf "$STAGE"; exit 51; }
'''
        if verify_before_swap:
            start += '''
mv(){
 if [ "$1" = "-Tf" ]; then
  [ "$(cat "$PORTAL_ACTIVE/portal.json")" = old ] || exit 60
 fi
 command mv "$@"
}
'''
        script = start + prelude + "\n" + activation_code() + "\n"
        return subprocess.run(
            ["sh", "-c", script],
            env={**os.environ, "TEST_RUNTIME": str(self.runtime),
                 "TEST_STAGE": str(self.stage)},
            text=True, capture_output=True, timeout=5,
        )

    def test_same_revision_repair_keeps_old_live_until_atomic_swap(self):
        previous = self.existing_active()
        result = self.shell(verify_before_swap=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.active.is_symlink())
        self.assertEqual((self.active / "portal.json").read_text(), "new")
        self.assertNotEqual(os.readlink(self.active), "revisions/rev-7")
        self.assertFalse(previous.exists(), "old revision must be pruned only after swap")
        self.assertEqual(len(list(self.revisions.glob("rev-*"))), 1)

    def test_different_revision_activates_and_removes_old_media(self):
        previous = self.existing_active("rev-6")
        result = self.shell(verify_before_swap=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.active / "portal.json").read_text(), "new")
        self.assertFalse(previous.exists())

    def test_existing_destination_is_rejected_without_overwrite(self):
        previous = self.existing_active()
        prelude = '''
mkdir -p "$PORTAL_REVISIONS/rev-$REV-$$"
printf occupied > "$PORTAL_REVISIONS/rev-$REV-$$/sentinel"
'''
        result = self.shell(prelude)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FAILED:revision_destination_occupied", result.stderr)
        self.assertEqual((self.active / "portal.json").read_text(), "old")
        self.assertTrue(previous.exists())

    def test_legacy_directory_kept_until_separate_migration(self):
        self.active.mkdir()
        (self.active / "portal.json").write_text("legacy")
        result = self.shell()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FAILED:legacy_active_nonatomic", result.stderr)
        self.assertEqual((self.active / "portal.json").read_text(), "legacy")
        self.assertFalse(self.active.is_symlink())

    def test_failed_atomic_swap_preserves_live_snapshot(self):
        previous = self.existing_active()
        prelude = '''
mv(){
 if [ "$1" = "-Tf" ]; then return 1; fi
 command mv "$@"
}
'''
        result = self.shell(prelude)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FAILED:active_swap", result.stderr)
        self.assertEqual((self.active / "portal.json").read_text(), "old")
        self.assertTrue(previous.exists())
        self.assertEqual(sorted(x.name for x in self.revisions.iterdir()), ["rev-7"])

    def test_activation_still_validates_media_before_switch(self):
        validate = SOURCE.index('got_hash="$(sha256sum "$out"')
        target = SOURCE.index('DEST="$PORTAL_REVISIONS/rev-$REV-$$"')
        swap = SOURCE.index('mv -Tf "$LINK" "$PORTAL_ACTIVE"')
        prune = SOURCE.index('for d in "$PORTAL_REVISIONS"/rev-*')
        self.assertLess(validate, target)
        self.assertLess(target, swap)
        self.assertLess(swap, prune)
        self.assertNotIn('rm -rf "$DEST" 2>/dev/null || true; mv "$STAGE"', SOURCE)


if __name__ == "__main__":
    unittest.main()
