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
WIFLOW_DEVICE_API="$WIFLOW_REST_ROOT/devices"
WIFLOW_PORTAL_API="$WIFLOW_REST_ROOT/portal"
WIFLOW_AGENT_VERSION='2.1.0'
WIFLOW_MODEL_CODE='NR3053'; WIFLOW_MODEL_NAME='Viettel NR3053'
WIFLOW_GATE_MASTER="WIFDID$WIFLOW_MODEL_CODE"
WIFLOW_DATA_GENERATION='4'
mkdir -p "$ROOT" "$CLIENT_SESSIONS" "$PORTAL_REVISIONS" 2>/dev/null || true
chmod 700 "$ROOT" "$CLIENT_SESSIONS" 2>/dev/null || true
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
    rm -rf "$PORTAL_REVISIONS" "$PORTAL_ACTIVE" "$PORTAL_RUNTIME"/.staging-* "$PORTAL_RUNTIME"/.active-* 2>/dev/null || true
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

website_url_valid(){ case "$1" in http://*|https://*) return 0;; *) return 1;; esac; }
website_host_from_url(){ printf '%s' "$1" | sed -n 's#^https\{0,1\}://\([^/:?]*\).*#\1#p'; }
portal_active_config(){ [ -f "$PORTAL_ACTIVE/portal.json" ] && printf '%s' "$PORTAL_ACTIVE/portal.json"; }

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
# v1.0.21: LuCI always uses the Wiflow theme. It is the only registered theme
# (System > System > Language and Style offers nothing else) and any change made
# from the shell, LuCI or a theme package (re)install is undone on the next
# check (boot + every 15 s). Cheap no-op when already correct.
LUCI_THEME_URL='/luci-static/wiflow'
# Used only when the whole Wiflow package is removed: LuCI goes back to Bootstrap.
# v1.0.23: LuCI root password defaults to 1234 (owner's decision; change it in
# LuCI > System > Administration). Fresh install: always set. Upgrade / boot: set only
# while root has no password (e.g. after a firmware reset), never over a changed one.
LUCI_DEFAULT_ROOT_PW='1234'
WIFLOW_SHADOW="${WIFLOW_SHADOW:-/etc/shadow}"

# ---------------------------------------------------------------------------
# v1.0.15: router Internet status for the portal. One small file replaced in
# one step (write tmp + rename): readers never see a partial file and writers
# never wait for a lock. Format: "<1|0> <epoch>".
# ---------------------------------------------------------------------------
NET_STATUS=/tmp/wiflow-net-status
net_status_write(){ _nt="$NET_STATUS.$$"; printf '%s %s\n' "$1" "$(date +%s)" > "$_nt" 2>/dev/null && mv -f "$_nt" "$NET_STATUS" 2>/dev/null; }
# Prints "<value> <age_seconds>"; value is "?" when unknown.
net_status_read(){
    _sv=''; _st=0; read -r _sv _st 2>/dev/null < "$NET_STATUS" || true
    case "$_sv" in 0|1) :;; *) _sv='?';; esac; case "$_st" in ''|*[!0-9]*) _st=0;; esac
    printf '%s %s' "$_sv" $(( $(date +%s) - _st ))
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
# Auto mode keeps both uplinks configured: cable metric 10, source WiFi 20, so
# the kernel moves to the WiFi by itself when the cable is pulled. When the
# cable is plugged in but its modem has no Internet, Wiflow adds a route of
# higher priority (proto 188) through the WiFi until the cable answers again.
# The override route is told apart by its metric (1); netifd never uses it.
UPLINK_OVR_METRIC=1

# --- Guest controls -----------------------------------------------------------
# Time is trusted only after NTP synced (hotplug.d/ntp) or WordPress confirmed
# it. Until then opening hours and session limits are not enforced (fail-open).
NTP_OK=/tmp/wiflow-ntp-ok
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
# Outside opening hours guests stay on the WiFi (Wiflow Setup at 10.0.0.1 keeps
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
# Per-guest speed limit (kbit/s, 0 = no limit), policed per IP in nftables.
guest_policy_apply(){
    portal_nft_ready || return 0
    _dn="$(cfg_num guest_down_kbps 0)"; _up="$(cfg_num guest_up_kbps 0)"; _sig="wf-shape:$_dn/$_up"
    [ "${1:-}" != force ] && /usr/sbin/nft list chain $CAPTIVE_TABLE shape 2>/dev/null | grep -q "\"$_sig\"" && return 0
    {
        printf 'flush chain %s shape\n' "$CAPTIVE_TABLE"
        if [ "$_dn" -gt 0 ]; then _b=$((_dn / 8)); [ "$_b" -ge 32 ] || _b=32
            printf 'add rule %s shape ip daddr 10.10.10.0/24 update @dl { ip daddr limit rate over %s kbytes/second burst %s kbytes } drop\n' "$CAPTIVE_TABLE" $((_dn / 8)) "$_b"; fi
        if [ "$_up" -gt 0 ]; then _b=$((_up / 8)); [ "$_b" -ge 32 ] || _b=32
            printf 'add rule %s shape ip saddr 10.10.10.0/24 update @ul { ip saddr limit rate over %s kbytes/second burst %s kbytes } drop\n' "$CAPTIVE_TABLE" $((_up / 8)) "$_b"; fi
        printf 'add rule %s shape counter comment "%s"\n' "$CAPTIVE_TABLE" "$_sig"
    } | /usr/sbin/nft -f - >/dev/null 2>&1 || return 1
    guest_offload_policy "$_dn" "$_up"
    return 0
}
# Hardware/software flow offloading bypasses the limit: it is turned off while
# a limit is set and given back (as it was) when the limit is removed.
guest_offload_policy(){
    [ -f /etc/config/firewall ] || return 0
    _lim=0; { [ "$1" -gt 0 ] || [ "$2" -gt 0 ]; } && _lim=1
    _cur="$(uci -q get 'firewall.@defaults[0].flow_offloading' 2>/dev/null || echo 0)"
    _hw="$(uci -q get 'firewall.@defaults[0].flow_offloading_hw' 2>/dev/null || echo 0)"
    _saved="$(uci -q get wiflow.core.saved_offload 2>/dev/null || true)"
    if [ "$_lim" = 1 ] && [ "$_cur" = 1 ]; then
        uci set "wiflow.core.saved_offload=$_cur$_hw"; uci commit wiflow >/dev/null 2>&1 || true
        uci set 'firewall.@defaults[0].flow_offloading=0'; uci set 'firewall.@defaults[0].flow_offloading_hw=0'; uci commit firewall >/dev/null 2>&1 || true
        /etc/init.d/firewall reload >/dev/null 2>&1 || true; wlog guest 'Tắt tăng tốc chuyển tiếp để giới hạn tốc độ khách chính xác'
    elif [ "$_lim" = 0 ] && [ -n "$_saved" ]; then
        uci set "firewall.@defaults[0].flow_offloading=$(printf '%s' "$_saved" | cut -c1)"; uci set "firewall.@defaults[0].flow_offloading_hw=$(printf '%s' "$_saved" | cut -c2)"; uci commit firewall >/dev/null 2>&1 || true
        uci -q delete wiflow.core.saved_offload >/dev/null 2>&1 || true; uci commit wiflow >/dev/null 2>&1 || true
        /etc/init.d/firewall reload >/dev/null 2>&1 || true; wlog guest 'Bật lại tăng tốc chuyển tiếp'
    fi
    return 0
}
guest_authorized_count(){ _n=0; for _f in "$CLIENT_SESSIONS"/*; do [ -f "$_f" ] || continue; IFS='|' read -r _a _b _c _d _e _au _g _h < "$_f" 2>/dev/null || continue; case "${_au:-0}" in ''|0|*[!0-9]*) :;; *) _n=$((_n+1));; esac; done; printf '%s' "$_n"; }
guest_connected_count(){ _n=0; for _f in "$CLIENT_SESSIONS"/*; do [ -f "$_f" ] || continue; IFS='|' read -r _a _b _c _d _e _au _g _ab < "$_f" 2>/dev/null || continue; [ "$(num_or0 "$_ab")" = 0 ] && _n=$((_n+1)); done; printf '%s' "$_n"; }
# Session time: after N minutes the guest sees the portal again (one confirm
# opens the Internet for another N minutes). Only with a trusted clock.
guest_session_expire(){
    _min="$(cfg_num guest_session_min 0)"; [ "$_min" -gt 0 ] || return 0
    time_valid || return 0
    _now="$(date +%s)"; _lim=$((_min * 60)); _n=0
    for _f in "$CLIENT_SESSIONS"/*; do
        [ -f "$_f" ] || continue
        IFS='|' read -r _mac _cid _sid _ip _cn _au _last _ab < "$_f" 2>/dev/null || continue
        case "${_au:-0}" in ''|0|*[!0-9]*) continue;; esac
        [ "$_au" -le "$_now" ] || continue
        [ $((_now - _au)) -ge "$_lim" ] || continue
        portal_nft_del "$_ip" "$_mac"
        client_session_write "$_f" "$_mac" "$_cid" "$_sid" "$_ip" "$_cn" 0 "$_now" "$(num_or0 "$_ab")" || true
        _n=$((_n+1))
    done
    [ "$_n" = 0 ] || wlog guest "$_n khách hết thời gian sử dụng, cần xác nhận lại"
    return 0
}
guest_full(){ _max="$(cfg_num guest_max 0)"; [ "$_max" -gt 0 ] || return 1; [ "$(guest_authorized_count)" -ge "$_max" ]; }

# --- Statistics (RAM, last 48 hours, aggregated counts only) ------------------
STATS=/tmp/wiflow-stats
AUTH_TICKS=/tmp/wiflow-auth-ticks
nft_counter_bytes(){ /usr/sbin/nft list chain $CAPTIVE_TABLE "$1" 2>/dev/null | sed -n "s/.*counter packets [0-9]* bytes \([0-9]*\) comment \"$2\".*/\1/p" | head -n1; }
ping_ms(){ ping -c 1 -W 1 -q "${1:-1.1.1.1}" 2>/dev/null | sed -n 's#.*= [0-9.]*/\([0-9]*\)[.0-9]*/.*#\1#p' | head -n1; }
# Once a minute from portal-session-loop.
stats_sample(){
    _now="$(date +%s)"; _up="$(uptime_s)"; _hour=$((_now / 3600 * 3600))
    _a="$(guest_authorized_count)"; _c="$(guest_connected_count)"
    _rx="$(num_or0 "$(nft_counter_bytes forward guest-in)")"; _tx="$(num_or0 "$(nft_counter_bytes postrouting guest-out)")"
    _prx="$(num_or0 "$(state_get stat_rx_total)")"; _ptx="$(num_or0 "$(state_get stat_tx_total)")"; _pup="$(num_or0 "$(state_get stat_at)")"
    _drx=$((_rx - _prx)); [ "$_drx" -ge 0 ] || _drx="$_rx"; _dtx=$((_tx - _ptx)); [ "$_dtx" -ge 0 ] || _dtx="$_tx"
    [ "$_pup" -gt 0 ] || { _drx=0; _dtx=0; }
    _el=$((_up - _pup)); [ "$_el" -gt 0 ] || _el=60
    state_set stat_rx_total "$_rx"; state_set stat_tx_total "$_tx"; state_set stat_at "$_up"
    state_set stat_rx_bps $((_drx * 8 / _el)); state_set stat_tx_bps $((_dtx * 8 / _el))
    _auth=0; [ -f "$AUTH_TICKS" ] && { _auth="$(wc -c < "$AUTH_TICKS" | tr -d ' ')"; : > "$AUTH_TICKS"; }
    _p=''; if [ "$(net_status_read | cut -d' ' -f1)" = 1 ]; then _p="$(ping_ms 1.1.1.1)"; [ -n "$_p" ] || _p="$(ping_ms 8.8.8.8)"; fi
    state_set stat_ping "${_p:-}"
    _pv="${_p:-0}"; _pn=0; [ -n "$_p" ] && _pn=1
    [ -f "$STATS" ] || : > "$STATS"
    awk -F'|' -v h="$_hour" -v a="$_a" -v n="$(num_or0 "$_auth")" -v rx="$_drx" -v tx="$_dtx" -v p="$_pv" -v pn="$_pn" '
        $1==h {f=1; pk=($2>a?$2:a); printf "%s|%s|%.0f|%.0f|%.0f|%.0f|%.0f\n",h,pk,$3+n,$4+rx,$5+tx,$6+p,$7+pn; next}
        {print}
        END{ if(!f) printf "%s|%s|%.0f|%.0f|%.0f|%.0f|%.0f\n",h,a,n,rx,tx,p,pn }' "$STATS" | tail -n 48 > "$STATS.$$" && mv -f "$STATS.$$" "$STATS"
    state_set clients_auth "$_a"; state_set clients_conn "$_c"
    # One line per minute for the last 24 hours: time|ping|guests|uplink|ram%|load%|rx bytes
    _mt="$(num_or0 "$(mem_kb MemTotal)")"; _ma="$(num_or0 "$(mem_kb MemAvailable)")"; _mp=0; [ "$_mt" -gt 0 ] && _mp=$(( (_mt - _ma) * 100 / _mt ))
    _ld="$(awk '{printf "%d", $1*25}' /proc/loadavg 2>/dev/null)"; _ld="$(num_or0 "$_ld")"; [ "$_ld" -le 100 ] || _ld=100
    _ul="$(uplink_active)"; [ "$(net_status_read | cut -d' ' -f1)" = 1 ] || _ul=none
    printf '%s|%s|%s|%s|%s|%s|%s\n' "$_now" "${_p:-}" "$_a" "$_ul" "$_mp" "$_ld" "$_drx" >> "$MINUTES"
    _ml="$(wc -l < "$MINUTES" 2>/dev/null | tr -d ' ')"; [ "$(num_or0 "$_ml")" -le 1500 ] || { tail -n 1440 "$MINUTES" > "$MINUTES.$$" && mv -f "$MINUTES.$$" "$MINUTES"; }
    return 0
}
MINUTES=/tmp/wiflow-minutes
# Last 3 hours for the heartbeat (WordPress keeps them; repeated hours replace).
stats_json(){ [ -s "$STATS" ] || { printf '[]'; return; }; tail -n 3 "$STATS" | awk -F'|' 'BEGIN{printf "["} {if(NR>1)printf ","; printf "{\"hour\":%s,\"peak\":%s,\"auth\":%s,\"rx\":%s,\"tx\":%s,\"ping\":%d}",$1,$2,$3,$4,$5,($7>0?$6/$7:0)} END{printf "]"}'; }
mem_kb(){ awk -v k="$1:" '$1==k{print $2;exit}' /proc/meminfo 2>/dev/null; }

# --- Watchdog and safe mode ---------------------------------------------------
# Safe mode = captive portal off for 10 minutes so guests keep the Internet
# when the portal itself cannot be served (fail-open).
safe_mode_active(){ _u="$(num_or0 "$(state_get safe_until)")"; [ "$_u" -gt 0 ] && [ "$(uptime_s)" -lt "$_u" ]; }
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
# guest_settings_set DOWN UP SESSION MAX SCHED_ON FROM TO DAYS ; "" keeps a value.
guest_settings_set(){
    _i=0
    for _pair in "guest_down_kbps:$1:1000000" "guest_up_kbps:$2:1000000" "guest_session_min:$3:1440" "guest_max:$4:250"; do
        _k="${_pair%%:*}"; _r="${_pair#*:}"; _v="${_r%%:*}"; _mx="${_r##*:}"
        [ -n "$_v" ] || continue
        case "$_v" in *[!0-9]*) return 2;; esac; [ "${#_v}" -le 7 ] && [ "$_v" -le "$_mx" ] || return 2
    done
    case "${5:-}" in ''|0|1) :;; *) return 2;; esac
    [ -z "${6:-}" ] || hm_to_min "$6" >/dev/null || return 2
    [ -z "${7:-}" ] || hm_to_min "$7" >/dev/null || return 2
    [ -z "${8:-}" ] || printf '%s' "$8" | grep -Eq '^[1-7]{1,7}$' || return 2
    case "${9:-}" in ''|none) :;; *) sched_week_valid "$9" || return 2;; esac
    [ -n "$1" ] && uci set "wiflow.core.guest_down_kbps=$1"
    [ -n "$2" ] && uci set "wiflow.core.guest_up_kbps=$2"
    [ -n "$3" ] && uci set "wiflow.core.guest_session_min=$3"
    [ -n "$4" ] && uci set "wiflow.core.guest_max=$4"
    [ -n "${5:-}" ] && uci set "wiflow.core.sched_enabled=$5"
    [ -n "${6:-}" ] && uci set "wiflow.core.sched_from=$6"
    [ -n "${7:-}" ] && uci set "wiflow.core.sched_to=$7"
    [ -n "${8:-}" ] && uci set "wiflow.core.sched_days=$(printf '%s' "$8" | awk '{for(i=1;i<=7;i++) if(index($0,i)) printf "%d", i}')"
    case "${9:-}" in '') :;; none) uci -q delete wiflow.core.sched_week >/dev/null 2>&1 || true;; *) uci set "wiflow.core.sched_week=$9";; esac
    uci commit wiflow || return 1
    secure_configs
    guest_policy_apply >/dev/null 2>&1 || true
    guest_sched_tick >/dev/null 2>&1 || true
    wlog guest "Cài đặt khách: tốc độ $(cfg_num guest_down_kbps 0)/$(cfg_num guest_up_kbps 0) kbps, thời gian $(cfg_num guest_session_min 0) phút, tối đa $(cfg_num guest_max 0), giờ phục vụ $(uci -q get wiflow.core.sched_enabled 2>/dev/null || echo 0)"
    return 0
}

# --- Support report, reset helpers, technician mode ---------------------------
TECH_MODE=/etc/wiflow/tech-mode

# --- this firmware -------------------------------------------------------------
# WiFi and network are set in LuCI: "the uplink is up" simply means a default route.
secure_configs(){ [ -f /etc/config/wiflow ] && chmod 600 /etc/config/wiflow 2>/dev/null || true; }
net_link_up(){ ip route show default 2>/dev/null | grep -q default; }
# The agent keeps the clock state in /tmp/wiflow/st (NTP hotplug or WordPress time).
time_valid(){ [ "$(cat /tmp/wiflow/st/time_ok 2>/dev/null)" = true ] || [ "$(state_get wp_time_ok)" = 1 ]; }
# Which uplink carries the traffic: lan (a cable/WAN device), wifi (apcli*) or none.
uplink_active(){
    _rd="$(ip route get 1.1.1.1 2>/dev/null | head -n1 | sed -n 's/.* dev \([^ ]*\).*/\1/p')"
    [ -n "$_rd" ] || { printf none; return 0; }
    case "$_rd" in apcli*) printf wifi;; *) printf lan;; esac
}
portal_health_json(){
    _sm=false; safe_mode_active && _sm=true; _tv=false; time_valid && _tv=true; _sc=false; sched_closed && _sc=true
    _se=false; [ "$(uci -q get wiflow.core.sched_enabled 2>/dev/null)" = 1 ] && _se=true
    printf '{"clients_now":%s,"clients_connected":%s,"rx_bps":%s,"tx_bps":%s,"ping_ms":%s,"watchdog_restarts":%s,"safe_mode":%s,"time_ok":%s,"sched_closed":%s,"sched_enabled":%s,"sched_week":"%s","guest_down_kbps":%s,"guest_up_kbps":%s,"guest_session_min":%s,"guest_max":%s}' \
        "$(num_or0 "$(state_get clients_auth)")" "$(num_or0 "$(state_get clients_conn)")" \
        "$(num_or0 "$(state_get stat_rx_bps)")" "$(num_or0 "$(state_get stat_tx_bps)")" "$(num_or0 "$(state_get stat_ping)")" "$(num_or0 "$(state_get wd_restarts)")" \
        "$_sm" "$_tv" "$_sc" "$_se" "$(sched_week_effective)" "$(cfg_num guest_down_kbps 0)" "$(cfg_num guest_up_kbps 0)" "$(cfg_num guest_session_min 0)" "$(cfg_num guest_max 0)"
}
# One place that turns the guest portal on: a valid content snapshot is on the router and
# safe mode is not active -> flag on + captive rules. Safe to call again and again.
portal_activate(){
    safe_mode_active && return 0
    [ -f "$PORTAL_ACTIVE/portal.json" ] || return 0
    if [ "$(uci -q get wiflow.core.portal_enabled 2>/dev/null || echo 0)" != 1 ]; then
        uci set wiflow.core.portal_enabled='1'; uci commit wiflow >/dev/null 2>&1 || true
    fi
    /usr/lib/wiflow/portal-firewall ensure >/dev/null 2>&1 || { state_set portal_error 'captive_firewall_enable_failed'; return 1; }
    return 0
}
# Every minute from portal-mode-loop: web server and DNS stay up; three failures
# of the portal listener in 10 minutes = safe mode (guests keep the Internet).
watchdog_tick(){
    [ "$(uptime_s)" -ge 180 ] || return 0
    _fix=''; _pe="$(uci -q get wiflow.core.portal_enabled 2>/dev/null || echo 0)"
    if [ "$_pe" = 1 ] && ! tcp_listening 010A0A0A 0820; then
        /etc/init.d/uhttpd restart >/dev/null 2>&1 || true; _fix="$_fix web"; sleep 3
    fi
    pidof dnsmasq >/dev/null 2>&1 || { /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true; _fix="$_fix dnsmasq"; }
    [ -n "$_fix" ] || return 0
    state_set wd_restarts $(( $(num_or0 "$(state_get wd_restarts)") + 1 ))
    wlog watchdog "Tự sửa lỗi, khởi động lại:$_fix"
    if [ "$_pe" = 1 ] && ! safe_mode_active && ! tcp_listening 010A0A0A 0820; then wd_strike && safe_mode_enter; fi
    return 0
}
