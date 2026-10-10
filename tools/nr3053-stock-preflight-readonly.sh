#!/bin/sh
# S5-A NR3053 STOCK-firmware preflight: READ ONLY, not an installer.
# Do not print MAC, SSID, IP, tokens, board serial, partition data or passwords.
# This does NOT verify flash safety, bootloader recovery or Wiflow runtime.
set -u
LC_ALL=C
export LC_ALL

STOCK_ROOT="${WIFLOW_STOCK_TEST_ROOT:-}"
case "$STOCK_ROOT" in
 '') CONTEXT=STOCK_DEVICE_READ_ONLY ;;
 /*) CONTEXT=HOST_FIXTURE_NOT_DEVICE ;;
 *) printf 'stock_preflight|BLOCK|fixture_path_not_absolute\n'; exit 2 ;;
esac
report(){ printf '%s|%s|%s\n' "$1" "$2" "$3"; }
path(){ printf '%s%s' "$STOCK_ROOT" "$1"; }
has(){ command -v "$1" >/dev/null 2>&1; }

report stage INFO S5_A_BEFORE_FIRST_WIFLOW_FLASH
report context INFO "$CONTEXT"

board_path="$(path /tmp/sysinfo/board_name)"
board=''
if [ -r "$board_path" ]; then board="$(cat "$board_path" 2>/dev/null || true)"; fi
if [ -z "$board" ] && [ -z "$STOCK_ROOT" ] && has ubus && has jsonfilter; then
 board="$(ubus call system board 2>/dev/null | jsonfilter -e '@.board_name' 2>/dev/null || true)"
fi
case "$board" in
 'viettel,nr3053') report board_identity PASS expected_board_identifier_observed ;;
 '') report board_identity WARN board_name_unavailable ;;
 *) report board_identity BLOCK board_identifier_mismatch ;;
esac

compatible_path="$(path /proc/device-tree/compatible)"
if [ -r "$compatible_path" ]; then
 if tr '\000' '\n' < "$compatible_path" 2>/dev/null | grep -Eq '^viettel,nr3053$'; then
  report dt_compatible PASS nr3053_compatible_observed
 else
  # An explicit, readable hardware mismatch is a blocking observation.
 # Only a missing/unreadable device-tree remains WARN (unknown).
 report dt_compatible BLOCK nr3053_compatible_mismatch
 fi
else
 report dt_compatible WARN device_tree_compatible_unavailable
fi

if [ -r "$(path /etc/openwrt_release)" ]; then
 report stock_os_metadata PASS openwrt_release_file_observed
else
 report stock_os_metadata WARN os_release_unavailable
fi

mtd_path="$(path /proc/mtd)"
if [ -r "$mtd_path" ]; then
 count="$(grep -Ec '^mtd[0-9]+:' "$mtd_path" 2>/dev/null || true)"
 case "$count" in ''|*[!0-9]*) count=0;; esac
 if [ "$count" -gt 0 ]; then
  report flash_partition_inventory PASS mtd_partition_table_observed
 else
  report flash_partition_inventory WARN no_mtd_partition_entries_observed
 fi
 if grep -Eiq '"[^"]*(factory|eeprom|calib|art)[^"]*"' "$mtd_path"; then
  report calibration_partition_hint INFO calibration_named_partition_seen
 else
  report calibration_partition_hint WARN calibration_partition_name_not_confirmed
 fi
else
 report flash_partition_inventory WARN mtd_table_unavailable
 report calibration_partition_hint WARN mtd_table_unavailable
fi

if [ -z "$STOCK_ROOT" ] && has ip; then
 net="$(ip -o -4 addr show 2>/dev/null || true)"
 if printf '%s\n' "$net" | grep -Eq '[[:space:]]inet[[:space:]]+[0-9]+\.'; then
  report ipv4_management_observed INFO ipv4_address_exists_not_proof_of_recovery
 else
  report ipv4_management_observed WARN ipv4_address_not_observed
 fi
else
 report ipv4_management_observed SKIP no_live_interface_probe
fi

if [ -z "$STOCK_ROOT" ] && has iw; then
 radios="$(iw dev 2>/dev/null || true)"
 if printf '%s\n' "$radios" | grep -Eq 'channel[[:space:]]+[0-9]+[[:space:]]+\(2[0-9]{3}[[:space:]]+MHz\)'; then
  report stock_radio_2g INFO active_2ghz_channel_observed
 else
  report stock_radio_2g WARN active_2ghz_channel_not_observed
 fi
 if printf '%s\n' "$radios" | grep -Eq 'channel[[:space:]]+[0-9]+[[:space:]]+\(5[0-9]{3}[[:space:]]+MHz\)'; then
  report stock_radio_5g INFO active_5ghz_channel_observed
 else
  report stock_radio_5g WARN active_5ghz_channel_not_observed
 fi
else
 report stock_radio_2g SKIP no_live_radio_probe
 report stock_radio_5g SKIP no_live_radio_probe
fi

if [ -e "$(path /usr/lib/wiflow/portal-client)" ]; then
 report wiflow_installation WARN wiflow_source_present_not_expected_on_stock
else
 report wiflow_installation INFO no_wiflow_runtime_observed
fi

# Neither a host build nor the above passive reads prove safe first flashing.
report original_firmware_backup NOT_VERIFIED independent_off_device_backup_required
report bootloader_recovery NOT_VERIFIED physical_uart_bootloader_restoration_required
report first_flash_approval BLOCK no_verified_recovery_or_board_migration
report wiflow_s5_runtime NOT_TESTED first_wiflow_boot_has_not_occurred
report release_s6 BLOCK no_device_runtime_evidence
