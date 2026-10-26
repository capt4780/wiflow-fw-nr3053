#!/bin/bash
# Wiflow Setup regression tests on the bench (see bench.sh). Exit 1 on failure.
#   sudo -E tools/app-test/run.sh        (PFX / UCODE_DIR as for bench.sh)
T="$(cd "$(dirname "$0")" && pwd)"
B="$T/bench.sh"
export WIFLOW_TICK=4
fails=0
pass(){ echo "PASS $*"; }
fail(){ echo "FAIL $*"; fails=$((fails+1)); }
call(){ $B x ubus -t 60 call wiflow "$@"; }
st(){ call status | python3 -c "import json,sys; s=json.load(sys.stdin); print(eval(sys.argv[1]))" "$1"; }
job(){ # job <method> [json] -> final "state|message"
	call "$@" >/dev/null
	for i in $(seq 1 60); do
		sleep 2
		r="$(st "(s['job'] or {}).get('state','') + '|' + (s['job'] or {}).get('message','')")"
		case "$r" in running*) ;; *) echo "$r"; return;; esac
	done
	echo "timeout|"
}
expect(){ # expect <name> <got> <regex>
	if printf '%s' "$2" | grep -Eq -- "$3"; then pass "$1"; else fail "$1: got '$2'"; fi
}
wp(){ python3 -c "import json; s=json.load(open('/tmp/mock/wp/state.json')); $1; json.dump(s, open('/tmp/mock/wp/state.json','w'))"; }
wait_for(){ # wait_for <secs> <python expr on status>
	for i in $(seq 1 "$1"); do [ "$(st "$2")" = True ] && return 0; sleep 1; done; return 1
}

$B start >/dev/null || exit 1
U(){ LD_LIBRARY_PATH=${PFX:-/opt/pfx}/lib ${PFX:-/opt/pfx}/bin/uci -q "$@"; }

# A router that kept its settings from an older build: WiFi on the LAN, no guest network,
# a custom-named AP on the LAN and a joined source
for c in "network.wiflow_wwan=interface" "wireless.wiflow_guest_2g=wifi-iface" "wireless.wiflow_uplink=wifi-iface"; do U set "$c"; done
U set network.wiflow_wwan.proto=dhcp
U set wireless.wiflow_guest_2g.device=MT7981_1_1; U set wireless.wiflow_guest_2g.mode=ap; U set wireless.wiflow_guest_2g.network=lan
U set wireless.wiflow_guest_2g.ssid='Wiflow Quan'
U set wireless.wiflow_uplink.device=MT7981_1_1; U set wireless.wiflow_uplink.mode=sta; U set wireless.wiflow_uplink.network=wiflow_wwan
U set wireless.wiflow_uplink.ssid='Cafe Sua Da'; U set wireless.wiflow_uplink.encryption=psk2; U set wireless.wiflow_uplink.key=cafe1234
U set wiflow.core=core 2>/dev/null
U commit

$B x /usr/libexec/wiflow/provision boot
expect "install: device id" "$(cat /etc/wiflow/device-id)" '^WIFDID-NR3053-[0-9]{6}$'
expect "install: gate code added" "$(U get wiflow_gate.main.code)" "WIFDIDNR3053 $(cut -c15-20 /etc/wiflow/device-id)"
expect "kept settings: guest network created (10.10.10.1, DHCP, firewall zone, portal web server)" "$(U get network.wiflow_guest.ipaddr)|$(U get network.wiflow_guest_dev.name)|$(U get dhcp.wiflow_guest.interface)|$(U get firewall.wiflow_guest.name)|$(U get firewall.wiflow_guest_portal.dest_port)|$(U get uhttpd.wiflow_portal.home)" '^10\.10\.10\.1\|br-wiflow\|wiflow_guest\|wiflow_guest\|2080\|/www-wiflow-portal$'
expect "kept settings: factory WiFi moved to the guest network and named Wiflow" "$(U get wireless.default_MT7981_1_1.network)|$(U get wireless.default_MT7981_1_2.network)|$(U get wireless.default_MT7981_1_1.ssid)|$(U get wireless.default_MT7981_1_2.ssid)" '^wiflow_guest\|wiflow_guest\|Wiflow\|Wiflow$'
expect "kept settings: a WiFi with a custom name stays where it was" "$(U get wireless.wiflow_guest_2g.network)|$(U get wireless.wiflow_guest_2g.ssid)" '^lan\|Wiflow Quan$'
expect "kept settings: joined source untouched" "$(U get wireless.wiflow_uplink.ssid)|$(U get wireless.wiflow_uplink.key)|$(U get network.wiflow_wwan.proto)" '^Cafe Sua Da\|cafe1234\|dhcp$'
expect "kept settings: marked done" "$(U get wiflow.core.migrated)|$(U get wiflow.core.guest_moved)|$(U get wiflow.core.ssid_merged)" '^2\|1\|1$'
cp -r /etc/config /tmp/cfg.before
$B x /usr/libexec/wiflow/provision boot
diff -r /tmp/cfg.before /etc/config >/dev/null && pass "boot is idempotent (no config rewrite)" || fail "boot rewrote configs"
rm -rf /tmp/cfg.before

expect "rpcd: only status, pair, unpair, job_clear" "$($B x ubus -v list wiflow | sed -n 's/^[[:space:]]*"\([a-z_]*\)":.*/\1/p' | sort | tr "\n" " ")" "^job_clear pair status unpair $"
expect "status before linking" "$(st "(s['wp']['paired'], s['device']['model'], s['device']['agent'])")" "^\(False, 'Viettel NR3053', '2\.0\.0'\)$"
expect "pair: bad format" "$(call pair '{"code":"abc"}')" '12 letters and digits'

$B world 'w["wan_cable"]=True'
$B agent
wait_for 30 "s['internet']['online']" && pass "agent: Internet check" || fail "online: $(st "s['internet']")"

r="$(job pair '{"code":"ZZZZ-1111-2222"}')"; expect "pair: unknown code" "$r" '^failed\|The code is not correct'
r="$(job pair '{"code":"abcd-1234-efgh"}')"; expect "pair" "$r" '^success\|Linked to account WIFUID482913'
wait_for 20 "s['wp']['online']" && pass "heartbeat accepted" || fail "heartbeat: $(st "s['wp']")"
wait_for 60 "s['clients']['now']==3" && pass "dashboard: 3 WiFi devices from the bridge table (2 on 2.4G, 1 on 5G; cable and the router itself not counted)" || fail "clients: $(st "s['clients']")"
expect "dashboard: devices per band, today" "$(st "(s['clients']['band2g'], s['clients']['band5g'], s['clients']['today'])")" '^\(2, 1, 3\)$'
expect "dashboard: WiFi networks" "$(st "[(n['ssid'], n['band'], n['channel'], n['clients'], n['enc']) for n in s['networks']]")" "^\[\('Wiflow', '2g', 'Auto', 2, 'Open'\), \('Wiflow', '5g', 'Auto', 1, 'Open'\), \('Wiflow Quan', '2g', 'Auto', 2, 'Open'\)\]$"
expect "dashboard: router health" "$(st "(s['metrics']['mem_total_mb'] > 0, s['metrics']['flash_total_mb'] >= 0, s['metrics']['cpu'] is None or 0 <= s['metrics']['cpu'] <= 100)")" '^\(True, True, True\)$'
expect "dashboard: 24 h history and latency" "$(st "(len(s['series']['devices']), s['series']['devices'][-1], len(s['series']['latency']), s['internet']['latency'] >= 0, s['wp']['since'] > 0)")" '^\(24, 3, 24, True, True\)$'
[ -z "$(grep -v '^info$' /tmp/mock/iwinfo.log 2>/dev/null)" ] && pass "Wiflow only reads the source WiFi signal (info), never scans or lists the driver" || fail "driver calls: $(sort /tmp/mock/iwinfo.log | uniq -c | tr '\n' ' ')"
sleep 50
n0="$(wc -l < /tmp/mock/iwinfo.log 2>/dev/null || echo 0)"
sleep 30
n1="$(wc -l < /tmp/mock/iwinfo.log 2>/dev/null || echo 0)"
[ "$n0" = "$n1" ] && pass "no driver access while the Wiflow App page is closed" || fail "driver polled in the background ($n0 -> $n1)"
expect "status after linking" "$(st "(s['wp']['paired'], s['wp']['account'])")" "^\(True, 'WIFUID482913'\)$"
hb="$(tail -n1 /tmp/mock/wp/heartbeat.jsonl)"
expect "heartbeat body: SSIDs as set in LuCI, no guest data" "$(printf '%s' "$hb" | python3 -c "import json,sys; b=json.load(sys.stdin); print(b['agent_version'], b['data_generation'], b['wifi_ssid'], b['guest_ssid'], b['health']['uplink_active'], b['events'])")" '^2\.0\.0 4 Cafe Sua Da Wiflow (lan|wifi) \[\]$'

wp "s['commands']=[
 {'id':'c1','action':'change_guest_ssid','payload':{'guest_ssid':'X'}},
 {'id':'c2','action':'change_setup_login','payload':{'username':'chuquan','password':'matkhau123'}},
 {'id':'c3','action':'change_wifi','payload':{'ssid':'Cafe Sua Da','password':'cafe1234','band':'2g','enc':'psk2','mode':'auto'}},
 {'id':'c4','action':'diag','payload':{}},
 {'id':'c5','action':'bogus','payload':{}},
 {'id':'c6','action':'reboot','payload':{}}]"
for i in $(seq 1 90); do
	n="$(python3 -c "import json; r=json.load(open('/tmp/mock/wp/state.json'))['results']; print(sum(1 for k in ['c1','c2','c3','c4','c5','c6'] if r.get(k,{}).get('status') in ('success','failed','rebooting')))")"
	[ "$n" = 6 ] && break; sleep 2
done
res="$(python3 -c "import json; r=json.load(open('/tmp/mock/wp/state.json'))['results']; print(' '.join(k+'='+r.get(k,{}).get('status','-') for k in ['c1','c2','c3','c4','c5','c6']))")"
expect "WordPress commands: diag and reboot only" "$res" '^c1=failed c2=failed c3=failed c4=success c5=failed c6=rebooting$'
expect "unsupported command says where to set it" "$(python3 -c "import json; print(json.load(open('/tmp/mock/wp/state.json'))['results']['c3']['message'])")" 'set in LuCI'
for i in $(seq 1 10); do grep -q '^reboot' /tmp/mock/calls.log && break; sleep 1; done
grep -q '^reboot' /tmp/mock/calls.log && pass "reboot command reboots" || fail "no reboot"
[ -s /tmp/mock/wp/diag.jsonl ] && pass "diag report sent" || fail "no diag report"

wp "
for hw,d in list(s['devices'].items()): s['revoked'].append([hw,d['token']]); del s['devices'][hw]"
wait_for 60 "not s['wp']['paired']" && pass "owner unpair in app: router forgets account (after confirmations)" || fail "server unpair: $(st "s['wp']")"
wp "s['codes']['QWER5678TYUI']={'account':'WIFUID555111'}; s['commands']=[]"
r="$(job pair '{"code":"QWER5678TYUI"}')"; expect "pair again" "$r" 'WIFUID555111'
r="$(job unpair)"; expect "unpair from router" "$r|$(U get wiflow.core.paired)|$(U get wiflow.core.device_token)" '^success\|.*\|0\|$'
echo '{}' > /tmp/rq.json; $B x /usr/libexec/wiflow/job diag /tmp/rq.json
r="$(st "(s['job'] or {}).get('state','')")"; expect "diagnostic report (keys hidden)" "$r|$(grep -c '== wireless' /tmp/wiflow/diag.txt)|$(grep -c 'cafe1234' /tmp/wiflow/diag.txt)" '^success\|1\|0$'

. "$T/portal-test.sh"

APP="$T/../../rom/overlay/usr/share/ucode/wiflow $T/../../rom/overlay/usr/libexec/wiflow $T/../../rom/overlay/etc/init.d/wiflow $T/../../rom/overlay/www/luci-static/resources/view/wiflow/account.js $T/../../rom/overlay/usr/share/rpcd/ucode/wiflow"
grep -rq iwpriv $APP && fail "Wiflow App calls iwpriv" || pass "Wiflow App never touches the driver with iwpriv"
if python3 -c "
import os,re,sys
r=re.compile('[\\u00c0-\\u024f\\u1ea0-\\u1ef9]')
bad=[p for a in sys.argv[1:] for p in ([a] if os.path.isfile(a) else [os.path.join(d,f) for d,_,fs in os.walk(a) for f in fs])
     if r.search(open(p,errors='ignore').read())]
print(bad); sys.exit(1 if bad else 0)" $APP; then pass "Wiflow App text is English only"; else fail "non-English text left in the Wiflow App"; fi

# --- self-recovery of the uplink (steps run 30x faster here: 6 s, 16 s, 40 s)
$B x sh -c 'kill $(pgrep -f "^/usr/bin/ucode /usr/libexec/wiflow/agen[t]")'; sleep 1
: > /tmp/mock/calls.log
export WIFLOW_REC_SCALE=30
$B world 'w["inet"]["wan"]=False'
$B agent
wait_for 40 "s['system']['recovery']['stage']>=1" && grep -q '^ifup wan' /tmp/mock/calls.log && pass "recovery 1: the WAN connection is renewed (ifup wan)" || fail "recovery 1: $(st "s['system']['recovery']") $(cat /tmp/mock/calls.log | tr '\n' ' ')"
wait_for 40 "s['system']['recovery']['stage']>=2" && grep -q '^wifi reload' /tmp/mock/calls.log && pass "recovery 2: the WiFi is restarted" || fail "recovery 2: $(st "s['system']['recovery']")"
grep -q '^reboot' /tmp/mock/calls.log && fail "recovery: rebooted too early"
wait_for 60 "s['system']['recovery']['stage']>=3" && pass "recovery 3 reached" || fail "recovery 3: $(st "s['system']['recovery']")"
sleep 5
grep -q '^reboot' /tmp/mock/calls.log && pass "recovery 3: the router restarts" || fail "recovery: no reboot"
expect "recovery: reason and counter kept for the next start" "$(U get wiflow.core.boot_reason)|$(U get wiflow.core.recovery_reboots)" '^auto_recovery\|1$'
$B x sh -c 'kill $(pgrep -f "^/usr/bin/ucode /usr/libexec/wiflow/agen[t]")'; sleep 1
rm -rf /tmp/wiflow/st/boot_reason /tmp/wiflow/st/recovery
$B world 'w["inet"]["wan"]=True'
$B agent
wait_for 30 "s['internet']['online']" && pass "recovery: online again" || fail "not online again"
expect "reboot reason shown after the restart, and cleared" "$(st "s['system']['boot_reason']")|$(U get wiflow.core.boot_reason)" '^auto_recovery\|$'
wait_for 60 "s['system']['recovery_reboots']==0" && pass "recovery: counter cleared after a steady connection" || fail "counter: $(st "s['system']")"
$B x sh -c 'kill $(pgrep -f "^/usr/bin/ucode /usr/libexec/wiflow/agen[t]")'; sleep 1
rm -rf /tmp/wiflow/st/boot_reason; $B agent; sleep 6
expect "reboot reason without a stored one: power or manual" "$(st "s['system']['boot_reason']")" '^power_or_manual$'
unset WIFLOW_REC_SCALE
$B x sh -c 'kill $(pgrep -f "^/usr/bin/ucode /usr/libexec/wiflow/agen[t]")'; sleep 1
pgrep -f '^/usr/bin/ucode /usr/libexec/wiflow/agen[t]' >/dev/null && fail "agent ignores SIGTERM" || pass "agent stops on SIGTERM"

cp /etc/config/wireless /tmp/wl.before
$B x /usr/libexec/wiflow/provision remove
expect "remove: WiFi untouched, gate code back to default" "$(diff /tmp/wl.before /etc/config/wireless >/dev/null && echo same)|$(U get wiflow_gate.main.code)" '^same\|WIFDIDNR3053$'
rm -f /tmp/wl.before

$B stop
echo; [ "$fails" = 0 ] && { echo "ALL PASSED"; exit 0; } || { echo "$fails FAILED"; exit 1; }
