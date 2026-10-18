{%
/*
 * Wiflow 1.0.25: LuCI behind the Wiflow login, at http://10.0.0.1/cgi-bin/luci
 * (uhttpd "wiflow" instance, ucode_prefix). Replaces luci-base's uhttpd.uc there:
 *
 *  - no valid Wiflow session (Security Gate + Wiflow login)  -> back to "/"
 *  - valid Wiflow session -> LuCI gets root / LUCI_DEFAULT_ROOT_PW through the
 *    same HTTP_AUTH_USER / HTTP_AUTH_PASS path LuCI already reads, so LuCI
 *    opens its own session (sysauth cookie) without showing its login page.
 *    If the root password was changed in LuCI, LuCI simply asks for it.
 *  - /admin/logout ends the LuCI session and the Wiflow session together.
 */
import dispatch from 'luci.dispatcher';
import request from 'luci.http';
import { readfile, writefile, rename, unlink } from 'fs';
import { connect } from 'ubus';

const SESS = '/tmp/wiflow-sessions';
const SESSION_TTL = 1800;
const ROOT_USER = 'root';
const ROOT_PASS = '1234';   /* LUCI_DEFAULT_ROOT_PW in /usr/lib/wiflow/common.sh */

function cookie(env, name) {
	for (let part in split(env?.HTTP_COOKIE ?? '', ';')) {
		let m = match(trim(part), regexp('^' + name + '=([0-9A-Fa-f]+)$'));
		if (m) return m[1];
	}
	return null;
}

/* Same rules as check_session() in common.sh: "<expiry>|<csrf>", sliding expiry. */
function wiflow_session(env) {
	let t = cookie(env, 'WFSESSION');
	if (!t || length(t) < 32 || length(t) > 128) return false;
	let f = `${SESS}/${t}`, line = trim(readfile(f) ?? '');
	let m = match(line, /^([0-9]+)\|(.*)$/);
	let now = time();
	if (!m) { if (line != '') unlink(f); return false; }
	if (now >= +m[1]) { unlink(f); return false; }
	let tmp = `${f}.luci`;
	if (writefile(tmp, `${now + SESSION_TTL}|${m[2]}\n`) != null) rename(tmp, f);
	return true;
}

function send_redirect(location, cookies) {
	let out = 'Status: 302 Found\r\nLocation: ' + location + '\r\nCache-Control: no-store\r\n';
	for (let c in (cookies ?? [])) out += 'Set-Cookie: ' + c + '\r\n';
	uhttpd.send(out + '\r\n');
}

global.handle_request = function(env) {
	let path = env?.PATH_INFO ?? '';

	if (match(path, /^\/admin\/logout\/?$/)) {
		let sid = cookie(env, (env?.HTTPS == 'on') ? 'sysauth_https' : 'sysauth_http');
		if (sid) {
			let bus = connect();
			bus?.call('session', 'destroy', { ubus_rpc_session: sid });
			bus?.disconnect();
		}
		send_redirect('/cgi-bin/logout', [
			'sysauth_http=; expires=Thu, 01 Jan 1970 01:00:00 GMT; path=/cgi-bin/luci',
			'sysauth_https=; expires=Thu, 01 Jan 1970 01:00:00 GMT; path=/cgi-bin/luci'
		]);
		return;
	}

	if (!wiflow_session(env)) {
		send_redirect('/');
		return;
	}

	env.HTTP_AUTH_USER = ROOT_USER;
	env.HTTP_AUTH_PASS = ROOT_PASS;

	let req = request(env, uhttpd.recv, uhttpd.send);

	dispatch(req);

	req.close();
};
