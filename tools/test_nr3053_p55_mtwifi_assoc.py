"""P55 regression: MediaTek MTWiFi APCLI station detection (host fixtures only)."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
COMMON=ROOT/"package/wiflow-setup/files/usr/lib/wiflow/common.sh"
UPLINK=ROOT/"package/wiflow-setup/files/usr/lib/wiflow/apply-uplink"


class MtWifiAssociationTests(unittest.TestCase):
    def test_association_backend_present(self):
        src=COMMON.read_text()
        fn=src.split("wifi_uplink_associated(){",1)[1].split("\nwifi_ssid_visible(){",1)[0]
        self.assertIn("/sys/class/net/apcli*", fn)
        self.assertIn('/usr/bin/iwinfo-ucode "$ifn" info', fn)
        self.assertIn("00:00:00:00:00:00", fn)
        self.assertIn('grep -Eiq', fn)
        self.assertIn("iw dev", fn) # preserve normal nl80211 fallback
        self.assertIn('wifi_uplink_associated "$ssid"', UPLINK.read_text())

    def run_fixture(self, bssid, ssid, expected):
        with tempfile.TemporaryDirectory(prefix="nr3053-p55-") as tmp:
            root=Path(tmp)
            (root/"apcli0").touch()
            cli=root/"iwinfo-ucode"
            # Use a fixed fixture; all controlled input is in the fixture script.
            cli.write_text(
                '#!/bin/sh\n'
                + 'printf \'apcli0 ESSID: "%s"\\nAccess Point: %s\\nMode: Client\\n\' '
                + "'" + ssid.replace("'", "") + "' '" + bssid.replace("'", "") + "'\n"
            )
            cli.chmod(0o755)
            src=COMMON.read_text()
            start=src.index("wifi_uplink_associated(){")
            end=src.index("wifi_ssid_visible(){",start)
            fn=src[start:end].replace("/sys/class/net/apcli*",str(root/"apcli*")).replace(
                "/usr/bin/iwinfo-ucode",str(cli))
            script=root/"run.sh"
            script.write_text("#!/bin/sh\n"+fn+"\niw(){ return 1; }\nwifi_uplink_associated Office\n")
            p=subprocess.run(["sh",str(script)],capture_output=True,text=True,timeout=5)
            self.assertEqual(p.returncode, expected, (p.stderr,p.stdout))

    def test_matching_apcli_station_is_detected(self):
        self.run_fixture("12:34:56:78:9A:BC","Office",0)

    def test_bssid_zero_is_not_association(self):
        self.run_fixture("00:00:00:00:00:00","Office",1)

    def test_wrong_ssid_is_not_association(self):
        self.run_fixture("12:34:56:78:9A:BC","Different",1)

    def test_invalid_bssid_is_not_association(self):
        self.run_fixture("Not-Associated","Office",1)


if __name__=="__main__":
    unittest.main()
