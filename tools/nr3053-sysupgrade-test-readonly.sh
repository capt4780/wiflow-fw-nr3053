#!/bin/sh
# NR3053: read-only first-flash image check against the currently running firmware.
# Requires an already-staged, exact-digest ITB in /tmp. It never installs,
# flashes, upgrades, restarts services, commits UCI, or reads Factory contents.
# Note: upstream sysupgrade -T may use volatile /tmp, but exits before write.
# A PASS here is image acceptance only; physical first-flash gate remains BLOCK.
set -u
LC_ALL=C
export LC_ALL

report(){ printf '%s|%s|%s\n' "$1" "$2" "$3"; }
block(){
    report "$1" BLOCK "$2"
    report first_flash_approval BLOCK independent_device_rescue_not_verified
    exit 2
}

[ "$#" -eq 2 ] || block usage exactly_two_arguments_required
candidate="$1"
expected="$2"
case "$expected" in *[!0123456789abcdef]*|'') block image_sha256 invalid_digest_format;; esac
[ "${#expected}" -eq 64 ] || block image_sha256 invalid_digest_length

# Test fixture isolation. An injected fixture must be explicitly identified
# as NOT a real router and can never be interpreted as hardware evidence.
TEST_ROOT="${WIFLOW_NR3053_TEST_ROOT:-}"
case "$TEST_ROOT" in
    '') CONTEXT=STOCK_DEVICE_READ_ONLY
        case "$candidate" in /tmp/*) :;; *) block image_location require_volatile_tmp_path;; esac
        ;;
    /*) CONTEXT=HOST_FIXTURE_NOT_DEVICE
        case "$candidate" in "$TEST_ROOT"/tmp/*) :;; *) block image_location fixture_candidate_must_be_inside_fixture_tmp;; esac
        ;;
    *) block context invalid_test_root
        ;;
esac
report context INFO "$CONTEXT"
[ -f "$candidate" ] && [ ! -L "$candidate" ] ||
    block image_location missing_or_symlink_candidate

# This is a FIT sysupgrade image, not a complete NAND dump.
size="$(wc -c < "$candidate" 2>/dev/null | tr -d ' ')"
case "$size" in ''|*[!0123456789]*) block image_size unreadable;; esac
[ "$size" -ge 1048576 ] && [ "$size" -le 67108864 ] ||
    block image_size outside_engineering_bounds

root="$TEST_ROOT"
[ -r "$root/tmp/sysinfo/board_name" ] ||
    block board_identity board_name_unavailable
board="$(cat "$root/tmp/sysinfo/board_name" 2>/dev/null || true)"
[ "$board" = 'viettel,nr3053' ] || block board_identity wrong_board
report board_identity PASS matching_nr3053_board

compatible="$root/proc/device-tree/compatible"
[ -r "$compatible" ] || block dt_compatible device_tree_missing
tr '\\000' '\\n' < "$compatible" | grep -Fqx 'viettel,nr3053' ||
    block dt_compatible nr3053_not_in_device_tree
tr '\\000' '\\n' < "$compatible" | grep -Fqx 'mediatek,mt7981' ||
    block soc_compatible mt7981_not_in_device_tree
report dt_compatible PASS matching_nr3053_dt
report soc_compatible PASS matching_mt7981

mtd="$root/proc/mtd"
[ -r "$mtd" ] || block mtd_layout partition_inventory_missing
mtd_status="$(awk '
BEGIN {
  expected["BL2"]="00100000"
  expected["u-boot-env"]="00100000"
  expected["Factory"]="00200000"
  expected["FIP"]="00200000"
  expected["ubi"]="0ea00000"
}
$1 ~ /^mtd[0-9]+:$/ {
  name=$4
  gsub(/^"|"$/, "", name)
  if (name in expected) {
    seen[name]++
    if (seen[name] > 1 || tolower($2) != expected[name]) bad=1
  }
}
END {
  for (n in expected) if (seen[n] != 1) bad=1
  print (bad ? "BLOCK" : "PASS")
}' "$mtd" 2>/dev/null)" || block mtd_layout parse_failed
[ "$mtd_status" = PASS ] || block mtd_layout different_from_pinned_partition_sizes
report mtd_layout PASS expected_partition_names_and_sizes
# Partition offsets and calibration bytes are NOT validated by /proc/mtd.

command -v sha256sum >/dev/null 2>&1 || block digest_tool sha256sum_missing
actual="$(sha256sum "$candidate" 2>/dev/null | awk '{print $1}')"
[ "$actual" = "$expected" ] || block image_sha256 mismatch
report image_sha256 PASS exact_candidate_digest

# 'sysupgrade -T -n' is the upstream no-write image-validation mode.
# -F, --force, '--ignore-minor-compat-version', and actual upgrade are forbidden.
command -v sysupgrade >/dev/null 2>&1 || block sysupgrade_dryrun sysupgrade_unavailable
if sysupgrade -T -n "$candidate" >/dev/null 2>&1; then
    report sysupgrade_dryrun PASS accepted_without_flash
else
    block sysupgrade_dryrun image_rejected_by_running_firmware
fi

report physical_recovery NOT_VERIFIED uart_bootloader_restore_required
report calibration_backup NOT_VERIFIED independently_validated_off_device_copy_required
report first_flash_approval BLOCK independent_device_rescue_not_verified
exit 0
