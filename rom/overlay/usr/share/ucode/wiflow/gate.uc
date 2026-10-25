// Wiflow access gate: an access code must be entered before the LuCI login.
//
// - Codes: uci wiflow_gate.main.code (list); the ROM ships WIFDIDNR3053, the
//   Wiflow app may add more (e.g. the 6-digit device code). enabled=0 turns
//   the gate off.
// - A correct code gives the browser a random token cookie, valid 12 hours,
//   kept in RAM only (/tmp), so a reboot asks again.
// - 5 wrong codes from one address lock that address for 60 seconds.
// Used by the Wiflow login template (shows the gate) and by the LuCI
// dispatcher (refuses username/password until the gate is passed).
'use strict';

import { readfile, writefile, mkdir, unlink, glob } from 'fs';
import { cursor } from 'uci';
import { rand } from 'math';

const DIR = '/tmp/wiflow-gate';
const TTL = 12 * 3600;
const MAX_FAIL = 5;
const LOCK = 60;
const COOKIE = 'wiflow_gate';

function codes() {
	const c = cursor();
	if (c.get('wiflow_gate', 'main', 'enabled') == '0')
		return null;

	let list = c.get('wiflow_gate', 'main', 'code');
	if (type(list) == 'string')
		list = [ list ];
	if (type(list) != 'array' || !length(list))
		list = [ 'WIFDIDNR3053' ];

	return map(list, (x) => uc(trim(x)));
};
function new_token() {
	const raw = readfile('/dev/urandom', 16);
	let s = '';
	for (let i = 0; i < length(raw ?? ''); i++)
		s += sprintf('%02x', ord(raw, i));
	while (length(s) < 32)
		s += sprintf('%02x', rand() % 256);
	return substr(s, 0, 32);
};
function valid_token(t) {
	if (type(t) != 'string' || !match(t, /^[0-9a-f]{32}$/))
		return false;

	const born = +(readfile(`${DIR}/t-${t}`) ?? 0);
	return born > 0 && time() - born < TTL;
};
function fail_file(ip) {
	return `${DIR}/f-${replace(ip ?? 'unknown', /[^0-9A-Fa-f.:]/g, '_')}`;
};
function cleanup() {
	for (let f in glob(`${DIR}/t-*`)) {
		const born = +(readfile(f) ?? 0);
		if (time() - born >= TTL)
			unlink(f);
	}
};
// true when the request carries a valid gate cookie (or the gate is off)
export function passed(http) {
	if (codes() == null)
		return true;

	return valid_token(http.getcookie(COOKIE));
};
// handles a submitted access code (form field wf_gate_code)
// returns null when no code was submitted, otherwise
// { ok: true, cookie } or { ok: false, error: 'invalid'|'locked', left, wait }
export function attempt(http) {
	const input = http.formvalue('wf_gate_code');
	if (input == null)
		return null;

	const allowed = codes();
	if (allowed == null)
		return { ok: true };

	mkdir(DIR, 0700);

	const ff = fail_file(http.getenv('REMOTE_ADDR'));
	const now = time();
	const rec = split(trim(readfile(ff) ?? '0 0'), ' ');
	let count = +rec[0] || 0;
	const since = +rec[1] || 0;

	if (now - since >= LOCK && count >= MAX_FAIL)
		count = 0;

	if (count >= MAX_FAIL)
		return { ok: false, error: 'locked', wait: LOCK - (now - since) };

	if (index(allowed, uc(trim(input))) >= 0) {
		cleanup();
		const t = new_token();
		writefile(`${DIR}/t-${t}`, `${now}`);
		unlink(ff);
		return { ok: true, cookie: `${COOKIE}=${t}; path=/; SameSite=Strict; HttpOnly; Max-Age=${TTL}` };
	}

	count++;
	writefile(ff, `${count} ${now}`);

	if (count >= MAX_FAIL)
		return { ok: false, error: 'locked', wait: LOCK };

	return { ok: false, error: 'invalid', left: MAX_FAIL - count };
};