export const ENCODE_IF_NEEDED = 1, ENCODE_FULL = 2, DECODE_IF_NEEDED = 4, DECODE_PLUS = 8;
export function urlencode(s) { return s; };
export function urldecode(s, f) { s = '' + (s ?? ''); if (f & 8) s = replace(s, '+', ' '); return replace(s, /%([0-9A-Fa-f]{2})/g, (m, h) => chr(hex(h))); };
export function header_attribute(h, a) { if (h == null) return null; if (a == null) return trim(split(h, ';')[0]); let m = match(h, regexp(a + '=([^;]+)')); return m ? m[1] : null; };
export function urlencoded_parser(cb) {
	let buf = '';
	let p = { TUPLE: 1, NAME: 2, VALUE: 3, ERROR: 4 };
	p.parse = function(chunk) {
		if (chunk != null) { buf += chunk; return true; }
		for (let pair in split(buf, '&')) {
			if (!length(pair)) continue;
			let kv = split(pair, '=', 2);
			cb(p.TUPLE, null, 0); cb(p.NAME, kv[0], length(kv[0])); cb(p.VALUE, kv[1] ?? '', length(kv[1] ?? ''));
		}
		return true;
	};
	return p;
};
export function multipart_parser() { die('multipart not stubbed'); };
