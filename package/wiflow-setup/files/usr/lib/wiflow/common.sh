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
# Volatile ACK receipt: retry once after reboot; never write every heartbeat to flash.
PORTAL_ACK_CONFIRMED=/tmp/wiflow-portal-ack-confirmed-revision
UPLINK_TXN=$ROOT/uplink-txn
RESUME_DIR=/tmp/wiflow-management-resume
# Production WordPress device API is package-owned, not user-configurable.
WIFLOW_REST_ROOT='https://projify.io.vn/wiflow/wp-json'
WIFLOW_DEVICE_API="$WIFLOW_REST_ROOT/devices"
WIFLOW_PORTAL_API="$WIFLOW_REST_ROOT/portal"
WIFLOW_AGENT_VERSION='1.0.0'
WIFLOW_DATA_GENERATION='4'
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

wifi_uplink_associated(){
    want="${1:-}"
    command -v iw >/dev/null 2>&1 || return 1
    for ifn in $(iw dev 2>/dev/null | awk '/Interface /{i=$2}/type managed/{print i}'); do
        link="$(iw dev "$ifn" link 2>/dev/null || true)"
        printf '%s\n' "$link" | grep -q '^Connected to ' || continue
        [ -z "$want" ] && return 0
        got="$(printf '%s\n' "$link" | sed -n 's/^[[:space:]]*SSID: //p' | head -n1)"
        [ "$got" = "$want" ] && return 0
    done
    return 1
}

wifi_ssid_visible(){
    radio="$1"; want="$2"; tmp="/tmp/wiflow-visible.$$"
    ( /usr/bin/iwinfo-ucode "$radio" scan > "$tmp" 2>/dev/null ) & p=$!
    ( sleep 6; kill "$p" 2>/dev/null ) & w=$!
    wait "$p" 2>/dev/null || true; kill "$w" 2>/dev/null || true
    awk -v want="$want" '/ESSID: /{s=$0;sub(/^.*ESSID: "/,"",s);sub(/".*$/,"",s);if(s==want){ok=1;exit}} END{exit(ok?0:1)}' "$tmp" 2>/dev/null
    rc=$?; rm -f "$tmp"; return "$rc"
}

setup_username(){ u="$(uci -q get wiflow.core.setup_username 2>/dev/null || true)"; [ -n "$u" ] && printf '%s' "$u" || printf 'wiflow'; }
setup_check_login(){
    u="$1"; p="$2"; stored_hash="$(uci -q get wiflow.core.setup_password_hash 2>/dev/null || true)"; stored_salt="$(uci -q get wiflow.core.setup_password_salt 2>/dev/null || true)"
    [ -n "$stored_hash" ] && [ -n "$stored_salt" ] || return 1
    [ "$u" = "$(setup_username)" ] || return 1
    got="$(printf '%s:%s' "$stored_salt" "$p" | sha256sum | awk '{print $1}')"
    [ "$got" = "$stored_hash" ]
}
setup_set_login(){
    u="$1"; p="$2"
    printf '%s' "$u" | grep -Eq '^[A-Za-z0-9._-]{3,32}$' || return 2
    plen="$(printf '%s' "$p" | wc -c | tr -d ' ')"; case "$plen" in ''|*[!0-9]*) return 2;; esac
    [ "$plen" -ge 12 ] && [ "$plen" -le 128 ] || return 2
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
portal_nft_ready(){
    /usr/sbin/nft list set inet fw4 wiflow_portal_authed >/dev/null 2>&1 &&
    /usr/sbin/nft list set inet fw4 wiflow_portal_granted >/dev/null 2>&1
}
portal_nft_grant_del(){
    ipx="$1"; mac="$2"
    printf 'delete element inet fw4 wiflow_portal_granted { %s . %s }\n' "$ipx" "$mac" | /usr/sbin/nft -f - >/dev/null 2>&1 || true
}
portal_nft_grant_add(){
    ipx="$1"; mac="$2"; valid_guest_ip "$ipx" || return 1; portal_nft_ready || return 1
    portal_nft_grant_del "$ipx" "$mac"
    printf 'add element inet fw4 wiflow_portal_granted { %s . %s timeout 30m }\n' "$ipx" "$mac" | /usr/sbin/nft -f - >/dev/null 2>&1 || return 1
    portal_nft_pair_granted "$ipx" "$mac"
}
portal_nft_pair_granted(){
    ipx="$1"; mac="$2"
    /usr/sbin/nft list set inet fw4 wiflow_portal_granted 2>/dev/null | grep -Fiq "$ipx . $mac"
}
portal_nft_del(){ ipx="$1"; mac="$2"; printf 'delete element inet fw4 wiflow_portal_authed { %s . %s }\n' "$ipx" "$mac" | /usr/sbin/nft -f - >/dev/null 2>&1 || true; }
# Unlike portal_nft_pair_authorized, this helper MUST prove a successful nft
# readback. A failed list/read command is never proof of revocation.
portal_nft_pair_revoked(){
    ipx="$1"; mac="$2"
    dump="$(/usr/sbin/nft list set inet fw4 wiflow_portal_authed 2>/dev/null)" || return 1
    ! printf '%s\n' "$dump" | grep -Fiq "$ipx . $mac"
}

portal_nft_add(){
    ipx="$1"; mac="$2"; valid_guest_ip "$ipx" || return 1; portal_nft_ready || return 1
    portal_nft_del "$ipx" "$mac"
    printf 'add element inet fw4 wiflow_portal_authed { %s . %s timeout 30d }\n' "$ipx" "$mac" | /usr/sbin/nft -f - >/dev/null 2>&1 || return 1
    portal_nft_pair_authorized "$ipx" "$mac"
}
portal_nft_pair_authorized(){ ipx="$1"; mac="$2"; /usr/sbin/nft list set inet fw4 wiflow_portal_authed 2>/dev/null | grep -Fiq "$ipx . $mac"; }
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
    : > "$HEARTBEAT_KICK" 2>/dev/null || true
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
    # Do not advertise CAPPORT (DHCPv4 Option 114) yet. RFC 8908 requires
    # an HTTPS API and TLS user-portal URL with a verifiable certificate.
    # Advertising the legacy HTTP endpoint would break standards-aware clients.
    # Keep HTTP captive fallback until a separately audited TLS deployment.
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
    # Android Private DNS uses DoT over TCP/853; UDP/853 is not part of the
    # pre-authorized contract and would open an additional WAN tunnel path.
    uci add_list firewall.wiflow_guest_private_dns.proto='tcp'
    uci set firewall.wiflow_guest_private_dns.target='ACCEPT'

    uci -q delete firewall.wiflow_guest_dhcp >/dev/null 2>&1 || true
    uci set firewall.wiflow_guest_dhcp='rule'
    uci set firewall.wiflow_guest_dhcp.name='Wiflow-Guest-DHCP'
    uci set firewall.wiflow_guest_dhcp.src='wiflow_guest'
    uci set firewall.wiflow_guest_dhcp.proto='udp'
    uci set firewall.wiflow_guest_dhcp.dest_port='67-68'
    uci set firewall.wiflow_guest_dhcp.target='ACCEPT'

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

    # Fail closed while Portal has no active validated snapshot.
    # The captive firewall is the SOLE owner of the guest->WAN forwarding.
    uci -q delete firewall.wiflow_guest_wan >/dev/null 2>&1 || true
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
