"""Source-level regressions for locked NR3053 Wiflow network/portal invariants.

Checks on committed text only. PASS is NOT proof of real packet flow,
hardware Wi-Fi, guest isolation, portal playback or device flash safety.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
DEVICE = ROOT / "package/wiflow-setup/files/usr/lib/wiflow"


class NR3053BehaviorContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.common = (DEVICE / "common.sh").read_text(encoding="utf-8")
        cls.portal_firewall = (DEVICE / "portal-firewall").read_text(encoding="utf-8")
        cls.sync = (DEVICE / "portal-sync").read_text(encoding="utf-8")
        cls.remote = (DEVICE / "remote-command").read_text(encoding="utf-8")
        cls.radio = (DEVICE / "radio-policy").read_text(encoding="utf-8")

    def test_pre_authorization_private_dns_retained(self):
        # DoT and DNS bootstrap must remain possible BEFORE portal confirmation.
        for field in (
            "firewall.wiflow_guest_private_dns.dest='wan'",
            "firewall.wiflow_guest_private_dns.dest_port='853'",
            "firewall.wiflow_guest_dns.dest_port='53'",
            "ip saddr 10.10.10.0/24 tcp dport 853 accept",
            "ip saddr 10.10.10.0/24 udp dport 853 accept",
            "ip saddr 10.10.10.0/24 reject",
        ):
            with self.subTest(field=field):
                self.assertIn(field, self.common + self.portal_firewall)
        self.assertIn("wiflow_portal_authed", self.portal_firewall)

    def test_guest_ssid_remote_command_updates_both_radios(self):
        self.assertIn("change_guest_ssid)", self.remote)
        self.assertIn("wireless.wiflow_guest_2g.ssid=$guest", self.remote)
        self.assertIn("wireless.wiflow_guest_5g.ssid=$guest", self.remote)
        self.assertIn("guest_ssid", self.common)

    def test_all_three_portal_families_retained(self):
        self.assertIn("website|image|video", self.sync)
        for role in ("image_landscape", "image_portrait",
                     "video_landscape", "video_portrait"):
            self.assertIn(role, self.sync)
        for number in range(1, 6):
            self.assertIn(f"popup_{number}", self.sync)

    def test_media_staging_validated_before_atomic_switch_and_cleanup(self):
        s = self.sync
        check = s.index('got_hash="$(sha256sum "$out"')
        stage = s.index('mv "$STAGE" "$DEST"')
        activate = s.index('mv -Tf "$LINK" "$PORTAL_ACTIVE"')
        cleanup = s.index('rm -rf "$d"; done')
        self.assertLess(check, stage)
        self.assertLess(stage, activate)
        self.assertLess(activate, cleanup)

    def test_remote_endpoint_and_generation_not_changed(self):
        self.assertIn(
            "WIFLOW_REST_ROOT='https://projify.io.vn/wiflow/wp-json'",
            self.common,
        )
        self.assertIn("WIFLOW_DATA_GENERATION='4'", self.common)
        self.assertIn('"$schema" = 2', self.sync)
        self.assertIn('"$manifest_generation" = "$WIFLOW_DATA_GENERATION"',
                      self.sync)

    def test_open_guest_ap_and_management_reachability_remain_unverified(self):
        # This source intentionally exposes guest AP and locally reachable
        # Gate pages; runtime isolation is an explicit release BLOCK.
        self.assertIn('wireless.$sec.encryption=none', self.radio)
        self.assertIn("firewall.wiflow_guest_setup.src='wiflow_guest'",
                      self.common)
        self.assertIn("firewall.wiflow_guest_gate.src='wiflow_guest'",
                      self.common)


if __name__ == "__main__":
    unittest.main()
