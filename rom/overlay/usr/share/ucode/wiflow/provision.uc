// Wiflow Setup: what the package keeps on the router.
// - /etc/config/wiflow (account link state);
// - the device code as an extra Security Gate code.
// WiFi, network and firewall are never changed here: that is LuCI's job.
// The one exception is migrate(), which tidies up what Wiflow Setup 1.x
// created (guest network, rules) so the router follows its LuCI settings.
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

// Old marker of Wiflow Setup 1.x clean-up: nothing is removed any more.
export function migrate() {
	if (W.core('migrated') != '2')
		W.core_set({ migrated: '2', activated: null, internet_mode: null, guest_ssid: null, source_ssid: null,
			setup_username: null, tz_set: null });
	return {};
};

// 1.2.4: both bands use one WiFi name, "Wiflow". Only the two factory names
// are changed, and only once: a name set in LuCI stays as it is.
export function merge_ssid() {
	if (W.core('ssid_merged') == '1')
		return {};
	const c = cursor();
	c.load('wireless');
	let wl = false;
	c.foreach('wireless', 'wifi-iface', s => {
		if (s.mode == 'ap' && (s.ssid == 'Wiflow 2.4G' || s.ssid == 'Wiflow 5G')) {
			c.set('wireless', s['.name'], 'ssid', 'Wiflow');
			wl = true;
		}
	});
	if (wl) c.commit('wireless');
	W.core_set({ ssid_merged: '1' });
	return { wireless: wl };
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
