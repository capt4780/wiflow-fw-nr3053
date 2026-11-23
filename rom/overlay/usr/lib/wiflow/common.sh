#!/bin/sh
ROOT=/etc/wiflow
STATE=/tmp/wiflow-state
STATE_LOCK=/tmp/wiflow-state.lock
CLIENT_SESSIONS=/tmp/wiflow-client-sessions
EVENT_QUEUE=/tmp/wiflow-events.queue
EVENT_LOCK=/tmp/wiflow-events.lock
HEARTBEAT_KICK=/tmp/wiflow-heartbeat-kick
PORTAL_RUNTIME=/www-wiflow-portal/runtime
PORTAL_REVISIONS=$PORTAL_RUNTIME/revisions
PORTAL_ACTIVE=$PORTAL_RUNTIME/active
# Production WordPress device API is package-owned, not user-configurable.
WIFLOW_REST_ROOT="${WIFLOW_REST:-https://wiflow.projifylab.com/wp-json}"
WIFLOW_PORTAL_API="$WIFLOW_REST_ROOT/portal"
WIFLOW_AGENT_VERSION="$( { tr -d ' \r\n' < /etc/wiflow_release; } 2>/dev/null)"; WIFLOW_AGENT_VERSION="${WIFLOW_AGENT_VERSION:-1.1.0}"
WIFLOW_MODEL_CODE='NR3053'; WIFLOW_MODEL_NAME='Wiflow Router'
WIFLOW_DATA_GENERATION='4'
[ -d "$ROOT" ] && [ -d "$CLIENT_SESSIONS" ] && [ -d "$PORTAL_REVISIONS" ] || {
    mkdir -p "$ROOT" "$CLIENT_SESSIONS" "$PORTAL_REVISIONS" 2>/dev/null || true
    chmod 700 "$ROOT" "$CLIENT_SESSIONS" 2>/dev/null || true
}
redirect(){ printf 'Status: 302 Found\r\nLocation: %s\r\nCache-Control: no-store\r\n\r\n' "$1"; exit 0; }
read_body(){ n="${CONTENT_LENGTH:-0}"; case "$n" in ''|*[!0-9]*) n=0;; esac; [ "$n" -le 16384 ] || n=16384; BODY="$(dd bs=1 count="$n" 2>/dev/null)"; }
urldecode(){ /usr/sbin/uhttpd -d "$(printf '%s' "$1" | tr '+' ' ')" 2>/dev/null; }
param(){ key="$1"; data="${BODY:-${QUERY_STRING:-}}"; old="$IFS"; IFS='&'; for kv in $data; do k="${kv%%=*}"; v="${kv#*=}"; if [ "$k" = "$key" ]; then IFS="$old"; urldecode "$v"; return 0; fi; done; IFS="$old"; return 1; }
new_token(){ (dd if=/dev/urandom bs=32 count=1 2>/dev/null; date +%s; echo $$) | sha256sum | awk '{print $1}'; }
# v1.0.26: char by char (BusyBox awk and gawk treat backslashes in gsub
# replacements differently; the old gsub version left quotes unescaped on the router).
JSON_ESC_AWK='function esc(s,  o,i,c){o="";for(i=1;i<=length(s);i++){c=substr(s,i,1);if(c=="\\")o=o "\\\\";else if(c=="\"")o=o "\\\"";else if(c=="\r")o=o "\\r";else if(c=="\n")o=o "\\n";else if(c=="\t")o=o "\\t";else o=o c}return o}'
json_escape(){ printf '%s' "$1" | awk "$JSON_ESC_AWK"' BEGIN{ORS="";n=0} {if(n++)printf "\\n";printf "%s",esc($0)}'; }

state_set(){ k="$1"; v="$2"; i=0; while ! mkdir "$STATE_LOCK" 2>/dev/null; do i=$((i+1)); if [ "$i" -ge 3 ]; then rmdir "$STATE_LOCK" 2>/dev/null || true; i=0; fi; sleep 1; done; tmp="$STATE.$$"; { [ -f "$STATE" ] && grep -v "^$k=" "$STATE" 2>/dev/null || true; printf '%s=%s\n' "$k" "$v"; } > "$tmp"; mv "$tmp" "$STATE"; rmdir "$STATE_LOCK" 2>/dev/null || true; }
state_get(){ [ -f "$STATE" ] && awk -F= -v k="$1" '$1==k{sub(/^[^=]*=/,"");print;exit}' "$STATE"; }

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
    rm -rf "$PORTAL_REVISIONS" "$PORTAL_ACTIVE" "$PORTAL_RUNTIME"/.staging-* "$PORTAL_RUNTIME"/.active-* "$PORTAL_RUNTIME"/pending-* "$PORTAL_RUNTIME"/partial 2>/dev/null || true
    mkdir -p "$PORTAL_REVISIONS" 2>/dev/null || true
    uci set wiflow.core.portal_revision='0'
    uci set wiflow.core.portal_sync_status='idle'
    uci set wiflow.core.portal_sync_error=''
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
    printf 'add element %s authed { %s . %s timeout %ss }\n' "$CAPTIVE_TABLE" "$ipx" "$mac" "$(guest_idle_secs)" | /usr/sbin/nft -f - >/dev/null 2>&1 || return 1
    portal_nft_pair_authorized "$ipx" "$mac"
}
# v3.4: how long an authorized guest may stay silent. Every packet the guest sends renews the timer inside the
# firewall (see portal-firewall), so nothing has to watch the guest; silence for this long ends the access.
guest_idle_secs(){ _gi="$(uci -q get wiflow.core.guest_idle_min 2>/dev/null)"; case "$_gi" in ''|*[!0-9]*) _gi=30;; esac; [ "$_gi" -ge 5 ] 2>/dev/null && [ "$_gi" -le 1440 ] || _gi=30; printf '%s' $((_gi * 60)); }
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

# v2.4: guest information typed into the popup form. One JSON object per line, kept in RAM
# until WordPress has taken it (and dropped when the router leaves its account).
GUEST_QUEUE=/tmp/wiflow-guests.queue
guest_enqueue(){
    _event_lock || return 1
    printf '%s\n' "$1" >> "$GUEST_QUEUE"
    lines="$(wc -l < "$GUEST_QUEUE" 2>/dev/null | tr -d ' ')"; case "$lines" in ''|*[!0-9]*) lines=0;; esac
    if [ "$lines" -gt 500 ]; then tmp="$GUEST_QUEUE.trim"; tail -n 400 "$GUEST_QUEUE" > "$tmp" 2>/dev/null || true; mv "$tmp" "$GUEST_QUEUE"; fi
    chmod 600 "$GUEST_QUEUE" 2>/dev/null || true
    _event_unlock
}
guest_prepare_batch(){
    out="$1"; limit="${2:-20}"; : > "$out"
    _event_lock || { echo 0; return 1; }
    [ -f "$GUEST_QUEUE" ] && head -n "$limit" "$GUEST_QUEUE" > "$out" 2>/dev/null || true
    _event_unlock
    wc -l < "$out" | tr -d ' '
}
guest_ack_batch(){
    count="$1"; case "$count" in ''|*[!0-9]*) return 1;; esac; [ "$count" -gt 0 ] || return 0
    _event_lock || return 1
    if [ -f "$GUEST_QUEUE" ]; then tmp="$GUEST_QUEUE.$$"; awk -v n="$count" 'NR>n' "$GUEST_QUEUE" > "$tmp" 2>/dev/null || : > "$tmp"; mv "$tmp" "$GUEST_QUEUE"; chmod 600 "$GUEST_QUEUE" 2>/dev/null || true; fi
    _event_unlock
}

# v2.4: guests (hashed device id only) who already filled the form: they get the banner popup instead of the form.
# Kept in flash, at most GUEST_KNOWN_MAX entries (the oldest drop first); a factory reset clears it.
GUEST_KNOWN=/etc/wiflow/guests.known
GUEST_KNOWN_MAX=20000
guest_known(){ [ -s "$GUEST_KNOWN" ] && grep -qxF -- "$1" "$GUEST_KNOWN" 2>/dev/null; }
guest_remember(){
    case "$1" in ''|*[!0-9A-Za-z]*) return 1;; esac
    guest_known "$1" && return 0
    _event_lock || return 1
    mkdir -p /etc/wiflow 2>/dev/null || true
    printf '%s\n' "$1" >> "$GUEST_KNOWN"
    lines="$(wc -l < "$GUEST_KNOWN" 2>/dev/null | tr -d ' ')"; case "$lines" in ''|*[!0-9]*) lines=0;; esac
    if [ "$lines" -gt $((GUEST_KNOWN_MAX + 500)) ]; then tmp="$GUEST_KNOWN.trim"; tail -n "$GUEST_KNOWN_MAX" "$GUEST_KNOWN" > "$tmp" 2>/dev/null && mv "$tmp" "$GUEST_KNOWN"; fi
    _event_unlock
}

website_url_valid(){ case "$1" in http://*|https://*) return 0;; *) return 1;; esac; }
website_host_from_url(){ printf '%s' "$1" | sed -n 's#^https\{0,1\}://\([^/:?]*\).*#\1#p'; }
portal_active_config(){ [ -f "$PORTAL_ACTIVE/portal.json" ] && printf '%s' "$PORTAL_ACTIVE/portal.json"; }

# ---------------------------------------------------------------------------
# v1.0.6: monotonic time, guest session persistence, confirmed unpair.
# ---------------------------------------------------------------------------
uptime_s(){ u="$(cut -d. -f1 /proc/uptime 2>/dev/null)"; case "$u" in ''|*[!0-9]*) u=0;; esac; printf '%s' "$u"; }

# v3.4: guest sessions live in RAM only. A restart of the router starts every guest from the portal again; a restart
# of the service keeps them (RAM and the firewall table stay). The firewall decides who is still authorized; once a
# minute one pass (sessions_sweep) brings the session files in line with it. No guest is polled.
LEASE_SECS=14400
# New session for a guest: prints "cid|sid".
session_open(){
    _so_mac="$1"; _so_ip="$2"; _so_f="$(client_file_for_mac "$_so_mac")" || return 1; _so_now="$(date +%s)"
    _so_cid="$(client_id_for_mac "$_so_mac")"; _so_sid="$(new_token | cut -c1-24)"
    client_session_write "$_so_f" "$_so_mac" "$_so_cid" "$_so_sid" "$_so_ip" "$_so_now" 0 "$_so_now" 0 || return 1
    event_enqueue connected "$_so_cid" "$_so_sid" "$_so_now" || true
    printf '%s|%s' "$_so_cid" "$_so_sid"
}
# The guest's access ended (silent too long): report it once.
guest_gone(){
    _gf="$1"; _gm="$2"; _gc="$3"; _gs="$4"; _gi="$5"; _gcn="$6"; _gl="$7"; _gw="$8"
    client_session_write "$_gf" "$_gm" "$_gc" "$_gs" "$_gi" "$_gcn" 0 "$_gl" "$_gw" || return 1
    event_enqueue disconnected "$_gc" "$_gs" "$_gw" || true
    : > "$HEARTBEAT_KICK" 2>/dev/null || true
}
# Once a minute (portal-session-loop): sessions against the firewall set and the DHCP leases. In a quiet minute this is
# three programs in total (nft, awk, one more awk), however many guests there are.
sessions_sweep(){
    portal_nft_ready || return 0
    _sw_now="$(date +%s)"; _sw_idle="$(guest_idle_secs)"; _sw_lim=$(( $(cfg_num guest_session_min 0) * 60 )); _sw_tv=0
    [ "$_sw_lim" -gt 0 ] && time_valid && _sw_tv=1
    set -- "$CLIENT_SESSIONS"/*
    if [ -e "$1" ]; then
        { /usr/sbin/nft list set $CAPTIVE_TABLE authed 2>/dev/null | grep -oEi '10\.10\.10\.[0-9]+ \. ([0-9a-f]{2}:){5}[0-9a-f]{2}' | tr 'a-f' 'A-F' | sed 's/^/S /'
          cat "$CLIENT_SESSIONS"/* 2>/dev/null; } | awk -F'|' -v now="$_sw_now" -v idle="$_sw_idle" -v lim="$_sw_lim" -v tv="$_sw_tv" '
            /^S / { split($1, a, " "); inset[a[4] " " a[2]] = 1; next }
            NF >= 8 {
                au = $6 + 0; ab = $8 + 0; k = $1 " " $4
                if (au > 0) {
                    if (!(k in inset)) { w = now - idle; if (w < au) w = au; print "GONE|" $0 "|" w }
                    else if (lim > 0 && tv && au > 1700000000 && now - au >= lim) print "LIM|" $0
                } else if (ab > 0) { if (now - ab >= 7200) print "DEL|" $0 }
                else if (now - $7 >= 1800) print "IDLE|" $0
            }' | while IFS='|' read -r _a _m _c _s _i _cn _au _l _ab _w; do
                _f="$(client_file_for_mac "$_m")" || continue
                case "$_a" in
                    GONE) guest_gone "$_f" "$_m" "$_c" "$_s" "$_i" "$_cn" "$_l" "${_w:-$_sw_now}";;
                    LIM) portal_nft_del "$_i" "$_m"; client_session_write "$_f" "$_m" "$_c" "$_s" "$_i" "$_cn" 0 "$_sw_now" 0; wlog guest "Khách hết thời gian sử dụng, cần xác nhận lại";;
                    DEL) rm -f "$_f";;
                    IDLE) event_enqueue disconnected "$_c" "$_s" "$_l"; rm -f "$_f";;
                esac
            done
    fi
    # Guests that just got a DHCP lease are new visitors: a session and the "connected" event.
    [ -s /tmp/dhcp.leases ] || return 0
    awk -v now="$_sw_now" -v ls="$LEASE_SECS" '$1 + 0 > 0 && $1 - ls >= now - 150 { print toupper($2), $3 }' /tmp/dhcp.leases 2>/dev/null | while read -r _m _i; do
        valid_guest_ip "$_i" || continue
        _f="$(client_file_for_mac "$_m")" || continue
        [ -f "$_f" ] || session_open "$_m" "$_i" >/dev/null
    done
    return 0
}
# v3.4: the captive rules come back after being off (safe mode, plan ended, no content): the guests who were online
# meanwhile had the Internet without the portal. They keep it (the same idle timer applies); nothing is recorded for
# them. After a restart of the router the lease file is empty, so everybody starts from the portal.
guest_carry_over(){
    [ -s /tmp/dhcp.leases ] || return 0
    _co_now="$(date +%s)"; _co_t="$(guest_idle_secs)"; _co_n=0; _co_s="/tmp/wiflow-carry.$$"; : > "$_co_s"
    while read -r _ex _mac _ip _rest; do
        valid_guest_ip "$_ip" || continue
        case "$_ex" in ''|*[!0-9]*) continue;; esac
        [ "$_ex" = 0 ] || [ "$_ex" -gt "$_co_now" ] || continue
        _mac="$(printf '%s' "$_mac" | tr 'a-f' 'A-F')"
        _f="$(client_file_for_mac "$_mac")" || continue
        printf 'add element %s authed { %s . %s timeout %ss }\n' "$CAPTIVE_TABLE" "$_ip" "$_mac" "$_co_t" >> "$_co_s"
        if [ -f "$_f" ]; then
            IFS='|' read -r _m2 _c2 _s2 _i2 _cn2 _a2 _l2 _ab2 < "$_f" 2>/dev/null || _s2=''
            [ -n "${_s2:-}" ] || { rm -f "$_f"; _c2="$(client_id_for_mac "$_mac")"; _s2="$(new_token | cut -c1-24)"; _cn2="$_co_now"; _a2=0; }
            case "${_a2:-0}" in ''|0) _a2="$_co_now";; esac
        else _c2="$(client_id_for_mac "$_mac")"; _s2="$(new_token | cut -c1-24)"; _cn2="$_co_now"; _a2="$_co_now"; fi
        client_session_write "$_f" "$_mac" "$_c2" "$_s2" "$_ip" "${_cn2:-$_co_now}" "$_a2" "$_co_now" 0 && _co_n=$((_co_n+1))
    done < /tmp/dhcp.leases
    [ -s "$_co_s" ] && /usr/sbin/nft -f "$_co_s" >/dev/null 2>&1
    rm -f "$_co_s"
    [ "$_co_n" = 0 ] || wlog portal "Cổng chào bật lại: giữ mạng cho $_co_n khách đang dùng"
    return 0
}

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
# ---------------------------------------------------------------------------
# Router Internet status: ONE checker (net_check_now, run by portal-session-loop) writes it, everybody else reads it
# (portal pages, guest sign-in, the agent that reports to WordPress and runs the recovery). One small file replaced
# in one step (write tmp + rename): readers never see a partial file and writers never wait for a lock.
# Format: "<1|0> <uptime seconds> <latency ms>" (latency 0 when unknown, -1 when offline). The time is the router's
# uptime, so a clock change (the time is set from WordPress after a start) never makes the status look old or new.
# ---------------------------------------------------------------------------
NET_STATUS=/tmp/wiflow-net-status
net_status_write(){ read -r _un _ < /proc/uptime 2>/dev/null || _un=0; _nt="$NET_STATUS.$$"; printf '%s %s %s\n' "$1" "${_un%%.*}" "${2:--1}" > "$_nt" 2>/dev/null && mv -f "$_nt" "$NET_STATUS" 2>/dev/null; }
# Sets NS_V (1, 0 or ?), NS_AGE (seconds since the check) and NS_MS (latency); starts no program.
net_status_load(){
    NS_V=''; NS_T=0; NS_MS=-1; read -r NS_V NS_T NS_MS 2>/dev/null < "$NET_STATUS" || true
    case "$NS_V" in 0|1) :;; *) NS_V='?';; esac; case "$NS_T" in ''|*[!0-9]*) NS_T=0;; esac; case "$NS_MS" in ''|*[!0-9]*) NS_MS=-1;; esac
    read -r _un _ < /proc/uptime 2>/dev/null || _un=0; NS_AGE=$(( ${_un%%.*} - NS_T ))
    [ "$NS_T" -gt 0 ] && [ "$NS_AGE" -ge 0 ] || NS_AGE=999999
}
# Prints "<value> <age_seconds> <latency_ms>"; value is "?" when unknown.
net_status_read(){ net_status_load; printf '%s %s %s' "$NS_V" "$NS_AGE" "$NS_MS"; }
# One real Internet check, about 3 s at most. Three independent tests run side by side and any one answering means
# "online": HTTPS to the connectivity-check server (also the latency), a TCP connect to 1.1.1.1:443 (needs no valid
# clock) and a plain HTTP request (needs no TLS). A weak source WiFi loses a check now and then, so the first failed
# round does not flip the status to offline; the second one in a row does. A lost default route is offline at once.
NET_FAILS=/tmp/wiflow-net-fails
net_check_now(){
    _nd="/tmp/wiflow-netchk.$$"; rm -rf "$_nd"; mkdir -p "$_nd" 2>/dev/null || return 1
    if net_link_up; then
        ( _o="$(curl -s -o /dev/null -m 3 --connect-timeout 3 -w '%{http_code} %{time_total}' 'https://connectivitycheck.gstatic.com/generate_204' 2>/dev/null)"; [ "${_o%% *}" = 204 ] && printf '%s\n' "$_o" > "$_nd/a" ) &
        ( _tc="$(curl -sk -m 3 --connect-timeout 3 -o /dev/null -w '%{time_connect}' 'https://1.1.1.1/' 2>/dev/null)"; awk -v t="${_tc:-0}" 'BEGIN{exit !(t+0>0)}' && printf '%s\n' "$_tc" > "$_nd/b" ) &
        ( [ "$(curl -s -m 3 --connect-timeout 3 'http://detectportal.firefox.com/success.txt' 2>/dev/null | tr -d '\r\n')" = success ] && : > "$_nd/c" ) &
        wait
    fi
    if [ -e "$_nd/a" ] || [ -e "$_nd/b" ] || [ -e "$_nd/c" ]; then
        _ms="$( { awk 'NF>=2{print $2}' "$_nd/a" 2>/dev/null; cat "$_nd/b" 2>/dev/null; } | awk '$1+0>0{printf "%d", $1*1000+0.5; exit}')"
        rm -rf "$_nd"; rm -f "$NET_FAILS"; net_status_write 1 "${_ms:-0}"; return 0
    fi
    rm -rf "$_nd"
    _nf="$(cat "$NET_FAILS" 2>/dev/null)"; case "$_nf" in ''|*[!0-9]*) _nf=0;; esac; _nf=$((_nf+1)); printf '%s\n' "$_nf" > "$NET_FAILS" 2>/dev/null
    if [ "$_nf" -ge 2 ] || ! net_link_up; then net_status_write 0 -1; fi
    return 1
}
# Something disruptive just ran (WiFi reload, network or firewall restart; not the recovery's own steps, they have their own timers): the self-recovery waits
# a while before it adds another one. The time is kept as uptime seconds, so a clock change cannot confuse it.
DISRUPT_MARK=/tmp/wiflow-disrupt
disrupt_mark(){ printf '%s\n' "$(uptime_s)" > "$DISRUPT_MARK" 2>/dev/null || true; }
# v3.1: run a command for at most $1 seconds (no dependency on a timeout applet); 124 when it was stopped.
run_limited(){
    _rs="$1"; shift; "$@" & _rp=$!; _ri=0
    while kill -0 "$_rp" 2>/dev/null; do
        _ri=$((_ri+1)); [ "$_ri" -le $((_rs*5)) ] || { kill "$_rp" 2>/dev/null; wait "$_rp" 2>/dev/null; return 124; }
        sleep 0.2 2>/dev/null || sleep 1
    done
    wait "$_rp"
}
# v3.1: a guest is only let in (and remembered) when the way out really works:
# the router's Internet, DNS through the router, and private DNS (DoT, port 853).
# The checks run together, about 4 s at most. v3.4: any one of four public DoT servers answering is enough; when none
# answers twice in a row while Internet and DNS are fine, the network blocks port 853 and the DoT check is skipped for
# 30 minutes (the log says so). wiflow.core.grant_dot=0 never requires DoT.
grant_verify(){
    _gd="/tmp/wiflow-grant.$$"; rm -rf "$_gd"; mkdir -p "$_gd" 2>/dev/null || return 0
    set -- $(net_status_read)
    if [ "$1" = 1 ] && [ "$2" -lt 10 ]; then : > "$_gd/net"
    else ( net_check_now >/dev/null 2>&1 && : > "$_gd/net" ) & fi
    ( run_limited 3 nslookup connectivitycheck.gstatic.com 127.0.0.1 >/dev/null 2>&1 && : > "$_gd/dns" ) &
    for _dt in 1.1.1.1 8.8.8.8 9.9.9.9 8.8.4.4; do
        ( _tc="$(curl -sk -m 4 --connect-timeout 3 -o /dev/null -w '%{time_connect}' "https://$_dt:853/" 2>/dev/null)"
          awk -v t="${_tc:-0}" 'BEGIN{exit !(t+0>0)}' && : > "$_gd/dot.$_dt" ) &
    done
    wait
    _gn=0; _gs=0; _gt=0
    [ -e "$_gd/net" ] && _gn=1; [ -e "$_gd/dns" ] && _gs=1; ls "$_gd"/dot.* >/dev/null 2>&1 && _gt=1
    rm -rf "$_gd"
    _gq=1; [ "$(uci -q get wiflow.core.grant_dot 2>/dev/null)" = 0 ] && _gq=0
    _gk="$(num_or0 "$(state_get dot_skip_until)")"; [ "$_gk" -gt 0 ] && [ "$(uptime_s)" -lt "$_gk" ] && _gq=0
    if [ "$_gt" = 1 ]; then state_set dot_fails 0
    elif [ "$_gn" = 1 ] && [ "$_gs" = 1 ] && [ "$_gq" = 1 ]; then
        _gf=$(( $(num_or0 "$(state_get dot_fails)") + 1 )); state_set dot_fails "$_gf"
        [ "$_gf" -lt 2 ] || { state_set dot_skip_until $(( $(uptime_s) + 1800 )); state_set dot_fails 0; wlog portal 'DNS riêng tư (cổng 853) không đi được: tạm không yêu cầu trong 30 phút'; }
    fi
    state_set grant_last "$(date +%s) net=$_gn dns=$_gs dot=$_gt" 2>/dev/null || true
    [ "$_gn" = 1 ] && [ "$_gs" = 1 ] && { [ "$_gt" = 1 ] || [ "$_gq" = 0 ]; } && return 0
    wlog portal "Không cấp mạng cho khách: Internet=$_gn DNS=$_gs DNS riêng tư=$_gt"
    return 1
}
# v3.1: the router lost its Internet for good: every guest must sign in again.
guest_revoke_all(){
    [ -n "$(ls "$CLIENT_SESSIONS" 2>/dev/null)" ] || { /usr/sbin/nft flush set $CAPTIVE_TABLE authed >/dev/null 2>&1 || true; return 0; }
    for _f in "$CLIENT_SESSIONS"/*; do
        [ -f "$_f" ] || continue
        IFS='|' read -r _m _c _s _i _cn _au _l _ab < "$_f" 2>/dev/null || continue
        [ "${_au:-0}" != 0 ] || continue
        client_session_write "$_f" "$_m" "$_c" "$_s" "$_i" "$_cn" 0 "$(date +%s)" "${_ab:-0}" || true
    done
    /usr/sbin/nft flush set $CAPTIVE_TABLE authed >/dev/null 2>&1 || true
    wlog portal "Mất Internet quá lâu: khách phải đăng nhập lại portal"
}
# v3.1: called every 5 s with the background check: Internet gone for 5 minutes -> guests sign in again.
NET_DOWN_SINCE=/tmp/wiflow-net-down-since
net_down_tick(){
    net_status_load
    if [ "$NS_V" = 0 ]; then
        read -r _dn _ < /proc/uptime 2>/dev/null || _dn=0; _dn="${_dn%%.*}"
        [ -f "$NET_DOWN_SINCE" ] || printf '%s\n' "$_dn" > "$NET_DOWN_SINCE"
        read -r _ds _dr < "$NET_DOWN_SINCE" 2>/dev/null || return 0
        case "$_ds" in ''|*[!0-9]*) return 0;; esac
        if [ $(( _dn - _ds )) -ge "${NET_DOWN_REVOKE:-300}" ] && [ "${_dr:-}" != done ]; then
            portal_nft_ready && guest_revoke_all
            printf '%s done\n' "$_ds" > "$NET_DOWN_SINCE"
        fi
    elif [ "$NS_V" = 1 ]; then [ -f "$NET_DOWN_SINCE" ] && rm -f "$NET_DOWN_SINCE"; fi
    return 0
}
ms_now(){ awk '{printf "%d", $1*1000}' /proc/uptime 2>/dev/null; }
# Last timing lines for /cgi-bin/diag (own files, no lock).
timing_write(){ _tt="/tmp/wiflow-timing-$1.$$"; printf '%s\n' "$2" > "$_tt" 2>/dev/null && mv -f "$_tt" "/tmp/wiflow-timing-$1" 2>/dev/null; }
# Refresh the status when older than $1 seconds (or unknown). Only one check
# runs at a time; anyone else simply keeps the current value (never waits).
net_refresh_if_stale(){
    _nm="$1"; net_status_load
    [ "$NS_V" != '?' ] && [ "$NS_AGE" -lt "$_nm" ] && return 0
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
    net_status_load
    if net_link_up; then
        if [ "$NS_V" = 1 ]; then net_refresh_if_stale "${WIFLOW_NET_ON:-30}"; else net_refresh_if_stale 5; fi
    else
        [ "$NS_V" = 0 ] && [ "$NS_AGE" -lt 30 ] || net_status_write 0 -1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# v1.0.26: RAM log, Internet auto (cable first, source WiFi as backup), guest
# controls (speed, session time, max guests, opening hours), statistics and a
# self-repair watchdog. Everything here lives in RAM (/tmp): no flash wear.
# ---------------------------------------------------------------------------
WLOG=/tmp/wiflow-log
# One line per event: epoch|area|message; kept to about 250 lines.
wlog(){
    _wm="$(printf '%s' "$2" | tr '|\n' '/ ')"
    printf '%s|%s|%s\n' "$(date +%s)" "$1" "$_wm" >> "$WLOG" 2>/dev/null || return 0
    _ws="$(wc -c < "$WLOG" 2>/dev/null | tr -d ' ')"; case "$_ws" in ''|*[!0-9]*) _ws=0;; esac
    if [ "$_ws" -gt 48000 ]; then tail -n 250 "$WLOG" > "$WLOG.t.$$" 2>/dev/null && mv -f "$WLOG.t.$$" "$WLOG"; fi
    logger -t "wiflow-$1" "$_wm" 2>/dev/null || true
    return 0
}
tcp_listening(){ addr="$1"; port="$2"; [ -r /proc/net/tcp ] || return 1; awk -v target="${addr}:${port}" '$2 == target && $4 == "0A" {ok=1} END{exit(ok?0:1)}' /proc/net/tcp; }
cfg_num(){ _cv="$(uci -q get "wiflow.core.$1" 2>/dev/null || true)"; case "$_cv" in ''|*[!0-9]*) _cv="$2";; esac; [ "${#_cv}" -le 7 ] || _cv="$2"; printf '%s' "$_cv"; }
num_or0(){ case "$1" in ''|*[!0-9]*) printf 0;; *) printf '%s' "$1";; esac; }
# --- Guest controls -----------------------------------------------------------
# Time is trusted only after NTP synced (hotplug.d/ntp) or WordPress confirmed
# it. Until then opening hours and session limits are not enforced (fail-open).
hm_to_min(){ case "$1" in [0-2][0-9]:[0-5][0-9]) _h="${1%%:*}"; _m="${1##*:}"; _h="${_h#0}"; _m="${_m#0}"; [ "${_h:-0}" -le 24 ] || return 1; printf '%s' $(( ${_h:-0} * 60 + ${_m:-0} ));; *) return 1;; esac; }
# 0 = guests may use the Internet now, 1 = outside opening hours.
sched_open_now(){
    [ "$(uci -q get wiflow.core.sched_enabled 2>/dev/null || echo 0)" = 1 ] || return 0
    time_valid || return 0
    _wk="$(uci -q get wiflow.core.sched_week 2>/dev/null || true)"
    if [ -n "$_wk" ]; then sched_week_open "$_wk"; return; fi
    _from="$(hm_to_min "$(uci -q get wiflow.core.sched_from 2>/dev/null)")" || return 0
    _to="$(hm_to_min "$(uci -q get wiflow.core.sched_to 2>/dev/null)")" || return 0
    _days="$(uci -q get wiflow.core.sched_days 2>/dev/null || true)"; [ -n "$_days" ] || _days=1234567
    set -- $(date '+%u %H %M'); _dow="$1"; _h="${2#0}"; _mm="${3#0}"; _now=$(( ${_h:-0} * 60 + ${_mm:-0} ))
    case "$_days" in *"$_dow"*) :;; *) return 1;; esac
    [ "$_from" = "$_to" ] && return 0
    if [ "$_from" -lt "$_to" ]; then [ "$_now" -ge "$_from" ] && [ "$_now" -lt "$_to" ] && return 0; return 1; fi
    { [ "$_now" -ge "$_from" ] || [ "$_now" -lt "$_to" ]; } && return 0; return 1
}
# v1.0.26: one window per weekday (Mon..Sun): "07:00-22:00", "all" or "off",
# comma separated. A window past midnight (22:00-02:00) continues next morning.
sched_day_entry(){ printf '%s' "$1" | awk -F, -v d="$2" '{print $d}'; }
sched_week_valid(){ printf '%s' "$1" | awk -F, '{ if(NF!=7) exit 1; for(i=1;i<=7;i++){ if($i!="all" && $i!="off" && $i !~ /^([01][0-9]|2[0-4]):[0-5][0-9]-([01][0-9]|2[0-4]):[0-5][0-9]$/) exit 1 } }'; }
# The 7-day schedule in force: sched_week when set, else built from from/to/days.
sched_week_effective(){
    _w="$(uci -q get wiflow.core.sched_week 2>/dev/null || true)"
    if [ -n "$_w" ] && sched_week_valid "$_w"; then printf '%s' "$_w"; return; fi
    _f="$(uci -q get wiflow.core.sched_from 2>/dev/null || echo 07:00)"; _t="$(uci -q get wiflow.core.sched_to 2>/dev/null || echo 22:00)"; _d="$(uci -q get wiflow.core.sched_days 2>/dev/null || echo 1234567)"
    _o=''; for _i in 1 2 3 4 5 6 7; do case "$_d" in *"$_i"*) _e="$_f-$_t";; *) _e=off;; esac; _o="${_o:+$_o,}$_e"; done
    sched_week_valid "$_o" && printf '%s' "$_o" || printf 'all,all,all,all,all,all,all'
}
sched_week_open(){
    set -- "$1" $(date '+%u %H %M'); _wk="$1"; _dow="$2"; _h="${3#0}"; _mm="${4#0}"; _now=$(( ${_h:-0} * 60 + ${_mm:-0} ))
    _e="$(sched_day_entry "$_wk" "$_dow")"
    case "$_e" in all) return 0;; off|'') :;; *)
        _f="$(hm_to_min "${_e%-*}")" && _t="$(hm_to_min "${_e#*-}")" || return 0
        if [ "$_f" = "$_t" ]; then return 0; fi
        if [ "$_f" -lt "$_t" ]; then [ "$_now" -ge "$_f" ] && [ "$_now" -lt "$_t" ] && return 0
        else [ "$_now" -ge "$_f" ] && return 0; fi;;
    esac
    _y=$(( _dow == 1 ? 7 : _dow - 1 )); _e="$(sched_day_entry "$_wk" "$_y")"
    case "$_e" in all|off|'') return 1;; esac
    _f="$(hm_to_min "${_e%-*}")" && _t="$(hm_to_min "${_e#*-}")" || return 1
    [ "$_f" -gt "$_t" ] && [ "$_now" -lt "$_t" ] && return 0
    return 1
}
SCHED_CLOSED=/tmp/wiflow-sched-closed
# Outside opening hours guests stay on the WiFi (the router page at 10.0.0.1 keeps
# working) and see the portal with the opening hours; the Internet is paused.
guest_sched_tick(){
    portal_nft_ready || return 0
    if sched_open_now; then _want=open; else _want=closed; fi
    _cur=open; /usr/sbin/nft list chain $CAPTIVE_TABLE sched_fwd 2>/dev/null | grep -q 'wf-closed' && _cur=closed
    [ "$_want" = "$_cur" ] && { [ "$_want" = closed ] && : > "$SCHED_CLOSED" || rm -f "$SCHED_CLOSED"; return 0; }
    if [ "$_want" = closed ]; then
        printf 'flush chain %s sched_fwd\nflush chain %s sched_nat\nadd rule %s sched_nat ip saddr 10.10.10.0/24 tcp dport 80 redirect to :2080 comment "wf-closed"\nadd rule %s sched_fwd ip saddr 10.10.10.0/24 meta l4proto tcp reject with tcp reset comment "wf-closed"\nadd rule %s sched_fwd ip saddr 10.10.10.0/24 reject comment "wf-closed"\n' \
            "$CAPTIVE_TABLE" "$CAPTIVE_TABLE" "$CAPTIVE_TABLE" "$CAPTIVE_TABLE" "$CAPTIVE_TABLE" | /usr/sbin/nft -f - >/dev/null 2>&1 || return 1
        : > "$SCHED_CLOSED"; wlog guest "Ngoài giờ phục vụ: tạm dừng Internet của khách"
    else
        printf 'flush chain %s sched_fwd\nflush chain %s sched_nat\n' "$CAPTIVE_TABLE" "$CAPTIVE_TABLE" | /usr/sbin/nft -f - >/dev/null 2>&1 || return 1
        rm -f "$SCHED_CLOSED"; wlog guest "Trong giờ phục vụ: mở lại Internet cho khách"
    fi
}
sched_closed(){ [ -f "$SCHED_CLOSED" ]; }
guest_authorized_count(){ _n=0; for _f in "$CLIENT_SESSIONS"/*; do [ -f "$_f" ] || continue; IFS='|' read -r _a _b _c _d _e _au _g _h < "$_f" 2>/dev/null || continue; case "${_au:-0}" in ''|0|*[!0-9]*) :;; *) _n=$((_n+1));; esac; done; printf '%s' "$_n"; }
guest_connected_count(){ _n=0; for _f in "$CLIENT_SESSIONS"/*; do [ -f "$_f" ] || continue; IFS='|' read -r _a _b _c _d _e _au _g _ab < "$_f" 2>/dev/null || continue; [ "$(num_or0 "$_ab")" = 0 ] && _n=$((_n+1)); done; printf '%s' "$_n"; }
# Session time (guest_session_min): sessions_sweep ends a session after N minutes; one confirm opens the Internet again.
guest_full(){ _max="$(cfg_num guest_max 0)"; [ "$_max" -gt 0 ] || return 1; [ "$(guest_authorized_count)" -ge "$_max" ]; }

# --- Statistics (RAM) ---------------------------------------------------------
# v3.4: only the number of guests; WordPress gets the visits from the events.
# Once a minute from portal-session-loop.
stats_sample(){
    state_set clients_auth "$(guest_authorized_count)"; state_set clients_conn "$(guest_connected_count)"
    return 0
}
mem_kb(){ awk -v k="$1:" '$1==k{print $2;exit}' /proc/meminfo 2>/dev/null; }
# --- Memory report (diagnostics only: the log and the support report; nothing here changes how the router runs) ---
# Sets MEM_T and MEM_A (kB, total and available); starts no program.
mem_load(){ MEM_T=0; MEM_A=0; while read -r _mk _mv _; do case "$_mk" in MemTotal:) MEM_T="$_mv";; MemAvailable:) MEM_A="$_mv";; esac; done < /proc/meminfo; }
# One line: RAM left, /tmp (RAM disk), connection table, load.
mem_line(){
    mem_load; _tu="$(df -k /tmp 2>/dev/null | awk 'END{print int($3/1024)}')"
    _cc="$(num_or0 "$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null)")"; _cm="$(num_or0 "$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null)")"
    read -r _ld _ < /proc/loadavg 2>/dev/null || _ld=0
    printf 'RAM: còn %s MB / %s MB · /tmp %s MB · kết nối %s/%s · tải %s' "$((MEM_A / 1024))" "$((MEM_T / 1024))" "${_tu:-0}" "$_cc" "$_cm" "$_ld"
}
# The biggest programs by resident memory (kB name), one pass over /proc.
mem_top(){
    awk 'FNR==1{if(n!="" && r>0)print r, n; n=""; r=0} /^Name:/{n=$2} /^VmRSS:/{r=$2} END{if(n!="" && r>0)print r, n}' /proc/[0-9]*/status 2>/dev/null | sort -rn | head -n "${1:-6}"
}

# --- Watchdog and safe mode ---------------------------------------------------
# Safe mode = captive portal off for 10 minutes so guests keep the Internet
# when the portal itself cannot be served (fail-open).
safe_mode_active(){ _u="$(num_or0 "$(state_get safe_until)")"; [ "$_u" -gt 0 ] && [ "$(uptime_s)" -lt "$_u" ]; }
# Safe mode ends by itself: forget it, the next portal_activate switches the captive portal back on.
safe_mode_tick(){
    [ -n "$(state_get safe_until)" ] && ! safe_mode_active || return 0
    state_set safe_until ''; wlog safe 'Hết chế độ an toàn: bật lại cổng chào'
}
safe_mode_enter(){
    state_set safe_until $(( $(uptime_s) + 600 ))
    /usr/lib/wiflow/portal-firewall disable >/dev/null 2>&1 || true
    wlog safe 'Chế độ an toàn: cổng chào lỗi nhiều lần, tạm mở Internet cho khách 10 phút'
}
wd_strike(){ # remember failures of the last 10 minutes; 3 = safe mode
    _now="$(uptime_s)"; _keep=''
    for _t in $(state_get wd_strikes | tr ',' ' ') "$_now"; do [ $((_now - _t)) -lt 600 ] && _keep="${_keep:+$_keep,}$_t"; done
    state_set wd_strikes "$_keep"
    [ "$(printf '%s' "$_keep" | tr ',' '\n' | grep -c .)" -ge 3 ]
}

# --- Portal content counters (per banner/video: views, clicks; no guest data) --
ADSTATS=/tmp/wiflow-adstats
adstats_add(){ # $1 = v|c, $2 = content item id
    case "$1" in v|c) :;; *) return 1;; esac
    printf '%s' "$2" | grep -Eq '^[A-Za-z0-9_.-]{1,48}$' || return 1
    _as="$(wc -c < "$ADSTATS" 2>/dev/null | tr -d ' ')"; [ "$(num_or0 "$_as")" -lt 200000 ] || return 0
    printf '%s|%s\n' "$1" "$2" >> "$ADSTATS"
}
adstats_take(){
    [ -f "$ADSTATS.sending" ] || { [ -s "$ADSTATS" ] && mv -f "$ADSTATS" "$ADSTATS.sending"; }
    [ -s "$ADSTATS.sending" ] || { printf '[]'; return 0; }
    awk -F'|' '{k[$2]=1; if($1=="v")v[$2]++; else c[$2]++} END{printf "[";n=0;for(i in k){if(n++)printf ",";printf "{\"item\":\"%s\",\"views\":%d,\"clicks\":%d}",i,v[i],c[i]}printf "]"}' "$ADSTATS.sending"
}
adstats_ack(){ rm -f "$ADSTATS.sending"; }

# --- Guest settings (local Setup and remote command share this) --------------
# guest_settings_set SESSION MAX SCHED_ON FROM TO DAYS WEEK ; "" keeps a value.
guest_settings_set(){
    for _pair in "guest_session_min:$1:1440" "guest_max:$2:250"; do
        _r="${_pair#*:}"; _v="${_r%%:*}"; _mx="${_r##*:}"
        [ -n "$_v" ] || continue
        case "$_v" in *[!0-9]*) return 2;; esac; [ "${#_v}" -le 7 ] && [ "$_v" -le "$_mx" ] || return 2
    done
    case "${3:-}" in ''|0|1) :;; *) return 2;; esac
    [ -z "${4:-}" ] || hm_to_min "$4" >/dev/null || return 2
    [ -z "${5:-}" ] || hm_to_min "$5" >/dev/null || return 2
    [ -z "${6:-}" ] || printf '%s' "$6" | grep -Eq '^[1-7]{1,7}$' || return 2
    case "${7:-}" in ''|none) :;; *) sched_week_valid "$7" || return 2;; esac
    [ -n "$1" ] && uci set "wiflow.core.guest_session_min=$1"
    [ -n "$2" ] && uci set "wiflow.core.guest_max=$2"
    [ -n "${3:-}" ] && uci set "wiflow.core.sched_enabled=$3"
    [ -n "${4:-}" ] && uci set "wiflow.core.sched_from=$4"
    [ -n "${5:-}" ] && uci set "wiflow.core.sched_to=$5"
    [ -n "${6:-}" ] && uci set "wiflow.core.sched_days=$(printf '%s' "$6" | awk '{for(i=1;i<=7;i++) if(index($0,i)) printf "%d", i}')"
    case "${7:-}" in '') :;; none) uci -q delete wiflow.core.sched_week >/dev/null 2>&1 || true;; *) uci set "wiflow.core.sched_week=$7";; esac
    uci commit wiflow || return 1
    secure_configs
    guest_sched_tick >/dev/null 2>&1 || true
    wlog guest "Cài đặt khách: thời gian $(cfg_num guest_session_min 0) phút, tối đa $(cfg_num guest_max 0), giờ phục vụ $(uci -q get wiflow.core.sched_enabled 2>/dev/null || echo 0)"
    return 0
}

# --- this firmware -------------------------------------------------------------
# WiFi and network are set in LuCI: "the uplink is up" simply means a default route.
secure_configs(){ [ -f /etc/config/wiflow ] && chmod 600 /etc/config/wiflow 2>/dev/null || true; }
# A default route exists (read from the kernel table, no program is started).
net_link_up(){ while read -r _li _ld _lg _lf _lc _lu _lm _lk _lx; do [ "$_ld" = 00000000 ] && [ "$_lk" = 00000000 ] && return 0; done < /proc/net/route; return 1; }
# The agent keeps the clock state in /tmp/wiflow/st (NTP hotplug or WordPress time).
time_valid(){ [ "$(cat /tmp/wiflow/st/time_ok 2>/dev/null)" = true ] || [ "$(state_get wp_time_ok)" = 1 ]; }
# What the guest portal is doing: on (captive rules in force), plan (usage plan ended), safe (safe mode), nocontent
# (nothing synced yet) or off. Guests have the Internet without the portal in every state but "on".
portal_state_name(){
    plan_locked && { printf plan; return; }
    safe_mode_active && { printf safe; return; }
    [ -f "$PORTAL_ACTIVE/portal.json" ] || { printf nocontent; return; }
    portal_nft_ready && { printf on; return; }
    printf off
}
portal_health_json(){
    _sm=false; safe_mode_active && _sm=true; _tv=false; time_valid && _tv=true; _sc=false; sched_closed && _sc=true
    _se=false; [ "$(uci -q get wiflow.core.sched_enabled 2>/dev/null)" = 1 ] && _se=true
    printf '{"clients_now":%s,"clients_connected":%s,"watchdog_restarts":%s,"safe_mode":%s,"time_ok":%s,"sched_closed":%s,"sched_enabled":%s,"sched_week":"%s","guest_session_min":%s,"guest_max":%s,"portal_state":"%s"}' \
        "$(num_or0 "$(state_get clients_auth)")" "$(num_or0 "$(state_get clients_conn)")" "$(num_or0 "$(state_get wd_restarts)")" \
        "$_sm" "$_tv" "$_sc" "$_se" "$(sched_week_effective)" "$(cfg_num guest_session_min 0)" "$(cfg_num guest_max 0)" "$(portal_state_name)"
}
# One place that turns the guest portal on: a valid content snapshot is on the router and
# safe mode is not active -> flag on + captive rules. Safe to call again and again.
# Usage plan (v2.5): WordPress says whether the plan runs and when it ends. The end date is kept here, so a router
# that cannot reach WordPress still turns the guest page off on that day (needs a clock that was confirmed).
# Guests keep the Internet, like in safe mode.
plan_locked(){
    [ "$(uci -q get wiflow.core.plan_active 2>/dev/null || echo 1)" = 0 ] && return 0
    _pe="$(num_or0 "$(uci -q get wiflow.core.plan_expires 2>/dev/null)")"
    [ "$_pe" -gt 0 ] && time_valid && [ "$(date +%s)" -ge "$_pe" ]
}
portal_activate(){
    if plan_locked; then /usr/lib/wiflow/portal-firewall disable >/dev/null 2>&1 || true; return 0; fi
    safe_mode_active && return 0
    [ -f "$PORTAL_ACTIVE/portal.json" ] || return 0
    if [ "$(uci -q get wiflow.core.portal_enabled 2>/dev/null || echo 0)" != 1 ]; then
        uci set wiflow.core.portal_enabled='1'; uci commit wiflow >/dev/null 2>&1 || true
    fi
    /usr/lib/wiflow/portal-firewall ensure >/dev/null 2>&1 || { state_set portal_error 'captive_firewall_enable_failed'; return 1; }
    return 0
}
# Every minute from portal-session-loop: web server and DNS stay up; three failures
# of the portal listener in 10 minutes = safe mode (guests keep the Internet).
watchdog_tick(){
    [ "$(uptime_s)" -ge 180 ] || return 0
    _fix=''; _pe="$(uci -q get wiflow.core.portal_enabled 2>/dev/null || echo 0)"
    if [ "$_pe" = 1 ] && ! tcp_listening 010A0A0A 0820; then
        /etc/init.d/uhttpd restart >/dev/null 2>&1 || true; _fix="$_fix web"; sleep 3
    fi
    pidof dnsmasq >/dev/null 2>&1 || { /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true; _fix="$_fix dnsmasq"; }
    # Connection table nearly full: say so once an hour (the short timeouts in sysctl.d keep it low).
    _cc="$(num_or0 "$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null)")"; _cm="$(num_or0 "$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null)")"
    if [ "$_cm" -gt 0 ] && [ $((_cc * 100 / _cm)) -ge 90 ] && [ $(( $(uptime_s) - $(num_or0 "$(state_get ct_warn)") )) -ge 3600 ]; then
        state_set ct_warn "$(uptime_s)"; wlog watchdog "Bảng kết nối gần đầy: $_cc/$_cm"
    fi
    # RAM in the log once after the start, then once an hour, and at once (at most every 10 minutes) when it runs low
    # with the biggest programs: a slow leak or a runaway program shows up later in the support report.
    mem_load; _up="$(uptime_s)"; _rs="$(state_get ram_log)"; _rl="$(num_or0 "$_rs")"; _low=0
    [ "$MEM_T" -gt 0 ] && [ $((MEM_A * 100 / MEM_T)) -lt 15 ] && _low=1
    if [ -z "$_rs" ] || [ "$_up" -ge $((_rl + 3600)) ] || { [ "$_low" = 1 ] && [ "$_up" -ge $((_rl + 600)) ]; }; then
        state_set ram_log "$_up"; wlog watchdog "$(mem_line)"
        [ "$_low" = 1 ] && wlog watchdog "Bộ nhớ thấp, lớn nhất: $(mem_top 3 | awk '{printf "%s%s %d MB", (NR>1?", ":""), $2, $1/1024}')"
    fi
    [ -n "$_fix" ] || return 0
    state_set wd_restarts $(( $(num_or0 "$(state_get wd_restarts)") + 1 ))
    wlog watchdog "Tự sửa lỗi, khởi động lại:$_fix"
    if [ "$_pe" = 1 ] && ! safe_mode_active && ! tcp_listening 010A0A0A 0820; then wd_strike && safe_mode_enter; fi
    return 0
}
