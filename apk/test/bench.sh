#!/bin/bash
# Wiflow Setup test bench (needs root): the real package code with the real
# ubusd, rpcd (ucode plugin), uci and ucode, inside a network namespace with
# veth "radios". netifd, the MediaTek WiFi driver and WordPress are mocks:
#   netsim.py  rebuilds uplink state (addresses, routes) from uci + world.json
#   netifd.uc  network.interface.* / network / iwinfo ubus objects
#   wp.py      WordPress device API (plugin 4.2, data generation 4)
#
#   bench.sh start | stop | agent | x <cmd...> | world '<python on w>'
# env: PFX (libubox/uci/ubus/rpcd prefix, default /opt/pfx),
#      UCODE_DIR (ucode build dir with ucode + *.so, default $PFX/ucode)
WFT="$(cd "$(dirname "$0")" && pwd)"
F="$(cd "$WFT/../wiflow/files" && pwd)"
PFX="${PFX:-/opt/pfx}"
U="${UCODE_DIR:-$PFX/ucode}"
PIDF=/tmp/wfbench.pid
ENVP="LD_LIBRARY_PATH=$PFX/lib PATH=$WFT/bin:$PFX/bin:$PFX/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin WIFLOW_REST=http://127.0.0.1:8099/wp-json WFT=$WFT PFX=$PFX WIFLOW_TICK=${WIFLOW_TICK:-20}"

x() { nsenter -t "$(cat $PIDF)" -n -m env -i HOME=/root $ENVP "$@"; }

install_files() {
	mkdir -p /usr/local/share/ucode /usr/local/lib/ucode /usr/libexec/wiflow "$PFX/share/rpcd/ucode" /etc/init.d
	ln -sfn "$F/usr/share/ucode/wiflow" /usr/local/share/ucode/wiflow
	for m in "$U"/*.so; do ln -sf "$m" /usr/local/lib/ucode/; done
	rm -f /usr/local/lib/ucode/libucode.so
	ln -sf "$U/ucode" /usr/bin/ucode
	for f in job agent provision; do ln -sf "$F/usr/libexec/wiflow/$f" /usr/libexec/wiflow/$f; done
	ln -sf "$F/usr/share/rpcd/ucode/wiflow" "$PFX/share/rpcd/ucode/wiflow"
	for s in firewall dnsmasq rpcd; do
		printf '#!/bin/sh\necho "init.d/%s $*" >> /tmp/mock/calls.log\n' $s > /etc/init.d/$s; chmod +x /etc/init.d/$s
	done
}

case "$1" in
start)
	$0 stop 2>/dev/null
	rm -rf /etc/config /etc/wiflow /tmp/wiflow /tmp/mock
	mkdir -p /etc/config /tmp/mock /var/run/ubus
	cp "$WFT"/cfg/* /etc/config/
	cat > /tmp/mock/world.json <<'EOF'
{ "wan_cable": false, "inet": { "wan": true, "apcli0": true, "apclix0": true },
  "aps": [
    { "ssid": "Cafe Sua Da", "bssid": "AA:BB:CC:00:00:01", "band": "2g", "channel": 6, "signal": -58, "enc": "psk2", "key": "cafe1234", "subnet": "192.168.31" },
    { "ssid": "Cafe Sua Da 5G", "bssid": "AA:BB:CC:00:00:02", "band": "5g", "channel": 36, "signal": -66, "enc": "mixed", "key": "cafe1234", "subnet": "192.168.32" },
    { "ssid": "Free WiFi Lobby", "bssid": "AA:BB:CC:00:00:03", "band": "2g", "channel": 11, "signal": -82, "enc": "none", "subnet": "10.0.0" },
    { "ssid": "Corp", "bssid": "AA:BB:CC:00:00:04", "band": "5g", "channel": 149, "signal": -70, "enc": "eap" },
    { "ssid": "Nha Ben Canh", "bssid": "AA:BB:CC:00:00:05", "band": "2g", "channel": 6, "signal": -64, "enc": "psk2", "key": "bencanh123", "subnet": "192.168.40" },
    { "ssid": "Office 5G", "bssid": "AA:BB:CC:00:00:06", "band": "5g", "channel": 100, "signal": -60, "enc": "psk2", "key": "office1234", "subnet": "192.168.50" }
  ],
  "clients": { "ra0": [], "rax0": [] } }
EOF
	install_files
	unshare -n -m sh -c 'mount -t sysfs none /sys; exec sleep infinity' & echo $! > $PIDF
	sleep 0.5
	x sh -c '
		ip link set lo up
		for d in wan apcli0 apclix0 ra0 rax0 lan1; do ip link add $d type veth peer name ${d}p; ip link set $d up; ip link set ${d}p up; done
		ip link add br-lan type bridge; ip link set br-lan up; ip addr add 10.0.0.1/24 dev br-lan
	'
	x setsid "$PFX/sbin/ubusd" -s /var/run/ubus/ubus.sock >/tmp/mock/ubusd.log 2>&1 &
	sleep 0.5
	x "$WFT/netsim.py" init
	x setsid ucode "$WFT/netifd.uc" >/tmp/mock/netifd.log 2>&1 &
	x setsid python3 "$WFT/wp.py" 8099 >/tmp/mock/wp.log 2>&1 &
	x setsid "$PFX/sbin/rpcd" -s /var/run/ubus/ubus.sock >/tmp/mock/rpcd.log 2>&1 &
	for i in $(seq 1 20); do x ubus list wiflow >/dev/null 2>&1 && x ubus list iwinfo >/dev/null 2>&1 && break; sleep 0.5; done
	x ubus list wiflow >/dev/null || { echo "bench: rpcd has no wiflow object"; cat /tmp/mock/rpcd.log; exit 1; }
	echo started
	;;
stop)
	pkill -f "^$PFX/sbin/rpc[d]"; pkill -f "^python3 $WFT/wp.p[y]"; pkill -f "^ucode $WFT/netifd.u[c]"
	pkill -f "^$PFX/sbin/ubus[d]"; pkill -f '^/usr/bin/ucode /usr/libexec/wiflow/agen[t]'
	[ -f $PIDF ] && kill "$(cat $PIDF)" 2>/dev/null; rm -f $PIDF
	;;
agent)
	pkill -f '^/usr/bin/ucode /usr/libexec/wiflow/agen[t]'; sleep 1
	nohup "$0" x /usr/bin/ucode /usr/libexec/wiflow/agent > /tmp/mock/agent.log 2>&1 &
	;;
x)
	shift; x "$@"
	;;
world)
	python3 -c "import json; w=json.load(open('/tmp/mock/world.json')); $2; json.dump(w, open('/tmp/mock/world.json','w'))"
	x "$WFT/netsim.py" world
	;;
*)
	echo "usage: $0 start|stop|agent|x <cmd>|world '<py>'" >&2; exit 1
	;;
esac
