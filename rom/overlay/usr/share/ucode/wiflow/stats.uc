// Wiflow App numbers for the dashboard: CPU, memory, storage, temperature,
// connected devices, WiFi networks, the Internet source and a 24 h history.
// Only the agent calls this (one sample every 20 s; the WiFi part every 60 s).
// Everything lives in RAM (/tmp/wiflow/st), nothing is written to flash.
'use strict';

import { readfile, lsdir } from 'fs';
import { cursor } from 'uci';
import * as W from 'wiflow.setup';

function fields(line) {
	return split(trim(replace(line ?? '', /\s+/g, ' ')), ' ');
}

// CPU load in percent since the previous sample.
function cpu() {
	const f = fields(split(readfile('/proc/stat') ?? '', '\n')[0]);
	let total = 0;
	for (let i = 1; i < length(f); i++)
		total += W.num(f[i], 0);
	const idle = W.num(f[4], 0) + W.num(f[5], 0);
	const prev = W.st_get('cpu_prev');
	W.st_set('cpu_prev', [ idle, total ]);
	if (!prev || total <= prev[1])
		return null;
	return int(100 * (1 - (idle - prev[0]) / (total - prev[1])) + 0.5);
}

function meminfo(k) {
	const m = match(readfile('/proc/meminfo') ?? '', regexp(`${k}:\\s+([0-9]+)`));
	return m ? +m[1] : 0;
}

function metrics() {
	const total = meminfo('MemTotal'), avail = meminfo('MemAvailable');
	const dl = split(trim(W.sh('df -k /overlay')), '\n');
	const df = fields(dl[length(dl) - 1]);
	const t = readfile('/sys/class/thermal/thermal_zone0/temp');
	return {
		cpu: cpu(),
		mem_total_mb: int(total / 1024), mem_used_mb: int((total - avail) / 1024),
		flash_total_mb: int(W.num(df[1], 0) / 1024), flash_used_mb: int(W.num(df[2], 0) / 1024),
		temp: t != null ? int(W.num(trim(t), 0) / 1000) : null,
		load: +(split(readfile('/proc/loadavg') ?? '0', ' ')[0])
	};
}

// The default route: device, gateway and our address on it.
function route() {
	for (let l in split(readfile('/proc/net/route') ?? '', '\n')) {
		const f = fields(l);
		if (length(f) >= 8 && f[1] == '00000000' && f[7] == '00000000') {
			const g = f[2];
			const gw = `${hexdec(substr(g, 6, 2))}.${hexdec(substr(g, 4, 2))}.${hexdec(substr(g, 2, 2))}.${hexdec(substr(g, 0, 2))}`;
			const a = match(W.sh(`ip -4 -o addr show dev ${W.q(f[0])}`), /inet ([0-9.]+)/);
			return { dev: f[0], gateway: gw, ip: a ? a[1] : '' };
		}
	}
	return null;
}

// Nothing here talks to the WiFi driver (no iwinfo, no iwpriv): the driver is
// the router's most delicate part and LuCI owns it. The WiFi names come from
// the configuration, the devices from the bridge forwarding table of the kernel.
const SYSNET = getenv('WIFLOW_SYSNET') || '/sys/class/net';

function enc_text(e) {
	switch (e ?? 'none') {
	case 'none': return 'Open';
	case 'psk2': case 'psk2+ccmp': case 'psk2+aes': return 'WPA2-PSK';
	case 'psk': case 'psk+ccmp': return 'WPA-PSK';
	case 'psk-mixed': case 'psk-mixed+ccmp': return 'WPA/WPA2-PSK';
	case 'sae': return 'WPA3-SAE';
	case 'sae-mixed': return 'WPA2/WPA3';
	default: return uc(`${e}`);
	}
}

// Access points and the source WiFi, as configured in LuCI.
function wifi_conf() {
	const c = cursor();
	c.load('wireless');
	const dev = {};
	c.foreach('wireless', 'wifi-device', d => {
		dev[d['.name']] = { band: d.band == '5g' ? '5g' : '2g', channel: d.channel, off: d.disabled == '1' };
	});
	const nets = [];
	let src = null;
	c.foreach('wireless', 'wifi-iface', s => {
		const d = dev[s.device];
		if (!d || d.off || s.disabled == '1' || !s.ssid)
			return;
		if (s.mode == 'sta') {
			if (!src)
				src = { ssid: s.ssid, band: d.band };
			return;
		}
		if (s.mode == 'ap')
			push(nets, { ssid: s.ssid, band: d.band, channel: (d.channel == null || d.channel == 'auto') ? 'Auto' : W.num(d.channel, 0), clients: 0, enc: enc_text(s.encryption) });
	});
	return { nets: nets, src: src };
}

// WiFi devices seen by the bridge: { MAC: band }. Entries come from
// brforward (16 bytes each: MAC, port, is_local, age, port high byte, pad);
// the ports named ra* / rax* are the WiFi interfaces (2.4 GHz / 5 GHz).
function stations() {
	const out = {};
	const ports = {};
	for (let n in lsdir(`${SYSNET}/br-lan/brif`) ?? []) {
		const p = trim(readfile(`${SYSNET}/br-lan/brif/${n}/port_no`) ?? '');
		if (p != '')
			ports[hexdec(replace(p, /^0x/, ''))] = n;
	}
	const raw = readfile(`${SYSNET}/br-lan/brforward`) ?? '';
	for (let o = 0; o + 16 <= length(raw); o += 16) {
		const port = ord(raw, o + 6) + ord(raw, o + 12) * 256;
		if (ord(raw, o + 7) != 0)
			continue;
		const name = ports[port];
		if (!name || !match(name, /^ra/))
			continue;
		out[sprintf('%02X:%02X:%02X:%02X:%02X:%02X', ord(raw, o), ord(raw, o + 1), ord(raw, o + 2), ord(raw, o + 3), ord(raw, o + 4), ord(raw, o + 5))] = match(name, /^ra[0-9]/) ? '2g' : '5g';
	}
	return out;
}

function wifi() {
	const w = wifi_conf();
	const macs = stations();
	let n2 = 0, n5 = 0;
	for (let m, b in macs) {
		if (b == '5g') n5++; else n2++;
	}
	for (let n in w.nets)
		n.clients = n.band == '5g' ? n5 : n2;
	return { nets: w.nets, macs: macs, n2: n2, n5: n5, src: w.src };
}

// Unique devices seen since local midnight.
function today(macs) {
	const lt = localtime(time());
	const day = `${lt.year}-${lt.yday}`;
	let s = W.st_get('seen');
	if (!s || s.day != day)
		s = { day: day, macs: {} };
	for (let m, v in macs) {
		if (length(s.macs) < 2000)
			s.macs[m] = 1;
	}
	W.st_set('seen', s);
	return length(s.macs);
}

// One bucket per hour for the last 24 h: most devices, mean latency.
function history(devices, latency) {
	const h = int(time() / 3600);
	const s = W.st_get('series', {});
	const k = `${h}`;
	const b = s[k] ?? { d: null, ls: 0, ln: 0 };
	if (devices != null)
		b.d = max(b.d ?? 0, devices);
	if (latency != null && latency >= 0) {
		b.ls += latency;
		b.ln++;
	}
	s[k] = b;
	for (let key in keys(s)) {
		if (+key < h - 23)
			delete s[key];
	}
	W.st_set('series', s);
}

let tick = 0;

export function sample(latency) {
	const st = W.st_get('stats', {});
	st.metrics = metrics();

	if (tick % 3 == 0 || !st.clients) {
		const w = wifi();
		const r = route();
		st.networks = w.nets;
		st.clients = { now: w.n2 + w.n5, band2g: w.n2, band5g: w.n5, today: today(w.macs) };
		const src = w.src ?? {};
		const viaWifi = r && match(r.dev, /^(apcli|apclii|apclix)/);
		st.source = {
			ssid: viaWifi ? (src.ssid ?? '') : '', band: viaWifi ? (src.band ?? '') : '',
			ip: r?.ip ?? '', gateway: r?.gateway ?? ''
		};
	}
	tick++;

	W.st_set('stats', st);
	history(st.clients?.now, latency);
	return st;
};
