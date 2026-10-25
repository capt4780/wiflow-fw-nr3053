// Wiflow Setup: router configuration owned by the package.
// - guest network 10.10.10.1/24 (br-wiflow), isolated from the admin LAN,
//   allowed to reach Wiflow Setup on 10.0.0.1 (web) and the Internet;
// - source-WiFi uplink interface wiflow_wwan (DHCP, in the wan zone);
// - guest APs wiflow_guest_2g / wiflow_guest_5g, the first AP of each radio
//   (mt_wifi: ra0 / rax0), the station wiflow_uplink when a source is set;
// - the device code as an extra Security Gate code.
// The stock configs are saved once in /etc/wiflow/stock and come back when
// the package is removed.
'use strict';

import { readfile, writefile, mkdir, access, unlink, rename } from 'fs';
import { cursor } from 'uci';
import * as W from 'wiflow.setup';

const STOCK = `${W.ROOT}/stock`;
const CONFS = [ 'network', 'wireless', 'firewall', 'dhcp' ];

// Create / update a named section; only what differs is written.
function sect(c, conf, name, stype, vals) {
	if (c.get(conf, name) != stype) {
		c.delete(conf, name);
		c.set(conf, name, stype);
	}
	for (let k, v in vals) {
		const cur = c.get(conf, name, k);
		if (v == null) {
			if (cur != null) c.delete(conf, name, k);
		}
		else if (sprintf('%J', cur) != sprintf('%J', v))
			c.set(conf, name, k, v);
	}
};

export function backup_stock() {
	if (access(`${STOCK}/.complete`))
		return false;
	mkdir(W.ROOT, 0700);
	mkdir(STOCK, 0700);
	for (let f in CONFS)
		if (access(`/etc/config/${f}`))
			writefile(`${STOCK}/${f}`, readfile(`/etc/config/${f}`));
	writefile(`${STOCK}/.complete`, '');
	return true;
};

export function ensure_core() {
	if (!access('/etc/config/wiflow'))
		writefile('/etc/config/wiflow', "config core 'core'\n");
	const c = cursor();
	c.load('wiflow');
	const d = { guest_ssid: 'Wiflow', internet_mode: 'auto', paired: '0', setup_username: 'wiflow' };
	let ch = false;
	if (c.get('wiflow', 'core') != 'core') { c.set('wiflow', 'core', 'core'); ch = true; }
	for (let k, v in d)
		if (c.get('wiflow', 'core', k) == null) { c.set('wiflow', 'core', k, v); ch = true; }
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

export function ensure_networks() {
	const c = cursor();
	for (let f in CONFS) c.load(f);

	/* guest bridge + interface */
	sect(c, 'network', 'wiflow_guest_dev', 'device', { name: 'br-wiflow', type: 'bridge', bridge_empty: '1' });
	sect(c, 'network', 'wiflow_guest', 'interface', {
		proto: 'static', device: 'br-wiflow', ipaddr: `${W.GUEST_NET}.1/24`, netmask: null, delegate: '0'
	});

	/* source WiFi uplink */
	if (c.get('network', 'wiflow_wwan') != 'interface')
		sect(c, 'network', 'wiflow_wwan', 'interface', { proto: 'dhcp', metric: '20', peerdns: '1' });
	else if (c.get('network', 'wiflow_wwan', 'proto') != 'dhcp')
		c.set('network', 'wiflow_wwan', 'proto', 'dhcp');

	/* DHCP for guests */
	sect(c, 'dhcp', 'wiflow_guest', 'dhcp', {
		interface: 'wiflow_guest', start: '100', limit: '150', leasetime: '2h', force: '1',
		dhcpv6: 'disabled', ra: 'disabled', ndp: 'disabled'
	});

	/* firewall: guest zone */
	sect(c, 'firewall', 'wiflow_guest', 'zone', {
		name: 'wiflow_guest', network: [ 'wiflow_guest' ], input: 'REJECT', output: 'ACCEPT', forward: 'REJECT'
	});
	sect(c, 'firewall', 'wiflow_guest_wan', 'forwarding', { src: 'wiflow_guest', dest: 'wan' });
	sect(c, 'firewall', 'wiflow_guest_dhcp', 'rule', {
		name: 'Wiflow-Guest-DHCP', src: 'wiflow_guest', proto: 'udp', dest_port: '67-68', target: 'ACCEPT', family: 'ipv4'
	});
	sect(c, 'firewall', 'wiflow_guest_dns', 'rule', {
		name: 'Wiflow-Guest-DNS', src: 'wiflow_guest', proto: [ 'tcp', 'udp' ], dest_port: '53', target: 'ACCEPT'
	});
	sect(c, 'firewall', 'wiflow_guest_setup', 'rule', {
		name: 'Wiflow-Guest-Setup', src: 'wiflow_guest', proto: 'tcp', dest_ip: '10.0.0.1', dest_port: '80 443', target: 'ACCEPT', family: 'ipv4'
	});

	/* uplink belongs to the wan zone */
	c.foreach('firewall', 'zone', s => {
		if (s.name != 'wan')
			return;
		let nets = s.network ?? [];
		if (type(nets) == 'string') nets = split(nets, ' ');
		if (index(nets, 'wiflow_wwan') < 0) {
			push(nets, 'wiflow_wwan');
			c.set('firewall', s['.name'], 'network', nets);
		}
	});

	for (let f in CONFS)
		if (f != 'wireless')
			c.commit(f);
};

// first = true on install: the stock / LuCI-made APs of the mt_wifi radios
// are removed (kept in /etc/wiflow/stock) so each radio has one AP, the
// guest AP, as its main interface.
// 5 GHz channels 100-140: the mtwifi table maps CN and VN to A-band region
// 0 (36-64, 149-165 only), so the radio never even scans a modem on 100-140.
// Region 7 = 36-64, 100-140, 149-165. Country VN, table entry VN -> [1, 7].
const DAT_DEFS = '/usr/share/schema/mtwifi/dat-defs.json';

export function ensure_region() {
	const d = json(readfile(DAT_DEFS) ?? 'null');
	if (type(d?.COUNTRY_REGIONS) == 'object' && d.COUNTRY_REGIONS.VN?.[1] != 7) {
		d.COUNTRY_REGIONS.VN = [ 1, 7 ];
		if (writefile(`${DAT_DEFS}.tmp`, sprintf('%J', d)))
			rename(`${DAT_DEFS}.tmp`, DAT_DEFS);
	}
	const c = cursor();
	c.load('wireless');
	let changed = false;
	for (let r in W.radios())
		if (c.get('wireless', r.name, 'country') != 'VN') {
			c.set('wireless', r.name, 'country', 'VN');
			changed = true;
		}
	if (changed)
		c.commit('wireless');
	return changed;
};

export function ensure_wireless(first) {
	const c = cursor();
	c.load('wireless');
	const ssid = W.core('guest_ssid', 'Wiflow');
	const rs = W.radios();
	let changed = false;

	if (first) {
		c.foreach('wireless', 'wifi-iface', s => {
			if (match(s['.name'], /^wiflow_/) || s.mode != 'ap')
				return;
			if (W.radio_named(s.device)) {
				c.delete('wireless', s['.name']);
				changed = true;
			}
		});
	}

	for (let r in rs) {
		const name = `wiflow_guest_${r.band}`;
		const want = { device: r.name, mode: 'ap', network: 'wiflow_guest', ssid: ssid, encryption: 'none', isolate: '1' };
		let same = c.get('wireless', name) == 'wifi-iface';
		for (let k, v in want)
			if (c.get('wireless', name, k) != v) same = false;
		if (!same) {
			sect(c, 'wireless', name, 'wifi-iface', want);
			changed = true;
		}
		if (c.get('wireless', r.name, 'disabled') == '1') {
			c.delete('wireless', r.name, 'disabled');
			changed = true;
		}
	}
	if (changed)
		c.commit('wireless');
	if (ensure_region())
		changed = true;
	W.run('chmod 600 /etc/config/wireless');
	return changed;
};

// Channels for a stable guest WiFi (chosen once, when Wiflow is switched on):
// 2.4 GHz on 1, 6 or 11, 5 GHz on 36 or 149 (never a DFS channel), the one
// with the least WiFi around it.
export function pick_channels(nets) {
	const load = (from, to, band) => {
		let s = 0;
		for (let n in nets ?? [])
			if (n.band == band && n.channel >= from && n.channel <= to)
				s += max(1, n.signal + 100);
		return s;
	};
	let c2 = 6, best = load(2, 10, '2g');
	for (let ch in [ 1, 11 ]) {
		const l = load(ch - 4, ch + 4, '2g');
		if (l < best) { best = l; c2 = ch; }
	}
	const c5 = load(149, 165, '5g') < load(36, 48, '5g') ? 149 : 36;
	return { '2g': c2, '5g': c5 };
};

// Radio settings that keep the source and the guests stable on mt_wifi:
//  - the radio that carries the source station (repeater mode): channel
//    "auto", the driver follows the source's channel;
//  - every other radio: the fixed channel picked above, no automatic
//    channel changes that would drop the guests;
//  - 2.4 GHz 20 MHz, 5 GHz 80 MHz (160 MHz would need DFS channels).
// Returns true when the wireless config changed.
export function plan_radios() {
	const c = cursor();
	c.load('wireless');
	const up = (W.core('internet_mode', 'auto') != 'lan'
		&& c.get('wireless', 'wiflow_uplink') == 'wifi-iface'
		&& c.get('wireless', 'wiflow_uplink', 'disabled') != '1')
		? c.get('wireless', 'wiflow_uplink', 'device') : null;
	let changed = false;
	for (let r in W.radios()) {
		const want = {
			channel: r.name == up ? 'auto' : W.core(`ch_${r.band}`, r.band == '2g' ? '6' : '36'),
			htmode: r.band == '2g' ? 'HE20' : 'HE80'
		};
		for (let k, v in want)
			if (c.get('wireless', r.name, k) != v) {
				c.set('wireless', r.name, k, v);
				changed = true;
			}
	}
	if (changed)
		c.commit('wireless');
	return changed;
};

// Routing for the chosen Internet mode.
//   auto: cable first (metric 10), source WiFi as backup (metric 20)
//   lan:  cable only (the source station is switched off)
//   wifi: source WiFi only (the cable interface is switched off)
// Returns { network, wireless } = which configs changed.
export function apply_mode(mode) {
	const c = cursor();
	c.load('network');
	c.load('wireless');
	let net = false, wl = false;
	const set = (conf, s, k, v) => {
		const cur = c.get(conf, s, k);
		if (cur == v) return false;
		if (v == null) c.delete(conf, s, k); else c.set(conf, s, k, v);
		return true;
	};

	if (c.get('network', 'wan') == 'interface') {
		net = set('network', 'wan', 'disabled', mode == 'wifi' ? '1' : null) || net;
		net = set('network', 'wan', 'metric', '10') || net;
	}
	if (c.get('network', 'wiflow_wwan') == 'interface')
		net = set('network', 'wiflow_wwan', 'metric', mode == 'wifi' ? '10' : '20') || net;
	if (c.get('wireless', 'wiflow_uplink') == 'wifi-iface')
		wl = set('wireless', 'wiflow_uplink', 'disabled', mode == 'lan' ? '1' : null) || wl;

	if (net) c.commit('network');
	if (wl) c.commit('wireless');
	return { network: net, wireless: wl };
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

// Package removal: Wiflow's own sections go away, the cable WAN is switched
// back on and the WiFi comes back as it was before the install.
export function remove_ours() {
	const c = cursor();
	for (let f in CONFS) c.load(f);
	for (let s in [ 'wiflow_guest', 'wiflow_guest_dev', 'wiflow_wwan' ])
		c.delete('network', s);
	if (c.get('network', 'wan') == 'interface') {
		c.delete('network', 'wan', 'disabled');
		if (c.get('network', 'wan', 'metric') == '10')
			c.delete('network', 'wan', 'metric');
	}
	c.delete('dhcp', 'wiflow_guest');
	for (let s in [ 'wiflow_guest', 'wiflow_guest_wan', 'wiflow_guest_dhcp', 'wiflow_guest_dns', 'wiflow_guest_setup' ])
		c.delete('firewall', s);
	c.foreach('firewall', 'zone', s => {
		let nets = s.network ?? [];
		if (type(nets) == 'string') nets = split(nets, ' ');
		if (index(nets, 'wiflow_wwan') >= 0)
			c.set('firewall', s['.name'], 'network', filter(nets, n => n != 'wiflow_wwan'));
	});
	for (let f in [ 'network', 'dhcp', 'firewall' ])
		c.commit(f);

	if (access(`${STOCK}/wireless`)) {
		writefile('/etc/config/wireless', readfile(`${STOCK}/wireless`));
	}
	else {
		c.load('wireless');
		for (let s in [ 'wiflow_guest_2g', 'wiflow_guest_5g', 'wiflow_uplink' ])
			c.delete('wireless', s);
		c.commit('wireless');
	}
	W.run('chmod 600 /etc/config/wireless');
	unlink(`${STOCK}/.complete`);
};
