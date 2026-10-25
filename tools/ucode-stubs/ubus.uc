// stub: one valid session id 'abcdef0123456789abcdef0123456789' after login;
// the session gets every rpcd ACL group (like the real read '*' / write '*' logins)
import { glob, readfile } from 'fs';
const SID = 'abcdef0123456789abcdef0123456789';
export function connect() {
	return {
		call: function(obj, method, args) {
			if (obj == 'session' && method == 'login') {
				let ok = (args.username == 'wiflow' && args.password == 'wiflow') || (args.username == 'root' && args.password == '1234');
				return ok ? { ubus_rpc_session: SID, timeout: 300, expires: 300, acls: {}, data: { username: args.username } } : null;
			}
			if (obj == 'session' && method == 'get') return args?.ubus_rpc_session == SID ? { values: { token: 'tok123', username: 'wiflow' } } : null;
			if (obj == 'session' && method == 'access') {
				if (args?.ubus_rpc_session != SID) return {};
				let groups = {};
				for (let f in glob('/usr/share/rpcd/acl.d/*.json'))
					for (let g in keys(json(readfile(f)) ?? {}))
						groups[g] = [ 'read', 'write' ];
				return { 'access-group': groups };
			}
			if (obj == 'session' && method == 'set') return {};
			if (obj == 'system' && method == 'board') return { hostname: 'Wiflow', model: 'Viettel NR3053', rootfs_type: 'squashfs', release: { distribution: 'ImmortalWrt', version: '25.12-SNAPSHOT', revision: 'r0-495af17', description: 'Wiflow OS 1.0.0' } };
			return null;
		},
		error: () => null,
		disconnect: () => true
	};
};
export function error() { return null; };
