import unittest
from check_nr3053_lean_manifest import REQUIRED, check, parse


def manifest(extra=(), drop=()):
    names = [p for p in REQUIRED if p not in drop] + list(extra)
    return "\n".join(f"{n} - 1.0-r1" for n in names) + "\n"


class LeanManifestTests(unittest.TestCase):
    def test_parse_ignores_blank_and_comments(self):
        self.assertEqual(parse("a - 1\n\n# c\nb - 2\n"), {"a", "b"})

    def test_good_manifest_passes_and_blocks_flash(self):
        r = check(manifest())
        self.assertEqual(r["lean_gate"], "PASS")
        self.assertEqual(r["flash_authorization"], "BLOCK")
        self.assertEqual(r["package_count"], len(REQUIRED))

    def test_missing_wiflow_runtime_dependency_fails(self):
        r = check(manifest(drop=("uhttpd",)))
        self.assertEqual(r["lean_gate"], "FAIL")
        self.assertEqual(r["missing_required"], ["uhttpd"])

    def test_extras_and_baked_in_wiflow_fail(self):
        for bad in ("htop", "luci-app-upnp", "wiflow-setup"):
            self.assertEqual(check(manifest(extra=(bad,)))["lean_gate"], "FAIL", bad)

    def test_apk_style_manifest_lines(self):
        apk = "\n".join(
            f"{n}-1.2.3-r1 aarch64_cortex-a53 {{{n}}} (GPL-2.0) [installed]" for n in REQUIRED)
        r = check(apk)
        self.assertEqual(r["lean_gate"], "PASS", r)
        self.assertEqual(parse("kmod-mt_wifi-6.12.94.2-r1 aarch64 {x} (x)\n"), {"kmod-mt_wifi"})
        self.assertEqual(parse("luci-i18n-base-vi-26.045.1-r1 all {l}\n"), {"luci-i18n-base-vi"})

    def test_library_abi_suffix_counts(self):
        txt = manifest(drop=("libustream-openssl",), extra=("libustream-openssl20201210",))
        self.assertEqual(check(txt)["lean_gate"], "PASS")

    def test_empty_manifest_fails(self):
        self.assertEqual(check("")["lean_gate"], "FAIL")


if __name__ == "__main__":
    unittest.main()
