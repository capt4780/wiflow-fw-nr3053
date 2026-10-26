// Wiflow Setup for Viettel NR3053 (Wiflow OS): links the router to a Wiflow
// (WordPress) account. Shared code for the LuCI rpcd plugin (ubus "wiflow"),
// the background job runner (/usr/libexec/wiflow/job) and the agent
// (/usr/libexec/wiflow/agent). It never touches the WiFi or network setup:
// that is done in LuCI.
//
// Runtime state lives in RAM (/tmp/wiflow), settings in uci "wiflow",
// the device identity in /etc/wiflow/device-id.
'use strict';

import { readfile, writefile, rename, mkdir, popen, unlink, access, glob, lsdir, stat } from 'fs';
import { cursor } from 'uci';
import { connect } from 'ubus';

export const VERSION = '2.0.0';
export const GEN = '4';
export const MODEL = 'Viettel NR3053';
export const REST = getenv('WIFLOW_REST') || 'https://wiflow.projifylab.com/wp-json';
export const ROOT = '/etc/wiflow';
export const RUN = '/tmp/wiflow';

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
// epoch|area|message, about the last 200 lines.

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

// Is there a default route (any uplink: cable, source WiFi, ...)?
export function has_default_route() {
	for (let l in split(readfile('/proc/net/route') ?? '', '\n')) {
		const f = split(trim(replace(l, /\s+/g, ' ')), ' ');
		if (length(f) >= 8 && f[1] == '00000000' && f[7] == '00000000')
			return true;
	}
	return false;
};

// One real Internet check (HTTPS 204). Returns the time it took in ms, or -1.
export function probe_ms(secs) {
	const t = secs ?? 4;
	const r = run(`curl -s -o /dev/null -w '%{http_code} %{time_total}' -m ${t} https://connectivitycheck.gstatic.com/generate_204`);
	const f = split(trim(r.out), ' ');
	if (f[0] == '204')
		return max(1, int(+(f[1] ?? 0) * 1000 + 0.5));
	const r2 = run(`curl -s -m ${t} http://detectportal.firefox.com/success.txt`);
	return trim(r2.out) == 'success' ? 0 : -1;
};

export function probe(secs) {
	return probe_ms(secs) >= 0;
};

// SSIDs as LuCI configured them (read only): the source WiFi (client) and the
// first access point, reported to WordPress.
export function wifi_names() {
	const c = cursor();
	c.load('wireless');
	let src = '', ap = '';
	c.foreach('wireless', 'wifi-iface', s => {
		if (s.mode == 'sta' && !src && s.disabled != '1')
			src = s.ssid ?? '';
		else if (s.mode == 'ap' && !ap)
			ap = s.ssid ?? '';
	});
	return { source: src, ap: ap };
};

/* ----------------------------------------------------------------- status */

const WP_ERRORS = {
	DEVICE_AUTH_INVALID: 'The server does not recognise this router yet (retrying)',
	DEVICE_AUTH_MISSING: 'Credentials are missing (retrying)',
	DEVICE_UNPAIRED: 'This router was removed from the account in the app (confirming)',
	DEVICE_GENERATION_MISMATCH: 'The Wiflow server and this router use different data versions',
	generation_mismatch: 'The Wiflow server and this router use different data versions',
	transport: 'Cannot reach the Wiflow server',
	no_internet: 'The router has no Internet'
};

export function wp_error_text(code) {
	if (!code)
		return null;
	return WP_ERRORS[code] ?? `The server returned ${code}`;
};

// 24 hourly values (oldest first); null where the router had no sample yet.
function series_out() {
	const s = st_get('series', {});
	const h = int(time() / 3600);
	const dev = [], lat = [];
	for (let i = h - 23; i <= h; i++) {
		const b = s[`${i}`];
		push(dev, (b && b.d != null) ? b.d : null);
		push(lat, (b && b.ln > 0) ? int(b.ls / b.ln + 0.5) : null);
	}
	return { devices: dev, latency: lat };
};

export function status() {
	// The Wiflow App page is open: the agent may read the source WiFi signal.
	rundir();
	writefile(`${RUN}/viewed`, `${uptime()}`);
	const online = !!st_get('online', false) && has_default_route();
	const st = st_get('stats', {});
	return {
		device: {
			id: device_id(), model: MODEL, os: os_version(), agent: VERSION, uptime: uptime()
		},
		internet: { online: online, latency: st_get('latency', -1) },
		wp: {
			paired: core('paired', '0') == '1' && !!core('device_token'),
			account: core('account_public_id'),
			online: !!st_get('wp_online', false),
			last_ok: st_get('wp_last_ok', 0),
			since: num(core('paired_at', '0'), 0),
			error: wp_error_text(st_get('wp_error'))
		},
		metrics: st.metrics ?? {},
		clients: st.clients ?? { now: 0, today: 0, band2g: 0, band5g: 0 },
		networks: st.networks ?? [],
		source: st.source ?? {},
		series: series_out(),
		log: wlog_list(8),
		now: time(),
		job: st_get('job')
	};
};

/* ------------------------------------------------------------ diagnostics */
// Plain-text report for support (sent on request from WordPress): no keys.

export function diag_text() {
	const lines = [];
	const add = (t) => push(lines, t);
	add(`Wiflow Setup ${VERSION} / Wiflow OS ${os_version()} / ${MODEL} / ${device_id() ?? '-'}`);
	add(`time ${time()} uptime ${uptime()}s`);
	add('');
	add('== status');
	add(sprintf('%.J', status()));
	add('== wireless (keys hidden)');
	add(replace(sh('uci -q show wireless'), /\.key='[^']*'/g, ".key='***'"));
	add('== network');
	add(sh('uci -q show network'));
	add('== routes');
	add(readfile('/proc/net/route') ?? '');
	add('== wiflow log');
	add(readfile(`${RUN}/log`) ?? '');
	const tail = (a, n) => slice(a, max(0, length(a) - n));
	add('== system log');
	add(join('\n', tail(filter(split(sh('logread'), '\n'), l => match(l, /wiflow|mtwifi|netifd|udhcpc/)), 150)));
	return join('\n', lines) + '\n';
};

/* -------------------------------------------------------------- jobs */
// Long work (pairing) runs in /usr/libexec/wiflow/job so the
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
		return { ok: false, error: 'Another change is in progress, please wait.' };
	rundir();
	const f = `${RUN}/req-${kind}-${uptime()}.json`;
	writefile(f, sprintf('%J', req));
	run(`chmod 600 ${q(f)}`);
	st_set('job', { kind: kind, state: 'running', message: 'Starting…', at: uptime(), pid: 0, id: f });
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
		paired: '0', paired_at: null, device_token: null, account_public_id: null,
		last_command_id: null, last_command_action: null, last_command_status: null, last_command_message: null
	});
	st_set('wp_online', false);
	st_set('wp_error', null);
	st_set('unpair_n', null);
	// Portal off, content and guest sessions cleared.
	run('/usr/lib/wiflow/portal-hb unpaired');
};

export function kick_agent() {
	rundir();
	writefile(`${RUN}/kick`, '1');
};

