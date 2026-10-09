"""Execute the NR3053 Wiflow package preparation recipe with OpenWrt-style macros.

This catches undefined make macros such as $(MKDIR), which GitHub's full
toolchain build previously expanded to an invalid shell command (Error 127).
It does not replace the target APK or actual firmware integration build.
"""
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
PKG = REPO / "package/wiflow-setup"
MAKEFILE = PKG / "Makefile"


class PackageBuildPrepareTests(unittest.TestCase):
    def _recipe(self):
        source = MAKEFILE.read_text()
        return source.split("define Build/Prepare\n", 1)[1].split("\nendef", 1)[0]

    def test_no_undefined_mkdir_macro(self):
        recipe = self._recipe()
        self.assertNotIn("$(MKDIR)", recipe)
        self.assertIn("$(INSTALL_DIR) $(PKG_BUILD_DIR)/rootfs", recipe)
        self.assertIn("$(CP) ./files/. $(PKG_BUILD_DIR)/rootfs/", recipe)

    def test_real_prepare_commands_stage_source_and_executable_cgis(self):
        with tempfile.TemporaryDirectory(prefix="nr3053-build-prepare-") as directory:
            build_dir = Path(directory) / "wiflow-setup-build"
            recipe = self._recipe()
            # Only the two reviewed, standard OpenWrt packaging macros are
            # substituted. Any unknown macro fails the regression test.
            recipe = recipe.replace("$(INSTALL_DIR)", "install -d")
            recipe = recipe.replace("$(CP)", "cp -fpR")
            recipe = recipe.replace("$(PKG_BUILD_DIR)", str(build_dir))
            self.assertNotIn("$(", recipe, "unresolved make macro in Build/Prepare")
            run = subprocess.run(
                ["/bin/sh", "-ec", recipe], cwd=PKG,
                capture_output=True, text=True, timeout=15,
            )
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            staging = build_dir / "rootfs"
            for rel in (
                "usr/lib/wiflow/bootstrap",
                "usr/lib/wiflow/common.sh",
                "etc/init.d/wiflow-setup",
                "etc/config/wiflow",
                "www-wiflow/cgi-bin/gate",
                "www-wiflow-luci-gate/cgi-bin/unlock",
            ):
                with self.subTest(path=rel):
                    self.assertTrue((staging / rel).is_file(), rel)
            for rel in (
                "etc/init.d/wiflow-setup",
                "www-wiflow/cgi-bin/gate",
                "www-wiflow-luci-gate/cgi-bin/unlock",
            ):
                with self.subTest(executable=rel):
                    self.assertTrue((staging / rel).stat().st_mode & 0o100, rel)


if __name__ == "__main__":
    unittest.main()
