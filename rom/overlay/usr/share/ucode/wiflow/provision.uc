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

// From Wiflow Setup 1.x (once): drop the guest network br-wiflow with its
// DHCP and firewall rules, and put the guest APs back on the LAN network.
// The source WiFi (client) and every other setting stay as they are, so a
// source joined before keeps working. Returns what to reload.
export function migrate() {
	if (W.core('migrated') == '2')
		return {};
	const c = cursor();
	for (let f in [ 'network', 'wireless', 'firewall', 'dhcp' ]) c.load(f);
	let net = false, wl = false, fw = false, dh = false;

	for (let s in [ 'wiflow_guest', 'wiflow_guest_dev' ])
		if (c.get('network', s) != null) { c.delete('network', s); net = true; }
	if (c.get('dhcp', 'wiflow_guest') != null) { c.delete('dhcp', 'wiflow_guest'); dh = true; }
	for (let s in [ 'wiflow_guest', 'wiflow_guest_wan', 'wiflow_guest_dhcp', 'wiflow_guest_dns', 'wiflow_guest_setup' ])
		if (c.get('firewall', s) != null) { c.delete('firewall', s); fw = true; }

	c.foreach('wireless', 'wifi-iface', s => {
		if (s.network == 'wiflow_guest') {
			c.set('wireless', s['.name'], 'network', 'lan');
			c.delete('wireless', s['.name'], 'isolate');
			wl = true;
		}
	});
	// the cable WAN is no longer switched off by Wiflow (it set metric 10 with it)
	if (c.get('network', 'wan', 'metric') == '10') {
		c.delete('network', 'wan', 'metric');
		c.delete('network', 'wan', 'disabled');
		net = true;
	}

	if (net) c.commit('network');
	if (wl) c.commit('wireless');
	if (fw) c.commit('firewall');
	if (dh) c.commit('dhcp');
	W.core_set({ migrated: '2', activated: null, internet_mode: null, guest_ssid: null, source_ssid: null,
		setup_username: null, tz_set: null });
	return { network: net, wireless: wl, firewall: fw, dhcp: dh };
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
