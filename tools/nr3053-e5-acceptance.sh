#!/bin/sh
# Wiflow NR3053 E5 acceptance: uplink, WordPress API, captive portal.
# READ-ONLY. Run on a Wiflow-image router:  sh nr3053-e5-acceptance.sh
# Exit 0 only when every automated check passes. This is NOT flash approval and
# does not replace the manual guest-phone steps printed at the end.
. /usr/lib/wiflow/common.sh
pass=0; fail=0; tmp="/tmp/wiflow-e5.$$"
ok(){ printf 'PASS  %s\n' "$1"; pass=$((pass+1)); }
bad(){ printf 'FAIL  %s\n' "$1"; fail=$((fail+1)); }
chk(){ d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
tcp_listening(){ awk -v t="$1:$2" '$2==t && $4=="0A"{f=1} END{exit(f?0:1)}' /proc/net/tcp; }
eq(){ [ "$1" = "$2" ]; }

echo "== 1. Uplink =="
chk 'L1 profile present' test -r "$WIFLOW_L1_PROFILE"
for band in 2g 5g; do
  r="$(radio_for_band "$band" 2>/dev/null || true)"
  ifn="$(radio_scan_ifname "$r")"
  chk "$band radio '$r' maps to interface $ifn" test -e "$WIFLOW_SYSFS_NET/$ifn"
  n="$(wiflow_iwinfo "$ifn" scan 2>/dev/null | grep -c 'ESSID: "')"
  [ "${n:-0}" -gt 0 ] && ok "$band scan lists $n network(s)" || bad "$band scan lists no network"
done
mode="$(uci -q get wiflow.core.internet_mode 2>/dev/null || true)"
case "$mode" in
  wifi)
    ssid="$(uci -q get wiflow.core.source_ssid 2>/dev/null || true)"
    chk "uplink associated to '$ssid'" wifi_uplink_associated "$ssid"
    chk 'wiflow_wwan has IPv4' iface_up wiflow_wwan
    chk 'default route uses wiflow_wwan' iface_route_active wiflow_wwan;;
  lan)
    chk 'wan has IPv4' iface_up wan
    chk 'default route uses wan' iface_route_active wan;;
  *) bad "no uplink configured (internet_mode='$mode')";;
esac
chk 'Internet reachable from router' internet_probe

echo "== 2. WordPress API =="
if uclient-fetch -q -T 8 -O "$tmp" "$WIFLOW_DEVICE_API/health" 2>/dev/null; then
  chk 'health ok' eq "$(jsonfilter -i "$tmp" -e '@.ok' 2>/dev/null)" true
  chk 'api_version 1' eq "$(jsonfilter -i "$tmp" -e '@.api_version' 2>/dev/null)" 1
  chk "data_generation $WIFLOW_DATA_GENERATION" eq "$(jsonfilter -i "$tmp" -e '@.data_generation' 2>/dev/null)" "$WIFLOW_DATA_GENERATION"
  chk 'rest_root matches firmware' eq "$(jsonfilter -i "$tmp" -e '@.rest_root' 2>/dev/null)" "$WIFLOW_REST_ROOT"
else bad "cannot reach $WIFLOW_DEVICE_API/health (TLS/time/DNS/uplink?)"; fi
rm -f "$tmp"
chk 'device paired' eq "$(uci -q get wiflow.core.paired 2>/dev/null)" 1
[ -n "$(device_token)" ] && ok 'device token stored' || bad 'device token missing'
chk 'last heartbeat accepted (wp_online=1)' eq "$(state_get wp_online)" 1
[ -z "$(state_get api_error)" ] && ok 'no api_error' || bad "api_error=$(state_get api_error)"
now="$(date +%s)"; last="$(state_get wp_last_ok)"; case "$last" in ''|*[!0-9]*) last=0;; esac
[ $((now-last)) -le 90 ] && ok 'heartbeat fresher than 90 s' || bad 'heartbeat older than 90 s'
chk 'portal sync status active' eq "$(uci -q get wiflow.core.portal_sync_status 2>/dev/null)" active
[ "$(uci -q get wiflow.core.portal_revision 2>/dev/null || echo 0)" -gt 0 ] && ok 'portal revision applied' || bad 'no portal revision applied'
chk 'active portal snapshot present' test -f "$PORTAL_ACTIVE/portal.json"

echo "== 3. Captive portal =="
chk 'portal_enabled=1' eq "$(uci -q get wiflow.core.portal_enabled 2>/dev/null)" 1
chk 'guest bridge has 10.10.10.1' sh -c "ip addr show dev br-wiflow | grep -q '10\\.10\\.10\\.1/'"
chk 'portal listener 10.10.10.1:2080' tcp_listening 010A0A0A 0820
chk 'captive prerouting chain loaded' nft list chain inet fw4 wiflow_portal_prerouting
chk 'captive forward chain loaded' nft list chain inet fw4 wiflow_portal_forward
chk 'authorized set exists' nft list set inet fw4 wiflow_portal_authed
chk 'guest->wan forwarding present only with portal' eq "$(uci -q get firewall.wiflow_guest_wan 2>/dev/null)" forwarding
chk 'guest DNS option 6 = 10.10.10.1' sh -c "uci -q get dhcp.wiflow_guest.dhcp_option | grep -q '6,10.10.10.1'"

printf '\nRESULT: %s passed, %s failed\n' "$pass" "$fail"
cat <<'MANUAL'
Manual guest-phone steps (cannot be automated here):
 1. Phone joins the Wiflow guest SSID: gets 10.10.10.x, captive popup opens.
 2. Before confirming: https://example.com must NOT load.
 3. Press the confirm button: page stays, Internet works.
 4. Router: nft list set inet fw4 wiflow_portal_authed  -> shows phone IP . MAC.
 5. Disable portal in WP: within ~20 s the phone loses Internet again.
NOT FLASH APPROVAL: UART/bootloader recovery must be proven separately.
MANUAL
[ "$fail" -eq 0 ]
