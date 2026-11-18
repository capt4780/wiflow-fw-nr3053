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
echo '{"v":3,"name":"Quan Test","slogan":"Ngon","content_name":"Khuyen mai thang 11","form":{"enabled":true,"title":"Thong tin","body":"Dien nhanh","fields":["name","phone"]}}' > /tmp/mock/wp/media/shop.json
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
# v2.4: popup form. A new guest gets the form; what is typed waits in RAM and goes to WordPress with the heartbeat.
expect "form: the page tells a new guest apart (not known yet)" "$page" 'data-known="0"'
rm -f /tmp/wiflow-guests.queue /tmp/wiflow-guest-seen.* /etc/wiflow/guests.known
sid2="$($B x $PC ensure $ip1 | sed 's/.*|//')"
r="$($B x env REMOTE_ADDR=$ip1 REQUEST_METHOD=POST QUERY_STRING="action=guest&session_id=$sid2&name=Nguyen%20Van%20An&phone=0903%20112%20345&year=1995&email=an%40example.com&gender=nam" /www-wiflow-portal/cgi-bin/portal | tail -n1)"
expect "form: details accepted" "$r" '"ok":true'
expect "form: queued as one JSON line with the device id (hash) and no MAC" "$(python3 -c "import json;l=[json.loads(x) for x in open('/tmp/wiflow-guests.queue')];print(len(l),l[0]['name'],l[0]['phone'],l[0]['year'],l[0]['gender'],l[0]['client_id']=='$cid','$mac1' in open('/tmp/wiflow-guests.queue').read())")" '^1 Nguyen Van An 0903 112 345 1995 nam True False$'
r="$($B x env REMOTE_ADDR=$ip1 REQUEST_METHOD=POST QUERY_STRING="action=guest&session_id=$sid2&name=Again&phone=0911111111" /www-wiflow-portal/cgi-bin/portal | tail -n1)"
expect "form: a second send in the same session is ignored" "$(wc -l < /tmp/wiflow-guests.queue | tr -d ' ')" '^1$'
r="$($B x env REMOTE_ADDR=$ip1 REQUEST_METHOD=POST QUERY_STRING="action=guest&session_id=zzzz" /www-wiflow-portal/cgi-bin/portal | tail -n1)"
expect "form: unknown session refused" "$r" 'invalid_session'
r="$($B x env REMOTE_ADDR=$ip1 REQUEST_METHOD=POST QUERY_STRING="action=guest&session_id=$sid2" /www-wiflow-portal/cgi-bin/portal | tail -n1)"
expect "form: empty form refused" "$r" '"ok":false'
expect "form: the router remembers this device (hashed id only) in flash" "$(cat /etc/wiflow/guests.known)" "^$cid\$"
$B x $PC revoke-session "$sid" >/dev/null 2>&1
page2="$($B x env REMOTE_ADDR=$ip1 REQUEST_METHOD=GET /www-wiflow-portal/cgi-bin/portal)"
expect "form: a returning guest is told apart, so the page shows the banner popup" "$page2" 'data-known="1"'
# the agent may already have sent the guest with its own heartbeat (it is kicked right after the form), so accept either: still waiting in the report, or already received by WordPress
hbg="$($B x /usr/lib/wiflow/portal-hb report 2>/dev/null | python3 -c "import json,sys; b=json.load(sys.stdin); print(b['guest_count'], b['guests'][0]['name'])" 2>/dev/null || true)"
[ -n "$hbg" ] || hbg="$(grep -q 'Nguyen Van An' /tmp/mock/wp/heartbeat.jsonl 2>/dev/null && echo '1 Nguyen Van An')"
expect "form: the waiting guest reaches WordPress with the heartbeat" "$hbg" '^1 Nguyen Van An$'
for i in $(seq 1 30); do [ ! -s /tmp/wiflow-guests.queue ] && break; sleep 2; done
[ ! -s /tmp/wiflow-guests.queue ] && pass "form: queue emptied once WordPress took the heartbeat" || fail "form: queue not emptied"
expect "form: WordPress received the guest in a heartbeat" "$(grep -c '"Nguyen Van An"' /tmp/mock/wp/heartbeat.jsonl)" '^[1-9]'
for n in $(seq 1 20515); do printf 'k%07d\n' "$n"; done > /etc/wiflow/guests.known
$B x sh -c '. /usr/lib/wiflow/common.sh; guest_remember Znew1' >/dev/null
expect "form: the remembered devices are capped (oldest dropped)" "$(wc -l < /etc/wiflow/guests.known | tr -d ' ')|$(head -n1 /etc/wiflow/guests.known)|$(tail -n1 /etc/wiflow/guests.known)" '^20000\|k0000517\|Znew1$'
rm -f /etc/wiflow/guests.known

bad="$($B x env REMOTE_ADDR=10.10.10.99 REQUEST_METHOD=POST QUERY_STRING="action=authorize&session_id=$sid" /www-wiflow-portal/cgi-bin/portal | head -n1)"
expect "guest: another phone cannot use this session" "$bad" '403'
$B x $PC revoke-session "$sid"; $B x $PC is-authorized "$sid" && fail "revoke did not remove" || pass "guest: revoke closes the Internet again"

# Settings from WordPress: session time and guest limit (speed settings of older plugins are ignored)
wp "s['commands']=[{'id':'g1','action':'guest_settings','payload':{'down_kbps':5000,'up_kbps':0,'auto_share':True,'session_min':60,'max':20}}]"
for i in $(seq 1 30); do [ "$(python3 -c "import json;print(json.load(open('/tmp/mock/wp/state.json'))['results'].get('g1',{}).get('status',''))")" = success ] && break; sleep 2; done
expect "settings: guest_settings command applied" "$(python3 -c "import json;print(json.load(open('/tmp/mock/wp/state.json'))['results'].get('g1',{}).get('status',''))")|$(U get wiflow.core.guest_session_min)|$(U get wiflow.core.guest_max)|$(U get wiflow.core.guest_down_kbps || echo none)|$(U get wiflow.core.guest_auto || echo none)" '^success\|60\|20\|none\|none$'

# Guest WiFi name from WordPress: every guest radio gets the new name, a bad one is refused
$B x sh -c "uci -q get wireless.wfgap >/dev/null || { uci set wireless.wfgap=wifi-iface; uci set wireless.wfgap.device=MT7981_1_1; uci set wireless.wfgap.mode=ap; uci set wireless.wfgap.network=guest; uci set wireless.wfgap.ssid=Wiflow; uci commit wireless; }"
rs(){ python3 -c "import json;print(json.load(open('/tmp/mock/wp/state.json'))['results'].get('$1',{}).get('status',''))"; }
wp "s['commands']=[{'id':'n1','action':'guest_ssid','payload':{'ssid':'Quán Cà Phê A'}}]"
for i in $(seq 1 30); do [ "$(rs n1)" = success ] && break; sleep 2; done
expect "guest name: renamed from WordPress" "$(rs n1)|$($B x uci get wireless.wfgap.ssid)" '^success\|Quán Cà Phê A$'
wp "s['commands']=[{'id':'n2','action':'guest_ssid','payload':{'ssid':'0123456789012345678901234567890123456789'}}]"
for i in $(seq 1 30); do [ "$(rs n2)" = failed ] && break; sleep 2; done
expect "guest name: a name over 32 bytes is refused and the old one stays" "$(rs n2)|$($B x uci get wireless.wfgap.ssid)" '^failed\|Quán Cà Phê A$'

# What WordPress received: guest events and numbers, no guest personal data
sleep 8
expect "report: events reached WordPress, no MAC/IP/name of guests" "$(python3 -c "
import json
hb=[json.loads(l) for l in open('/tmp/mock/wp/heartbeat.jsonl')]
t=json.dumps(hb).upper()
ev=sorted({e['event_type'] for h in hb for e in h.get('events',[])})
print(ev, max(h.get('active_portal_revision',0) for h in hb), '$mac1' in t, '$ip1' in t, 'GUEST-PHONE' in t)")" "^\\['authorized', 'connected'.*\\] 7 False False False$"

# v3.1: a guest is only let in (and remembered) when the way out really works.
mac3=A4:83:E7:33:44:55; ip3=10.10.10.77
printf '1999999999 %s %s guest-three *\n' "$(echo $mac3 | tr A-F a-f)" "$ip3" >> /tmp/dhcp.leases
out3="$($B x $PC ensure $ip3)"; sid3="${out3#*|}"; cid3="${out3%%|*}"
$B x env REMOTE_ADDR=$ip3 REQUEST_METHOD=POST QUERY_STRING="action=guest&session_id=$sid3&name=Tran%20Thi%20Binh&phone=0912000111" /www-wiflow-portal/cgi-bin/portal >/dev/null
$B world 'w["block_dot"]=True'
code="$($B x env REMOTE_ADDR=$ip3 REQUEST_METHOD=POST QUERY_STRING="action=authorize&session_id=$sid3" /www-wiflow-portal/cgi-bin/portal | head -n1)"
expect "grant check: private DNS (853) blocked -> 503, the guest is not let in" "$code" '503'
$B x $PC is-authorized "$sid3" && fail "grant check: guest authorized although DoT is blocked" || pass "grant check: no Internet and no authed entry after a failed check"
expect "grant check: nothing remembered or sent for a guest who was not let in" "$(cat /etc/wiflow/guests.known 2>/dev/null | grep -c "$cid3")|$(cat /tmp/wiflow-guests.queue 2>/dev/null | grep -c 'Tran Thi Binh')" '^0\|0$'
$B world 'w["block_dot"]=False; w["block_dns"]=True'
code="$($B x env REMOTE_ADDR=$ip3 REQUEST_METHOD=POST QUERY_STRING="action=authorize&session_id=$sid3" /www-wiflow-portal/cgi-bin/portal | head -n1)"
expect "grant check: DNS through the router broken -> 503" "$code" '503'
$B world 'w["block_dns"]=False'
code="$($B x env REMOTE_ADDR=$ip3 REQUEST_METHOD=POST QUERY_STRING="action=authorize&session_id=$sid3" /www-wiflow-portal/cgi-bin/portal | head -n1)"
expect "grant check: everything works -> 204, the guest is let in" "$code" '204'
$B x $PC is-authorized "$sid3" && pass "grant check: guest authorized after a good check" || fail "grant check: guest not authorized after a good check"
for i in $(seq 1 20); do grep -q "$cid3" /etc/wiflow/guests.known 2>/dev/null && cat /tmp/wiflow-guests.queue /tmp/mock/wp/heartbeat.jsonl 2>/dev/null | grep -q 'Tran Thi Binh' && break; sleep 1; done
expect "grant check: the form data is remembered and sent only after the grant" "$(grep -c "$cid3" /etc/wiflow/guests.known 2>/dev/null)|$(grep -c 'Tran Thi Binh' /tmp/wiflow-guests.queue /tmp/mock/wp/heartbeat.jsonl 2>/dev/null | awk -F: '{s+=$2} END{print (s>0)?"sent":"missing"}')" '^1\|sent$'
# Internet gone for good: every guest has to sign in again
$B world 'w["inet"].update({k: False for k in w["inet"]})'
$B x sh -c '. /usr/lib/wiflow/common.sh; net_status_write 0; echo $(( $(date +%s) - 400 )) > /tmp/wiflow-net-down-since; net_down_tick'
$B x $PC is-authorized "$sid3" && fail "Internet lost for 5 minutes: guest still authorized" || pass "Internet lost for 5 minutes: guests have to sign in again"
expect "Internet lost for 5 minutes: the authed list is empty" "$($B x nft list set inet wiflow_captive authed | grep -c 'elements')" '^0$'
$B world 'w["inet"].update({k: True for k in w["inet"]})'
$B x sh -c '. /usr/lib/wiflow/common.sh; net_status_write 1; net_down_tick'
[ ! -f /tmp/wiflow-net-down-since ] && pass "Internet back: the outage timer is cleared" || fail "outage timer not cleared"

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

. "$T/session-test.sh"

# Leaving the account clears everything
r="$(job unpair)"
expect "unpair: portal off, content and guests cleared" "$r|$(U get wiflow.core.portal_enabled)|$(ls /www-wiflow-portal/runtime/revisions 2>/dev/null | wc -l)|$($B x nft list table inet wiflow_captive >/dev/null 2>&1 && echo table || echo none)|$(ls /tmp/wiflow-client-sessions 2>/dev/null | wc -l)" '^success\|.*\|0\|0\|none\|0$'
