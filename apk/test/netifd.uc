// Mock netifd: network.interface.<name> status from /tmp/mock/net.json,
// network reload -> netsim.
'use strict';
import * as ubus from 'ubus';
import * as uloop from 'uloop';
import { readfile } from 'fs';

uloop.init();
const conn = ubus.connect();
function net() { return json(readfile('/tmp/mock/net.json') ?? '{}'); }

for (let name in [ 'wan', 'wiflow_wwan', 'lan', 'wiflow_guest' ]) {
	let n = name;
	conn.publish(`network.interface.${n}`, {
		status: { call: function() { return net()[n] ?? { up: false }; }, args: {} },
		up: { call: function() { system(`${getenv('WFT')}/netsim.py "ubus up ${n}"`); return {}; }, args: {} }
	});
}
conn.publish('network', {
	reload: { call: function() { system(getenv('WFT') + '/netsim.py "network reload"'); return {}; }, args: {} }
});
function world() { return json(readfile('/tmp/mock/world.json') ?? '{}'); }
const ENC = {
	none: { enabled: false },
	psk2: { enabled: true, wpa: [ 2 ], authentication: [ 'psk' ], ciphers: [ 'ccmp' ] },
	psk: { enabled: true, wpa: [ 1 ], authentication: [ 'psk' ], ciphers: [ 'tkip' ] },
	sae: { enabled: true, wpa: [ 3 ], authentication: [ 'sae' ], ciphers: [ 'ccmp' ] },
	mixed: { enabled: true, wpa: [ 2, 3 ], authentication: [ 'psk', 'sae' ], ciphers: [ 'ccmp' ] },
	eap: { enabled: true, wpa: [ 2 ], authentication: [ '802.1x' ], ciphers: [ 'ccmp' ] }
};
conn.publish('iwinfo', {
	info: { args: { device: '' }, call: function(req) {
		const i = json(readfile('/tmp/mock/iw.json') ?? '{}')[req.args.device] ?? {};
		return i.ssid ? { ssid: i.ssid, bssid: i.bssid, signal: i.signal, channel: i.channel, mode: 'Client' }
			: { bssid: '00:00:00:00:00:00', mode: 'Client' };
	} },
	scan: { args: { device: '' }, call: function(req) {
		const band = req.args.device == 'rax0' ? '5g' : '2g';
		return { results: map(filter(world().aps, a => a.band == band), a => ({ ssid: a.ssid, bssid: a.bssid, channel: a.channel, signal: a.signal, mode: 'Master', encryption: ENC[a.enc] })) };
	} },
	assoclist: { args: { device: '' }, call: function(req) {
		return { results: map(world().clients?.[req.args.device] ?? [], m => ({ mac: m, signal: -60 })) };
	} }
});
uloop.run();
