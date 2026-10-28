// Wiflow App: what the firmware keeps on the router.
// - /etc/config/wiflow (account link state);
// - the device code as an extra Security Gate code;
// - the guest network (br-wiflow), written on first boot and checked at every start.
// Source WiFi and the WiFi names are never changed here: that is LuCI's job.
'use strict';

import { readfile, writefile, access } from 'fs';
import { cursor } from 'uci';
import * as W from 'wiflow.setup';

export function ensure_core() {
	if (!access('/etc/config/wiflow'))
		writefile('/etc/config/wiflow', "config core 'core'\n");
	const c = cursor();
	c.load('wiflow');
	let ch = false;
	if (c.get('wiflow', 'core') != 'core') { c.set('wiflow', 'core', 'core'); ch = true; }
	if (c.get('wiflow', 'core', 'paired') == null) { c.set('wiflow', 'core', 'paired', '0'); ch = true; }
	if (ch) c.commit('wiflow');
	W.run('chmod 600 /etc/config/wiflow');
};

export function ensure_gate_code() {
	const pin = W.device_pin();
	if (!pin || !access('/etc/config/wiflow_gate'))
		return;
	const c = cursor();
	c.load('wiflow_gate');
	let list = c.get('wiflow_gate', 'main', 'code') ?? [];
	if (type(list) == 'string') list = [ list ];
	if (index(list, pin) < 0) {
		push(list, pin);
		c.set('wiflow_gate', 'main', 'code', list);
		c.commit('wiflow_gate');
	}
};

export function remove_gate_code() {
	const pin = W.device_pin();
	if (!pin || !access('/etc/config/wiflow_gate'))
		return;
	const c = cursor();
	c.load('wiflow_gate');
	let list = c.get('wiflow_gate', 'main', 'code') ?? [];
	if (type(list) == 'string') list = [ list ];
	list = filter(list, x => x != pin);
	c.set('wiflow_gate', 'main', 'code', length(list) ? list : [ 'WIFDIDNR3053' ]);
	c.commit('wiflow_gate');
};

// The guest network (br-wiflow, 10.10.10.0/24) belongs to Wiflow OS: it is written on
// first boot and checked at every start. Anything missing is written again, and the
// factory Wiflow WiFi (still on the LAN) is moved onto it once. Returns what changed.
export function ensure_guest_network() {
	const r = W.run('/usr/libexec/wiflow/guest-net ensure');
	return { reloaded: match(r.out ?? '', /changed/) != null };
};

export function reload(what) {
	if (what.network)
		W.run('ubus call network reload');
	if (what.wireless)
		W.run('wifi reload');
	if (what.firewall)
		W.run('/etc/init.d/firewall reload');
	if (what.dhcp)
		W.run('/etc/init.d/dnsmasq reload');
};
