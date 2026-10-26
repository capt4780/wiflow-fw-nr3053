#!/usr/bin/env python3
"""Builds rom/overlay/usr/lib/wiflow/common.sh for the guest portal.

Source: common.sh of the Wiflow guest portal as finalised on the CR6609
(Wiflow Setup 1.0.26). Only the functions the portal scripts really use are
kept (call-graph closure); the Setup-only parts (WiFi scan/uplink, setup
login, LuCI web linking, ...) are left out. A few functions are replaced for
this firmware (see OVERRIDES). Usage:

  tools/make-portal-lib.py <ref common.sh> <overlay dir>
"""
import re, sys, os

src, overlay = sys.argv[1], sys.argv[2]
lines = open(src).read().split('\n')

FUNC = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*)\(\)\s*\{')
chunks = []          # (kind, name, text-lines)
i = 0
pending = []         # comment/blank lines waiting for the next chunk
while i < len(lines):
    l = lines[i]
    m = FUNC.match(l)
    if m:
        name = m.group(1)
        body = [l]
        depth = l.count('{') - l.count('}')
        # heuristic: a one-liner ends with "}" at the end of the same line
        if not (l.rstrip().endswith('}') and depth <= 0):
            i += 1
            while i < len(lines):
                body.append(lines[i])
                if lines[i] == '}':
                    break
                i += 1
        chunks.append(('func', name, pending + body))
        pending = []
    elif l.startswith('#') or l.strip() == '':
        pending.append(l)
    else:
        chunks.append(('top', None, pending + [l]))
        pending = []
    i += 1

funcs = {c[1]: c for c in chunks if c[0] == 'func'}

ROOTS_FILES = [
    'usr/lib/wiflow/portal-client', 'usr/lib/wiflow/portal-firewall', 'usr/lib/wiflow/portal-sync',
    'usr/lib/wiflow/portal-mode-loop', 'usr/lib/wiflow/portal-session-loop', 'usr/lib/wiflow/portal-hb',
    'usr/lib/wiflow/portal-boot', 'www-wiflow-portal/cgi-bin/portal', 'www-wiflow-portal/cgi-bin/captive-api',
]
# Replaced for this firmware (the originals are dropped).
OVERRIDES = r'''
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
'''
DROP = {'net_link_up', 'time_valid', 'uplink_active', 'health_json', 'watchdog_tick', 'pairing_clear_local', 'ensure_guest_network', 'secure_configs'}

def words(text):
    return set(re.findall(r'[A-Za-z_][A-Za-z0-9_]*', text))

need = set()
todo = []
for f in ROOTS_FILES:
    p = os.path.join(overlay, f)
    if os.path.exists(p):
        todo.append(open(p).read() + '\n' + OVERRIDES)
todo.append(OVERRIDES)
# top-level statements are always kept: their words count too
for c in chunks:
    if c[0] == 'top':
        todo.append('\n'.join(c[2]))
defined_over = words(OVERRIDES)
seen = set()
queue = []
for t in todo:
    for w in words(t):
        if w in funcs and w not in DROP and w not in seen:
            seen.add(w); queue.append(w)
while queue:
    n = queue.pop()
    for w in words('\n'.join(funcs[n][2])):
        if w in funcs and w not in DROP and w not in seen:
            seen.add(w); queue.append(w)

out = []
for c in chunks:
    if c[0] == 'top':
        out.extend(c[2])
    elif c[1] in seen:
        out.extend(c[2])
text = '\n'.join(out)
# model: one common.sh for every board (device ID / emergency Gate code)
text = text.replace("WIFLOW_AGENT_VERSION='1.0.26'",
"""WIFLOW_AGENT_VERSION='2.1.0'
WIFLOW_MODEL_CODE='NR3053'; WIFLOW_MODEL_NAME='Viettel NR3053'
WIFLOW_GATE_MASTER="WIFDID$WIFLOW_MODEL_CODE\"""")
for junk in ('SESS=/tmp/wiflow-sessions\n', 'GATE_SESS=/tmp/wiflow-gate-sessions\n', 'UPLINK_TXN=$ROOT/uplink-txn\n',
             'RESUME_DIR=/tmp/wiflow-management-resume\n', 'SESSION_TTL=1800\n', 'GATE_TTL=1200\n',
             '# Short-lived management resume grant used only while changing uplink.\n',
             '# It lets the same physical client recover its authenticated Wiflow Setup\n',
             '# session after a radio restart without asking for the PIN/login again.\n', 'RESUME_TTL=300\n'):
    text = text.replace(junk, '')
text = text.replace('mkdir -p "$ROOT" "$SESS" "$GATE_SESS" "$CLIENT_SESSIONS" "$RESUME_DIR" "$PORTAL_REVISIONS"', 'mkdir -p "$ROOT" "$CLIENT_SESSIONS" "$PORTAL_REVISIONS"')
text = text.replace('chmod 700 "$ROOT" "$SESS" "$GATE_SESS" "$CLIENT_SESSIONS" "$RESUME_DIR"', 'chmod 700 "$ROOT" "$CLIENT_SESSIONS"')
text = re.sub(r'# Short-lived management resume grant.*?\n(?=\S)', '', text, flags=re.S) if False else text
text = text.replace("WIFLOW_REST_ROOT='https://wiflow.projifylab.com/wp-json'", 'WIFLOW_REST_ROOT="${WIFLOW_REST:-https://wiflow.projifylab.com/wp-json}"')
text = re.sub(r'\n{3,}', '\n\n', text) + '\n' + OVERRIDES
open(os.path.join(overlay, 'usr/lib/wiflow/common.sh'), 'w').write(text)
print('kept %d of %d functions, %d bytes' % (len(seen) + 5, len(funcs) + 0, len(text)))
print(sorted(seen))
