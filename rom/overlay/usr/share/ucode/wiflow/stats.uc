// Wiflow App numbers for the dashboard: CPU, memory, storage, temperature,
// connected devices, WiFi networks, the Internet source and a 24 h history.
// Only the agent calls this (one sample every 20 s; the WiFi part every 60 s).
// Everything lives in RAM (/tmp/wiflow/st), nothing is written to flash.
'use strict';

import { readfile } from 'fs';
import * as W from 'wiflow.setup';

function jq(cmd) {
	let o = null;
	try { o = json(W.sh(cmd)); } catch (e) { o = null; }
	return o;
}

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

function enc_text(e) {
	if (!e || !e.enabled)
		return 'Open';
	return replace(e.description ?? 'Encrypted', /\s*\(.*\)/, '');
}

// Access points (SSID, band, channel, devices) and the source WiFi (client).
function wifi() {
	const nets = [], macs = {};
	let n2 = 0, n5 = 0, src = null;
	const d = jq("ubus -t 3 call iwinfo devices '{}'");
	for (let dev in d?.devices ?? []) {
		if (!match(dev, /^[A-Za-z0-9_.-]+$/))
			continue;
		const i = jq(`ubus -t 3 call iwinfo info '{"device":"${dev}"}'`);
		if (!i)
			continue;
		const ch = W.num(i.channel, 0);
		const band = (ch > 14 || W.num(i.frequency, 0) >= 4900) ? '5g' : '2g';
		if (i.mode == 'Client' || match(dev, /^apcli/)) {
			if (i.ssid)
				src = { ssid: i.ssid, band: band, signal: W.num(i.signal, 0), channel: ch };
			continue;
		}
		if (i.mode != 'Master' || !i.ssid)
			continue;
		const a = jq(`ubus -t 3 call iwinfo assoclist '{"device":"${dev}"}'`);
		let n = 0;
		for (let s in a?.results ?? []) {
			n++;
			if (s.mac)
				macs[uc(s.mac)] = 1;
		}
		if (band == '5g') n5 += n; else n2 += n;
		push(nets, { ssid: i.ssid, band: band, channel: ch, clients: n, enc: enc_text(i.encryption) });
	}
	return { nets: nets, macs: macs, n2: n2, n5: n5, src: src };
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
			ssid: viaWifi ? (src.ssid ?? '') : '', band: viaWifi ? (src.band ?? '') : '', signal: viaWifi ? (src.signal ?? 0) : 0,
			ip: r?.ip ?? '', gateway: r?.gateway ?? ''
		};
	}
	tick++;

	W.st_set('stats', st);
	history(st.clients?.now, latency);
	return st;
};
