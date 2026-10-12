import pathlib, re, subprocess, unittest
B = pathlib.Path(__file__).resolve().parents[1] / "package/wiflow-setup/files"
COMMON = (B / "usr/lib/wiflow/common.sh").read_text()
API = (B / "www-wiflow/cgi-bin/api").read_text()
JS = (B / "www-wiflow/assets/setup-v1.js").read_text()
FN = re.search(r"^guest_bands_effective\(\)\{.*?^\}\n", COMMON, re.S | re.M).group(0)

def eff(mode, up, cfg):
    script = 'uci(){ [ -n "$CFG" ] && echo "$CFG"; return 0; }\n' + FN + f'\nguest_bands_effective "{mode}" "{up}"'
    return subprocess.run(["sh", "-c", script], capture_output=True, text=True,
                          env={"CFG": cfg, "PATH": "/usr/bin:/bin"}).stdout

class T(unittest.TestCase):
    def test_matrix(self):
        cases = [("lan", "", "", "2g 5g"), ("lan", "", "2g", "2g"), ("lan", "", "5g", "5g"),
                 ("wifi", "2g", "", "5g"), ("wifi", "5g", "", "2g"),
                 ("wifi", "2g", "2g", "5g"), ("wifi", "5g", "5g", "2g"),
                 ("wifi", "2g", "5g", "5g"), ("wifi", "5g", "2g", "2g")]
        for m, up, cfg, want in cases:
            with self.subTest(m=m, up=up, cfg=cfg):
                self.assertEqual(eff(m, up, cfg), want)

    def test_never_same_band_as_source(self):
        for up in ("2g", "5g"):
            for cfg in ("", "2g", "5g"):
                self.assertNotIn(up, eff("wifi", up, cfg).split())

    def test_api_broadcast(self):
        self.assertIn("broadcast)", API)
        self.assertIn("require_csrf", API.split("broadcast)")[1].split("job)")[0])
        self.assertIn("apply-broadcast", API)
        self.assertIn("source_band", API)
        self.assertIn("guest_bands", API)

    def test_ui_two_steps(self):
        self.assertIn("function showBroadcast", JS)
        self.assertIn("Bước 1", JS)
        self.assertIn("Bước 2", JS)
        self.assertIn("api('broadcast'", JS)

if __name__ == "__main__":
    unittest.main()
