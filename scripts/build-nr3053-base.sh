#!/usr/bin/env bash
# NR3053 public upstream BUILD PROBE, NOT Wiflow firmware and NOT FLASH-APPROVED.
# No private assets or secrets. Run only in GitHub-hosted Ubuntu Actions.
set -Eeuo pipefail
export LC_ALL=C GIT_TERMINAL_PROMPT=0
readonly UPSTREAM="https://github.com/manhhaikd-dell/immortalwrt-mt798x-rebase.git"
readonly PIN="e39aded8420d454804a376e63400aff73da66247"
readonly ROOT="${RUNNER_TEMP:?}/nr3053-clean-upstream"
readonly OUTPUT="${GITHUB_WORKSPACE:?}/output"
mkdir -p "$ROOT" "$OUTPUT"

echo "::group::Verify pinned public upstream"
git -C "$ROOT" init -q
git -C "$ROOT" remote add origin "$UPSTREAM"
git -C "$ROOT" -c protocol.version=2 fetch --depth=1 --no-tags --filter=blob:none origin "$PIN"
git -C "$ROOT" checkout -q --detach FETCH_HEAD
test "$(git -C "$ROOT" rev-parse HEAD)" = "$PIN"
echo "PINNED_PUBLIC_SOURCE_PASS=$PIN"
echo "::endgroup::"
cd "$ROOT"

echo "::group::Derive NR3053-only configuration and disable unsafe radio writers"
python3 - <<'PY'
from pathlib import Path
import re
import subprocess

profile = Path("target/linux/mediatek/image/filogic-ext-viettel-fork.mk")
cfgpath = Path("defconfig/viettel-only.config")
expected_blobs = {
    "target/linux/mediatek/filogic/base-files/etc/hotplug.d/net/99-viettel-nr3053-throughwall": "faaf18ef64a632dfd3fbbdc37341fc7789d15986",
    "target/linux/mediatek/filogic/base-files/etc/init.d/viettel-nr3053-throughwall": "3a77c2999012a41325c136bb2f66f1f20d7d4f76",
    "target/linux/mediatek/filogic/base-files/etc/uci-defaults/99-viettel-nr3053-throughwall": "c3b9bbd1ef2d7c6a8097cbeace06d769a2187de1",
    "target/linux/mediatek/filogic/base-files/lib/viettel-nr3053-throughwall.sh": "d0539ff3e05b11cfa6fffcdd493dfca64121610c",
}
for rel, sha in expected_blobs.items():
    p = Path(rel)
    assert p.is_file() and not p.is_symlink(), ("radio source missing", rel)
    actual = subprocess.check_output(["git", "hash-object", rel], text=True).strip()
    assert actual == sha, ("radio source drift", rel, actual)
    p.unlink()
    print("RADIO_AUTOWRITER_REMOVED", rel)

text = profile.read_text(encoding="utf-8")
pattern = r"(?ms)^define Device/viettel_nr3053\n.*?^endef[ \t]*$"
matches = list(re.finditer(pattern, text))
assert len(matches) == 1, "ambiguous NR3053 profile"
m = matches[0]
section = m.group()
assert "default-settings-vn" in section
for required in ("DEVICE_DTS := mt7981b-viettel-nr3053",
                 "IMAGES := sysupgrade.itb",
                 "KERNEL_IN_UBI := 1",
                 "ARTIFACTS := preloader.bin bl31-uboot.fip"):
    assert required in section, ("unexpected device profile", required)
start = section.index("  DEVICE_PACKAGES :=")
end = section.index("\nendef", start)
remaining = section[end:]
# Keep essentials: LuCI, firewall, MTWiFi driver and configuration; no optional addons.
section = (section[:start] +
           "  DEVICE_PACKAGES := luci-ssl luci-app-firewall kmod-mt_wifi " +
           "-kmod-usb3 -kmod-usb-ledtrig-usbport -automount -autosamba" +
           remaining)
profile.write_text(text[:m.start()] + section + text[m.end():], encoding="utf-8")

config = cfgpath.read_text(encoding="utf-8")
for required in (
    "CONFIG_TARGET_MULTI_PROFILE=y",
    "CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_viettel_nr3053=y",
    "CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_viettel_32x6=y",
    "CONFIG_PACKAGE_kmod-mt_wifi=y",
    "CONFIG_PACKAGE_mtwifi-cfg-ucode=y",
):
    assert config.count(required) == 1, ("pinned defconfig unexpected", required)
config = config.replace(
    "CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_viettel_32x6=y",
    "# CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_viettel_32x6 is not set"
)
# Disable only known optional features; no WiFi driver, boot, DHCP, DNS or firewall removal.
optional = {
    "luci-app-nr3053-throughwall", "luci-i18n-nr3053-throughwall-vi",
    # Legacy LuCI mtwifi-cfg requires missing host-build dependencies;
    # preserve mtwifi-cfg-ucode and kmod-mt_wifi wireless runtime.
    "luci-app-mtwifi-cfg", "luci-i18n-mtwifi-cfg-vi",
    "luci-app-turboacc-mtk", "luci-app-eqos-mtk", "luci-i18n-eqos-mtk-vi",
    "luci-app-ddns", "luci-i18n-ddns-vi", "ddns-scripts",
    "ddns-scripts-cloudflare", "ddns-scripts-noip", "bndstrg",
    "luci-app-upnp", "luci-i18n-upnp-vi", "miniupnpd",
    "luci-app-adblock", "luci-i18n-adblock-vi",
    "luci-theme-aurora", "luci-app-aurora-config", "luci-theme-bootstrap-mod",
    "kmod-wireguard", "wireguard-tools", "luci-proto-wireguard",
    "rpcd-mod-wireguard", "mtkhqos_util",
}
for name in sorted(optional):
    config = re.sub(
        r"(?m)^CONFIG_PACKAGE_" + re.escape(name) + r"=[ym]$",
        "# CONFIG_PACKAGE_" + name + " is not set", config
    )
Path(".config").write_text(config, encoding="utf-8")
print("NR3053_SOURCE_CONFIG_PREPARED")
PY
echo "::endgroup::"

# Optional experimental Wiflow source is copied exactly once into its
# authoritative package owner before feeds/Kconfig. The standard base build
# remains unchanged when WIFLOW_SOURCE_BUILD is unset.
if [[ "${WIFLOW_SOURCE_BUILD:-0}" == "1" ]]; then
  echo "::group::Stage cleaned public Wiflow package source"
  source_dir="$GITHUB_WORKSPACE/package/wiflow-setup"
  test -s "$source_dir/Makefile"
  for path in usr/lib/wiflow/common.sh usr/lib/wiflow/portal-sync \
              etc/init.d/wiflow-setup www-wiflow/cgi-bin/api \
              www-wiflow/cgi-bin/enroll; do
    test -s "$source_dir/files/$path" || {
      echo "::error::Wiflow public package missing: $path"
      exit 1
    }
  done
  cp -a "$source_dir" package/wiflow-setup
  echo "CONFIG_PACKAGE_wiflow-setup=y" >> .config
  echo "NR3053_WIFLOW_SOURCE_STAGE_PASS"
  echo "::endgroup::"
fi

echo "::group::Install public 25.12 package feeds"
./scripts/feeds update -a
./scripts/feeds install -a
echo "::endgroup::"

echo "::group::Run Kconfig and verify only NR3053 is selected"
make defconfig
python3 - <<'PY'
from pathlib import Path
config = Path(".config").read_text()
targets = [x for x in config.splitlines()
           if x.startswith("CONFIG_TARGET_DEVICE_") and x.endswith("=y")]
expected = ["CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_viettel_nr3053=y"]
assert targets == expected, ("NR3053_ONLY_DEVICE_FAILED", targets)
for value in ("CONFIG_TARGET_MULTI_PROFILE=y",
              "CONFIG_PACKAGE_kmod-mt_wifi=y",
              "CONFIG_PACKAGE_mtwifi-cfg-ucode=y",
              "CONFIG_MTK_MT_WIFI_DRIVER_VERSION_7673=y",
              'CONFIG_MTK_MT_WIFI_FIRMWARE_PATH_MT7981="mt7981-fw-20250408"'):
    assert value in config, ("REQUIRED_WIFI_CONFIG_DROPPED", value)
for pkg in ("luci-app-mtwifi-cfg", "luci-app-nr3053-throughwall", "luci-theme-aurora",
            "luci-app-aurora-config"):
    assert "CONFIG_PACKAGE_" + pkg + "=y" not in config, ("UNSAFE_OR_UNUSED_PACKAGE_SELECTED", pkg)
import os
if os.getenv("WIFLOW_SOURCE_BUILD") == "1":
    assert "CONFIG_PACKAGE_wiflow-setup=y" in config, "Wiflow APK source not selected by Kconfig"
    # Pinned mtwifi-cfg-ucode requires iwinfo-ucode, whose Kconfig forbids
    # the legacy iwinfo variant (@!PACKAGE_iwinfo). Never select both.
    assert "CONFIG_PACKAGE_iwinfo-ucode=y" in config, ("REQUIRED_UCODE_IWINFO_DROPPED", "CONFIG_PACKAGE_iwinfo-ucode=y")
    assert "CONFIG_PACKAGE_iwinfo=y" not in config, ("LEGACY_IWINFO_CONFLICT", "CONFIG_PACKAGE_iwinfo=y")
    print("NR3053_WIFLOW_PACKAGE_CONFIG_PASS")
print("NR3053_ONLY_KCONFIG_PASS")
PY
echo "::endgroup::"

# A fast, real pinned-upstream + full-feeds Kconfig preflight for PRs.
# No downloads, toolchain compilation, or image artifact in this mode.
if [[ "${WIFLOW_KCONFIG_ONLY:-0}" == "1" ]]; then
  echo "NR3053_PINNED_KCONFIG_PREFLIGHT_PASS_NO_IMAGE_NO_FLASH"
  exit 0
fi

echo "::group::Download sources and check disk"
for feed in packages luci routing telephony; do
  printf '%s %s\n' "$feed" "$(git -C "feeds/$feed" rev-parse HEAD)"
done > "$OUTPUT/PUBLIC-FEED-COMMITS.txt"
make download -j4
avail_kib="$(df -Pk . | awk 'END{print $4}')"
echo "DISK_FREE_KIB_BEFORE_BUILD=$avail_kib"
if (( avail_kib < 15728640 )); then
  echo "::error::Insufficient disk (< 15 GiB) for image build"
  exit 1
fi
echo "::endgroup::"

echo "::group::Compile full public-source NR3053 base firmware"
make -j4 V=s
echo "::endgroup::"

echo "::group::Verify image; do not publish as Wiflow final release"
shopt -s nullglob
files=(bin/targets/mediatek/filogic/*viettel_nr3053*sysupgrade.itb)
if (( ${#files[@]} != 1 )); then
  echo "::error::Expected exactly 1 NR3053 ITB, found ${#files[@]}"
  exit 1
fi
test -s "${files[0]}"
if find target/linux/mediatek/filogic/base-files -type f -name '*nr3053-throughwall*' | grep -q .; then
  echo "::error::Radio auto-writer unexpectedly reintroduced"
  exit 1
fi
cp "${files[0]}" "$OUTPUT/"
(
  cd "$OUTPUT"
  sha256sum ./*.itb > SHA256SUMS
)
{
  if [[ "${WIFLOW_SOURCE_BUILD:-0}" == "1" ]]; then
    echo "STATE=PUBLIC_WIFLOW_EXPERIMENTAL_SOURCE_BUILD_ONLY"
    echo "WIFLOW_SOURCE_PACKAGE_SELECTED=YES"
    echo "WIFLOW_RUNTIME_E5_VERIFIED=NO"
  else
    echo "STATE=PUBLIC_UPSTREAM_BASE_BUILD_ONLY"
    echo "WIFLOW_RUNTIME_PRESENT=NO"
  fi
  echo "FIRMWARE_RELEASE_APPROVED=NO"
  echo "DO_NOT_FLASH=YES"
  echo "UPSTREAM_COMMIT=$PIN"
  echo "GITHUB_RUN_ID=$GITHUB_RUN_ID"
  echo "ITB_NAME=$(basename "${files[0]}")"
} > "$OUTPUT/BUILD-STATUS.txt"
ls -lh "$OUTPUT"
echo "NR3053_UPSTREAM_BASE_IMAGE_BUILT_NOT_FLASH_APPROVED"
echo "::endgroup::"
