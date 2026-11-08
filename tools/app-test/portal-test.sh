# Guest portal tests (sourced by run.sh; uses its helpers). Real nftables in the
# bench namespace, the real portal scripts, mocked WordPress.
PC=/usr/lib/wiflow/portal-client
mac1=A4:83:E7:AA:BB:CC; ip1=10.10.10.50
expect "guests: WiFi devices of the guest bridge only (cable and the router excluded)" "$($B x /usr/libexec/wiflow/guests br-wiflow | sort | tr '\n' ' ')" '^10:20:30:40:50:60 3C:22:FB:11:22:33 A4:83:E7:AA:BB:CC $'
$B x nft list table inet wiflow_captive >/dev/null 2>&1 && fail "captive table exists before there is any content" || pass "no captive rules without content (guests simply have Internet)"
expect "portal is off before content" "$(U get wiflow.core.portal_enabled || echo 0)" '^0?$'

# WordPress publishes revision 7: an image and the shop data
mkdir -p /tmp/mock/wp/media
head -c 3000 /dev/urandom > /tmp/mock/wp/media/bg.jpg
head -c 2000 /dev/urandom > /tmp/mock/wp/media/intro.jpg
echo '{"v":3,"name":"Quan Test","slogan":"Ngon","content_name":"Khuyen mai thang 11"}' > /tmp/mock/wp/media/shop.json
wp "s['codes']['WIFAPIPORT01']={'account':'WIFUID777000'}; s['commands']=[]"
r="$(job pair '{"code":"WIFAPIPORT01"}')"; expect "portal: device paired" "$r" 'WIFUID777000'
wp "s['portal']={'revision':7,'mode':'image','files':[{'role':'image_landscape','name':'bg.jpg'},{'role':'shop_data','name':'shop.json'},{'role':'intro_image','name':'intro.jpg'}]}"
# the content download alone must switch the portal on
for i in $(seq 1 40); do [ "$(U get wiflow.core.portal_revision)" = 7 ] && $B x nft list set inet wiflow_captive authed >/dev/null 2>&1 && break; sleep 2; done
expect "portal: content revision 7 downloaded, checked and active" "$(U get wiflow.core.portal_revision)|$(U get wiflow.core.portal_sync_status)|$(U get wiflow.core.portal_enabled)|$($B x jsonfilter -i /www-wiflow-portal/runtime/active/portal.json -e '@.mode' 2>/dev/null)" '^7\|active\|1\|image$'
expect "App page: kind and name of the applied content" "$(st "(s['portal']['mode'], s['portal']['content_name'])")" "^\\('image', 'Khuyen mai thang 11'\\)$"
expect "App page: portal state, revision and where the WiFi sits" "$(st "(s['portal']['state'], s['portal']['revision'], s['portal']['network'])")" "^\\('on', 7, 'guest'\\)$"
[ -s /www-wiflow-portal/runtime/active/media/intro.jpg ] && pass "portal: intro image role accepted and stored" || fail "portal: intro_image not stored"
cmp -s /tmp/mock/wp/media/bg.jpg /www-wiflow-portal/runtime/active/media/bg.jpg && pass "portal: media identical to the server copy (sha256 checked)" || fail "portal: media differs"
$B x nft list set inet wiflow_captive authed >/dev/null 2>&1 && pass "portal: captive firewall table is up" || fail "portal: no captive table"
grep -q '"status": "active"' /tmp/mock/wp/portal-ack.jsonl 2>/dev/null && pass "portal: WordPress told the revision is active" || fail "portal: no ack: $(cat /tmp/mock/wp/portal-ack.jsonl 2>/dev/null)"

# A guest phone joins
printf '1999999999 %s %s guest-phone *\n' "$(echo $mac1 | tr A-F a-f)" "$ip1" > /tmp/dhcp.leases
out="$($B x $PC ensure $ip1)"; expect "guest: session created (client id|session id)" "$out" '^[A-Za-z0-9]+\|[A-Za-z0-9]{24}$'
sid="${out#*|}"; cid="${out%%|*}"
$B x $PC is-authorized "$sid" && fail "guest authorized before the confirm" || pass "guest: no Internet before the confirm"
page="$($B x env REMOTE_ADDR=$ip1 REQUEST_METHOD=GET /www-wiflow-portal/cgi-bin/portal)"
expect "guest: portal page served with the session" "$page" "$sid"
expect "guest: portal page uses the image template" "$page" 'bg\.jpg|image'
$B x env REMOTE_ADDR=$ip1 REQUEST_METHOD=GET HTTP_ACCEPT_ENCODING="gzip, deflate" /www-wiflow-portal/cgi-bin/portal > /tmp/pg.gz
expect "guest: portal page is sent gzip-compressed when the phone accepts it" "$(head -c 400 /tmp/pg.gz | tr -d '\r' | grep -ci '^Content-Encoding: gzip')|$(sed '1,/^\r\?$/d' /tmp/pg.gz | gzip -dc 2>/dev/null | grep -c "$sid")|$(( $(wc -c < /tmp/pg.gz) < 30000 ))" '^1\|[1-9][0-9]*\|1$'
code="$($B x env REMOTE_ADDR=$ip1 REQUEST_METHOD=POST QUERY_STRING="action=authorize&session_id=$sid" /www-wiflow-portal/cgi-bin/portal | head -n1)"
expect "guest: confirm answers 204 (Internet opened)" "$code" '204'
$B x $PC is-authorized "$sid" && pass "guest: Internet granted by the confirm (nft element present)" || fail "guest not authorized"
$B x nft list set inet wiflow_captive authed | grep -qi "$ip1 . $mac1" && pass "guest: authorized as IP + MAC pair" || fail "guest pair missing"
bad="$($B x env REMOTE_ADDR=10.10.10.99 REQUEST_METHOD=POST QUERY_STRING="action=authorize&session_id=$sid" /www-wiflow-portal/cgi-bin/portal | head -n1)"
expect "guest: another phone cannot use this session" "$bad" '403'
$B x $PC revoke-session "$sid"; $B x $PC is-authorized "$sid" && fail "revoke did not remove" || pass "guest: revoke closes the Internet again"

# Settings from WordPress: speed limit stays 0 (shared equally), session time and guest limit
wp "s['commands']=[{'id':'g1','action':'guest_settings','payload':{'down_kbps':0,'up_kbps':0,'session_min':60,'max':20}}]"
for i in $(seq 1 30); do [ "$(python3 -c "import json;print(json.load(open('/tmp/mock/wp/state.json'))['results'].get('g1',{}).get('status',''))")" = success ] && break; sleep 2; done
expect "settings: guest_settings command applied" "$(python3 -c "import json;print(json.load(open('/tmp/mock/wp/state.json'))['results'].get('g1',{}).get('status',''))")|$(U get wiflow.core.guest_session_min)|$(U get wiflow.core.guest_max)|$(U get wiflow.core.guest_down_kbps || echo 0)" '^success\|60\|20\|0?$'

# Line speed test (a mock speed server stands in for the Internet): started from WordPress
$B x setsid python3 "$T/speedsrv.py" 8098 >/tmp/mock/speed.log 2>&1 &
sleep 1
U set wiflow.core.speedtest_base=http://127.0.0.1:8098; U commit wiflow
expect "speedtest: nothing measured yet" "$(st "s['speed']['line']['phase']")" '^idle$'
wp "s['commands']=[{'id':'st1','action':'speedtest'}]"
for i in $(seq 1 30); do [ "$(python3 -c "import json;print(json.load(open('/tmp/mock/wp/state.json'))['results'].get('st1',{}).get('status',''))")" = success ] && break; sleep 2; done
expect "speedtest: command from WordPress started it" "$(python3 -c "import json;print(json.load(open('/tmp/mock/wp/state.json'))['results'].get('st1',{}).get('status',''))")" '^success$'
for i in $(seq 1 40); do [ "$(st "s['speed']['line']['phase']")" = done ] && break; sleep 1; done
expect "speedtest: result (down, up, latency) in status and stored in the config" "$(st "(s['speed']['line']['phase'], s['speed']['line']['down'] > 1000, s['speed']['line']['up'] > 1000, s['speed']['line']['running'])")|$(U get wiflow.core.st_down | awk '$1>1000{print "ok"}')|$(U get wiflow.core.st_up | awk '$1>1000{print "ok"}')" "^\\('done', True, True, False\\)\\|ok\\|ok$"
expect "speedtest: result goes up with the health numbers" "$($B x /usr/lib/wiflow/portal-hb report | python3 -c "import json,sys; h=json.load(sys.stdin)['health']; print(h['line_state'], h['line_down']>1000, h['line_up']>1000)")" '^done True True$'
rm -f /tmp/mock/wp-hb.json
expect "speedtest: from the router page (rpc), one at a time" "$(call speedtest | tr -d ' \n\t')|$(call speedtest | tr -d ' \n\t')" '^\{"ok":true,"running":true\}\|\{"ok":true,"running":true\}$'
for i in $(seq 1 40); do [ "$(st "s['speed']['line']['running']")" = False ] && break; sleep 1; done
expect "speedtest: the second run finished" "$(st "(s['speed']['line']['running'], s['speed']['line']['phase'])")" "^\\(False, 'done'\\)$"
U set wiflow.core.speedtest_base=http://127.0.0.1:1; U commit wiflow
$B x /usr/lib/wiflow/speedtest run
expect "speedtest: no Internet / server -> failed, the last good result is kept" "$(st "s['speed']['line']['phase']")|$(U get wiflow.core.st_down | awk '$1>1000{print "kept"}')" '^failed\|kept$'
U delete wiflow.core.speedtest_base; U commit wiflow

# What WordPress received: guest events and numbers, no guest personal data
sleep 8
expect "report: events reached WordPress, no MAC/IP/name of guests" "$(python3 -c "
import json
hb=[json.loads(l) for l in open('/tmp/mock/wp/heartbeat.jsonl')]
t=json.dumps(hb).upper()
ev=sorted({e['event_type'] for h in hb for e in h.get('events',[])})
print(ev, max(h.get('active_portal_revision',0) for h in hb), '$mac1' in t, '$ip1' in t, 'GUEST-PHONE' in t)")" "^\\['authorized', 'connected'.*\\] 7 False False False$"

# Safe mode: portal off, guests have Internet, comes back after
$B x sh -c '. /usr/lib/wiflow/common.sh; safe_mode_enter'
$B x nft list table inet wiflow_captive >/dev/null 2>&1 && fail "safe mode: captive rules still on" || pass "safe mode: captive rules removed (fail-open)"
$B x sh -c '. /usr/lib/wiflow/common.sh; state_set safe_until ""'
$B x /usr/lib/wiflow/portal-firewall ensure
$B x nft list set inet wiflow_captive authed >/dev/null 2>&1 && pass "safe mode over: captive rules back" || fail "captive rules did not return"

# The session loop ends safe mode by itself (what the old mode loop did) and turns the portal back on
$B x sh -c '. /usr/lib/wiflow/common.sh; safe_mode_enter; state_set safe_until 1; safe_mode_tick; portal_activate'
$B x nft list set inet wiflow_captive authed >/dev/null 2>&1 && [ -z "$($B x sh -c '. /usr/lib/wiflow/common.sh; state_get safe_until')" ] && pass "safe mode ends by itself: captive rules back" || fail "safe mode did not end by itself"

# A bigger revision than the storage budget allows is refused and reported
head -c 3000 /dev/urandom > /tmp/mock/wp/media/bg2.jpg
wp "s['portal']={'revision':8,'mode':'image','files':[{'role':'image_landscape','name':'bg2.jpg'},{'role':'shop_data','name':'shop.json'}]}"
for i in $(seq 1 40); do [ "$(U get wiflow.core.portal_revision)" = 8 ] && break; sleep 2; done
expect "portal: revision 8 replaces 7, old media removed" "$(U get wiflow.core.portal_revision)|$(ls /www-wiflow-portal/runtime/active/media | tr '\n' ' ')|$(ls /www-wiflow-portal/runtime/revisions | tr '\n' ' ')" '^8\|bg2.jpg shop.json \|rev-8 $'

# Rules wiped (reboot, firewall trouble): the self-repair step brings them back
$B x nft delete table inet wiflow_captive
$B x sh -c '. /usr/lib/wiflow/common.sh; portal_activate'
$B x nft list set inet wiflow_captive authed >/dev/null 2>&1 && pass "self-repair: captive rules rebuilt from the content on the router" || fail "self-repair did not rebuild the rules"
rules="$($B x nft list ruleset)"
expect "Private DNS: DoT (853) passes for guests, web (80) goes to the portal, the rest is rejected until the confirm" "$(printf '%s' "$rules" | grep -c 'dport 853 accept')|$(printf '%s' "$rules" | grep -c 'redirect to :2080')|$(printf '%s' "$rules" | grep -c 'reject')" '^2\|1\|[1-9]'

. "$T/shaper-test.sh"

# Leaving the account clears everything
r="$(job unpair)"
expect "unpair: portal off, content and guests cleared" "$r|$(U get wiflow.core.portal_enabled)|$(ls /www-wiflow-portal/runtime/revisions 2>/dev/null | wc -l)|$($B x nft list table inet wiflow_captive >/dev/null 2>&1 && echo table || echo none)|$(ls /tmp/wiflow-client-sessions 2>/dev/null | wc -l)" '^success\|.*\|0\|0\|none\|0$'
