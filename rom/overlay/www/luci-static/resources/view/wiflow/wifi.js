'use strict';
'require view';
'require ui';
'require uci';
'require rpc';
'require poll';
'require network';
'require wiflow.kit as K';

/* WiFi: the source WiFi the router takes Internet from, and the two Wiflow
   networks it broadcasts. */

const svg = K.svg, chip = K.chip, card = K.card, band = K.band, signalBars = K.signalBars;

const callStatus = rpc.declare({ object: 'wiflow', method: 'status', expect: { '': {} } });

function ifaces() { return uci.sections('wireless', 'wifi-iface'); }
function bandOf(dev) { return uci.get('wireless', dev, 'band') || ''; }
function ownSsids() { return ifaces().filter(i => i.mode == 'ap').map(i => i.ssid); }

function apOf(b) {
	return ifaces().find(i => i.mode == 'ap' && bandOf(i.device) == b);
}

function applyNow() {
	return uci.save().then(() => uci.callApply(0, false));
}

return view.extend({
	load() {
		return Promise.all([ uci.load([ 'wireless', 'network', 'firewall' ]), callStatus() ]).then(r => r[1]);
	},

	sourceCard() {
		const sta = ifaces().find(i => i.mode == 'sta');
		const src = this.st.source || {}, inet = this.st.internet || {};
		const on = !!(sta && src.ssid && src.ssid == sta.ssid && inet.online);
		const btn = E('button', { 'class': 'wa-btn sm wa-r', 'type': 'button' }, sta ? _('Change network') : _('Choose network'));
		btn.addEventListener('click', () => this.scan());
		return card('wa-c4', 'wifi', _('Source WiFi'), btn, [
			E('dl', { 'class': 'wa-kv' }, [
				E('dt', {}, _('Network')), E('dd', {}, sta ? sta.ssid : '—'),
				E('dt', {}, _('Status')), E('dd', {}, sta ? (on ? _('Connected') : _('Not connected')) : '—'),
				E('dt', {}, _('Signal')), E('dd', {}, on && src.signal ? [ signalBars(src.signal), ' ' + src.signal + ' dBm' ] : '—')
			])
		]);
	},

	bandCard(b) {
		const ap = apOf(b);
		if (!ap)
			return '';
		const net = (this.st.networks || []).find(n => n.band == b) || {};
		const sw = E('input', { 'type': 'checkbox', 'aria-label': ap.ssid });
		sw.checked = ap.disabled != '1';
		sw.addEventListener('change', () => {
			sw.disabled = true;
			if (sw.checked) uci.unset('wireless', ap['.name'], 'disabled');
			else uci.set('wireless', ap['.name'], 'disabled', '1');
			applyNow().catch(e => {
				ui.addNotification(null, E('p', {}, String(e)), 'danger');
			}).finally(() => { sw.disabled = false; });
		});
		return card('wa-c4', 'wifi', band(b), E('label', { 'class': 'wa-r' }, sw), [
			E('dl', { 'class': 'wa-kv' }, [
				E('dt', {}, _('Network')), E('dd', {}, ap.ssid),
				E('dt', {}, _('Devices')), E('dd', {}, String(net.clients ?? 0)),
				E('dt', {}, _('Channel')), E('dd', {}, String(net.channel || uci.get('wireless', ap.device, 'channel') || '—'))
			])
		]);
	},

	draw() {
		return E('div', { 'class': 'wa-grid' }, [ this.sourceCard(), this.bandCard('2g'), this.bandCard('5g') ]);
	},

	/* Networks around, both bands, strongest first. */
	scan(cached) {
		const list = E('div', { 'class': 'wa-scan-empty' }, _('Scanning…'));
		const again = E('button', { 'class': 'btn', 'type': 'button' }, _('Scan again'));
		const show = rows => {
			if (!rows.length) {
				list.className = 'wa-scan-empty';
				list.replaceChildren(_('No networks found'));
				return;
			}
			list.className = 'wa-scan';
			list.replaceChildren.apply(list, rows.map(r => {
				const open = !r.encryption || !r.encryption.enabled;
				const li = E('li', { 'tabindex': '0', 'role': 'button' }, [
					signalBars(r.signal || -90),
					E('span', { 'class': 'n' }, r.ssid),
					E('span', { 'class': 'l' }, band(r.band)),
					open ? '' : E('span', { 'class': 'wa-ico' }, svg('lock'))
				]);
				const pick = () => this.password(r);
				li.addEventListener('click', pick);
				li.addEventListener('keydown', ev => { if (ev.key == 'Enter' || ev.key == ' ') { ev.preventDefault(); pick(); } });
				return li;
			}));
		};
		const run = () => {
			list.className = 'wa-scan-empty';
			list.replaceChildren(_('Scanning…'));
			again.disabled = true;
			return network.getWifiDevices().then(devs => Promise.all(devs.map(d =>
				d.getScanList().then(l => l.map(r => Object.assign({}, r, { dev: d.getName(), band: bandOf(d.getName()) || (r.channel > 14 ? '5g' : '2g') })), () => [])
			))).then(all => {
				const own = ownSsids(), best = {};
				all.forEach(l => l.forEach(r => {
					if (!r.ssid || own.indexOf(r.ssid) >= 0) return;
					const k = r.band + '|' + r.ssid;
					if (!best[k] || (r.signal || -200) > (best[k].signal || -200)) best[k] = r;
				}));
				const rows = Object.keys(best).map(k => best[k]).sort((a, b) => (b.signal || -200) - (a.signal || -200));
				this.rows = rows;
				show(rows);
			}).catch(e => {
				list.className = 'wa-scan-empty';
				list.replaceChildren(String(e && e.message || e));
			}).finally(() => { again.disabled = false; });
		};
		again.addEventListener('click', run);
		ui.showModal(_('Choose network'), [
			list,
			E('div', { 'class': 'right' }, [ E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')), ' ', again ])
		]);
		if (cached && this.rows) { show(this.rows); return; }
		return run();
	},

	password(bss) {
		const open = !bss.encryption || !bss.encryption.enabled;
		const pw = E('input', { 'type': 'password', 'class': 'wa-pw', 'autocomplete': 'off', 'placeholder': _('Password'), 'aria-label': _('Password') });
		const go = E('button', { 'class': 'btn cbi-button-action important', 'type': 'button' }, _('Connect'));
		const check = () => { go.disabled = !open && pw.value.length < 8; };
		pw.addEventListener('input', check);
		pw.addEventListener('keydown', ev => { if (ev.key == 'Enter' && !go.disabled) go.click(); });
		go.addEventListener('click', () => this.connect(bss, pw.value));
		check();
		ui.showModal(bss.ssid, [
			open ? '' : pw,
			E('div', { 'class': 'right' }, [ E('button', { 'class': 'btn', 'click': () => this.scan(true) }, _('Back')), ' ', go ])
		]);
		if (!open) pw.focus();
	},

	connect(bss, key) {
		const enc = bss.encryption || {};
		const auth = L.toArray(enc.authentication), wpa = L.toArray(enc.wpa);
		let mode = 'none';
		if (Array.isArray(enc.wep)) mode = 'wep-open';
		else if (wpa.length && auth.indexOf('psk') >= 0) mode = (wpa.indexOf(2) >= 0 || wpa.indexOf(3) >= 0) ? 'psk2' : 'psk';
		else if (wpa.length && auth.indexOf('sae') >= 0) mode = 'sae';
		else if (enc.enabled) mode = 'psk2';

		ui.showModal(null, E('p', { 'class': 'spinning' }, _('Connecting…')));

		ifaces().filter(i => i.mode == 'sta').forEach(i => uci.remove('wireless', i['.name']));

		const dev = bss.dev;
		uci.unset('wireless', dev, 'disabled');
		uci.set('wireless', dev, 'channel', String(bss.channel));
		if (bss.band == '2g') {
			uci.set('wireless', dev, 'htmode', 'HE20');
		} else {
			const w = bss.vht_operation ? bss.vht_operation.channel_width : 0;
			uci.set('wireless', dev, 'htmode', w >= 80 ? 'HE80' : (bss.ht_operation && bss.ht_operation.secondary_channel_offset != 'no secondary') ? 'HE40' : 'HE20');
		}

		const sid = uci.add('wireless', 'wifi-iface', 'wiflow_src');
		uci.set('wireless', sid, 'device', dev);
		uci.set('wireless', sid, 'mode', 'sta');
		uci.set('wireless', sid, 'network', 'wwan');
		uci.set('wireless', sid, 'ssid', bss.ssid);
		uci.set('wireless', sid, 'encryption', mode);
		if (mode == 'wep-open') { uci.set('wireless', sid, 'key', '1'); uci.set('wireless', sid, 'key1', key); }
		else if (mode != 'none') uci.set('wireless', sid, 'key', key);

		// the network of the source WiFi: DHCP, in the WAN zone, second to the cable
		if (!uci.get('network', 'wwan')) uci.add('network', 'interface', 'wwan');
		uci.set('network', 'wwan', 'proto', 'dhcp');
		uci.set('network', 'wwan', 'metric', '20');
		const wz = uci.sections('firewall', 'zone').find(z => z.name == 'wan');
		if (wz) {
			const nets = L.toArray(wz.network);
			if (nets.indexOf('wwan') < 0)
				uci.set('firewall', wz['.name'], 'network', nets.concat('wwan'));
		}

		return applyNow().then(() => { uci.unload([ 'wireless', 'network', 'firewall' ]); return uci.load([ 'wireless', 'network', 'firewall' ]); }).then(() => {
			ui.hideModal();
			this.refresh();
		}).catch(e => {
			ui.hideModal();
			ui.addNotification(null, E('p', {}, String(e && e.message || e)), 'danger');
		});
	},

	refresh() {
		return callStatus().then(st => {
			this.st = st;
			if (this.body) this.body.replaceChildren(this.draw());
		});
	},

	render(st) {
		this.st = st;
		this.body = E('div', {}, this.draw());
		poll.add(() => {
			if (document.body.classList.contains('modal-overlay-active'))
				return;
			return this.refresh();
		}, 10);
		return E('div', { 'class': 'wa' }, [ this.body ]);
	},

	handleSave: null, handleSaveApply: null, handleReset: null
});
