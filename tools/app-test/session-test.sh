# v3.5 guest session tests (sourced by portal-test.sh, uses its helpers and variables). Real nftables in the bench
# namespace, a real veth "phone" for the idle timer, the real portal scripts. Covers: the firewall renews the idle timer
# by itself, one sweep a minute keeps the session files in line, guests who were online while the portal was off keep
# their Internet, the fast probe path, captive-api by the real state, the Internet check (two failures in a row) and
# the private DNS (DoT) skip, opening hours and the guest limit.
SESS=/tmp/wiflow-client-sessions
LOG=/tmp/wiflow-log
setx(){ $B x nft list set inet wiflow_captive authed; }
sweep(){ $B x sh -c '. /usr/lib/wiflow/common.sh; sessions_sweep'; }
# evn <type> <client id>: events of this kind still queued plus the ones already sent to WordPress
evn(){
	local q h
	q="$($B x sh -c "grep -c '|$2|[^|]*|$1|' /tmp/wiflow-events.queue 2>/dev/null || true" | tail -n1)"
	h="$(grep -oE "\"client_id\": \"$2\", \"session_id\": \"[^\"]*\", \"event_type\": \"$1\"" /tmp/mock/wp/heartbeat.jsonl 2>/dev/null | wc -l)"
	echo $(( ${q:-0} + h ))
}
# sfield <mac> <n>: field n of the session file of a guest (1 mac, 2 client id, 3 session id, 4 ip, 5 connected, 6 authorized, 7 last, 8 absent)
sfield(){ $B x sh -c "cut -d'|' -f$2 $SESS/$(printf '%s' "$1" | tr -d : | tr a-f A-F) 2>/dev/null"; }
# exp <ip> <mac>: what the firewall set says about this guest's idle timer (e.g. "expires 29m58s")
exp(){ setx | grep -oiE "$1 \. $2 [^,}]*" | grep -o 'expires [0-9hms]*' | head -n1; }
inset(){ setx | grep -oiE "$1 \. $2" | wc -l | tr -d ' '; }
authz(){ # authz <ip> <session id>: the confirm, first line of the answer
	$B x env REMOTE_ADDR=$1 REQUEST_METHOD=POST QUERY_STRING="action=authorize&session_id=$2" /www-wiflow-portal/cgi-bin/portal | head -n1 | tr -d '\r'
}
mac5=A4:83:E7:55:55:55; ip5=10.10.10.61
mac6=A4:83:E7:66:66:66; ip6=10.10.10.62
mac7=A4:83:E7:77:77:77; ip7=10.10.10.64
mac8=A4:83:E7:88:88:88; ip8=10.10.10.63

# ---- 1. idle timer: a guest who sends packets keeps its entry, nothing watches it (a real veth phone, real nftables)
$B x nft delete element inet wiflow_captive authed "{ $ip1 . $mac1 }" >/dev/null 2>&1
gp="$($B x sh -c 'ip link add tgst type veth peer name tgstp && ip link set tgstp master br-wiflow && ip link set tgstp up && echo 1 > /proc/sys/net/ipv4/ip_forward; setsid unshare -n sleep 900 >/dev/null 2>&1 </dev/null & echo $!' | tail -n1)"
$B x sh -c "ip link set tgst netns $gp"
$B x nsenter -t "$gp" -n sh -c "ip link set lo up; ip link set tgst address $(echo $mac1 | tr A-F a-f); ip link set tgst up; ip addr add $ip1/24 dev tgst; ip route add default via 10.10.10.1"
gsend(){ $B x nsenter -t "$gp" -n python3 -c "import socket; s=socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.sendto(b'x', ('198.51.100.7', 9))"; }
$B x nft add element inet wiflow_captive authed "{ $ip1 . $mac1 timeout 30s }"
sleep 5
before="$(exp $ip1 $mac1)"; gsend; sleep 1; after="$(exp $ip1 $mac1)"
expect "idle timer: a guest who sends packets gets its timer renewed by the firewall itself (seconds left -> 30 minutes)" "$before|$after" '^expires [0-9]{1,2}s.*\|expires (29|30)m'
$B x nft delete element inet wiflow_captive authed "{ $ip1 . $mac1 }"
gsend; sleep 1
expect "idle timer: a guest who is not in the set never gets in by sending packets" "$(inset $ip1 $mac1)" '^0$'

# ---- 2. the confirm gives the idle time; a silent guest is dropped by the kernel, the sweep closes the session
$B x sh -c "rm -f $SESS/*"
out="$($B x $PC ensure $ip1)"; sid="${out#*|}"; cid="${out%%|*}"
expect "idle timer: the confirm opens the Internet with the idle time (30 minutes by default)" "$(authz $ip1 $sid)|$(exp $ip1 $mac1)" '204.*\|expires (29|30)m'
$B x nft delete element inet wiflow_captive authed "{ $ip1 . $mac1 }"
$B x nft add element inet wiflow_captive authed "{ $ip1 . $mac1 timeout 3s }"
sleep 5
expect "idle timer: a silent guest is dropped by the kernel, no program involved" "$(inset $ip1 $mac1)" '^0$'
n0="$(evn disconnected $cid)"
sweep
expect "sweep: the session of the dropped guest ends and 'disconnected' is reported" "$(sfield $mac1 6)|$(( $(evn disconnected $cid) - n0 ))" '^0\|[1-9]$'
$B x $PC is-authorized "$sid" && fail "sweep: the dropped guest still counts as authorized" || pass "sweep: the dropped guest is not authorized any more"
$B x $PC ensure $ip1 >/dev/null
expect "sweep: the same guest coming back starts a new visit ('connected' again, same session)" "$(sfield $mac1 8)|$(sfield $mac1 3 | grep -c "^$sid\$")|$(evn connected $cid)" '^0\|1\|[2-9]'

# ---- 3. session time: the minute sweep closes the Internet when the time is up
U set wiflow.core.guest_session_min=1; U commit wiflow
$B x sh -c '. /usr/lib/wiflow/common.sh; state_set wp_time_ok 1'
expect "session time: the guest confirms again" "$(authz $ip1 $sid)" '204'
$B x sh -c ". /usr/lib/wiflow/common.sh; f=\"\$(client_file_for_mac $mac1)\"; IFS='|' read -r m c s i cn au l ab < \"\$f\"; client_session_write \"\$f\" \"\$m\" \"\$c\" \"\$s\" \"\$i\" \"\$cn\" \$(( \$(date +%s) - 180 )) \"\$l\" \"\$ab\""
sweep
expect "session time: after the time is up the Internet closes and the guest has to confirm again" "$(inset $ip1 $mac1)|$(sfield $mac1 6)|$($B x grep -c 'Khách hết thời gian' $LOG)" '^0\|0\|[1-9]'
U set wiflow.core.guest_session_min=60; U commit wiflow

# ---- 4. new phones and forgotten sessions
printf '%s %s %s guest-five *\n' "$(( $(date +%s) + 14400 ))" "$(echo $mac5 | tr A-F a-f)" "$ip5" >> /tmp/dhcp.leases
$B x sh -c ". /usr/lib/wiflow/common.sh; now=\$(date +%s)
 client_session_write \"\$(client_file_for_mac $mac6)\" $mac6 cid6test sid6test $ip6 \$((now-4000)) 0 \$((now-2000)) 0
 client_session_write \"\$(client_file_for_mac $mac7)\" $mac7 cid7test sid7test $ip7 \$((now-9000)) 0 \$((now-8000)) \$((now-7300))"
sweep
cid5="$(sfield $mac5 2)"
expect "sweep: a phone that just got an address becomes a visit (a session and 'connected')" "$(sfield $mac5 4)|$(sfield $mac5 6)|$(evn connected "$cid5")" "^$ip5\\|0\\|[1-9]"
expect "sweep: a phone that never confirmed and went silent is forgotten, reported once" "$($B x sh -c "[ -f $SESS/A483E7666666 ] && echo kept || echo gone")|$(evn disconnected cid6test)" '^gone\|[1-9]'
expect "sweep: a visit that ended two hours ago is removed without a report" "$($B x sh -c "[ -f $SESS/A483E7777777 ] && echo kept || echo gone")|$(evn disconnected cid7test)" '^gone\|0$'

# ---- 5. the rules were off (safe mode, plan ended, no content, a rebuild): guests who were online keep the Internet
printf '1000 %s %s old-phone *\n' "$(echo $mac8 | tr A-F a-f)" "$ip8" >> /tmp/dhcp.leases
$B x sh -c "rm -f $SESS/*"
r="$($B x sh -c ". /usr/lib/wiflow/common.sh; /usr/lib/wiflow/portal-firewall disable; printf '%s|' \"\$(portal_state_name)\"; nft list table inet wiflow_captive >/dev/null 2>&1 && printf 'up|' || printf 'down|'; REMOTE_ADDR=$ip1 /www-wiflow-portal/cgi-bin/captive-api | tail -n1")"
expect "portal state: rules off with content on the router = off; captive-api then says 'not captive' (the Internet is open)" "$r" '^off\|down\|\{"captive":false\}$'
$B x /usr/lib/wiflow/portal-firewall enable
expect "carry-over: guests with a lease who were online meanwhile keep the Internet, an expired lease does not" "$(inset $ip1 $mac1)|$(inset $ip3 $mac3)|$(inset $ip5 $mac5)|$(inset $ip8 $mac8)" '^1\|1\|1\|0$'
expect "carry-over: the same idle timer applies (30 minutes)" "$(exp $ip5 $mac5)" '^expires (29|30)m'
expect "carry-over: the router says so in its log" "$($B x grep -c 'giữ mạng cho' $LOG)" '^[1-9]'
cid5="$(sfield $mac5 2)"
$B x sh -c "grep -q '^$cid5\$' /etc/wiflow/guests.known 2>/dev/null" && known=1 || known=0
expect "carry-over: they are marked as let in, with no 'authorized' event and nothing remembered or sent as a returning guest" "$([ "$(sfield $mac5 6)" -gt 0 ] && echo auth)|$(evn authorized "$cid5")|$known|$(cat /tmp/wiflow-guests.queue 2>/dev/null | grep -c "$cid5")" '^auth\|0\|0\|0$'
$B x nft delete element inet wiflow_captive authed "{ $ip5 . $mac5 }"
$B x /usr/lib/wiflow/portal-firewall ensure; $B x /usr/lib/wiflow/portal-firewall enable
expect "carry-over: only when the rules were off; a self-repair pass with the table in place never re-admits a guest" "$(inset $ip5 $mac5)" '^0$'
$B x nft delete table inet wiflow_captive
$B x sh -c '. /usr/lib/wiflow/common.sh; portal_activate'
expect "carry-over: a wiped table that is rebuilt gives the online guests their Internet back" "$(inset $ip5 $mac5)" '^1$'

# ---- 6. rules and the fast probe path
fw="$($B x nft list chain inet wiflow_captive forward)"
expect "rules: renew-on-traffic rule, new-connection limit per phone, no stale 10.0.0.2 rule" "$(printf '%s' "$fw" | grep -c 'update @authed')|$(printf '%s' "$fw" | grep -c 'limit rate over 500/second')|$($B x nft list ruleset | grep -c '10\.0\.0\.2')" '^1\|1\|0$'
probe(){ $B x env REMOTE_ADDR=$1 REQUEST_METHOD=GET HTTP_HOST=$2 REQUEST_URI=$3 /www-wiflow-portal/cgi-bin/portal | tr -d '\r'; }
expect "probe: a guest who is let in gets the answers the OS checks expect (Apple, Android), no portal page" "$(probe $ip1 captive.apple.com /hotspot-detect.html | grep -c Success)|$(probe $ip1 connectivitycheck.gstatic.com /generate_204 | head -n1)" '^1\|Status: 204'
ns0="$($B x sh -c "ls $SESS | wc -l" | tr -d ' ')"
u="$(probe $ip8 connectivitycheck.gstatic.com /generate_204 | head -n2 | tr '\n' ' ')"
expect "probe: a guest who is not let in is sent to the portal (302) at once, no session is created" "$u|$($B x sh -c "ls $SESS | wc -l" | tr -d ' ')|$ns0" '^Status: 302 Found Location: http://10\.10\.10\.1:2080/cgi-bin/portal \|([0-9]+)\|\1$'
ca(){ $B x env REMOTE_ADDR=$1 /www-wiflow-portal/cgi-bin/captive-api | tail -n1; }
expect "captive-api: a guest who is let in is not captive, one who is not is, with the portal address" "$(ca $ip1)|$(ca $ip8)" '^\{"captive":false\}\|\{"captive":true,"user-portal-url":"http://10\.10\.10\.1:2080/cgi-bin/portal"\}$'
U set wiflow.core.guest_idle_min=10; U commit wiflow
$B x /usr/lib/wiflow/portal-firewall enable
expect "idle time: the time set in the config goes into the rules, the guest stays in" "$($B x nft list chain inet wiflow_captive forward | grep -c 'update @authed.*timeout 10m')|$(inset $ip1 $mac1)" '^1\|1$'
U delete wiflow.core.guest_idle_min; U commit wiflow
$B x /usr/lib/wiflow/portal-firewall enable

# ---- 7. portal state in the health report
ps(){ $B x /usr/lib/wiflow/portal-hb report | python3 -c "import json,sys; print(json.load(sys.stdin)['health']['portal_state'])"; }
on="$(ps)"
$B x sh -c '. /usr/lib/wiflow/common.sh; safe_mode_enter'; safe="$(ps)"
$B x sh -c '. /usr/lib/wiflow/common.sh; state_set safe_until ""; portal_activate'; on2="$(ps)"
expect "health report: the portal state is on, then safe in safe mode, then on again" "$on|$safe|$on2" '^on\|safe\|on$'

# ---- 8. the Internet check: ONE checker with three tests (HTTPS, a TCP connect, plain HTTP); any one answering means online.
# One failed round is not an outage, two in a row are; a lost default route is an outage at once.
nc(){ $B x sh -c '. /usr/lib/wiflow/common.sh; net_check_now; echo "$? $(net_status_read | cut -d" " -f1)"'; }
rm -f /tmp/wiflow-net-fails
expect "net check: online" "$(nc)" '^0 1$'
expect "net check: the status file holds value, uptime seconds and latency (50 ms from the HTTPS check)" "$($B x cat /tmp/wiflow-net-status)" '^1 [0-9]+ 50$'
$B world 'w["block_https"]=True; w["block_443"]=True; w["block_http"]=True'
expect "net check: one failed round does not flip the status to offline" "$(nc)" '^1 1$'
expect "net check: the second failed round in a row does" "$(nc)" '^1 0$'
$B world 'w["block_https"]=False'
expect "net check: only the HTTPS check answers -> online again" "$(nc)" '^0 1$'
$B world 'w["block_https"]=True; w["block_443"]=False'
expect "net check: only the TCP connect answers -> online" "$(nc)" '^0 1$'
$B world 'w["block_443"]=True; w["block_http"]=False'
expect "net check: only the plain HTTP check answers -> online (a blocked HTTPS or TLS never makes the router look offline)" "$(nc)" '^0 1$'
$B world 'w["block_https"]=False; w["block_443"]=False; w["block_http"]=False'
$B x sh -c '. /usr/lib/wiflow/common.sh; printf "%s\n" 5 > /tmp/wiflow-net-fails; net_check_now'
expect "net check: a good round clears the failure count" "$($B x sh -c 'cat /tmp/wiflow-net-fails 2>/dev/null | wc -c')" '^0$'
# the status is written once per check and read without starting any program
$B x sh -c '. /usr/lib/wiflow/common.sh; net_status_write 1 42; net_status_read' | grep -Eq '^1 [0-9] 42$' && pass "net status: value, age (uptime based) and latency read back" || fail "net status read: $($B x sh -c '. /usr/lib/wiflow/common.sh; net_status_read')"
$B x sh -c '. /usr/lib/wiflow/common.sh; printf "1 999999 20\n" > /tmp/wiflow-net-status; net_status_read' | grep -Eq '^1 -' && fail "net status: a time in the future (clock or reboot) must read as old, not new" || pass "net status: a time in the future reads as old"
# net_maintain refreshes an old status and leaves a fresh one alone (no extra requests)
$B x sh -c '. /usr/lib/wiflow/common.sh; net_status_write 1 42'; : > /tmp/mock/calls.log
$B x sh -c '. /usr/lib/wiflow/common.sh; WIFLOW_NET_ON=30 net_maintain'
expect "net maintain: a fresh status is not checked again" "$(grep -c '^probe' /tmp/mock/calls.log)" '^0$'
$B x sh -c '. /usr/lib/wiflow/common.sh; printf "1 1 42\n" > /tmp/wiflow-net-status; WIFLOW_NET_ON=30 net_maintain'
expect "net maintain: an old status is checked again, once" "$(grep -c '^probe .* True$' /tmp/mock/calls.log | awk '{print ($1>=1)?"checked":"not"}')|$($B x sh -c '. /usr/lib/wiflow/common.sh; net_status_read | cut -d" " -f1')" '^checked\|1$'

# ---- 9. private DNS (853): refused while the network might be to blame, skipped for 30 minutes when it keeps being blocked
$B x sh -c '. /usr/lib/wiflow/common.sh; state_set dot_fails 0; state_set dot_skip_until 0'
sid8="$($B x $PC ensure $ip8 | sed 's/.*|//')"
$B world 'w["block_dot"]=True'
r1="$(authz $ip8 $sid8)"; r2="$(authz $ip8 $sid8)"; r3="$(authz $ip8 $sid8)"
expect "private DNS: blocked by the network -> refused twice, then skipped for 30 minutes and the guest gets in (and the log says so)" "$r1|$r2|$r3|$($B x grep -c 'tạm không yêu cầu' $LOG)" '503.*\|.*503.*\|.*204.*\|[1-9]'
$B x $PC revoke-session "$sid8"
$B x sh -c '. /usr/lib/wiflow/common.sh; state_set dot_fails 0; state_set dot_skip_until 0'
$B world 'w["block_dot"]=False; w["dot_ok"]=["9.9.9.9"]'
expect "private DNS: one of the four servers answering is enough" "$(authz $ip8 $sid8)|$($B x sh -c '. /usr/lib/wiflow/common.sh; state_get grant_last' | grep -o 'dot=[01]')" '204.*\|dot=1$'
$B world 'w.pop("dot_ok", None)'
$B x $PC revoke-session "$sid8"

# ---- 10. opening hours and the guest limit (one loop, no extra programs)
$B x sh -c '. /usr/lib/wiflow/common.sh; state_set wp_time_ok 1; guest_settings_set "" "" 1 "" "" "" off,off,off,off,off,off,off'
sid3x="$($B x $PC ensure $ip3 | sed 's/.*|//')"
expect "opening hours: closed -> the Internet is paused for guests, the confirm is refused (423), an OS check goes to the portal" "$($B x nft list chain inet wiflow_captive sched_fwd | grep -c wf-closed)|$(authz $ip3 $sid3x)|$(probe $ip1 connectivitycheck.gstatic.com /generate_204 | head -n1)" '^[1-9]\|.*423.*\|Status: 302'
$B x sh -c '. /usr/lib/wiflow/common.sh; guest_settings_set "" "" 0 "" "" "" none'
expect "opening hours: open again -> the pause is lifted" "$($B x nft list chain inet wiflow_captive sched_fwd | grep -c wf-closed)|$(probe $ip1 connectivitycheck.gstatic.com /generate_204 | head -n1)" '^0\|Status: 204'
$B x sh -c '. /usr/lib/wiflow/common.sh; guest_settings_set "" 1'
sid8="$($B x $PC ensure $ip8 | sed 's/.*|//')"
expect "guest limit: when every place is taken a new guest is refused (429)" "$(authz $ip8 $sid8)" '429'
$B x sh -c '. /usr/lib/wiflow/common.sh; guest_settings_set 60 0'

# ---- clean up the veth phone and the leases of this file
$B x sh -c "ip link del tgstp 2>/dev/null; kill $gp 2>/dev/null; rm -f $SESS/*"
sed -i "/$(echo $mac5 | tr A-F a-f)/d;/$(echo $mac8 | tr A-F a-f)/d" /tmp/dhcp.leases
