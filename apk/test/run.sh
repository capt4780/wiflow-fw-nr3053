#!/bin/bash
# Wiflow Setup regression tests on the bench (see bench.sh). Exit 1 on failure.
#   sudo -E apk/test/run.sh        (PFX / UCODE_DIR as for bench.sh)
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
$B x /usr/libexec/wiflow/provision boot
expect "install: device id" "$(cat /etc/wiflow/device-id)" '^WIFDID-NR3053-[0-9]{6}$'
expect "install: gate code added" "$(uci_() { "$PFX/bin/uci" "$@"; }; LD_LIBRARY_PATH=${PFX:-/opt/pfx}/lib ${PFX:-/opt/pfx}/bin/uci -q get wiflow_gate.main.code)" "WIFDIDNR3053 $(cut -c15-20 /etc/wiflow/device-id)"
U(){ LD_LIBRARY_PATH=${PFX:-/opt/pfx}/lib ${PFX:-/opt/pfx}/bin/uci -q "$@"; }
expect "install: WiFi untouched until 'Bật Wiflow'" "$(U get wiflow.core.activated)|$(U get wireless.default_MT7981_1_1.ssid)|$(U get wireless.wiflow_guest_2g)" '^0\|Wiflow 2.4G\|$'
expect "install: guest network" "$(U get network.wiflow_guest.ipaddr) $(U get firewall.wiflow_guest.input) $(U get firewall.wiflow_guest_wan.dest)" '^10.10.10.1/24 REJECT wan$'
expect "install: uplink in wan zone" "$(U show firewall | grep "network=.*wiflow_wwan")" 'wiflow_wwan'
cp -r /etc/config /tmp/cfg.before
$B x /usr/libexec/wiflow/provision boot
diff -r /tmp/cfg.before /etc/config >/dev/null && pass "boot is idempotent (no config rewrite)" || fail "boot rewrote configs"
rm -rf /tmp/cfg.before

$B agent
r="$(job set_uplink '{"mode":"auto","ssid":"Cafe Sua Da","band":"2g","key":"cafe1234","encryption":"psk2"}')"
expect "source WiFi needs activation" "$r" '^failed\|.*Bật Wiflow'
r="$(job activate)"; expect "activate" "$r" '^success\|Đã bật Wiflow'
expect "activate: stock APs replaced by guest APs" "$(U show wireless | grep -c "=wifi-iface")/$(U get wireless.wiflow_guest_2g.ssid)/$(U get wireless.wiflow_guest_5g.network)/$(U get wireless.wiflow_guest_2g.isolate)" '^2/Wiflow/wiflow_guest/1$'
expect "activate: fixed quiet channels, 20/80 MHz" "$(U get wireless.MT7981_1_1.channel)/$(U get wireless.MT7981_1_1.htmode) $(U get wireless.MT7981_1_2.channel)/$(U get wireless.MT7981_1_2.htmode)" '^1/HE20 (36|149)/HE80$'
r="$(job scan)"; expect "scan job" "$r" '^success\|Tìm thấy 5 mạng'
expect "scan: enterprise hidden, mixed WPA2/3 as psk2" "$(st "sorted((n['ssid'],n['band'],n['encryption']) for n in s['job']['networks'])")" "\('Cafe Sua Da 5G', '5g', 'psk2'\).*\('Free WiFi Lobby', '2g', 'none'\)"
expect "scan: advice (5G non-DFS good signal, DFS flagged)" "$(st "sorted((n['ssid'], bool(n.get('recommended')), n['dfs'], n['weak']) for n in s['job']['networks'])")" "\('Cafe Sua Da 5G', True, False, False\).*\('Office 5G', False, True, False\)"
$B world 'w["iwinfo_empty"]=["5g"]'
r="$(job scan '{"band":"5g"}')"
expect "scan 5G when libiwinfo sees nothing: driver survey" "$r|$(st "sorted((n['ssid'],n['band'],n['channel'],n['encryption']) for n in s['job']['networks'])")" "^success\|.*\('Cafe Sua Da 5G', '5g', 1?[0-9]+, 'psk2'\).*\('Office 5G', '5g', (5[2-9]|[6-9][0-9]|1[0-4][0-9]), 'psk2'\)"
expect "scan cache keeps the other band" "$(st "sorted(set(n['band'] for n in s['scan']['networks']))")" "^\['2g', '5g'\]$"
$B world 'w["iwinfo_empty"]=[]'
r="$(job set_uplink '{"mode":"auto","ssid":"Cafe Sua Da","band":"2g","key":"wrongpass","encryption":"psk2"}')"
expect "wrong password fails and rolls back" "$r|$(U -q get wireless.wiflow_uplink.ssid)" '^failed\|Không vào được.*mật khẩu\.\|$'
expect "failed join leaves driver notes for the report" "$(head -1 /tmp/wiflow/join-fail.txt)|$(grep -c wrongpass /tmp/wiflow/join-fail.txt)" '^join "Cafe Sua Da" on MT7981_1_1 .*failed: not associated.*\|0$'
r="$(job set_uplink '{"mode":"auto","ssid":"Cafe Sua Da","band":"2g","key":"cafe1234","encryption":"psk2"}')"
expect "join 2.4G source" "$r" '^success\|Đã kết nối “Cafe Sua Da”'
wait_for 15 "s['internet']['source'].get('connected') and s['internet']['online']" && pass "status: source connected, online" || fail "status after join: $(st "s['internet']")"
expect "guest follows source band" "$(st "s['guest']['follows']")" '^2g$'
expect "source radio follows the source, other radio fixed" "$(U get wireless.MT7981_1_1.channel) $(U get wireless.MT7981_1_2.channel)" '^auto (36|149)$'
: > /tmp/mock/calls.log
r="$(job set_uplink '{"mode":"auto","ssid":"Nha Ben Canh","band":"2g","key":"bencanh123","encryption":"psk2"}')"
expect "switch source on the same band" "$r" '^success\|Đã kết nối “Nha Ben Canh”'
grep -q "iwpriv apcli0 set ApCliSsid=Nha Ben Canh" /tmp/mock/calls.log && ! grep -q "^wifi reload" /tmp/mock/calls.log && pass "same-band switch without reloading the WiFi" || fail "same-band switch reloaded WiFi: $(grep -E '^wifi|ApCliSsid' /tmp/mock/calls.log | tr '\n' ';')"
$B world 'w["iw_blind"]=True'
r="$(job set_uplink '{"mode":"auto","ssid":"Cafe Sua Da","band":"2g","key":"cafe1234","encryption":"psk2"}')"
expect "join when the driver hides the BSSID (DHCP is the proof)" "$r" '^success\|Đã kết nối “Cafe Sua Da”'
wait_for 15 "s['internet']['source'].get('connected')" && pass "status: connected without BSSID" || fail "blind status: $(st "s['internet']['source']")"
$B world 'w["iw_blind"]=False'
r="$(job set_uplink '{"mode":"wifi","ssid":"Free WiFi Lobby","band":"2g","key":"","encryption":"none"}')"
expect "source on 10.0.0.x refused" "$r|$(U get wireless.wiflow_uplink.ssid)" '^failed\|.*trùng mạng nội bộ.*\|Cafe Sua Da$'
r="$(job set_uplink '{"mode":"wifi","ssid":"Cafe Sua Da 5G","band":"5g","key":"cafe1234","encryption":"psk2"}')"
expect "join 5G, WiFi only" "$r|$(U get network.wan.disabled)|$(U get wireless.wiflow_uplink.device)" '^success\|.*\|1\|MT7981_1_2$'
r="$(job set_uplink '{"mode":"lan"}')"
expect "mode cable only" "$r|$(U get wireless.wiflow_uplink.disabled)|$(U get network.wan.disabled)" '^success\|.*\|1\|$'
$B world 'w["wan_cable"]=True'
r="$(job set_uplink '{"mode":"auto"}')"
expect "mode auto keeps saved source" "$r|$(U get wireless.wiflow_uplink.disabled)|$(U get network.wan.metric)/$(U get network.wiflow_wwan.metric)" '^success\|.*\|\|10/20$'
wait_for 20 "s['internet']['via'] == 'lan' and s['internet']['online']" && pass "auto: cable first" || fail "auto via: $(st "s['internet']")"
r="$(job set_uplink '{"mode":"wifi"}')"; r="$(job set_uplink '{"mode":"auto"}')"

$B world 'w["inet"]["wan"]=False'
wait_for 40 "s['internet']['override'] and s['internet']['via'] == 'wifi' and s['internet']['online']" && pass "auto: cable without Internet -> source WiFi" || fail "failover: $(st "s['internet']")"
$B world 'w["inet"]["wan"]=True'
$B x ip route replace default via 192.168.32.1 dev apclix0 metric 1 2>/dev/null
wait_for 40 "not s['internet']['override'] and s['internet']['via'] == 'lan'" && pass "auto: back to cable" || fail "failback: $(st "s['internet']")"

r="$(job set_guest '{"ssid":"Cafe Sua Da 5G"}')"; expect "guest name must differ from source" "$r" '^failed'
r="$(job set_guest '{"ssid":"Wiflow Cafe"}')"
expect "rename guest WiFi" "$r|$(U get wireless.wiflow_guest_2g.ssid)|$(U get wireless.wiflow_guest_5g.ssid)" '^success\|.*\|Wiflow Cafe\|Wiflow Cafe$'

r="$(job pair '{"code":"ZZZZ-1111-2222"}')"; expect "pair: unknown code" "$r" '^failed\|Mã kết nối không đúng'
r="$(job pair '{"code":"abcd-1234-efgh"}')"; expect "pair" "$r" '^success\|Đã kết nối tài khoản WIFUID482913'
wait_for 20 "s['wp']['online']" && pass "heartbeat accepted" || fail "heartbeat: $(st "s['wp']")"
hb="$(tail -n1 /tmp/mock/wp/heartbeat.jsonl)"
expect "heartbeat body" "$(printf '%s' "$hb" | python3 -c "import json,sys; b=json.load(sys.stdin); print(b['agent_version'], b['data_generation'], b['connection'], b['guest_ssid'], b['health']['uplink_active'])")" '^1\.[0-9]+\.[0-9]+ 4 auto Wiflow Cafe lan$'

python3 -c "import json; w=json.load(open('/tmp/mock/world.json')); w['clients']={'ra0':['11:22:33:44:55:66','11:22:33:44:55:77'],'rax0':[]}; json.dump(w,open('/tmp/mock/world.json','w'))"
sleep 14
python3 -c "import json; w=json.load(open('/tmp/mock/world.json')); w['clients']={'ra0':['11:22:33:44:55:66'],'rax0':[]}; json.dump(w,open('/tmp/mock/world.json','w'))"
sleep 40
ev="$(python3 -c "
import json
ev=[e for l in open('/tmp/mock/wp/heartbeat.jsonl') for e in json.loads(l)['events']]
print(sorted(e['event_type'] for e in ev), len(set(e['client_id'] for e in ev)), all(len(e['client_id'])==32 and ':' not in e['client_id'] for e in ev))")"
expect "guest events (hashed client ids)" "$ev" "^\['connected', 'connected', 'disconnected'\] 2 True$"

wp "s['commands']=[
 {'id':'c1','action':'change_guest_ssid','payload':{'guest_ssid':'Wiflow Quan 1'}},
 {'id':'c2','action':'change_setup_login','payload':{'username':'chuquan','password':'matkhau123'}},
 {'id':'c3','action':'set_internet_mode','payload':{'mode':'lan'}},
 {'id':'c4','action':'diag','payload':{}},
 {'id':'c5','action':'guest_settings','payload':{'down_kbps':1000}},
 {'id':'c6','action':'change_wifi','payload':{'ssid':'Cafe Sua Da','password':'cafe1234','band':'2g','enc':'psk2','mode':'auto'}},
 {'id':'c7','action':'bogus','payload':{}},
 {'id':'c8','action':'reboot','payload':{}}]"
for i in $(seq 1 90); do
	n="$(python3 -c "import json; r=json.load(open('/tmp/mock/wp/state.json'))['results']; print(sum(1 for k in ['c1','c2','c3','c4','c5','c6','c7','c8'] if r.get(k,{}).get('status') in ('success','failed','rebooting')))")"
	[ "$n" = 8 ] && break; sleep 2
done
res="$(python3 -c "import json; r=json.load(open('/tmp/mock/wp/state.json'))['results']; print(' '.join(k+'='+r.get(k,{}).get('status','-') for k in ['c1','c2','c3','c4','c5','c6','c7','c8']))")"
expect "WordPress commands" "$res" '^c1=success c2=success c3=success c4=success c5=failed c6=success c7=failed c8=rebooting$'
expect "change_setup_login: rpcd login" "$(grep -A1 "username 'chuquan'" /etc/config/rpcd | tail -1)" "password '\\\$1\\\$"
expect "root login untouched" "$(grep -A1 "username 'root'" /etc/config/rpcd | tail -1)" "\\\$p\\\$root"
for i in $(seq 1 10); do grep -q '^reboot' /tmp/mock/calls.log && break; sleep 1; done
grep -q '^reboot' /tmp/mock/calls.log && pass "reboot command reboots" || fail "no reboot"
[ -s /tmp/mock/wp/diag.jsonl ] && pass "diag report sent" || fail "no diag report"

wp "
for hw,d in list(s['devices'].items()): s['revoked'].append([hw,d['token']]); del s['devices'][hw]"
wait_for 60 "not s['wp']['paired']" && pass "owner unpair in app: router forgets account (after confirmations)" || fail "server unpair: $(st "s['wp']")"
wp "s['codes']['QWER5678TYUI']={'account':'WIFUID555111'}; s['commands']=[]"
r="$(job pair '{"code":"QWER5678TYUI"}')"; expect "pair again" "$r" 'WIFUID555111'
r="$(job unpair)"; expect "unpair from router" "$r|$(U get wiflow.core.paired)|$(U get wiflow.core.device_token)" '^success\|.*\|0\|$'
r="$(job diag)"; expect "diagnostic report" "$r|$(grep -c '== radios' /tmp/wiflow/diag.txt)|$(grep -c 'cafe1234\|bencanh123' /tmp/wiflow/diag.txt)" '^success\|.*\|1\|0$'

ov="$(call overview | python3 -c "import json,sys; o=json.load(sys.stdin); print(o['ok'], len(o['minutes'])>0, len(o['day']['runs'])>0, o['health']['mem_total_kb']>0, isinstance(o['hours'],list))")"
expect "overview: page charts from the agent's samples" "$ov" '^True True True True True$'
expect "inet: both uplinks" "$(call inet | python3 -c "import json,sys; o=json.load(sys.stdin); print(o['ok'], o['wan']['up'], o['wan']['addr'], o['wifi_ssid'])")" '^True True 192.168.1.10 '
expect "log for the page" "$(call log | python3 -c "import json,sys; o=json.load(sys.stdin); print(o['ok'], len(o['log'])>3)")" '^True True$'
expect "change_login rejects a short password" "$(call change_login '{"username":"chuquan","password":"123"}')" 'tối thiểu 8'
r="$(job reset)"
expect "reset Wiflow (package kept)" "$r|$(U get wiflow.core.paired)|$(U -q get wireless.wiflow_uplink)|$(U get wiflow.core.guest_ssid)|$(U get wireless.wiflow_guest_2g.ssid)|$(U get wiflow.core.setup_username)" '^success\|.*\|0\|\|Wiflow\|Wiflow\|wiflow$'

$B x sh -c 'kill $(pgrep -f "^/usr/bin/ucode /usr/libexec/wiflow/agen[t]")'; sleep 1
pgrep -f '^/usr/bin/ucode /usr/libexec/wiflow/agen[t]' >/dev/null && fail "agent ignores SIGTERM" || pass "agent stops on SIGTERM"

cp /etc/wiflow/stock/wireless /tmp/wl.stock
$B x /usr/libexec/wiflow/provision remove
expect "remove: WiFi back to stock" "$(diff /tmp/wl.stock /etc/config/wireless >/dev/null && echo same)|$(U show network | grep -c wiflow)|$(U show firewall | grep -c wiflow)|$(U show dhcp | grep -c wiflow)|$(U get wiflow_gate.main.code)" '^same\|0\|0\|0\|WIFDIDNR3053$'
rm -f /tmp/wl.stock

$B stop
echo; [ "$fails" = 0 ] && { echo "ALL PASSED"; exit 0; } || { echo "$fails FAILED"; exit 1; }
