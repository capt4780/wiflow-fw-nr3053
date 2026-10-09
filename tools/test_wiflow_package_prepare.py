"""Execute Wiflow Build/Prepare and install using GNU Make on the source tree.

Prevents the Error 127 caused by undefined $(MKDIR), $(CP), or other
buildroot-specific helper variables. Does NOT compile firmware or APK.
"""
from pathlib import Path
import hashlib
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PKG = ROOT / "package/wiflow-setup"
MAKEFILE = PKG / "Makefile"


def extract_block(text: str, name: str) -> str:
    pattern = rf"(?ms)^define {re.escape(name)}[ \t]*\n(.*?)^endef[ \t]*$"
    matches = re.findall(pattern, text)
    if len(matches) != 1:
        raise AssertionError(f"exactly one authoritative {name} expected")
    return f"define {name}\n{matches[0]}endef\n"


class WiflowPackagePrepareTests(unittest.TestCase):
    def test_prepare_and_install_copy_every_file_with_modes(self):
        source = MAKEFILE.read_text()
        prepare = extract_block(source, "Build/Prepare")
        install = extract_block(source, "Package/wiflow-setup/install")
        for block in (prepare, install):
            self.assertNotIn("$(MKDIR)", block)
            self.assertNotIn("$(CP)", block)
        with tempfile.TemporaryDirectory(prefix="wiflow-make-smoke-") as work:
            base = Path(work)
            build = base / "build"
            stage = base / "staged"
            recipes = (f"PKG_BUILD_DIR := {build}\n"
                       + prepare + install
                       + "\n.PHONY: prepare install\n"
                       + "prepare:\n\t$(Build/Prepare)\n"
                       + f"install:\n\t$(call Package/wiflow-setup/install,{stage})\n")
            run = subprocess.run(
                ["make", "--no-print-directory", "--silent", "-f", "-",
                 "prepare", "install"],
                cwd=PKG, input=recipes, text=True,
                capture_output=True, timeout=30,
            )
            self.assertEqual(run.returncode, 0, run.stderr + run.stdout)
            source_files = sorted(p for p in (PKG / "files").rglob("*")
                                  if p.is_file())
            self.assertGreaterEqual(len(source_files), 25)
            for original in source_files:
                relative = original.relative_to(PKG / "files")
                prepared = build / "rootfs" / relative
                packaged = stage / relative
                with self.subTest(path=str(relative)):
                    self.assertTrue(prepared.is_file())
                    self.assertTrue(packaged.is_file())
                    self.assertEqual(hashlib.sha256(packaged.read_bytes()).digest(),
                                     hashlib.sha256(original.read_bytes()).digest())
                    self.assertEqual(original.stat().st_mode & 0o777,
                                     packaged.stat().st_mode & 0o777)
            self.assertTrue((stage / "etc/init.d/wiflow-setup").stat().st_mode & 0o111)
            self.assertTrue((stage / "www-wiflow/cgi-bin/gate").stat().st_mode & 0o111)


if __name__ == "__main__":
    unittest.main()
