"""Reproduce OpenWrt Wiflow Build/Prepare with actual GNU make.

The old undefined $(MKDIR) produced '.../rootfs: No such file or directory'
(Error 127) on integrated build 37880903707. Host test only, not an image build.
"""
from pathlib import Path
import os
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "package/wiflow-setup/Makefile"


class WiflowPrepareTests(unittest.TestCase):
    def test_openwrt_make_prepare_creates_and_copies_files(self):
        contents = PACKAGE.read_text(encoding="utf-8")
        match = re.search(r"(?ms)^define Build/Prepare\n(.*?)\nendef", contents)
        self.assertIsNotNone(match)
        recipe = match.group(1)
        self.assertIn("$(INSTALL_DIR) $(PKG_BUILD_DIR)/rootfs", recipe)
        self.assertNotIn("$(MKDIR)", recipe)
        self.assertIn("$(CP) ./files/. $(PKG_BUILD_DIR)/rootfs/", recipe)

        with tempfile.TemporaryDirectory(prefix="wiflow-make-prepare-") as temp:
            workspace = Path(temp)
            source = workspace / "files"
            source.mkdir()
            script = source / "cgi-bin" / "gate"
            script.parent.mkdir()
            script.write_text("#!/bin/sh\nexit 0\n")
            script.chmod(0o755)
            regular = source / "device.conf"
            regular.write_text("wiflow=1\n")
            out = workspace / "build" / "rootfs"
            mk = workspace / "Makefile"
            # Use the OpenWrt macros named by the package recipe. Deliberately
            # leave MKDIR undefined to catch regression to the failing macro.
            mk.write_text(
                "PKG_BUILD_DIR := " + str(workspace / "build") + "\n"
                "INSTALL_DIR := install -d -m0755\n"
                "CP := cp -fpR\n"
                "define Build/Prepare\n" + recipe + "\nendef\n"
                ".PHONY: prepare\n"
                "prepare:\n"
                "\t$(Build/Prepare)\n"
            )
            run = subprocess.run(
                ["make", "-f", str(mk), "prepare"],
                cwd=workspace, capture_output=True, text=True,
                timeout=10, env=os.environ.copy(),
            )
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertEqual((out / "device.conf").read_text(), "wiflow=1\n")
            dest = out / "cgi-bin" / "gate"
            self.assertEqual(dest.read_text(), script.read_text())
            self.assertTrue(dest.stat().st_mode & 0o100, "CGI executable mode lost")


if __name__ == "__main__":
    unittest.main()
