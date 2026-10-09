"""Executed regressions for full-replacement portal media stage integrity.

The user-selected portal snapshot must be atomically activated only after
every unique media filename has been validated. A different role must never
overwrite a previously verified file in the shared staging directory.
"""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "package/wiflow-setup/files/usr/lib/wiflow/portal-sync").read_text()


def actual_shell_functions():
    # Invoke the exact reviewed production functions, not a Python imitation.
    begin = SOURCE.index("media_name_valid(){")
    end = SOURCE.index("seen='|'; seen_names='|'; i=0", begin)
    return SOURCE[begin:end]


def run_shell(script):
    return subprocess.run(
        ["/bin/sh", "-ec", actual_shell_functions() + "\n" + script],
        capture_output=True, text=True, timeout=5,
    )


class PortalMediaNameIntegrityTests(unittest.TestCase):
    def test_unique_cross_role_names_accepted(self):
        outcome = run_shell("""
seen_names='|'
media_name_valid 'landscape.webp'
media_name_unique 'landscape.webp'
media_name_valid 'portrait.webp'
media_name_unique 'portrait.webp'
media_name_valid 'popup_1.webp'
media_name_unique 'popup_1.webp'
[ "$seen_names" = '|landscape.webp|portrait.webp|popup_1.webp|' ]
""")
        self.assertEqual(outcome.returncode, 0, outcome.stderr)

    def test_identical_filename_in_different_roles_rejected(self):
        outcome = run_shell("""
seen_names='|'
media_name_unique 'same.webp'
if media_name_unique 'same.webp'; then exit 13; fi
[ "$seen_names" = '|same.webp|' ]
""")
        self.assertEqual(outcome.returncode, 0, outcome.stderr)

    def test_dot_parent_and_unsafe_names_rejected(self):
        for filename in ("", ".", "..", "../escape", "x/y", "bad|name",
                         "bad name.webp", "x"*121):
            with self.subTest(filename=filename):
                outcome = run_shell("media_name_valid " + self._quote(filename) +
                                    " && exit 17 || exit 0")
                self.assertEqual(outcome.returncode, 0, outcome.stderr)

    def test_validation_and_uniqueness_precede_stage_download(self):
        start = SOURCE.index("seen='|'; seen_names='|'; i=0")
        validation = SOURCE.index('media_name_valid "$name" || fail')
        unique = SOURCE.index('media_name_unique "$name" || fail')
        download = SOURCE.index('out="$STAGE/media/$name"; wiflow_get')
        activated = SOURCE.index('mv -Tf "$LINK" "$PORTAL_ACTIVE"')
        self.assertLess(start, validation)
        self.assertLess(validation, unique)
        self.assertLess(unique, download)
        self.assertLess(download, activated)
        self.assertIn("fail 'media_name_duplicate'", SOURCE)
        self.assertIn("fail 'media_name'", SOURCE)
        self.assertIn("rm -rf \"$STAGE\"", SOURCE)

    @staticmethod
    def _quote(s):
        return "'" + s.replace("'", "'\\''") + "'"


if __name__ == "__main__":
    unittest.main()
