"""Host-only regressions for the NR3053 first-boot command ordering audit."""
import unittest
from audit_nr3053_rootfs import wifi_command_precedes_module_load


class BootSequenceTests(unittest.TestCase):
    def test_actual_upstream_boot_script_shape(self):
        script = """#!/bin/sh /etc/rc.common
        # get executed because of '/sbin/kmodloader' kmod loading.
        # update wifi config before additional ieee80211 hotplug events
        [ -f /etc/board.json ] && /sbin/wifi config
        /sbin/kmodloader
        """
        self.assertTrue(wifi_command_precedes_module_load(script))

    def test_reverse_order_is_rejected(self):
        script = "/sbin/kmodloader\n/sbin/wifi config\n"
        self.assertFalse(wifi_command_precedes_module_load(script))

    def test_comment_only_false_positive_is_rejected(self):
        script = "# /sbin/wifi config\n/sbin/kmodloader\n"
        self.assertFalse(wifi_command_precedes_module_load(script))

    def test_missing_module_loader_is_rejected(self):
        self.assertFalse(wifi_command_precedes_module_load(
            "[ -f /etc/board.json ] && /sbin/wifi config\n"
        ))


if __name__ == "__main__":
    unittest.main()
