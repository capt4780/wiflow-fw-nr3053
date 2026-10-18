#!/bin/sh
ROOT=/etc/wiflow
SESS=/tmp/wiflow-sessions
GATE_SESS=/tmp/wiflow-gate-sessions
STATE=/tmp/wiflow-state
STATE_LOCK=/tmp/wiflow-state.lock
CLIENT_SESSIONS=/tmp/wiflow-client-sessions
EVENT_QUEUE=/tmp/wiflow-events.queue
EVENT_LOCK=/tmp/wiflow-events.lock
HEARTBEAT_KICK=/tmp/wiflow-heartbeat-kick
PORTAL_RUNTIME=/www-wiflow-portal/runtime
PORTAL_REVISIONS=$PORTAL_RUNTIME/revisions
PORTAL_ACTIVE=$PORTAL_RUNTIME/active
UPLINK_TXN=$ROOT/uplink-txn
RESUME_DIR=/tmp/wiflow-management-resume
# Production WordPress device API is package-owned, not user-configurable.
WIFLOW_REST_ROOT='https://wiflow.projifylab.com/wp-json'
WIFLOW_DEVICE_API="$WIFLOW_REST_ROOT/devices"
WIFLOW_PORTAL_API="$WIFLOW_REST_ROOT/portal"
WIFLOW_AGENT_VERSION='1.0.26'
WIFLOW_DATA_GENERATION='4'
# v1.0.26: one package for every supported router. The board name decides the
# model code (device ID, emergency Gate code, pairing model).
case "$(cat /tmp/sysinfo/board_name 2>/dev/null)" in
    viettel,nr3053) WIFLOW_MODEL_CODE='NR3053'; WIFLOW_MODEL_NAME='Viettel NR3053';;
    *) WIFLOW_MODEL_CODE='CR6609'; WIFLOW_MODEL_NAME='Xiaomi CR6609';;
esac
WIFLOW_GATE_MASTER="WIFDID$WIFLOW_MODEL_CODE"
mkdir -p "$ROOT" "$SESS" "$GATE_SESS" "$CLIENT_SESSIONS" "$RESUME_DIR" "$PORTAL_REVISIONS" 2>/dev/null || true
chmod 700 "$ROOT" "$SESS" "$GATE_SESS" "$CLIENT_SESSIONS" "$RESUME_DIR" 2>/dev/null || true

header_json(){ printf 'Content-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n\r\n'; }
redirect(){ printf 'Status: 302 Found\r\nLocation: %s\r\nCache-Control: no-store\r\n\r\n' "$1"; exit 0; }
read_body(){ n="${CONTENT_LENGTH:-0}"; case "$n" in ''|*[!0-9]*) n=0;; esac; [ "$n" -le 16384 ] || n=16384; BODY="$(dd bs=1 count="$n" 2>/dev/null)"; }
urldecode(){ /usr/sbin/uhttpd -d "$(printf '%s' "$1" | tr '+' ' ')" 2>/dev/null; }
param(){ key="$1"; data="${BODY:-${QUERY_STRING:-}}"; old="$IFS"; IFS='&'; for kv in $data; do k="${kv%%=*}"; v="${kv#*=}"; if [ "$k" = "$key" ]; then IFS="$old"; urldecode "$v"; return 0; fi; done; IFS="$old"; return 1; }
new_token(){ (dd if=/dev/urandom bs=32 count=1 2>/dev/null; date +%s; echo $$) | sha256sum | awk '{print $1}'; }
json_escape(){ printf '%s' "$1" | awk 'BEGIN{ORS=""}{gsub(/\\/,"\\\\");gsub(/"/,"\\\"");gsub(/\r/,"\\r");gsub(/\n/,"\\n");print}'; }

cookie_value(){ name="$1"; printf '%s' "${HTTP_COOKIE:-}" | tr ';' '\n' | sed -n "s/^[[:space:]]*$name=\([0-9a-fA-F]*\).*$/\1/p" | head -n1; }
cookie_token(){ cookie_value WFSESSION; }
gate_cookie_token(){ cookie_value WFGATE; }

SESSION_TTL=1800
GATE_TTL=1200

make_gate_session(){
    t="$(new_token)"; e=$(( $(date +%s) + GATE_TTL ))
    printf '%s\n' "$e" > "$GATE_SESS/$t" || return 1
    chmod 600 "$GATE_SESS/$t"
    printf '%s' "$t"
}
check_gate_session(){
    t="$(gate_cookie_token)"; [ -n "$t" ] || return 1
    f="$GATE_SESS/$t"; [ -f "$f" ] || return 1
    e="$(cat "$f" 2>/dev/null)"; now="$(date +%s)"
    case "$e" in ''|*[!0-9]*) rm -f "$f"; return 1;; esac
    [ "$now" -lt "$e" ] || { rm -f "$f"; return 1; }
    printf '%s' "$t"
}

make_session(){
    t="$(new_token)"; c="$(new_token | cut -c1-32)"; e=$(( $(date +%s) + SESSION_TTL ))
    printf '%s|%s\n' "$e" "$c" > "$SESS/$t" || return 1
    chmod 600 "$SESS/$t"
    printf '%s|%s' "$t" "$c"
}
refresh_active_gate(){
    g="$(gate_cookie_token)"; [ -n "$g" ] || return 0
    gf="$GATE_SESS/$g"; [ -f "$gf" ] || return 0
    ge=$(( $(date +%s) + GATE_TTL )); gt="$gf.$$"
    printf '%s\n' "$ge" > "$gt" 2>/dev/null || return 0
    chmod 600 "$gt" 2>/dev/null || true
    mv "$gt" "$gf" 2>/dev/null || rm -f "$gt"
}
check_session(){
    t="$(cookie_token)"; [ -n "$t" ] || return 1
    f="$SESS/$t"; [ -f "$f" ] || return 1
    line="$(cat "$f" 2>/dev/null)"; e="${line%%|*}"; c="${line#*|}"; now="$(date +%s)"
    case "$e" in ''|*[!0-9]*) rm -f "$f"; return 1;; esac
    [ "$now" -lt "$e" ] || { rm -f "$f"; return 1; }
    ne=$(( now + SESSION_TTL )); tmp="$f.$$"
    if printf '%s|%s\n' "$ne" "$c" > "$tmp" 2>/dev/null; then
        chmod 600 "$tmp" 2>/dev/null || true
        mv "$tmp" "$f" 2>/dev/null || rm -f "$tmp"
    fi
    refresh_active_gate
    printf '%s|%s' "$t" "$c"
}
require_session(){ S="$(check_session)" || { header_json; echo '{"ok":false,"error":"unauthorized"}'; exit 0; }; CSRF="${S#*|}"; }
require_csrf(){ got="$(param csrf 2>/dev/null || true)"; [ -n "$got" ] && [ "$got" = "$CSRF" ] || { header_json; echo '{"ok":false,"error":"csrf"}'; exit 0; }; }

# Short-lived management resume grant used only while changing uplink.
# It lets the same physical client recover its authenticated Wiflow Setup
# session after a radio restart without asking for the PIN/login again.
RESUME_TTL=300
client_mac_for_ip(){
    ipaddr="$1"
    mac="$(ip neigh show "$ipaddr" 2>/dev/null | awk '/lladdr/{for(i=1;i<=NF;i++)if($i=="lladdr"){print $(i+1);exit}}')"
    [ -n "$mac" ] || mac="$(awk -v ip="$ipaddr" '$1==ip{print $4;exit}' /proc/net/arp 2>/dev/null || true)"
    mac="$(printf '%s' "$mac" | tr 'A-F' 'a-f')"
    printf '%s' "$mac" | grep -Eq '^[0-9a-f]{2}(:[0-9a-f]{2}){5}$' || return 1
    printf '%s' "$mac"
}
resume_file_for_mac(){ safe="$(printf '%s' "$1" | tr -cd '0-9A-Fa-f')"; [ -n "$safe" ] || return 1; printf '%s/%s' "$RESUME_DIR" "$safe"; }
arm_management_resume(){
    ipaddr="${REMOTE_ADDR:-}"; [ -n "$ipaddr" ] || return 1
    mac="$(client_mac_for_ip "$ipaddr" 2>/dev/null || true)"; [ -n "$mac" ] || return 1
    f="$(resume_file_for_mac "$mac")" || return 1
    exp=$(( $(date +%s) + RESUME_TTL ))
    printf '%s|%s\n' "$exp" "$ipaddr" > "$f" || return 1
    chmod 600 "$f" 2>/dev/null || true
}
check_management_resume(){
    ipaddr="${REMOTE_ADDR:-}"; [ -n "$ipaddr" ] || return 1
    mac="$(client_mac_for_ip "$ipaddr" 2>/dev/null || true)"; [ -n "$mac" ] || return 1
    f="$(resume_file_for_mac "$mac")" || return 1
    [ -f "$f" ] || return 1
    line="$(cat "$f" 2>/dev/null || true)"; exp="${line%%|*}"; now="$(date +%s)"
    case "$exp" in ''|*[!0-9]*) rm -f "$f"; return 1;; esac
    [ "$now" -lt "$exp" ] || { rm -f "$f"; return 1; }
    return 0
}
clear_management_resume(){
    ipaddr="${REMOTE_ADDR:-}"; [ -n "$ipaddr" ] || return 0
    mac="$(client_mac_for_ip "$ipaddr" 2>/dev/null || true)"; [ -n "$mac" ] || return 0
    f="$(resume_file_for_mac "$mac" 2>/dev/null || true)"; [ -n "$f" ] && rm -f "$f" 2>/dev/null || true
}
clear_all_management_resume(){ rm -rf "$RESUME_DIR"/* 2>/dev/null || true; }

state_set(){ k="$1"; v="$2"; i=0; while ! mkdir "$STATE_LOCK" 2>/dev/null; do i=$((i+1)); if [ "$i" -ge 3 ]; then rmdir "$STATE_LOCK" 2>/dev/null || true; i=0; fi; sleep 1; done; tmp="$STATE.$$"; { [ -f "$STATE" ] && grep -v "^$k=" "$STATE" 2>/dev/null || true; printf '%s=%s\n' "$k" "$v"; } > "$tmp"; mv "$tmp" "$STATE"; rmdir "$STATE_LOCK" 2>/dev/null || true; }
state_get(){ [ -f "$STATE" ] && awk -F= -v k="$1" '$1==k{sub(/^[^=]*=/,"");print;exit}' "$STATE"; }
wan_zone(){ uci -q show firewall 2>/dev/null | awk -F= '$2 == "\047wan\047" && $1 ~ /\.name$/ {n=$1;sub(/^firewall\./,"",n);sub(/\.name$/,"",n);print n;exit}'; }
iface_up(){ iface="$1"; st="$(ubus call "network.interface.$iface" status 2>/dev/null || true)"; [ -n "$st" ] || return 1; up="$(printf '%s' "$st" | jsonfilter -e '@.up' 2>/dev/null || true)"; [ "$up" = true ] || [ "$up" = 1 ] || return 1; addr="$(printf '%s' "$st" | jsonfilter -e '@["ipv4-address"][0].address' 2>/dev/null || true)"; [ -n "$addr" ] || return 1; return 0; }
iface_route_active(){ iface="$1"; st="$(ubus call "network.interface.$iface" status 2>/dev/null || true)"; dev="$(printf '%s' "$st" | jsonfilter -e '@.l3_device' 2>/dev/null || true)"; [ -n "$dev" ] || dev="$(printf '%s' "$st" | jsonfilter -e '@.device' 2>/dev/null || true)"; [ -n "$dev" ] || return 1; route="$(ip route get 1.1.1.1 2>/dev/null | head -n1)"; printf '%s' "$route" | grep -Fq " dev $dev "; }
radio_band(){ r="$1"; b="$(uci -q get wireless.$r.band 2>/dev/null || true)"; case "$b" in 2g|5g) printf '%s' "$b"; return;; esac; h="$(uci -q get wireless.$r.hwmode 2>/dev/null || true)"; case "$h" in *11a*|a) printf '5g';; *) printf '2g';; esac; }
radio_for_band(){ want="$1"; for r in $(uci -q show wireless 2>/dev/null | awk -F= '$2 == "wifi-device" {n=$1;sub(/^wireless\./,"",n);print n}'); do [ "$(radio_band "$r")" = "$want" ] && { printf '%s' "$r"; return 0; }; done; return 1; }
secure_configs(){ [ -f /etc/config/wiflow ] && chmod 600 /etc/config/wiflow 2>/dev/null || true; [ -f /etc/config/wireless ] && chmod 600 /etc/config/wireless 2>/dev/null || true; }

internet_probe(){
    out="/tmp/wiflow-internet-probe.$$"
    rm -f "$out"
    if uclient-fetch -q -T 5 -O "$out" 'http://detectportal.firefox.com/success.txt' >/dev/null 2>&1 && grep -qx 'success' "$out" 2>/dev/null; then rm -f "$out"; return 0; fi
    rm -f "$out"
    if uclient-fetch -q -T 5 -O "$out" 'http://www.msftconnecttest.com/connecttest.txt' >/dev/null 2>&1 && grep -q 'Microsoft Connect Test' "$out" 2>/dev/null; then rm -f "$out"; return 0; fi
    rm -f "$out"
    # HTTPS 204 is a third independent probe. An upstream captive portal cannot
    # transparently replace this response without failing TLS validation.
    if uclient-fetch -q -T 5 -O "$out" 'https://connectivitycheck.gstatic.com/generate_204' >/dev/null 2>&1; then rm -f "$out"; return 0; fi
    rm -f "$out"
    return 1
}


# Bounded WAN verification used by the authorization state machine. This is
# an error/recovery check, not an artificial progress timer.
internet_probe_fast(){
    out="/tmp/wiflow-internet-fast.$$"; rm -f "$out"
    if uclient-fetch -q -T 3 -O "$out" 'https://connectivitycheck.gstatic.com/generate_204' >/dev/null 2>&1; then rm -f "$out"; return 0; fi
    rm -f "$out"
    if uclient-fetch -q -T 3 -O "$out" 'http://detectportal.firefox.com/success.txt' >/dev/null 2>&1 && grep -qx 'success' "$out" 2>/dev/null; then rm -f "$out"; return 0; fi
    rm -f "$out"; return 1
}

# v1.0.6: WiFi helpers use only what a stock OpenWrt 24.10 + LuCI image has
# (ubus, rpcd iwinfo, sysfs). The `iw` and `iwinfo` command-line packages are
# not required; the iwinfo CLI is used only as a fallback when present.

# v1.0.26: radios driven by MediaTek mt_wifi (type 'mtwifi', e.g. Viettel NR3053)
# use fixed interface names from the driver's l1profile: the radio's main
# interface (ra0 / rax0) answers scans, its station is apcli0 / apclix0.
radio_type(){ uci -q get "wireless.$1.type" 2>/dev/null || true; }
radio_is_mtwifi(){ [ "$(radio_type "$1")" = mtwifi ]; }
mtwifi_main_if(){ m="$(uci -q get "wireless.$1.phy" 2>/dev/null || true)"; [ -n "$m" ] || { [ "$(radio_band "$1")" = 5g ] && m=rax0 || m=ra0; }; printf '%s' "$m"; }
mtwifi_sta_if(){ case "$(mtwifi_main_if "$1")" in rax*) printf 'apclix0';; *) printf 'apcli0';; esac; }

# Kernel interface name of the source-WiFi station (wireless.wiflow_uplink).
wifi_sta_ifname(){
    radio="$(uci -q get wireless.wiflow_uplink.device 2>/dev/null || true)"; [ -n "$radio" ] || return 1
    st="$(ubus call network.wireless status 2>/dev/null || true)"
    k=0
    while [ -n "$st" ] && [ "$k" -lt 8 ]; do
        sec="$(printf '%s' "$st" | jsonfilter -e "@.$radio.interfaces[$k].section" 2>/dev/null || true)"
        [ -n "$sec" ] || break
        if [ "$sec" = wiflow_uplink ]; then
            ifn="$(printf '%s' "$st" | jsonfilter -e "@.$radio.interfaces[$k].ifname" 2>/dev/null || true)"
            [ -n "$ifn" ] && { printf '%s' "$ifn"; return 0; }
            break
        fi
        k=$((k+1))
    done
    radio_is_mtwifi "$radio" || return 1
    ifn="$(mtwifi_sta_if "$radio")"; [ -d "/sys/class/net/$ifn" ] || return 1
    printf '%s' "$ifn"
}

# BSSID the station is associated with (empty when not associated).
wifi_sta_bssid(){
    ifn="$1"
    b="$(ubus call iwinfo info "{\"device\":\"$ifn\"}" 2>/dev/null | jsonfilter -e '@.bssid' 2>/dev/null || true)"
    if [ -z "$b" ] && command -v iwconfig >/dev/null 2>&1; then
        b="$(iwconfig "$ifn" 2>/dev/null | sed -n 's/.*Access Point: *\([0-9A-Fa-f:]\{17\}\).*/\1/p' | head -n1)"
    fi
    case "$b" in ''|00:00:00:00:00:00|FF:FF:FF:FF:FF:FF|ff:ff:ff:ff:ff:ff|44:44:44:44:44:44) return 1;; esac
    printf '%s' "$b"
}

# Associated = the station interface has carrier (mac80211 sets it only after
# association). When rpcd iwinfo is available the SSID is checked as well.
# mt_wifi keeps carrier on an unassociated apcli, so there the station must
# report the BSSID of the source WiFi.
wifi_uplink_associated(){
    want="${1:-}"; ifn="$(wifi_sta_ifname 2>/dev/null || true)"; [ -n "$ifn" ] || return 1
    radio="$(uci -q get wireless.wiflow_uplink.device 2>/dev/null || true)"
    if radio_is_mtwifi "$radio"; then
        fl="$(cat "/sys/class/net/$ifn/flags" 2>/dev/null || echo 0)"; [ $(( fl & 1 )) = 1 ] || return 1
        wifi_sta_bssid "$ifn" >/dev/null || return 1
    else
        [ "$(cat "/sys/class/net/$ifn/carrier" 2>/dev/null)" = 1 ] || return 1
    fi
    [ -n "$want" ] || return 0
    got="$(ubus call iwinfo info "{\"device\":\"$ifn\"}" 2>/dev/null | jsonfilter -e '@.ssid' 2>/dev/null || true)"
    [ -z "$got" ] || [ "$got" = "$want" ]
}

# ENC = none | psk | psk2 | sae | sae-mixed (sae: WPA3 only, sae-mixed: WPA2/WPA3).
wifi_enc_from_iwinfo(){
    en="$1"; au="$2"; wv="$3"
    if [ "$en" != true ] && [ "$en" != 1 ]; then printf none
    elif printf '%s' "$au" | grep -qi sae; then
        if printf '%s' "$au" | grep -qi psk; then printf sae-mixed; else printf sae; fi
    elif printf '%s' "$wv" | grep -Eq '^\[?1\]?$'; then printf psk
    else printf psk2; fi
}

wifi_parse_iwinfo_scan(){
    raw="$1"; k=0
    while [ "$k" -lt 64 ]; do
        b="$(jsonfilter -i "$raw" -e "@.results[$k].bssid" 2>/dev/null || true)"; [ -n "$b" ] || break
        s="$(jsonfilter -i "$raw" -e "@.results[$k].ssid" 2>/dev/null || true)"
        en="$(jsonfilter -i "$raw" -e "@.results[$k].encryption.enabled" 2>/dev/null || true)"
        au="$(jsonfilter -i "$raw" -e "@.results[$k].encryption.authentication" 2>/dev/null | tr -d '\n' || true)"
        wv="$(jsonfilter -i "$raw" -e "@.results[$k].encryption.wpa" 2>/dev/null | tr -d '\n ' || true)"
        e="$(wifi_enc_from_iwinfo "$en" "$au" "$wv")"
        sg="$(jsonfilter -i "$raw" -e "@.results[$k].signal" 2>/dev/null || true)"; case "$sg" in -[0-9]*) :;; *) sg='';; esac
        [ -n "$s" ] && printf '%s\t%s\t%s\t%s\n' "$s" "$b" "$e" "$sg"
        k=$((k+1))
    done
}

wifi_iwinfo_scan(){
    dev="$1"; raw="$2"; : > "$raw"
    ( ubus -t 8 call iwinfo scan "{\"device\":\"$dev\"}" > "$raw" 2>/dev/null ) & p=$!
    ( sleep 9; kill "$p" 2>/dev/null ) & w=$!
    wait "$p" 2>/dev/null || true; kill "$w" 2>/dev/null || true
}

# mt_wifi fallback: the driver's own site survey table (fixed-width columns,
# "Security" like WPA2PSK/AES, signal in percent).
mtwifi_site_survey(){
    dev="$1"; command -v iwpriv >/dev/null 2>&1 || return 0
    iwpriv "$dev" set SiteSurvey=1 >/dev/null 2>&1 || return 0
    sleep 4
    iwpriv "$dev" get_site_survey 2>/dev/null | awk '
      /SSID/ && /BSSID/ && /Security/ { s0=index($0,"SSID"); next }
      s0 && match($0, /[0-9A-Fa-f][0-9A-Fa-f](:[0-9A-Fa-f][0-9A-Fa-f])(:[0-9A-Fa-f][0-9A-Fa-f])(:[0-9A-Fa-f][0-9A-Fa-f])(:[0-9A-Fa-f][0-9A-Fa-f])(:[0-9A-Fa-f][0-9A-Fa-f])/) {
        ssid=substr($0, s0, RSTART-s0); sub(/[ \t]+$/, "", ssid)
        bssid=tolower(substr($0, RSTART, 17)); rest=substr($0, RSTART+17)
        n=split(rest, f, /[ \t]+/); i=1; while (i<=n && f[i]=="") i++
        sec=toupper(f[i]); pct=f[i+1]+0
        if (sec ~ /OWE/) next
        if (sec ~ /WPA3/) enc=(sec ~ /WPA2/ ? "sae-mixed" : "sae")
        else if (sec ~ /WPA2/) enc="psk2"
        else if (sec ~ /WPA/) enc="psk"
        else enc="none"
        sig=""; if (pct>0) sig=int(pct/2)-100
        if (ssid!="") printf "%s\t%s\t%s\t%s\n", ssid, bssid, enc, sig
      }'
}

# Prints one line per network seen by a radio: SSID<TAB>BSSID<TAB>ENC<TAB>SIGNAL_DBM (may be empty)
# Bounded to 8 seconds per scan (mt_wifi: up to 3 scans, then the site survey).
wifi_scan_radio(){
    sr="$1"; raw="/tmp/wiflow-scanraw.$$"; out="/tmp/wiflow-scanlist.$$"; : > "$out"
    if radio_is_mtwifi "$sr"; then
        dev="$(mtwifi_main_if "$sr")"
        if ubus list iwinfo >/dev/null 2>&1; then
            n=0
            while [ "$n" -lt 3 ]; do
                wifi_iwinfo_scan "$dev" "$raw"; wifi_parse_iwinfo_scan "$raw" > "$out"
                [ -s "$out" ] && break
                n=$((n+1)); [ "$n" -lt 3 ] && sleep 2
            done
        fi
        [ -s "$out" ] || mtwifi_site_survey "$dev" > "$out"
        cat "$out"
    elif ubus list iwinfo >/dev/null 2>&1; then
        wifi_iwinfo_scan "$sr" "$raw"; wifi_parse_iwinfo_scan "$raw"
    elif command -v iwinfo >/dev/null 2>&1; then
        ( iwinfo "$sr" scan > "$raw" 2>/dev/null ) & p=$!
        ( sleep 8; kill "$p" 2>/dev/null ) & w=$!
        wait "$p" 2>/dev/null || true; kill "$w" 2>/dev/null || true
        awk '
          /Cell [0-9]+ - Address:/ {b=$0; sub(/^.*Address: /,"",b); gsub(/[[:space:]]+$/,"",b)}
          /ESSID: / {s=$0; sub(/^.*ESSID: \"/,"",s); sub(/\".*$/,"",s)}
          /Signal: / {g=$0; sub(/^.*Signal: /,"",g); sub(/ .*$/,"",g)}
          /Encryption: / { e=$0; sub(/^.*Encryption: /,"",e); enc="psk2";
            if(e ~ /none|None/) enc="none"; else if(e ~ /WPA3|SAE/) enc=(e ~ /WPA2|PSK/ ? "sae-mixed" : "sae"); else if(e ~ /WPA[^2]/) enc="psk";
            if(s!="") {print s "\t" b "\t" enc "\t" g; s=""; b=""; g=""} }' "$raw" 2>/dev/null
    fi
    rm -f "$raw" "$out"
}

wifi_ssid_visible(){
    radio="$1"; want="$2"
    wifi_scan_radio "$radio" | awk -F '\t' -v want="$want" '$1==want{ok=1} END{exit(ok?0:1)}'
}

setup_username(){ u="$(uci -q get wiflow.core.setup_username 2>/dev/null || true)"; [ -n "$u" ] && printf '%s' "$u" || printf 'wiflow'; }
setup_check_login(){
    u="$1"; p="$2"; stored_hash="$(uci -q get wiflow.core.setup_password_hash 2>/dev/null || true)"; stored_salt="$(uci -q get wiflow.core.setup_password_salt 2>/dev/null || true)"
    if [ -z "$stored_hash" ] || [ -z "$stored_salt" ]; then [ "$u" = wiflow ] && [ "$p" = wiflow ]; return; fi
    [ "$u" = "$(setup_username)" ] || return 1
    got="$(printf '%s:%s' "$stored_salt" "$p" | sha256sum | awk '{print $1}')"
    [ "$got" = "$stored_hash" ]
}
setup_set_login(){
    u="$1"; p="$2"
    printf '%s' "$u" | grep -Eq '^[A-Za-z0-9._-]{3,32}$' || return 2
    plen="$(printf '%s' "$p" | wc -c | tr -d ' ')"; case "$plen" in ''|*[!0-9]*) return 2;; esac
    [ "$plen" -ge 6 ] && [ "$plen" -le 128 ] || return 2
    salt="$(new_token | cut -c1-32)"; hash="$(printf '%s:%s' "$salt" "$p" | sha256sum | awk '{print $1}')"
    uci set "wiflow.core.setup_username=$u"
    uci set "wiflow.core.setup_password_salt=$salt"
    uci set "wiflow.core.setup_password_hash=$hash"
    uci commit wiflow || return 1
    secure_configs
    rm -rf "$SESS"/* 2>/dev/null || true
    clear_all_management_resume
    return 0
}
setup_reset_login(){
    uci -q delete wiflow.core.setup_username >/dev/null 2>&1 || true
    uci -q delete wiflow.core.setup_password_salt >/dev/null 2>&1 || true
    uci -q delete wiflow.core.setup_password_hash >/dev/null 2>&1 || true
    uci commit wiflow >/dev/null 2>&1 || true
    secure_configs
    rm -rf "$SESS"/* 2>/dev/null || true
    clear_all_management_resume
}


device_id(){ cat /etc/wiflow/device-id 2>/dev/null | tr -d "\r\n"; }
device_token(){ uci -q get wiflow.core.device_token 2>/dev/null || true; }
wiflow_get(){
 out="$1"; url="$2"; did="$(device_id)"; tok="$(device_token)"; [ -n "$did" ] && [ -n "$tok" ] || return 2
 err="${out}.fetch-error"; rm -f "$err"; uclient-fetch -T 15 --header="X-Wiflow-Device-ID: $did" --header="X-Wiflow-Device-Token: $tok" -O "$out" "$url" 2>"$err"; rc=$?
 [ "$rc" -eq 0 ] && rm -f "$err"; return "$rc"
}
wiflow_post(){
 out="$1"; url="$2"; body="$3"; did="$(device_id)"; tok="$(device_token)"; [ -n "$did" ] && [ -n "$tok" ] || return 2
 err="${out}.fetch-error"; rm -f "$err"; uclient-fetch -T 15 --post-data="$body" --header='Content-Type: application/json' --header="X-Wiflow-Device-ID: $did" --header="X-Wiflow-Device-Token: $tok" -O "$out" "$url" 2>"$err"; rc=$?
 [ "$rc" -eq 0 ] && rm -f "$err"; return "$rc"
}

portal_storage_reset(){
    rm -rf "$PORTAL_REVISIONS" "$PORTAL_ACTIVE" "$PORTAL_RUNTIME"/.staging-* "$PORTAL_RUNTIME"/.active-* 2>/dev/null || true
    mkdir -p "$PORTAL_REVISIONS" 2>/dev/null || true
    uci set wiflow.core.portal_revision='0'
    uci set wiflow.core.portal_sync_status='idle'
    uci set wiflow.core.portal_sync_error=''
}

pairing_clear_local(){
    /usr/lib/wiflow/portal-firewall disable >/dev/null 2>&1 || true
    uci set wiflow.core.paired='0'
    uci set wiflow.core.portal_enabled='0'
    uci set wiflow.core.pair_required='1'
    for k in device_token account_public_id client_hash_salt last_command_id last_command_action last_command_status last_command_message; do
        uci -q delete "wiflow.core.$k" >/dev/null 2>&1 || true
    done
    portal_storage_reset
    uci commit wiflow >/dev/null 2>&1 || true
    secure_configs
    rm -f "$EVENT_QUEUE" "$HEARTBEAT_KICK" 2>/dev/null || true
    rm -rf "$CLIENT_SESSIONS"/* 2>/dev/null || true
    ensure_guest_network >/dev/null 2>&1 || true
    /etc/init.d/firewall reload >/dev/null 2>&1 || true
}

client_id_for_mac(){
    mac="$1"; salt="$(uci -q get wiflow.core.client_hash_salt 2>/dev/null || true)"
    [ -n "$salt" ] || salt="$(cat /etc/wiflow/device-id 2>/dev/null | tr -d '\r\n')"
    printf '%s|%s' "$salt" "$mac" | sha256sum | awk '{print substr($1,1,32)}'
}
client_file_for_mac(){ safe="$(printf '%s' "$1" | tr -cd '0-9A-Fa-f')"; [ -n "$safe" ] || return 1; printf '%s/%s' "$CLIENT_SESSIONS" "$safe"; }
client_find_file_by_session(){
    sid="$1"; for f in "$CLIENT_SESSIONS"/*; do [ -f "$f" ] || continue; IFS='|' read -r _mac _cid _sid _ip _connected _authorized _last _absent < "$f" 2>/dev/null || true; [ "$_sid" = "$sid" ] && { printf '%s' "$f"; return 0; }; done; return 1
}
valid_guest_ip(){ case "${1:-}" in 10.10.10.*) last="${1##*.}";; *) return 1;; esac; case "$last" in ''|*[!0-9]*) return 1;; esac; [ "$last" -ge 2 ] 2>/dev/null && [ "$last" -le 254 ] 2>/dev/null; }
guest_mac_for_ip(){
    ipx="$1"; valid_guest_ip "$ipx" || return 1
    mac="$(awk -v ip="$ipx" '$3==ip{print toupper($2);exit}' /tmp/dhcp.leases 2>/dev/null || true)"
    [ -n "$mac" ] || mac="$(ip neigh show "$ipx" dev br-wiflow 2>/dev/null | awk '/lladdr/{print toupper($5);exit}')"
    printf '%s' "$mac" | grep -Eq '^([0-9A-F]{2}:){5}[0-9A-F]{2}$' || return 1
    printf '%s' "$mac"
}
client_session_write(){
    f="$1"; mac="$2"; cid="$3"; sid="$4"; ipx="$5"; connected="$6"; authorized="$7"; last="$8"; absent="$9"
    tmp="$f.$$"; printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$mac" "$cid" "$sid" "$ipx" "$connected" "$authorized" "$last" "$absent" > "$tmp" || return 1
    chmod 600 "$tmp" 2>/dev/null || true; mv "$tmp" "$f"
}
# v1.0.12: own table, untouched by fw4 reloads (see portal-firewall).
CAPTIVE_TABLE='inet wiflow_captive'
portal_nft_ready(){
    /usr/sbin/nft list set $CAPTIVE_TABLE authed >/dev/null 2>&1
}
portal_nft_del(){ ipx="$1"; mac="$2"; printf 'delete element %s authed { %s . %s }\n' "$CAPTIVE_TABLE" "$ipx" "$mac" | /usr/sbin/nft -f - >/dev/null 2>&1 || true; }
# Idempotent: an element that is already present is left untouched, so a
# periodic re-assert never opens a delete/add gap for an authorized client.
portal_nft_add(){
    ipx="$1"; mac="$2"; valid_guest_ip "$ipx" || return 1; portal_nft_ready || return 1
    portal_nft_pair_authorized "$ipx" "$mac" && return 0
    printf 'add element %s authed { %s . %s timeout 30d }\n' "$CAPTIVE_TABLE" "$ipx" "$mac" | /usr/sbin/nft -f - >/dev/null 2>&1 || return 1
    portal_nft_pair_authorized "$ipx" "$mac"
}
portal_nft_pair_authorized(){ ipx="$1"; mac="$2"; /usr/sbin/nft list set $CAPTIVE_TABLE authed 2>/dev/null | grep -Fiq "$ipx . $mac"; }
_event_lock(){ i=0; while ! mkdir "$EVENT_LOCK" 2>/dev/null; do i=$((i+1)); if [ "$i" -ge 3 ]; then rmdir "$EVENT_LOCK" 2>/dev/null || true; i=0; fi; sleep 1; done; }
_event_unlock(){ rmdir "$EVENT_LOCK" 2>/dev/null || true; }
event_enqueue(){
    event="$1"; cid="$2"; sid="$3"; when="${4:-$(date +%s)}"; eid="$(new_token | cut -c1-24)"
    _event_lock || return 1
    printf '%s|%s|%s|%s|%s\n' "$eid" "$cid" "$sid" "$event" "$when" >> "$EVENT_QUEUE"
    lines="$(wc -l < "$EVENT_QUEUE" 2>/dev/null | tr -d ' ')"; case "$lines" in ''|*[!0-9]*) lines=0;; esac
    if [ "$lines" -gt 5000 ]; then tmp="$EVENT_QUEUE.trim"; tail -n 4000 "$EVENT_QUEUE" > "$tmp" 2>/dev/null || true; mv "$tmp" "$EVENT_QUEUE"; fi
    chmod 600 "$EVENT_QUEUE" 2>/dev/null || true
    _event_unlock
}
event_prepare_batch(){
    out="$1"; limit="${2:-20}"; : > "$out"
    _event_lock || { echo 0; return 1; }
    [ -f "$EVENT_QUEUE" ] && head -n "$limit" "$EVENT_QUEUE" > "$out" 2>/dev/null || true
    _event_unlock
    wc -l < "$out" | tr -d ' '
}
event_ack_batch(){
    count="$1"; case "$count" in ''|*[!0-9]*) return 1;; esac; [ "$count" -gt 0 ] || return 0
    _event_lock || return 1
    if [ -f "$EVENT_QUEUE" ]; then tmp="$EVENT_QUEUE.$$"; awk -v n="$count" 'NR>n' "$EVENT_QUEUE" > "$tmp" 2>/dev/null || : > "$tmp"; mv "$tmp" "$EVENT_QUEUE"; chmod 600 "$EVENT_QUEUE" 2>/dev/null || true; fi
    _event_unlock
}

command_result_set(){
    id="$1"; action="$2"; status="$3"; message="${4:-}"
    uci set "wiflow.core.last_command_id=$id"
    uci set "wiflow.core.last_command_action=$action"
    uci set "wiflow.core.last_command_status=$status"
    uci set "wiflow.core.last_command_message=$message"
    uci commit wiflow >/dev/null 2>&1 || true
    secure_configs
}
command_result_clear(){
    for k in last_command_id last_command_action last_command_status last_command_message; do uci -q delete "wiflow.core.$k" >/dev/null 2>&1 || true; done
    uci commit wiflow >/dev/null 2>&1 || true
}

recover_uplink_transaction(){
    [ -f "$UPLINK_TXN/.pending" ] || return 1
    cid="$(cat "$UPLINK_TXN/command_id" 2>/dev/null || true)"
    action="$(cat "$UPLINK_TXN/command_action" 2>/dev/null || true)"; [ -n "$action" ] || action=change_wifi
    [ -f "$UPLINK_TXN/wireless" ] && cp "$UPLINK_TXN/wireless" /etc/config/wireless 2>/dev/null || true
    [ -f "$UPLINK_TXN/network" ] && cp "$UPLINK_TXN/network" /etc/config/network 2>/dev/null || true
    [ -f "$UPLINK_TXN/wiflow" ] && cp "$UPLINK_TXN/wiflow" /etc/config/wiflow 2>/dev/null || true
    rm -rf "$UPLINK_TXN"
    secure_configs
    [ -n "$cid" ] && command_result_set "$cid" "$action" failed 'Thay đổi kết nối bị gián đoạn; cấu hình trước đó đã được khôi phục' || true
    return 0
}

website_url_valid(){ case "$1" in http://*|https://*) return 0;; *) return 1;; esac; }
website_host_from_url(){ printf '%s' "$1" | sed -n 's#^https\{0,1\}://\([^/:?]*\).*#\1#p'; }
portal_active_config(){ [ -f "$PORTAL_ACTIVE/portal.json" ] && printf '%s' "$PORTAL_ACTIVE/portal.json"; }

tune_wiflow_runtime(){
    if uci -q get network.lan >/dev/null 2>&1; then
        uci set network.lan.delegate='0'
        uci -q delete network.lan.ip6assign >/dev/null 2>&1 || true
        uci -q delete network.lan.ip6hint >/dev/null 2>&1 || true
        uci -q delete network.lan.ip6ifaceid >/dev/null 2>&1 || true
    fi
    if uci -q get dhcp.lan >/dev/null 2>&1; then
        uci set dhcp.lan.dhcpv6='disabled'
        uci set dhcp.lan.ra='disabled'
        uci set dhcp.lan.ndp='disabled'
    fi
    if uci -q get 'dhcp.@dnsmasq[0]' >/dev/null 2>&1; then
        uci set 'dhcp.@dnsmasq[0].cachesize=1000'
        uci set 'dhcp.@dnsmasq[0].logqueries=0'
        uci set 'dhcp.@dnsmasq[0].logdhcp=0'
        uci set 'dhcp.@dnsmasq[0].localservice=1'
    fi
    uci commit network >/dev/null 2>&1 || true
    uci commit dhcp >/dev/null 2>&1 || true
}

ensure_guest_network(){
    uci -q delete network.wiflow_guest >/dev/null 2>&1 || true
    uci set network.wiflow_guest='interface'
    uci set network.wiflow_guest.proto='static'
    uci set network.wiflow_guest.device='br-wiflow'
    uci set network.wiflow_guest.ipaddr='10.10.10.1'
    uci set network.wiflow_guest.netmask='255.255.255.0'
    uci set network.wiflow_guest.delegate='0'
    uci -q delete network.wiflow_guest.ip6assign >/dev/null 2>&1 || true
    uci -q delete network.wiflow_guest.ip6hint >/dev/null 2>&1 || true
    uci -q delete network.wiflow_guest_dev >/dev/null 2>&1 || true
    uci set network.wiflow_guest_dev='device'
    uci set network.wiflow_guest_dev.name='br-wiflow'
    uci set network.wiflow_guest_dev.type='bridge'
    uci set network.wiflow_guest_dev.bridge_empty='1'
    uci commit network

    uci -q delete dhcp.wiflow_guest >/dev/null 2>&1 || true
    uci set dhcp.wiflow_guest='dhcp'
    uci set dhcp.wiflow_guest.interface='wiflow_guest'
    uci set dhcp.wiflow_guest.start='100'
    uci set dhcp.wiflow_guest.limit='150'
    uci set dhcp.wiflow_guest.leasetime='4h'
    uci set dhcp.wiflow_guest.force='1'
    # Router DNS is the DHCP default only. After authorization the firewall
    # does not intercept or force DNS, DoT or DoH, so clients may use their own
    # resolvers/tunnels as supported by the operating system and upstream WAN.
    uci -q delete dhcp.wiflow_guest.dhcp_option >/dev/null 2>&1 || true
    uci add_list dhcp.wiflow_guest.dhcp_option='6,10.10.10.1'
    # RFC 7710/8910 captive-portal advertisement. This is additive to the
    # classic HTTP redirect and gives modern Android/iOS a deterministic local
    # captive status endpoint without depending on public probe DNS.
    uci add_list dhcp.wiflow_guest.dhcp_option='114,http://10.10.10.1:2080/cgi-bin/captive-api'
    uci set dhcp.wiflow_guest.dhcpv6='disabled'
    uci set dhcp.wiflow_guest.ra='disabled'
    uci set dhcp.wiflow_guest.ndp='disabled'
    uci commit dhcp

    uci -q delete firewall.wiflow_guest >/dev/null 2>&1 || true
    uci set firewall.wiflow_guest='zone'
    uci set firewall.wiflow_guest.name='wiflow_guest'
    uci add_list firewall.wiflow_guest.network='wiflow_guest'
    uci set firewall.wiflow_guest.input='REJECT'
    uci set firewall.wiflow_guest.output='ACCEPT'
    uci set firewall.wiflow_guest.forward='REJECT'

    uci -q delete firewall.wiflow_guest_dns >/dev/null 2>&1 || true
    uci set firewall.wiflow_guest_dns='rule'
    uci set firewall.wiflow_guest_dns.name='Wiflow-Guest-DNS'
    uci set firewall.wiflow_guest_dns.src='wiflow_guest'
    uci set firewall.wiflow_guest_dns.dest_port='53'
    uci add_list firewall.wiflow_guest_dns.proto='tcp'
    uci add_list firewall.wiflow_guest_dns.proto='udp'
    uci set firewall.wiflow_guest_dns.target='ACCEPT'

    # Private DNS (Android/Samsung "Private DNS") must remain reachable even
    # before Portal authorization. Keep this as a normal fw4 rule so it does
    # not disappear when captive NAT rules are rebuilt.
    uci -q delete firewall.wiflow_guest_private_dns >/dev/null 2>&1 || true
    uci set firewall.wiflow_guest_private_dns='rule'
    uci set firewall.wiflow_guest_private_dns.name='Wiflow-Guest-Private-DNS'
    uci set firewall.wiflow_guest_private_dns.src='wiflow_guest'
    uci set firewall.wiflow_guest_private_dns.dest='wan'
    uci set firewall.wiflow_guest_private_dns.dest_port='853'
    uci add_list firewall.wiflow_guest_private_dns.proto='tcp'
    uci add_list firewall.wiflow_guest_private_dns.proto='udp'
    uci set firewall.wiflow_guest_private_dns.target='ACCEPT'

    uci -q delete firewall.wiflow_guest_dhcp >/dev/null 2>&1 || true
    uci set firewall.wiflow_guest_dhcp='rule'
    uci set firewall.wiflow_guest_dhcp.name='Wiflow-Guest-DHCP'
    uci set firewall.wiflow_guest_dhcp.src='wiflow_guest'
    uci set firewall.wiflow_guest_dhcp.proto='udp'
    uci set firewall.wiflow_guest_dhcp.dest_port='67-68'
    uci set firewall.wiflow_guest_dhcp.target='ACCEPT'

    # Guests reach Wiflow (10.0.0.1:80: Security Gate, Wiflow login, LuCI) and
    # 10.0.0.2:80, which only redirects to 10.0.0.1.
    uci -q delete firewall.wiflow_guest_setup >/dev/null 2>&1 || true
    uci set firewall.wiflow_guest_setup='rule'
    uci set firewall.wiflow_guest_setup.name='Wiflow-Guest-Setup-Access'
    uci set firewall.wiflow_guest_setup.src='wiflow_guest'
    uci set firewall.wiflow_guest_setup.dest_ip='10.0.0.1'
    uci set firewall.wiflow_guest_setup.dest_port='80'
    uci set firewall.wiflow_guest_setup.proto='tcp'
    uci set firewall.wiflow_guest_setup.target='ACCEPT'
    uci -q delete firewall.wiflow_guest_gate >/dev/null 2>&1 || true
    uci set firewall.wiflow_guest_gate='rule'
    uci set firewall.wiflow_guest_gate.name='Wiflow-LuCI-Security-Gate'
    uci set firewall.wiflow_guest_gate.src='wiflow_guest'
    uci set firewall.wiflow_guest_gate.dest_ip='10.0.0.2'
    uci set firewall.wiflow_guest_gate.dest_port='80'
    uci set firewall.wiflow_guest_gate.proto='tcp'
    uci set firewall.wiflow_guest_gate.target='ACCEPT'

    uci -q delete firewall.wiflow_guest_wan >/dev/null 2>&1 || true
    uci set firewall.wiflow_guest_wan='forwarding'
    uci set firewall.wiflow_guest_wan.src='wiflow_guest'
    uci set firewall.wiflow_guest_wan.dest='wan'
    uci commit firewall
}

ensure_uplink_network(){
    uci -q get network.wiflow_wwan >/dev/null 2>&1 || uci set network.wiflow_wwan='interface'
    uci set network.wiflow_wwan.proto='dhcp'
    uci set network.wiflow_wwan.metric='10'
    uci commit network
    z="$(wan_zone || true)"
    if [ -n "$z" ]; then
        uci -q del_list "firewall.$z.network=wiflow_wwan" >/dev/null 2>&1 || true
        uci add_list "firewall.$z.network=wiflow_wwan"
        uci commit firewall
    fi
}

# v1.0.5: default credentials must be replaced at the first Setup login.
# v1.0.25: wiflow / wiflow stays valid until the owner changes it (no forced change).
setup_must_change_password(){ return 1; }


# ---------------------------------------------------------------------------
# v1.0.6: monotonic time, guest session persistence, confirmed unpair.
# ---------------------------------------------------------------------------
uptime_s(){ u="$(cut -d. -f1 /proc/uptime 2>/dev/null)"; case "$u" in ''|*[!0-9]*) u=0;; esac; printf '%s' "$u"; }

# Authorized guest sessions survive reboot and power loss. Snapshot is written
# at most every 10 minutes (and on a clean stop) and only when it changed, to
# keep NAND writes low. A power cut loses at most the last 10 minutes.
SESSION_SNAP=$ROOT/sessions.snap
session_snapshot(){
    tmp="$SESSION_SNAP.tmp.$$"; : > "$tmp" || return 1
    for f in "$CLIENT_SESSIONS"/*; do
        [ -f "$f" ] || continue
        IFS='|' read -r _m _c _s _i _cn _a _l _ab < "$f" 2>/dev/null || continue
        case "${_a:-0}" in ''|0|*[!0-9]*) continue;; esac
        printf '%s|%s|%s|%s|%s|%s|%s|0\n' "$_m" "$_c" "$_s" "$_i" "$_cn" "$_a" "$_l" >> "$tmp"
    done
    sort -o "$tmp" "$tmp" 2>/dev/null || true
    if [ -f "$SESSION_SNAP" ] && [ "$(sha256sum < "$tmp")" = "$(sha256sum < "$SESSION_SNAP")" ]; then rm -f "$tmp"; return 0; fi
    chmod 600 "$tmp" 2>/dev/null || true
    mv "$tmp" "$SESSION_SNAP" && sync
}
# Restored sessions start as "present"; the session loop re-adds each client to
# the firewall set when it reconnects, or drops it after the disconnect grace.
session_restore(){
    [ -s "$SESSION_SNAP" ] || return 0
    mkdir -p "$CLIENT_SESSIONS"; now="$(date +%s)"; n=0
    while IFS='|' read -r _m _c _s _i _cn _a _l _ab; do
        printf '%s' "$_m" | grep -Eq '^([0-9A-F]{2}:){5}[0-9A-F]{2}$' || continue
        printf '%s' "$_s" | grep -Eq '^[0-9a-fA-F]{16,64}$' || continue
        case "$_a" in ''|0|*[!0-9]*) continue;; esac
        f="$(client_file_for_mac "$_m")" || continue
        [ -f "$f" ] && continue
        client_session_write "$f" "$_m" "$_c" "$_s" "$_i" "$_cn" "$_a" "$now" 0 && n=$((n+1))
    done < "$SESSION_SNAP"
    printf '%s' "$n"
}

# Only an explicit DEVICE_UNPAIRED from WordPress, seen 3 times in a row over
# at least 10 minutes, clears the local pairing. Any other auth error is
# treated as a server-side problem: the router keeps serving guests.
UNPAIR_CONFIRMATIONS=3
UNPAIR_MIN_SECONDS=600
unpair_signal(){
    up="$(uptime_s)"; c="$(state_get unpair_count)"; first="$(state_get unpair_first_up)"
    case "$c" in ''|*[!0-9]*) c=0;; esac; case "$first" in ''|*[!0-9]*) first="$up";; esac
    [ "$c" -gt 0 ] || first="$up"
    c=$((c+1)); state_set unpair_count "$c"; state_set unpair_first_up "$first"
    [ "$c" -ge "$UNPAIR_CONFIRMATIONS" ] && [ $((up - first)) -ge "$UNPAIR_MIN_SECONDS" ]
}
unpair_signal_reset(){ [ -n "$(state_get unpair_count)" ] && { state_set unpair_count ''; state_set unpair_first_up ''; }; return 0; }

# Keep only the revision the active link points to, plus nothing half-written.
# Covers a power cut between the active-link swap and the old-revision cleanup.
portal_storage_gc(){
    rm -rf "$PORTAL_RUNTIME"/.staging-* "$PORTAL_RUNTIME"/.active-* 2>/dev/null || true
    target="$(readlink "$PORTAL_ACTIVE" 2>/dev/null || true)"
    case "$target" in revisions/rev-[0-9]*) :;; *) return 0;; esac
    [ -f "$PORTAL_RUNTIME/$target/portal.json" ] || return 0
    for d in "$PORTAL_REVISIONS"/rev-*; do
        [ -e "$d" ] || continue
        [ "$d" = "$PORTAL_RUNTIME/$target" ] || rm -rf "$d"
    done
}

# v1.0.7: one media set may use MEDIA_CEILING_PCT of the real usable space:
# free space plus the media Wiflow already holds (active + pending). When an
# update does not fit next to the old set, portal-sync frees the old files
# first (see portal-sync). The budget is reported to WordPress, which enforces
# it at upload time; portal-sync enforces it again before downloading.
MEDIA_CEILING_PCT=80
storage_total_bytes(){ kb="$(df -k "$PORTAL_RUNTIME" 2>/dev/null | awk 'END{print $(NF-4)}')"; case "$kb" in ''|*[!0-9]*) kb=0;; esac; printf '%s' $((kb * 1024)); }
storage_free_bytes(){ kb="$(df -k "$PORTAL_RUNTIME" 2>/dev/null | awk 'END{print $(NF-2)}')"; case "$kb" in ''|*[!0-9]*) kb=0;; esac; printf '%s' $((kb * 1024)); }
media_held_bytes(){ kb="$( { du -sk "$PORTAL_ACTIVE/media/" "$PORTAL_RUNTIME"/pending-*/media 2>/dev/null || true; } | awk '{s+=$1} END{print s+0}')"; case "$kb" in ''|*[!0-9]*) kb=0;; esac; printf '%s' $((kb * 1024)); }
storage_usable_bytes(){ printf '%s' $(( $(storage_free_bytes) + $(media_held_bytes) )); }
media_budget_bytes(){ u="$(storage_usable_bytes)"; printf '%s' $((u / 100 * MEDIA_CEILING_PCT)); }

# v1.0.8: web assets (logo + fonts) for every Wiflow web root. Hard link when the
# filesystem allows it, otherwise copy. Safe to run on every boot.
wiflow_link_assets(){
    shared=/usr/share/wiflow/assets
    for webroot in /www-wiflow /www-wiflow-portal /www-wiflow-portal/runtime; do
        [ -d "$webroot" ] || continue
        mkdir -p "$webroot/assets/fonts" 2>/dev/null || continue
        for rel in wiflow-logo.png fonts/inter-400.woff2 fonts/inter-600.woff2; do
            src="$shared/$rel"; dst="$webroot/assets/$rel"; [ -f "$src" ] || continue
            if [ -f "$dst" ] && [ "$(sha256sum "$src" | cut -d" " -f1)" = "$(sha256sum "$dst" | cut -d" " -f1)" ]; then continue; fi
            rm -f "$dst.tmp"; { ln "$src" "$dst.tmp" 2>/dev/null || cp "$src" "$dst.tmp" 2>/dev/null; } && chmod 644 "$dst.tmp" && mv -f "$dst.tmp" "$dst"
        done
    done
}
# v1.0.25: LuCI is served by the Wiflow web server (10.0.0.1): its static files and
# the cgi-io helpers (upload/download/backup used by LuCI pages) are linked in.
wiflow_link_luci_web(){
    w=/www-wiflow; [ -d "$w" ] || return 0
    if [ -d /www/luci-static ]; then
        [ "$(readlink "$w/luci-static" 2>/dev/null)" = /www/luci-static ] || { rm -rf "$w/luci-static" 2>/dev/null; ln -s /www/luci-static "$w/luci-static" 2>/dev/null || true; }
    fi
    mkdir -p "$w/cgi-bin" 2>/dev/null || return 0
    for n in cgi-upload cgi-download cgi-backup cgi-exec; do
        t="$(readlink -f "/www/cgi-bin/$n" 2>/dev/null || true)"; [ -n "$t" ] && [ -x "$t" ] || continue
        [ "$(readlink "$w/cgi-bin/$n" 2>/dev/null)" = "$t" ] || { rm -f "$w/cgi-bin/$n"; ln -s "$t" "$w/cgi-bin/$n" 2>/dev/null || true; }
    done
}
# v1.0.21: the LuCI Wiflow theme uses the same Inter fonts (shared copy, no duplicate in the package).
wiflow_link_luci_fonts(){
    shared=/usr/share/wiflow/assets/fonts; dir=/www/luci-static/wiflow/fonts
    [ -d /www/luci-static/wiflow ] || return 0
    mkdir -p "$dir" 2>/dev/null || return 0
    for f in inter-400.woff2 inter-600.woff2; do
        src="$shared/$f"; dst="$dir/$f"; [ -f "$src" ] || continue
        if [ -f "$dst" ] && [ "$(sha256sum "$src" | cut -d" " -f1)" = "$(sha256sum "$dst" | cut -d" " -f1)" ]; then continue; fi
        rm -f "$dst.tmp"; { ln "$src" "$dst.tmp" 2>/dev/null || cp "$src" "$dst.tmp" 2>/dev/null; } && chmod 644 "$dst.tmp" && mv -f "$dst.tmp" "$dst"
    done
}
# v1.0.21: LuCI always uses the Wiflow theme. It is the only registered theme
# (System > System > Language and Style offers nothing else) and any change made
# from the shell, LuCI or a theme package (re)install is undone on the next
# check (boot + every 15 s). Cheap no-op when already correct.
LUCI_THEME_URL='/luci-static/wiflow'
luci_theme_enforce(){
    [ -f /etc/config/luci ] || return 0
    [ -f /usr/share/ucode/luci/template/themes/wiflow/header.ut ] || return 0
    cur="$(uci -q get luci.main.mediaurlbase 2>/dev/null || true)"
    reg="$(uci -q get luci.themes.Wiflow 2>/dev/null || true)"
    others="$(uci -q show luci.themes 2>/dev/null | sed -n 's/^luci\.themes\.\([^=]*\)=.*/\1/p' | grep -vx 'Wiflow' || true)"
    [ "$cur" = "$LUCI_THEME_URL" ] && [ "$reg" = "$LUCI_THEME_URL" ] && [ -z "$others" ] && return 0
    uci -q get luci.themes >/dev/null 2>&1 || uci set luci.themes='internal'
    for k in $others; do uci -q delete "luci.themes.$k" >/dev/null 2>&1 || true; done
    uci set "luci.themes.Wiflow=$LUCI_THEME_URL"
    uci set "luci.main.mediaurlbase=$LUCI_THEME_URL"
    uci commit luci >/dev/null 2>&1 || true
    logger -t wiflow-luci-theme "enforced (was: ${cur:-unset}; removed: $(printf '%s' "$others" | tr '\n' ' '))" 2>/dev/null || true
}
# Used only when the whole Wiflow package is removed: LuCI goes back to Bootstrap.
# v1.0.23: LuCI root password defaults to 1234 (owner's decision; change it in
# LuCI > System > Administration). Fresh install: always set. Upgrade / boot: set only
# while root has no password (e.g. after a firmware reset), never over a changed one.
LUCI_DEFAULT_ROOT_PW='1234'
WIFLOW_SHADOW="${WIFLOW_SHADOW:-/etc/shadow}"
luci_root_pw_empty(){
    [ -f "$WIFLOW_SHADOW" ] || return 1
    f="$(awk -F: '$1=="root"{print $2; exit}' "$WIFLOW_SHADOW" 2>/dev/null)"
    [ -z "$f" ] || [ "$f" = '!' ] || [ "$f" = '*' ] || [ "$f" = '!!' ]
}
luci_root_pw_default(){ # $1 = 1: set even when root already has a password (fresh install)
    [ "${1:-0}" = 1 ] || luci_root_pw_empty || return 0
    command -v passwd >/dev/null 2>&1 || return 0
    # Same way LuCI sets it: the password twice on stdin.
    if (echo "$LUCI_DEFAULT_ROOT_PW"; sleep 1; echo "$LUCI_DEFAULT_ROOT_PW") | passwd root >/dev/null 2>&1; then
        command -v logger >/dev/null 2>&1 && logger -t wiflow 'LuCI root password set to the Wiflow default' || true
        return 0
    fi
    return 1
}
luci_theme_release(){
    [ -f /etc/config/luci ] || return 0
    uci -q get luci.themes >/dev/null 2>&1 || uci set luci.themes='internal'
    uci -q delete luci.themes.Wiflow >/dev/null 2>&1 || true
    if [ -d /www/luci-static/bootstrap ]; then
        uci set luci.themes.Bootstrap='/luci-static/bootstrap'
        if [ -d /www/luci-static/bootstrap-dark ]; then uci set luci.themes.BootstrapDark='/luci-static/bootstrap-dark'; fi
        if [ -d /www/luci-static/bootstrap-light ]; then uci set luci.themes.BootstrapLight='/luci-static/bootstrap-light'; fi
        uci set luci.main.mediaurlbase='/luci-static/bootstrap'
    else
        uci -q delete luci.main.mediaurlbase >/dev/null 2>&1 || true
    fi
    uci commit luci >/dev/null 2>&1 || true
}
# v1.0.8: gate codes are compared without spaces/dashes and case-insensitively.
gate_pin_normalize(){ printf '%s' "$1" | tr -d ' \t\r\n-' | tr 'a-z' 'A-Z'; }
gate_diag(){ printf '%s %s len=%s head=%s\n' "$(date +%s)" "$1" "${#2}" "$(printf '%s' "$2" | cut -c1-3)" > /tmp/wiflow-gate-diag 2>/dev/null || true; }

# ---------------------------------------------------------------------------
# v1.0.15: router Internet status for the portal. One small file replaced in
# one step (write tmp + rename): readers never see a partial file and writers
# never wait for a lock. Format: "<1|0> <epoch>".
# ---------------------------------------------------------------------------
NET_STATUS=/tmp/wiflow-net-status
net_status_write(){ _nt="$NET_STATUS.$$"; printf '%s %s\n' "$1" "$(date +%s)" > "$_nt" 2>/dev/null && mv -f "$_nt" "$NET_STATUS" 2>/dev/null; }
# Prints "<value> <age_seconds>"; value is "?" when unknown.
net_status_read(){
    _sv=''; _st=0; read -r _sv _st < "$NET_STATUS" 2>/dev/null || true
    case "$_sv" in 0|1) :;; *) _sv='?';; esac; case "$_st" in ''|*[!0-9]*) _st=0;; esac
    printf '%s %s' "$_sv" $(( $(date +%s) - _st ))
}
# Uplink link state from the system (no network traffic).
net_link_up(){
    case "$(uci -q get wiflow.core.internet_mode 2>/dev/null || true)" in
        wifi) iface_up wiflow_wwan && iface_route_active wiflow_wwan;;
        lan) iface_up wan && iface_route_active wan;;
        *) return 1;;
    esac
}
# One real Internet check, hard limit about 2 s.
net_check_now(){
    if net_link_up && uclient-fetch -q -T 2 -O /dev/null 'https://connectivitycheck.gstatic.com/generate_204' >/dev/null 2>&1; then
        net_status_write 1; return 0
    fi
    net_status_write 0; return 1
}
ms_now(){ awk '{printf "%d", $1*1000}' /proc/uptime 2>/dev/null; }
# Last timing lines for /cgi-bin/diag (own files, no lock).
timing_write(){ _tt="/tmp/wiflow-timing-$1.$$"; printf '%s\n' "$2" > "$_tt" 2>/dev/null && mv -f "$_tt" "/tmp/wiflow-timing-$1" 2>/dev/null; }
# Refresh the status when older than $1 seconds (or unknown). Only one check
# runs at a time; anyone else simply keeps the current value (never waits).
net_refresh_if_stale(){
    _nm="$1"; set -- $(net_status_read)
    [ "$1" != '?' ] && [ "$2" -lt "$_nm" ] && return 0
    _nl=/tmp/wiflow-netcheck.lock
    if ! mkdir "$_nl" 2>/dev/null; then
        # A check killed mid-way must not block future checks.
        [ -n "$(find "$_nl" -maxdepth 0 -mmin +1 2>/dev/null)" ] && rmdir "$_nl" 2>/dev/null
        return 0
    fi
    net_check_now >/dev/null 2>&1; _nr=$?; rmdir "$_nl" 2>/dev/null; return $_nr
}
# One pass of the background check (portal-session-loop, every 5 s).
net_maintain(){
    if net_link_up; then
        set -- $(net_status_read)
        if [ "$1" = 1 ]; then net_refresh_if_stale 30; else net_refresh_if_stale 5; fi
    else
        set -- $(net_status_read); [ "$1" = 0 ] && [ "$2" -lt 30 ] || net_status_write 0
    fi
    return 0
}
