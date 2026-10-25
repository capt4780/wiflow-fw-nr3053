import { readfile, lsdir } from 'fs';
function parse(text) {
	let conf = {}, cur = null, n = 0;
	for (let line in split(text ?? '', '\n')) {
		line = trim(replace(line, /#.*$/, ''));
		if (!length(line)) continue;
		let m = match(line, /^(config|option|list)\s+(\S+)(\s+(.*))?$/);
		if (!m) continue;
		let val = m[4] ? replace(trim(m[4]), /^['"]|['"]$/g, '') : null;
		if (m[1] == 'config') { let name = val ?? sprintf('cfg%02x', n); cur = { '.type': m[2], '.name': name, '.anonymous': val == null, '.index': n++ }; conf[name] = cur; }
		else if (m[1] == 'option' && cur) cur[m[2]] = val;
		else if (m[1] == 'list' && cur) { cur[m[2]] ??= []; push(cur[m[2]], val); }
	}
	return conf;
};
export function cursor() {
	let cache = {};
	const load = (c) => (cache[c] ??= parse(readfile(`/etc/config/${c}`)));
	return {
		load: (c) => { load(c); return true; },
		unload: () => true,
		get: (c, s, o) => { let x = load(c); if (substr(s ?? '', 0, 1) == '@') { let m = match(s, /^@(.+)\[(-?\d+)\]$/); let l = filter(values(x), (v) => v['.type'] == m[1]); s = l[+m[2] < 0 ? length(l) + +m[2] : +m[2]]?.['.name']; }
			let sec = x[s]; if (!sec) return null; return o == null ? sec['.type'] : sec[o]; },
		get_all: (c, s) => s == null ? load(c) : load(c)[s],
		foreach: (c, t, cb) => { for (let k, v in load(c)) if (t == null || v['.type'] == t) if (cb(v) === false) break; return true; },
		get_first: (c, t, o) => { for (let k, v in load(c)) if (v['.type'] == t) return o ? v[o] : k; },
		set: () => true, delete: () => true, save: () => true, commit: () => true, changes: () => ({}),
	};
};