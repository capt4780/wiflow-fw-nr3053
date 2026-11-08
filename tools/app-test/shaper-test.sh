# Auto fair-share tests (sourced by run.sh): the real controller (shaper.awk) on a
# simulated Internet link, and the tc commands it would run (recorded by a stub).
SA="$T/../../rom/overlay/usr/lib/wiflow/shaper.awk"
python3 - "$SA" <<'PY' && pass "auto share: simulated link keeps the delay low and the rate high" || fail "auto share: simulation"
import random,subprocess,sys
def link(seed):
    r=random.Random(seed); cap=[]; c=60.0
    for t in range(1800):
        if t%300==0: c=r.choice([20.0,50.0,100.0,40.0])
        cap.append(c)
    return cap
def run(seed):
    cap=link(seed); rr=random.Random(seed+1)
    p=subprocess.Popen(['awk','-W','interactive','-f',sys.argv[1],'-v','SIM=1','-v','TC=cat'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True,bufsize=1)
    R=20.0;q=0.0;eff=[];dl=[]
    for t in range(1800):
        busy=(t//200)%3!=2
        offer=R if busy else 0.01
        got=min(offer,cap[t]); q=max(0,q+offer-cap[t]); q=min(q,cap[t]*0.35)
        delay=q/cap[t]*1000
        rtt=20+delay+rr.uniform(-1.5,1.5)
        p.stdin.write("%.3f %.1f 0\n"%(rtt,got*1000));p.stdin.flush()
        R=int(p.stdout.readline().split()[1])/1000
        if busy and t>120: eff.append(got/cap[t]);dl.append(delay)
    p.stdin.close();p.wait()
    return sum(eff)/len(eff),sum(dl)/len(dl)
for s in (1,2,3):
    e,d=run(s)
    print(s,round(e,2),round(d,1))
    assert e>0.65 and d<120,(s,e,d)
PY
S=/tmp/shaper-t; rm -rf $S; mkdir -p $S/sys $S/cs
printf '#!/bin/sh\ncat >> %s/tc.log\n' "$S" > $S/tc; chmod +x $S/tc; echo 0 > $S/sys/tx_bytes; echo 0 > $S/sys/rx_bytes
printf 'a|b|c|10.10.10.21|x|1700|0|0\nd|e|f|10.10.10.35|x|0|0|0\ng|h|i|10.10.10.40|x|1700|0|0\nj|k|l|192.168.1.9|x|1700|0|0\n' > $S/cs/s1
( for i in $(seq 1 35); do echo "64 bytes from 1.1.1.1: seq=$i ttl=57 time=21.3 ms"; sleep 0.02; done ) | awk -f "$SA" -v BR=br-wiflow -v IFB=ifb0 -v TC=$S/tc -v SYS=$S/sys -v "GCMD=awk -F'|' '\$6+0>0{print \$4}' $S/cs/* 2>/dev/null" -v MAXDN=8000 -v MAXUP=0 -v STATUS=$S/status
expect "auto share: status line (limits, guests, state)" "$(cat $S/status)" '^35 20000 20000 [0-9]+ [0-9]+ 21 21 2 on$'
expect "auto share: root queues for download, upload and the redirect" "$(grep -c 'htb default fff\|ingress\|redirect dev ifb0' $S/tc.log)" '^4$'
expect "auto share: only authorized guests of 10.10.10.x get a class" "$(grep -c '^class add dev br-wiflow' $S/tc.log)|$(grep -c 'classid 1:25 \|classid 1:38 ' $S/tc.log)" '^2\|'
expect "auto share: u32 hash on the last octet (download dst, upload src)" "$(grep -c 'ht 2:15: match ip dst 10.10.10.21 flowid 1:25' $S/tc.log)|$(grep -c 'ht 2:15: match ip src 10.10.10.21 flowid 1:25' $S/tc.log)" '^1\|1$'
expect "auto share: fair share and the fixed speed as the per-guest maximum" "$(grep -m1 '^class add dev br-wiflow parent 1:1 classid 1:25' $S/tc.log)" 'rate 8000kbit ceil 8000kbit'
expect "auto share: the router (not a guest) is never limited" "$(grep -c 'default fff' $S/tc.log)" '^2$'
# a guest leaves: its filter and class are removed
rm -f $S/tc.log; printf 'a|b|c|10.10.10.21|x|1700|0|0\n' > $S/cs/s1; rm -f $S/cs/s1.x
( for i in $(seq 1 12); do echo "64 bytes from 1.1.1.1: seq=$i ttl=57 time=21.3 ms"; done ) | awk -f "$SA" -v BR=br-wiflow -v IFB=ifb0 -v TC=$S/tc -v SYS=$S/sys -v "GCMD=awk -F'|' '\$6+0>0{print \$4}' $S/cs/* 2>/dev/null" -v MAXDN=0 -v MAXUP=0 -v STATUS=$S/status >/dev/null
expect "auto share: one guest gets the whole rate" "$(grep -m1 '^class add dev br-wiflow parent 1:1 classid 1:25' $S/tc.log)" 'rate 20000kbit ceil 20000kbit'
# Switch (same path as LuCI): config, status and the fixed policer stepping aside
$B x /usr/lib/wiflow/portal-hb guest-settings /dev/null >/dev/null 2>&1
echo '{"down_kbps":9000,"up_kbps":3000}' > /tmp/gs.json; $B x /usr/lib/wiflow/portal-hb guest-settings /tmp/gs.json
expect "auto share: on by default (no config entry); fixed speeds set meanwhile are not applied" "$(st "(s['speed']['auto'], s['speed']['state'], s['speed']['fixed_down'])")|$($B x nft list chain inet wiflow_captive shape 2>/dev/null | grep -c 'limit rate over [0-9]* kbytes')" "^\\(True, 'waiting', 9000\\)\\|0$"
call guest_auto '{"on":false}' >/dev/null
expect "auto share: switched off from LuCI (config, status, the fixed limit policed again)" "$(U get wiflow.core.guest_auto)|$(st "(s['speed']['auto'], s['speed']['state'])")|$($B x nft list chain inet wiflow_captive shape 2>/dev/null | grep -c 'limit rate over [0-9]* kbytes')" "^0\\|\\(False, 'off'\\)\\|2$"
call guest_auto '{"on":true}' >/dev/null
expect "auto share: switched on (config, status, no policer; idle without guests)" "$(U get wiflow.core.guest_auto)|$(st "(s['speed']['auto'], s['speed']['active'], s['speed']['fixed_down'])")|$($B x nft list chain inet wiflow_captive shape 2>/dev/null | grep -c 'limit rate over [0-9]* kbytes')" "^1\\|\\(True, False, 9000\\)\\|0$"
echo '{"auto_share":false}' > /tmp/gs.json; $B x /usr/lib/wiflow/portal-hb guest-settings /tmp/gs.json
expect "auto share: off again from WordPress, fixed limit back" "$(U get wiflow.core.guest_auto)|$($B x nft list chain inet wiflow_captive shape 2>/dev/null | grep -c 'limit rate over [0-9]* kbytes')" '^0\|2$'
echo '{"down_kbps":0,"up_kbps":0}' > /tmp/gs.json; $B x /usr/lib/wiflow/portal-hb guest-settings /tmp/gs.json
# new-connection flood limit: in the guest chain, and added again after a firewall rebuild
expect "guest: new-connection rate limit per phone in the shape chain" "$($B x nft list chain inet wiflow_captive shape 2>/dev/null | grep -c 'ct state new.*limit rate over 500/second')" '^1$'
# fixed speed per guest typed in LuCI (Mbit/s on screen, kbit/s on the router)
expect "guest_limit: down/up saved in kbit/s" "$(call guest_limit '{"down":5000,"up":2000}' | tr -d ' \n\t')|$(U get wiflow.core.guest_down_kbps)|$(U get wiflow.core.guest_up_kbps)" '^\{"ok":true\}\|5000\|2000$'
expect "guest_limit: a speed out of range is refused" "$(call guest_limit '{"down":2000000,"up":0}' | tr -d ' \n\t')|$(U get wiflow.core.guest_down_kbps)" '^\{"ok":false.*\|5000$'
expect "guest_limit: 0 = no limit" "$(call guest_limit '{"down":0,"up":0}' >/dev/null; U get wiflow.core.guest_down_kbps)" '^0$'
