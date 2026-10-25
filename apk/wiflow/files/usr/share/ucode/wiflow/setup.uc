// Wiflow Setup for Viettel NR3053 (Wiflow OS, MediaTek mt_wifi).
// Shared code for the LuCI rpcd plugin (ubus "wiflow"), the background job
// runner (/usr/libexec/wiflow/job) and the agent (/usr/libexec/wiflow/agent).
//
// Runtime state lives in RAM (/tmp/wiflow), settings in uci "wiflow",
// the device identity in /etc/wiflow/device-id.
'use strict';

import { readfile, writefile, rename, mkdir, popen, unlink, access, glob, lsdir, stat } from 'fs';
import { cursor } from 'uci';
import { connect } from 'ubus';

export const VERSION = '1.5.0';
export const GEN = '4';
export const MODEL = 'Viettel NR3053';
export const REST = getenv('WIFLOW_REST') || 'https://wiflow.projifylab.com/wp-json';
export const ROOT = '/etc/wiflow';
export const RUN = '/tmp/wiflow';
export const GUEST_NET = '10.10.10';

/* ------------------------------------------------------------------ basics */

export function q(s) {
	return "'" + replace(`${s ?? ''}`, "'", "'\\''") + "'";
};

// Run a shell command, return { code, out }.
export function run(cmd) {
	const p = popen(`${cmd} 2>/dev/null`, 'r');
	if (!p)
		return { code: -1, out: '' };
	const out = p.read('all') ?? '';
	const code = p.close();
	return { code: code, out: out };
};

export function sh(cmd) {
	return run(cmd).out;
};

export function uptime() {
	return int(split(readfile('/proc/uptime') ?? '0', '.')[0]);
};

export function now() {
	return time();
};

export function num(v, dflt) {
	const n = +v;
	return (type(n) == 'int' || type(n) == 'double') && n == n ? int(n) : (dflt ?? 0);
};

function rundir() {
	mkdir(RUN, 0700);
	mkdir(`${RUN}/st`, 0700);
};

/* --------------------------------------------------------- RAM state (k/v) */
// One small JSON file per key, written with rename: no lost updates between
// the agent, the job runner and rpcd.

export function st_get(k, dflt) {
	const s = readfile(`${RUN}/st/${k}`);
	if (s == null)
		return dflt;
	const v = json(s);
	return v ?? dflt;
};

export function st_set(k, v) {
	rundir();
	const f = `${RUN}/st/${k}`;
	if (v == null) {
		unlink(f);
		return;
	}
	const t = `${f}.${clock()[1]}.tmp`;
	writefile(t, sprintf('%J', v));
	rename(t, f);
};

/* --------------------------------------------------------------- RAM log */
// epoch|area|message, about the last 200 lines. Areas follow the WordPress
// log filter: uplink, watchdog, guest, content, security, system.

export function wlog(area, msg) {
	rundir();
	const f = `${RUN}/log`;
	const line = sprintf('%d|%s|%s\n', time(), area, replace(`${msg}`, /[|\n]/g, ' '));
	const fd = popen(`logger -t wiflow-${area} ${q(msg)}`, 'r');
	if (fd) fd.close();
	let cur = readfile(f) ?? '';
	if (length(cur) > 24000) {
		const l = split(cur, '\n');
		cur = join('\n', slice(l, length(l) - 150));
	}
	writefile(f, cur + line);
};

export function wlog_list(n) {
	const l = filter(split(readfile(`${RUN}/log`) ?? '', '\n'), x => length(x));
	const out = [];
	for (let i = length(l) - 1; i >= 0 && length(out) < n; i--) {
		const p = split(l[i], '|');
		if (length(p) >= 3)
			push(out, { t: +p[0], a: p[1], m: join('|', slice(p, 2)) });
	}
	return out;
};

/* ------------------------------------------------------------------- uci */

export function uci_get(conf, sec, opt) {
	const c = cursor();
	return c.get(conf, sec, opt);
};

export function core(opt, dflt) {
	return uci_get('wiflow', 'core', opt) ?? dflt;
};

export function core_set(vals) {
	const c = cursor();
	c.load('wiflow');
	if (c.get('wiflow', 'core') == null)
		c.set('wiflow', 'core', 'core');
	for (let k, v in vals) {
		if (v == null)
			c.delete('wiflow', 'core', k);
		else
			c.set('wiflow', 'core', k, `${v}`);
	}
	c.commit('wiflow');
	run('chmod 600 /etc/config/wiflow');
};

/* -------------------------------------------------------------- identity */

export function device_id() {
	const s = trim(readfile(`${ROOT}/device-id`) ?? '');
	return match(s, /^WIFDID-NR3053-[0-9]{6}$/) ? s : null;
};

// The 6 digits come from the factory MAC, so the code printed for this
// router stays the same after a factory reset or a reinstall.
export function ensure_device_id() {
	let id = device_id();
	if (id)
		return id;

	let seed = '';
	for (let dev in [ 'eth0', 'br-lan', 'lan1', 'wan' ]) {
		seed = trim(readfile(`/sys/class/net/${dev}/address`) ?? '');
		if (length(seed) && seed != '00:00:00:00:00:00')
			break;
	}
	let n = 0;
	if (length(seed)) {
		const h = split(sh(`printf %s ${q('wiflow-nr3053:' + seed)} | sha256sum`), ' ')[0];
		n = int(hex(substr(h, 0, 8)));
	}
	if (!n) {
		const r = readfile('/dev/urandom', 4) ?? '';
		for (let i = 0; i < length(r); i++)
			n = n * 256 + ord(r, i);
	}
	id = sprintf('WIFDID-NR3053-%06d', 100000 + n % 900000);
	mkdir(ROOT, 0700);
	writefile(`${ROOT}/device-id`, id + '\n');
	run(`chmod 600 ${ROOT}/device-id`);
	return id;
};

export function device_pin() {
	const id = device_id();
	return id ? substr(id, -6) : null;
};

export function os_version() {
	return trim(readfile('/etc/wiflow_release') ?? '') || '1.0.0';
};

/* ---------------------------------------------------------------- network */

let ubus_conn = null;

export function bus() {
	if (!ubus_conn)
		ubus_conn = connect();
	return ubus_conn;
};

export function ifstatus(name) {
	const b = bus();
	return b ? b.call(`network.interface.${name}`, 'status') : null;
};

export function if_ipv4(st) {
	return st?.['ipv4-address']?.[0]?.address;
};

export function if_up(name) {
	const s = ifstatus(name);
	return !!(s?.up && if_ipv4(s));
};

export function if_l3dev(name) {
	const s = ifstatus(name);
	return s?.l3_device ?? s?.device;
};

export function if_gateway(name) {
	const s = ifstatus(name);
	for (let r in s?.route ?? [])
		if (r.target == '0.0.0.0' && r.mask == 0)
			return r.nexthop;
	return null;
};

// Default routes from the kernel: [{ dev, gw, metric }] sorted by metric.
export function default_routes() {
	const out = [];
	for (let l in split(readfile('/proc/net/route') ?? '', '\n')) {
		const f = split(trim(replace(l, /\s+/g, ' ')), ' ');
		if (length(f) < 8 || f[1] != '00000000' || f[7] != '00000000')
			continue;
		const g = f[2];
		const gw = sprintf('%d.%d.%d.%d', hex(substr(g, 6, 2)), hex(substr(g, 4, 2)), hex(substr(g, 2, 2)), hex(substr(g, 0, 2)));
		push(out, { dev: f[0], gw: gw, metric: +f[6] });
	}
	return sort(out, (a, b) => a.metric - b.metric);
};

// Which uplink carries the traffic now: lan | wifi | none | other.
export function uplink_active() {
	const r = default_routes();
	if (!length(r))
		return 'none';
	const dev = r[0].dev;
	if (dev == if_l3dev('wan'))
		return 'lan';
	if (dev == if_l3dev('wiflow_wwan'))
		return 'wifi';
	return 'other';
};

export function wan_carrier() {
	const dev = uci_get('network', 'wan', 'device') ?? 'wan';
	return trim(readfile(`/sys/class/net/${dev}/carrier`) ?? '0') == '1';
};

// One real Internet check (HTTPS 204). dev = through this interface only.
export function probe(dev, secs) {
	const ifc = dev ? `--interface ${q(dev)} ` : '';
	const r = run(`curl -s -o /dev/null -w '%{http_code}' -m ${secs ?? 4} ${ifc}https://connectivitycheck.gstatic.com/generate_204`);
	if (trim(r.out) == '204')
		return true;
	const r2 = run(`curl -s -m ${secs ?? 4} ${ifc}http://detectportal.firefox.com/success.txt`);
	return trim(r2.out) == 'success';
};

/* ------------------------------------------------------------------- WiFi */

export function radios() {
	const c = cursor();
	const out = [];
	c.foreach('wireless', 'wifi-device', s => {
		let band = s.band;
		if (band != '2g' && band != '5g')
			band = (s.phy == 'rax0' || index(s.hwmode ?? '', 'a') >= 0) ? '5g' : '2g';
		push(out, { name: s['.name'], band: band, phy: s.phy ?? (band == '5g' ? 'rax0' : 'ra0'), type: s.type });
	});
	return out;
};

export function radio_for(band) {
	for (let r in radios())
		if (r.band == band)
			return r;
	return null;
};

export function radio_named(name) {
	for (let r in radios())
		if (r.name == name)
			return r;
	return null;
};

// mt_wifi: the radio's main interface (ra0 / rax0) is the first AP, its
// station is apcli0 / apclix0 (l1profile apcli_ifname "apcli;apclix").
export function sta_if(r) {
	return (r && substr(r.phy, 0, 3) == 'rax') ? 'apclix0' : 'apcli0';
};

function sysflag_up(ifn) {
	return (num(trim(readfile(`/sys/class/net/${ifn}/flags`) ?? '0'), 0) & 1) == 1;
};

// WiFi data comes from rpcd's "iwinfo" object (libiwinfo, MediaTek backend,
// the same source LuCI uses). The ROM's iwinfo command is the nl80211
// version and cannot see mt_wifi. Never call these from inside rpcd: the
// call would wait on rpcd itself. The agent and the job runner use them and
// leave snapshots (st "wifi", scan results) for the LuCI plugin.

function iw(method, dev) {
	const b = bus();
	if (!b) return null;
	const r = b.call('iwinfo', method, { device: dev });
	return type(r) == 'object' ? r : null;
};

function bssid_ok(b) {
	return type(b) == 'string' && match(b, /^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$/)
		&& !match(b, /^(00:00:00:00:00:00|44:44:44:44:44:44|FF:FF:FF:FF:FF:FF)$/i);
};

export function iw_info(ifn) {
	if (!access(`/sys/class/net/${ifn}`))
		return null;
	const i = iw('info', ifn) ?? {};
	let ssid = i.ssid, bssid = i.bssid;
	if (!bssid_ok(bssid)) {
		// wireless-tools (wext) as a second opinion for the mt_wifi station
		const o = sh(`iwconfig ${q(ifn)}`);
		ssid = match(o, /ESSID:"(.*)"/)?.[1] ?? ssid;
		bssid = match(o, /Access Point: ([0-9A-Fa-f:]{17})/)?.[1];
	}
	return {
		up: sysflag_up(ifn),
		ssid: length(ssid) ? ssid : null,
		bssid: bssid_ok(bssid) ? uc(bssid) : null,
		signal: num(i.signal, 0),
		channel: num(i.channel, 0)
	};
};

export function sta_up(r) {
	const i = sta_if(r);
	return !!access(`/sys/class/net/${i}`) && sysflag_up(i);
};

export function sta_associated(r, want) {
	const i = iw_info(sta_if(r));
	if (!i || !i.up || !i.bssid || !i.ssid)
		return false;
	return !want || i.ssid == want;
};

function enc_of(e) {
	if (type(e) != 'object' || !e.enabled)
		return 'none';
	const auth = join(' ', e.authentication ?? []);
	const wpa = e.wpa ?? [];
	if (match(auth, /802\.1x|eap|owe/i) || length(e.wep ?? []))
		return null;	// enterprise / OWE / WEP: not offered
	if (match(auth, /sae/i) && !match(auth, /psk/i))
		return 'sae';
	if (index(wpa, 2) >= 0 || index(wpa, 3) >= 0)
		return 'psk2';
	if (index(wpa, 1) >= 0)
		return 'psk';
	return 'psk2';
};

function scan_iwinfo(r) {
	const out = [];
	for (let c in iw('scan', r.phy)?.results ?? []) {
		if (!length(c.ssid) || !bssid_ok(c.bssid))
			continue;
		const enc = enc_of(c.encryption);
		if (!enc)
			continue;
		push(out, { ssid: c.ssid, bssid: uc(c.bssid), encryption: enc, channel: num(c.channel, 0), signal: num(c.signal, -95) });
	}
	return out;
};

// Networks heard by one radio: the system scan (libiwinfo), the same one
// LuCI's Scan button uses. Up to 3 tries, 2 s apart, until it lists something.
// The list is kept for the diagnostics report.
export function scan_radio(r) {
	let found = [], tries = 0;
	while (tries < 3) {
		tries++;
		found = scan_iwinfo(r);
		if (length(found) > 0)
			break;
		if (tries < 3)
			sleep(2000);
	}
	mkdir(RUN, 0700);
	const rec = [ sprintf('uptime %d %s tries=%d networks=%d', uptime(), r.phy, tries, length(found)) ];
	for (let n in found)
		push(rec, sprintf('  %-32s ch=%-3d %4d dBm %-5s %s', n.ssid, n.channel, n.signal, n.encryption, n.bssid));
	writefile(`${RUN}/scan-${r.band}.txt`, join('\n', rec) + '\n');
	st_set(`scan_${r.band}`, { at: uptime(), tries: tries, total: length(found) });
	return found;
};

// Both radios (or one band); the radio that heard a network joins it.
export function scan(band) {
	let nets = [];
	for (let r in radios()) {
		if (band && r.band != band)
			continue;
		for (let n in scan_radio(r)) {
			n.band = r.band;
			push(nets, n);
		}
	}

	// One row per SSID and band: the strongest access point.
	const best = {};
	for (let n in nets) {
		const k = n.band + '|' + n.ssid;
		if (!best[k] || n.signal > best[k].signal)
			best[k] = n;
	}
	const guest = core('guest_ssid', 'Wiflow');
	const list = sort(filter(values(best), n => n.ssid != guest), (a, b) => b.signal - a.signal);

	// Advice for a stable source: 5 GHz on a non-DFS channel when its signal
	// is good, otherwise 2.4 GHz. DFS channels (52-144) can make the radio
	// wait 60 s or jump channel on radar; weak signals drop.
	const by_ssid = {};
	for (let n in list) {
		n.dfs = n.band == '5g' && n.channel >= 52 && n.channel <= 144;
		n.weak = n.signal < -75;
		if (!by_ssid[n.ssid]) by_ssid[n.ssid] = [];
		push(by_ssid[n.ssid], n);
	}
	for (let ssid, rows in by_ssid) {
		let pick = null;
		for (let n in rows)
			if (n.band == '5g' && !n.dfs && n.signal >= -70) pick = n;
		if (!pick)
			for (let n in rows)
				if (n.band == '2g' && (!pick || n.signal > pick.signal)) pick = n;
		if (!pick)
			pick = rows[0];
		if (length(rows) > 1 || (!pick.dfs && !pick.weak))
			pick.recommended = true;
	}
	return list;
};

export function guest_ifnames() {
	const out = [];
	for (let r in radios())
		if (uci_get('wireless', `wiflow_guest_${r.band}`, 'disabled') != '1')
			push(out, { band: r.band, ifn: r.phy });
	return out;
};

// Guest stations: [ MAC, ... ]
export function guest_macs() {
	const out = [];
	for (let g in guest_ifnames())
		for (let s in iw('assoclist', g.ifn)?.results ?? [])
			if (bssid_ok(s.mac))
				push(out, uc(s.mac));
	return out;
};

// Snapshot for status() (written by the agent every tick, by jobs after a join).
export function wifi_snapshot() {
	const r = radio_named(uci_get('wireless', 'wiflow_uplink', 'device'));
	const snap = { at: uptime(), sta: r ? iw_info(sta_if(r)) : null };
	st_set('wifi', snap);
	return snap;
};

/* ----------------------------------------------------------------- status */

const WP_ERRORS = {
	DEVICE_AUTH_INVALID: 'Máy chủ chưa nhận ra router (đang thử lại)',
	DEVICE_AUTH_MISSING: 'Thiếu thông tin xác thực (đang thử lại)',
	DEVICE_UNPAIRED: 'Router đã bị gỡ khỏi tài khoản trong ứng dụng (đang xác nhận)',
	DEVICE_GENERATION_MISMATCH:'Máy chủ Wiflow và router khác phiên bản dữ liệu',
	generation_mismatch: 'Máy chủ Wiflow và router khác phiên bản dữ liệu',
	transport: 'Không liên lạc được máy chủ Wiflow',
	no_internet: 'Router chưa có Internet'
};

export function wp_error_text(code) {
	if (!code)
		return null;
	return WP_ERRORS[code] ?? `Máy chủ trả lỗi ${code}`;
};

// Channel per band as configured ("auto" = follows the source WiFi).
export function guest_channels() {
	const out = {};
	for (let r in radios())
		out[r.band] = uci_get('wireless', r.name, 'channel') ?? 'auto';
	return out;
};

export function status() {
	const mode = core('internet_mode', 'auto');
	const via = uplink_active();
	const online = !!st_get('online', false) && via != 'none';
	const src_radio = radio_named(uci_get('wireless', 'wiflow_uplink', 'device'));
	const src_ssid = uci_get('wireless', 'wiflow_uplink', 'ssid');
	let source = {};
	if (src_ssid) {
		const i = st_get('wifi')?.sta;
		// DHCP on the station is the proof; libiwinfo may not report a BSSID.
		const same = !!(i && i.bssid && i.ssid == src_ssid);
		const conn = if_up('wiflow_wwan') && (same || !(i && i.bssid));
		source = {
			ssid: src_ssid, band: src_radio?.band, connected: conn,
			signal: conn && same ? i.signal : null, channel: conn && same ? i.channel : null,
			enabled: uci_get('wireless', 'wiflow_uplink', 'disabled') != '1'
		};
	}
	const wan = ifstatus('wan');
	const wwan = ifstatus('wiflow_wwan');
	const active_ip = via == 'lan' ? if_ipv4(wan) : (via == 'wifi' ? if_ipv4(wwan) : null);
	const since = st_get('online_since', 0);
	const gbands = map(guest_ifnames(), g => g.band);

	return {
		device: {
			id: device_id(), model: MODEL, os: os_version(), agent: VERSION, uptime: uptime()
		},
		internet: {
			online: online, via: online ? via : (via == 'none' ? 'none' : via), mode: mode,
			ip: active_ip, since_sec: online && since ? max(0, uptime() - since) : 0,
			wan_link: wan_carrier(), wan_ip: if_ipv4(wan), wan_gateway: if_gateway('wan'),
			wwan_ip: if_ipv4(wwan), source: source,
			override: st_get('override', false)
		},
		guest: {
			ssid: core('guest_ssid', 'Wiflow'), bands: gbands, clients: st_get('clients_now', 0),
			clients_today: st_get('today', {}).n ?? 0,
			up: length(gbands) > 0, subnet: `${GUEST_NET}.0/24`,
			follows: src_ssid && source.enabled ? src_radio?.band : null,
			channels: guest_channels()
		},
		activated: core('activated', '0') == '1',
		login: core('setup_username', 'wiflow'),
		wp: {
			paired: core('paired', '0') == '1' && !!core('device_token'),
			account: core('account_public_id'),
			online: !!st_get('wp_online', false),
			last_ok: st_get('wp_last_ok', 0),
			error: wp_error_text(st_get('wp_error'))
		},
		job: st_get('job'),
		scan: st_get('scan')
	};
};

/* ------------------------------------------------------ Setup page data */
// Charts come from the agent's once-a-minute samples (RAM only):
//   minutes  time|ping ms|guests|uplink|ram %|load %   (24 h)
//   hours    [ { hour, peak, rx, tx } ]                (48 h, guest bytes)

export function meminfo(k) {
	const m = match(readfile('/proc/meminfo') ?? '', regexp(`${k}:\\s+([0-9]+)`));
	return m ? +m[1] : 0;
};

function minute_rows() {
	const out = [];
	for (let l in split(readfile(`${RUN}/minutes`) ?? '', '\n')) {
		const p = split(l, '|');
		if (length(p) < 6) continue;
		push(out, { t: +p[0], p: length(p[1]) ? +p[1] : null, g: +p[2], u: p[3], m: +p[4], c: +p[5] });
	}
	return out;
};

export function overview() {
	const rows = minute_rows();
	// uplink runs and 15-minute latency / RAM averages for the 24 h charts
	const runs = [], q = [];
	let b = null;
	for (let r in rows) {
		const last = runs[length(runs) - 1];
		if (!last || last.u != r.u) {
			if (last) last.to = r.t;
			push(runs, { u: r.u, from: r.t, to: r.t });
		}
		else last.to = r.t;
		const k = int(r.t / 900);
		if (!b || b.k != k) {
			b = { k: k, ps: 0, pn: 0, ms: 0, mn: 0 };
			push(q, b);
		}
		if (r.p != null) { b.ps += r.p; b.pn++; }
		b.ms += r.m; b.mn++;
	}
	const qq = map(q, x => ({ t: x.k * 900, p: x.pn ? int(x.ps / x.pn + 0.5) : null, m: x.mn ? int(x.ms / x.mn) : 0 }));
	let ping = null;
	for (let r in rows) if (r.p != null) ping = r.p;
	const df = split(trim(replace(split(sh('df -k /overlay 2>/dev/null'), '\n')[1] ?? '', /\s+/g, ' ')), ' ');
	return {
		ok: true, now: time(),
		health: {
			ping_ms: length(rows) && rows[length(rows) - 1].p != null ? rows[length(rows) - 1].p : ping,
			mem_total_kb: meminfo('MemTotal'), mem_free_kb: meminfo('MemAvailable'),
			load: +(split(readfile('/proc/loadavg') ?? '0', ' ')[0]),
			watchdog_restarts: st_get('watchdog_restarts', 0)
		},
		minutes: slice(rows, max(0, length(rows) - 60)),
		hours: json(readfile(`${RUN}/hours.json`) ?? '[]') ?? [],
		day: { runs: runs, q: qq },
		storage: { total: num(df[1], 0) * 1024, free: num(df[3], 0) * 1024, media: 0, budget: 0 },
		log: wlog_list(40),
		guest: { max: 0, down_kbps: 0, session_min: 0 },
		wp_last_ok: st_get('wp_last_ok', 0)
	};
};

function if_detail(name) {
	const s = ifstatus(name);
	const d = s?.l3_device ?? s?.device;
	let sp = d ? num(trim(readfile(`/sys/class/net/${d}/speed`) ?? ''), 0) : 0;
	if (sp < 0) sp = 0;
	return { up: !!s?.up, dev: d, addr: if_ipv4(s), gw: if_gateway(name), dns: s?.['dns-server']?.[0], speed: sp };
};

export function inet() {
	const r = radio_named(uci_get('wireless', 'wiflow_uplink', 'device'));
	const sta = st_get('wifi')?.sta;
	return {
		ok: true, mode: core('internet_mode', 'auto'), active: uplink_active(), override: !!st_get('override', false),
		wan: if_detail('wan'), wwan: if_detail('wiflow_wwan'),
		wifi_ssid: uci_get('wireless', 'wiflow_uplink', 'ssid') ?? '', wifi_band: r?.band ?? '',
		wifi_enabled: uci_get('wireless', 'wiflow_uplink', 'disabled') != '1',
		wifi_signal: sta && sta.bssid && sta.signal ? sta.signal : null
	};
};

// Live check for the page: Internet (HTTPS 204), DNS, 5 pings.
export function netcheck() {
	const ok = probe(null, 4);
	const dns = run('nslookup connectivitycheck.gstatic.com 127.0.0.1').code == 0;
	let out = sh('ping -c 5 -W 1 -i 0.3 -q 1.1.1.1 2>/dev/null');
	if (!match(out, /packet loss/))
		out = sh('ping -c 5 -W 1 -q 1.1.1.1 2>/dev/null');
	const loss = match(out, /([0-9]+)% packet loss/);
	const rtt = match(out, /= ([0-9.]+)\/([0-9.]+)\/([0-9.]+)/);
	return {
		ok: true, internet: ok, dns: dns, active: uplink_active(),
		ping: rtt ? int(+rtt[2] + 0.5) : null, jitter: rtt ? int((+rtt[3] - +rtt[1]) / 2) : null,
		loss: loss ? +loss[1] : 100
	};
};

/* ------------------------------------------------------------ diagnostics */
// Plain-text report for support: no passwords, no guest MACs.

export function diag_text() {
	const lines = [];
	const add = (t) => push(lines, t);
	add(`Wiflow Setup ${VERSION} / Wiflow OS ${os_version()} / ${MODEL} / ${device_id() ?? '-'}`);
	add(`time ${time()} uptime ${uptime()}s`);
	add('');
	add(`== status`);
	add(sprintf('%.J', status()));
	add('');
	add('== radios');
	for (let r in radios()) {
		const info = iw('info', r.phy) ?? {};
		add(sprintf('%s %s phy=%s channel(uci)=%s htmode=%s now: ch=%s ssid=%s txpower=%s',
			r.name, r.band, r.phy, uci_get('wireless', r.name, 'channel') ?? '-', uci_get('wireless', r.name, 'htmode') ?? '-',
			info.channel ?? '-', info.ssid ?? '-', info.txpower ?? '-'));
		const sta = iw_info(sta_if(r));
		if (sta) add(sprintf('  %s up=%s ssid=%s bssid=%s signal=%s ch=%s', sta_if(r), sta.up, sta.ssid ?? '-', sta.bssid ?? '-', sta.signal, sta.channel));
		add(sprintf('  guests on %s: %d', r.phy, length(iw('assoclist', r.phy)?.results ?? [])));
	}
	add('');
	add('== wireless (keys hidden)');
	add(replace(sh('uci -q show wireless'), /\.key='[^']*'/g, ".key='***'"));
	add('== network');
	add(sh('uci -q show network'));
	add('== interfaces');
	for (let i in [ 'wan', 'wiflow_wwan', 'lan', 'wiflow_guest' ]) {
		const s = ifstatus(i);
		add(sprintf('%s up=%s dev=%s ip=%s gw=%s', i, s?.up, s?.l3_device ?? s?.device, if_ipv4(s) ?? '-', if_gateway(i) ?? '-'));
	}
	add('== routes');
	add(readfile('/proc/net/route') ?? '');
	add('== wiflow log');
	add(readfile(`${RUN}/log`) ?? '');
	add('== last join failure');
	add(readfile(`${RUN}/join-fail.txt`) ?? '(none)');
	add('== last scan');
	for (let b in [ '2g', '5g' ])
		add(sprintf('%s %J', b, st_get(`scan_${b}`)));
	for (let b in [ '2g', '5g' ])
		add(readfile(`${RUN}/scan-${b}.txt`) ?? '');
	// mt_wifi logs every scanned channel at notice level: keep it out.
	const noise = /AsicSwitchChannel|MtCmd|dpd_flatness|scan_type|EDCCA|PrintSrCmd|BcnCheck|TakeChannelOpCharge|ReleaseChannelOpCharge|ChannelInfo|SYNC - |MlmeEnqueue|wdev_do_|HcUpdate|Ch(Switch|annel)Op/;
	const tail = (a, n) => slice(a, max(0, length(a) - n));
	add('== system log (wifi, network, wiflow)');
	add(join('\n', tail(filter(split(sh('logread'), '\n'), l => match(l, /wiflow|mtwifi|apcli|netifd|hostapd|udhcpc|kernel/) && !match(l, noise)), 200)));
	add('== kernel');
	add(join('\n', tail(filter(split(sh('dmesg'), '\n'), l => !match(l, noise)), 80)));
	return join('\n', lines) + '\n';
};

/* -------------------------------------------------------------- jobs */
// Long work (joining a WiFi, pairing) runs in /usr/libexec/wiflow/job so the
// LuCI call returns at once; the page follows status().job.

export function job_busy() {
	const j = st_get('job');
	if (!j || j.state != 'running')
		return false;
	// A runner killed mid-way must not block the next one.
	return access(`/proc/${j.pid}`) && (uptime() - (j.at ?? 0)) < 300;
};

export function job_start(kind, req) {
	if (job_busy())
		return { ok: false, error: 'Một thay đổi khác đang được xử lý, vui lòng đợi.' };
	rundir();
	const f = `${RUN}/req-${kind}-${uptime()}.json`;
	writefile(f, sprintf('%J', req));
	run(`chmod 600 ${q(f)}`);
	st_set('job', { kind: kind, state: 'running', message: 'Đang bắt đầu…', at: uptime(), pid: 0, id: f });
	run(`setsid /usr/libexec/wiflow/job ${q(kind)} ${q(f)} </dev/null >/dev/null 2>&1 &`);
	return { ok: true, job: kind };
};

/* --------------------------------------------------------------- WordPress */

// HTTP via curl; returns { ok, http, body (parsed JSON or null), err }.
export function http(method, path, body, auth, secs) {
	rundir();
	const out = `${RUN}/http.${clock()[1]}.${method}`;
	let cmd = `curl -sS -m ${secs ?? 15} -o ${q(out)} -w '%{http_code}' -H 'Accept: application/json'`;
	if (auth) {
		cmd += ` -H ${q('X-Wiflow-Device-ID: ' + auth.id)} -H ${q('X-Wiflow-Device-Token: ' + auth.token)}`;
	}
	let bodyf = null;
	if (body != null) {
		bodyf = `${out}.body`;
		writefile(bodyf, sprintf('%J', body));
		cmd += ` -H 'Content-Type: application/json' --data-binary @${q(bodyf)}`;
	}
	cmd += ` -X ${method} ${q(REST + path)}`;
	const r = run(cmd);
	const raw = readfile(out);
	unlink(out);
	if (bodyf) unlink(bodyf);
	const code = num(trim(r.out), 0);
	let parsed = null;
	try { parsed = raw ? json(raw) : null; } catch (e) { parsed = null; }
	return { ok: code >= 200 && code < 300 && type(parsed) == 'object', http: code, body: parsed, err: r.code };
};

export function auth() {
	const id = device_id(), token = core('device_token');
	return (id && token) ? { id: id, token: token } : null;
};

export function clear_pairing() {
	core_set({
		paired: '0', device_token: null, account_public_id: null,
		last_command_id: null, last_command_action: null, last_command_status: null, last_command_message: null
	});
	st_set('wp_online', false);
	st_set('wp_error', null);
	st_set('unpair_n', null);
};

export function kick_agent() {
	rundir();
	writefile(`${RUN}/kick`, '1');
};

/* --------------------------------------------------------- setup account */

// Wiflow web login = the rpcd login named by wiflow.core.setup_username
// (default "wiflow"). root is never touched.
export function setup_set_login(user, pass) {
	if (type(user) != 'string' || !match(user, /^[A-Za-z0-9._-]{3,32}$/) || user == 'root')
		return 'Tên đăng nhập 3–32 ký tự (chữ, số, . _ -), không dùng "root".';
	if (type(pass) != 'string' || length(pass) < 6 || length(pass) > 128)
		return 'Mật khẩu cần từ 6 đến 128 ký tự.';
	const hash = trim(sh(`uhttpd -m ${q(pass)}`));
	if (!match(hash, /^\$1\$[^$]+\$[A-Za-z0-9.\/]{22}$/))
		return 'Không tạo được mật khẩu mới.';

	const cur = core('setup_username', 'wiflow');
	const c = cursor();
	c.load('rpcd');
	let sec = null, clash = false;
	c.foreach('rpcd', 'login', s => {
		if (s.username == cur) sec = s['.name'];
		else if (s.username == user) clash = true;
	});
	if (clash)
		return 'Tên đăng nhập này đã được dùng.';
	if (!sec) {
		sec = c.add('rpcd', 'login');
		c.set('rpcd', sec, 'read', [ '*' ]);
		c.set('rpcd', sec, 'write', [ '*' ]);
	}
	c.set('rpcd', sec, 'username', user);
	c.set('rpcd', sec, 'password', hash);
	c.commit('rpcd');
	core_set({ setup_username: user });
	run('/etc/init.d/rpcd reload');
	return null;
};
