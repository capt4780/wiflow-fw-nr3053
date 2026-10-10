#!/bin/sh
# NR3053 S5 evidence: read-only diagnostics. This NEVER approves flashing.
# Never prints SSIDs, client leases, MACs, tokens, root hashes or device IDs.
set -u
LC_ALL=C
export LC_ALL

TEST_ROOT="${WIFLOW_S5_TEST_ROOT:-}"
case "$TEST_ROOT" in
 '') CONTEXT=ROUTER_READ_ONLY ;;
 /*) CONTEXT=HOST_FIXTURE_NOT_DEVICE ;;
 *) printf 'ERROR|BLOCK|test_root_requires_absolute_path\n'; exit 2 ;;
esac

report(){ printf '%s|%s|%s\n' "$1" "$2" "$3"; }
has(){ command -v "$1" >/dev/null 2>&1; }
sys_file(){ printf '%s%s' "$TEST_ROOT" "$1"; }

report s5_tool PASS source_only_no_mutation
report context INFO "$CONTEXT"

board=''
board_file="$(sys_file /tmp/sysinfo/board_name)"
if [ -r "$board_file" ]; then board="$(cat "$board_file" 2>/dev/null || true)"; fi
if [ -z "$board" ] && has ubus && has jsonfilter; then
 board="$(ubus call system board 2>/dev/null | jsonfilter -e '@.board_name' 2>/dev/null || true)"
fi
case "$board" in
 'viettel,nr3053') report target_board PASS exact_nr3053_board ;;
 '') report target_board WARN board_identifier_unavailable ;;
 *) report target_board BLOCK unexpected_board ;;
esac

if has ip; then
 lan="$(ip -o -4 addr show dev br-lan 2>/dev/null || true)"
 guest="$(ip -o -4 addr show dev br-wiflow 2>/dev/null || true)"
else
 lan=''; guest=''
fi
if printf '%s\n' "$lan" | grep -Eq '(^|[[:space:]])inet[[:space:]]+10\.0\.0\.1/24([[:space:]]|$)'; then
 report setup_address PASS br_lan_10_0_0_1
else
 report setup_address WARN management_address_not_observed
fi
if printf '%s\n' "$lan" | grep -Eq '(^|[[:space:]])inet[[:space:]]+10\.0\.0\.2/32([[:space:]]|$)'; then
 report luci_gate_address PASS br_lan_10_0_0_2
else
 report luci_gate_address WARN luci_gate_alias_not_observed
fi
if printf '%s\n' "$guest" | grep -Eq '(^|[[:space:]])inet[[:space:]]+10\.10\.10\.1/24([[:space:]]|$)'; then
 report guest_gateway PASS br_wiflow_10_10_10_1
else
 report guest_gateway WARN guest_gateway_not_observed
fi

setup_gate="$(sys_file /www-wiflow/cgi-bin/gate)"
luci_gate="$(sys_file /www-wiflow-luci-gate/cgi-bin/unlock)"
portal_handler="$(sys_file /www-wiflow-portal/cgi-bin/portal)"
for role in setup_gate luci_gate portal_handler; do
 case "$role" in
  setup_gate) p="$setup_gate" ;;
  luci_gate) p="$luci_gate" ;;
  portal_handler) p="$portal_handler" ;;
 esac
 if [ -f "$p" ] && [ ! -L "$p" ]; then
  report "$role" PASS local_handler_file_present
 else
  report "$role" BLOCK local_handler_missing_or_symlink
 fi
done

enabled=''
if has uci; then enabled="$(uci -q get wiflow.core.portal_enabled 2>/dev/null || true)"; fi
case "$enabled" in
 1) report portal_enabled INFO enabled ;;
 0) report portal_enabled INFO disabled ;;
 *) report portal_enabled WARN state_unavailable ;;
esac

active="$(sys_file /www-wiflow-portal/runtime/active)"
cfg="$active/portal.json"
snapshot_ok=0
if [ -f "$cfg" ] && [ -L "$active" ] && has jsonfilter; then
 schema="$(jsonfilter -i "$cfg" -e '@.schema' 2>/dev/null || true)"
 generation="$(jsonfilter -i "$cfg" -e '@.data_generation' 2>/dev/null || true)"
 revision="$(jsonfilter -i "$cfg" -e '@.revision' 2>/dev/null || true)"
 mode="$(jsonfilter -i "$cfg" -e '@.mode' 2>/dev/null || true)"
 case "$revision" in ''|*[!0-9]*) revision=0;; esac
 case "$mode" in website|image|video) mode_ok=1;; *) mode_ok=0;; esac
 if [ "$schema" = 2 ] && [ "$generation" = 4 ] && [ "$revision" -gt 0 ] && [ "$mode_ok" = 1 ]; then
  snapshot_ok=1
 fi
fi
if [ "$snapshot_ok" = 1 ]; then
 report portal_snapshot PASS active_symlink_valid_schema_generation
elif [ "$enabled" = 1 ]; then
 report portal_snapshot BLOCK enabled_without_valid_active_snapshot
else
 report portal_snapshot SKIP not_enabled_or_snapshot_unavailable
fi

if [ "$enabled" = 1 ]; then
 if ! has nft; then
  report captive_forward BLOCK nft_command_missing
  report captive_redirect BLOCK nft_command_missing
  report captive_sets BLOCK nft_command_missing
  report private_dns_rule BLOCK nft_command_missing
 else
  fw="$(nft list chain inet fw4 wiflow_portal_forward 2>/dev/null || true)"
  nat="$(nft list chain inet fw4 wiflow_portal_prerouting 2>/dev/null || true)"
  if printf '%s\n' "$fw" | grep -Fq 'wiflow_portal_authed' &&
     printf '%s\n' "$fw" | grep -Fq '10.10.10.0/24 reject'; then
   report captive_forward PASS authed_bypass_and_guest_reject_present
  else
   report captive_forward BLOCK captive_filter_rules_not_observed
  fi
  if printf '%s\n' "$nat" | grep -Fq '10.0.0.1 return' &&
     printf '%s\n' "$nat" | grep -Fq '10.0.0.2 return' &&
     printf '%s\n' "$nat" | grep -Fq 'redirect to :2080'; then
   report captive_redirect PASS both_management_exemptions_and_redirect_present
  else
   report captive_redirect BLOCK captive_redirect_rules_not_observed
  fi
  if nft list set inet fw4 wiflow_portal_authed >/dev/null 2>&1 &&
     nft list set inet fw4 wiflow_portal_granted >/dev/null 2>&1; then
   report captive_sets PASS auth_and_grant_sets_present
  else
   report captive_sets BLOCK captive_sets_not_observed
  fi
  if printf '%s\n' "$fw" | grep -Fq 'tcp dport 853 accept'; then
   report private_dns_rule PASS preauth_tcp_853_rule_present
  else
   report private_dns_rule WARN private_dns_rule_not_observed
  fi
 fi
else
 report captive_forward SKIP portal_not_active
 report captive_redirect SKIP portal_not_active
 report captive_sets SKIP portal_not_active
 report private_dns_rule SKIP portal_not_active
fi

if has iw; then radios="$(iw dev 2>/dev/null || true)"; else radios=''; fi
if printf '%s\n' "$radios" | grep -Eq 'channel[[:space:]]+[0-9]+[[:space:]]+\(2[0-9]{3}[[:space:]]+MHz\)'; then
 report radio_2g_channel PASS 2_4ghz_channel_observed_not_client_tested
else
 report radio_2g_channel WARN no_active_2_4ghz_channel_observed
fi
if printf '%s\n' "$radios" | grep -Eq 'channel[[:space:]]+[0-9]+[[:space:]]+\(5[0-9]{3}[[:space:]]+MHz\)'; then
 report radio_5g_channel PASS 5ghz_channel_observed_not_client_tested
else
 report radio_5g_channel WARN no_active_5ghz_channel_observed
fi

# E5/S6 requires independent clients, physical recovery, and a real WP roundtrip.
report guest_pre_post_authorization NOT_TESTED independent_guest_packet_trace_required
report gate_guest_reachability NOT_TESTED separate_10_10_10_client_required
report luci_real_login NOT_TESTED account_login_required
report wordpress_sync_roundtrip NOT_TESTED server_receipt_and_media_test_required
report wifi_real_clients NOT_TESTED both_bands_with_clients_required
report physical_recovery NOT_VERIFIED uart_bootloader_and_restore_plan_required
report running_firmware_provenance NOT_ATTESTED compare_running_image_to_exact_build_required
report e5_complete BLOCK physical_acceptance_incomplete
report flash_authorization BLOCK no_device_recovery_evidence
