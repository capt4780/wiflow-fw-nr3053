'use strict';
'require view';
'require ui';
'require uci';
'require rpc';
'require poll';
'require network';
'require wiflow.kit as K';

/* Network: the connection path (cable and source WiFi -> router -> guest WiFi), the source WiFi
   the router takes Internet from, scanning, and the guest WiFi it broadcasts. Changes are
   collected first and only written when the person presses Save / Save & apply. */

const chip = K.chip, btn = K.btn, row = K.row, panel = K.panel, svg = K.svg, band = K.band, sig = K.sig;

const callStatus = rpc.declare({ object: 'wiflow', method: 'status', expect: { '': {} } });
const callChanges = rpc.declare({ object: 'uci', method: 'changes', params: [ 'config' ], expect: { changes: [] } });
const callRevert = rpc.declare({ object: 'uci', method: 'revert', params: [ 'config' ] });
const CONFIGS = [ 'wireless', 'network', 'firewall' ];

function ifaces() { return uci.sections('wireless', 'wifi-iface'); }
function bandOf(dev) { return uci.get('wireless', dev, 'band') || ''; }
function ownSsids() { return ifaces().filter(i => i.mode == 'ap').map(i => i.ssid); }
function staOf() { return ifaces().find(i => i.mode == 'sta'); }

function encOf(enc) {
	enc = enc || {};
	const auth = L.toArray(enc.authentication), wpa = L.toArray(enc.wpa);
	if (Array.isArray(enc.wep)) return 'wep-open';
	if (wpa.length && auth.indexOf('psk') >= 0) return (wpa.indexOf(2) >= 0 || wpa.indexOf(3) >= 0) ? 'psk2' : 'psk';
	if (wpa.length && auth.indexOf('sae') >= 0) return 'sae';
	return enc.enabled ? 'psk2' : 'none';
}

function encLabel(enc) {
	enc = enc || {};
	if (!enc.enabled) return _('Open');
	const wpa = L.toArray(enc.wpa), auth = L.toArray(enc.authentication);
	if (auth.indexOf('sae') >= 0) return wpa.indexOf(2) >= 0 ? 'WPA2/3' : 'WPA3';
	if (Array.isArray(enc.wep)) return 'WEP';
	return wpa.indexOf(2) >= 0 || wpa.indexOf(3) >= 0 ? 'WPA2' : wpa.length ? 'WPA' : _('Protected');
}

return view.extend({
	mem: 0,

	load() {
		return Promise.all([ uci.load(CONFIGS), callStatus(), this.serverCount() ]).then(r => r[1]);
	},

	/* Changes saved on the router but not applied yet. */
	serverCount() {
		return Promise.all(CONFIGS.map(c => callChanges(c).then(a => a.length, () => 0))).then(n => {
			this.srv = n.reduce((a, b) => a + b, 0);
			return this.srv;
		});
	},

	pending() { return this.mem + (this.srv || 0); },

	/* uci calls that count as one change each. */
	set(c, s, o, v) { uci.set(c, s, o, v); this.mem++; },
	unset(c, s, o) { uci.unset(c, s, o); this.mem++; },
	remove(c, s) { uci.remove(c, s); this.mem++; },
	add(c, t, n) { this.mem++; return uci.add(c, t, n); },

	/* ---- panels ---- */

	flowPanel() {
		const src = this.st.source || {}, inet = this.st.internet || {}, sta = staOf();
		const ap = (this.st.networks || []).map(n => n.ssid)[0];
		return panel('globe', _('Connection path'), '', [
			K.flow({ via: src.via, saved: sta ? sta.ssid : '', band: src.via == 'wifi' ? src.band : (sta ? bandOf(sta.device) : ''), cable: src.cable, online: inet.online,
				guests: (this.st.clients || {}).now || 0, guestName: ap })
		], 'w-full');
	},

	sourcePanel() {
		const src = this.st.source || {}, inet = this.st.internet || {}, sta = staOf();
		const lanRow = row(_('LAN cable'), src.via == 'lan' ? _('In use') : src.cable ? _('Cable plugged in') : _('No cable'));
		if (!sta)
			return panel('wifi', _('Source WiFi'), chip('', _('Not connected yet')), [
				E('div', { 'class': 'w-row' }, E('div', { 'class': 'w-k', 'style': 'color:var(--mut);font-weight:400' }, _('No source WiFi'))), lanRow
			], 'w-half w-r2');

		const off = sta.disabled == '1', on = src.via == 'wifi' && !off, changed = this.pending() > 0;
		const acts = E('div', { 'class': 'w-acts' }, [
			btn('g', off ? _('Turn on') : _('Disable'), () => this.toggle(sta), { sm: true }),
			btn('s', _('Edit WiFi'), () => this.edit(sta), { sm: true }),
			btn('d', _('Remove WiFi'), () => this.drop(sta), { sm: true })
		]);
		const rows = [ E('div', { 'class': 'w-row w-stack' }, [
			E('div', { 'class': 'w-k' }, [ sta.ssid, E('small', {}, band(bandOf(sta.device)) + ' · ' + _('Client mode')) ]), acts
		]) ];
		let state;
		if (changed) state = chip('warn', _('Waiting to save'));
		else if (off) state = chip('', _('Turned off'));
		else if (on) state = chip('ok', _('Connected'));
		else state = chip('warn', _('Not connected yet'));
		if (on && !changed) {
			rows.push(row(_('Signal'), src.signal ? [ sig(src.signal), ' ' + src.signal + ' dBm' ] : '—'));
			rows.push(row(_('IP address'), src.ip || '—'));
			rows.push(row(_('Gateway address'), src.gateway || '—'));
			rows.push(row(_('Latency'), inet.latency > 0 ? inet.latency + ' ms' : '—'));
		}
		rows.push(lanRow);
		return panel('wifi', _('Source WiFi'), state, rows, 'w-half w-r2');
	},

	scanPanel() {
		const one = b => E('div', { 'class': 'w-row' }, [
			E('span', { 'class': 'w-bandi' }, svg('band')), E('div', { 'class': 'w-k' }, band(b)),
			btn('p', _('Scan now'), () => this.scan(b), { sm: true })
		]);
		const bands = [ '2g', '5g' ].filter(b => uci.sections('wireless', 'wifi-device').some(d => d.band == b));
		return panel('band', _('Scan source WiFi'), '', bands.map(one), 'w-half');
	},

	guestPanel() {
		const nets = this.st.networks || [];
		const aps = ifaces().filter(i => i.mode == 'ap');
		const rows = aps.map(a => {
			const n = nets.find(x => x.band == bandOf(a.device)) || {};
			return row(a.ssid, a.disabled == '1' ? chip('', _('Off')) : chip('ok', _('Broadcasting')), { sub: band(bandOf(a.device)) + ' · ' + _('%d devices').format(n.clients ?? 0) });
		});
		rows.push(row(_('Connected now'), String((this.st.clients || {}).now ?? 0), { t: 1 }));
		return panel('users', _('Guest WiFi'), '', rows, 'w-half');
	},

	/* The bar that appears once something is changed. */
	actionBar() {
		const n = this.pending();
		const bar = E('div', { 'class': 'w-act', 'hidden': n ? null : '' });
		if (!n) return bar;
		bar.appendChild(E('div', { 'class': 'w-t' }, [ E('span', {}, _('%d unsaved changes').format(n)), btn('t', _('Reset changes'), () => this.reset(), { sm: true }) ]));
		const b = E('div', { 'class': 'w-b' });
		if (this.mem > 0) b.appendChild(btn('s', _('Save'), () => this.saveOnly()));
		b.appendChild(btn('p', _('Save & apply'), () => this.apply()));
		bar.appendChild(b);
		return bar;
	},

	draw() {
		const inet = this.st.internet || {};
		return E('div', {}, [
			K.head(_('Network'), inet.online ? chip('ok', _('Online')) : chip('warn', _('No Internet'))),
			E('div', { 'class': 'w-gr' }, [ this.flowPanel(), this.sourcePanel(), this.scanPanel(), this.guestPanel() ]),
			this.actionBar()
		]);
	},

	redraw() {
		if (this.body) this.body.replaceChildren(this.draw());
	},

	/* ---- changes ---- */

	toggle(sta) {
		if (sta.disabled == '1') this.unset('wireless', sta['.name'], 'disabled');
		else this.set('wireless', sta['.name'], 'disabled', '1');
		this.redraw();
	},

	drop(sta) {
		K.dialog(_('Remove WiFi'), E('p', {}, _('Remove the source WiFi %s from this router?').format(sta.ssid)), [
			btn('g', _('Close dialog'), ui.hideModal),
			btn('d', _('Remove WiFi'), () => { this.remove('wireless', sta['.name']); ui.hideModal(); this.redraw(); })
		]);
	},

	edit(sta) {
		const pw = E('input', { 'type': 'password', 'autocomplete': 'off', 'placeholder': _('Leave empty to keep it'), 'aria-label': _('WPA password') });
		K.dialog(_('Wireless network: %s').format(sta.ssid), E('div', { 'class': 'w-fgrid', 'style': 'padding-bottom:12px' }, [
			K.field(_('Source WiFi name'), E('input', { 'type': 'text', 'value': sta.ssid, 'readonly': '' }), { rd: 1 }),
			K.field(_('Radio band'), E('input', { 'type': 'text', 'value': band(bandOf(sta.device)), 'readonly': '' }), { rd: 1 }),
			K.field(_('WPA password'), pw, { pw: 1 })
		]), [
			btn('g', _('Not now'), ui.hideModal),
			btn('p', _('Save'), () => {
				if (pw.value) {
					if (pw.value.length < 8) return ui.addNotification(null, E('p', {}, _('The password needs at least 8 characters.')), 'danger');
					this.set('wireless', sta['.name'], 'key', pw.value);
				}
				ui.hideModal();
				this.redraw();
			})
		]);
	},

	/* Scan one band, refreshing every 8 s until stopped or closed. */
	scan(b) {
		let timer = 0, stopped = false;
		const body = E('div', {}, K.waitBox(_('Starting the scan…')));
		const halt = () => { stopped = true; window.clearTimeout(timer); };
		const stop = btn('g', _('Stop refreshing'), () => { halt(); stop.disabled = true; });
		K.dialog(_('Scan WiFi %s').format(band(b)), body, [ stop, btn('g', _('Not now'), () => { halt(); ui.hideModal(); }) ], { wide: true });
		const list = rows => {
			if (!rows.length) { body.replaceChildren(K.waitBox(_('No networks found'))); return; }
			body.replaceChildren(E('div', {}, rows.map(r => E('div', { 'class': 'w-net' + (r.ssid ? '' : ' w-hid') }, [
				E('div', { 'class': 'w-i' }, [
					E('div', { 'class': 'w-n' }, r.ssid || _('Hidden network')),
					E('div', { 'class': 'w-m' }, [ sig(r.signal || -90), E('span', {}, (r.signal || -90) + ' dBm · ' + encLabel(r.encryption)) ])
				]),
				btn('p', _('Join'), () => { halt(); this.join(r); }, { sm: true })
			]))));
		};
		const run = () => network.getWifiDevices().then(devs => Promise.all(devs.filter(d => bandOf(d.getName()) == b).map(d =>
			d.getScanList().then(l => l.map(r => Object.assign({}, r, { dev: d.getName(), band: b, modes: d.getHTModes() || [] })), () => [])
		))).then(all => {
			if (stopped) return;
			const own = ownSsids(), best = {};
			[].concat.apply([], all).forEach(r => {
				if (r.ssid && own.indexOf(r.ssid) >= 0) return;
				const key = r.ssid || ('#' + r.bssid);
				if (!best[key] || (r.signal || -200) > (best[key].signal || -200)) best[key] = r;
			});
			list(Object.keys(best).map(k => best[k]).sort((x, y) => (y.signal || -200) - (x.signal || -200)));
		}).catch(() => {}).then(() => { if (!stopped) timer = window.setTimeout(run, 8000); });
		run();
	},

	/* Password, then the settings page, then the change is collected. */
	join(bss) {
		const open = !bss.encryption || !bss.encryption.enabled;
		const hidden = !bss.ssid;
		const nm = hidden ? E('input', { 'type': 'text', 'autocomplete': 'off', 'aria-label': _('Source WiFi name') }) : null;
		const next = key => this.review(hidden ? Object.assign({}, bss, { ssid: nm.value.trim(), hid: true }) : bss, key);
		if (open && !hidden) return next('');
		const pw = E('input', { 'type': 'password', 'autocomplete': 'off', 'aria-label': _('WPA password') });
		const go = btn('p', _('Continue'), () => next(open ? '' : pw.value));
		const check = () => { go.disabled = (hidden && !nm.value.trim()) || (!open && pw.value.length < 8); };
		pw.addEventListener('input', check);
		if (nm) nm.addEventListener('input', check);
		pw.addEventListener('keydown', ev => { if (ev.key == 'Enter' && !go.disabled) go.click(); });
		check();
		K.dialog(_('Join: %s').format(bss.ssid || _('Hidden network')), E('div', { 'class': 'w-fgrid', 'style': 'padding-bottom:12px' }, [].concat(hidden ? [ K.field(_('Source WiFi name'), nm) ] : [], open ? [] : [ K.field(_('WPA password'), pw, { pw: 1 }) ])), [
			btn('g', _('Close dialog'), ui.hideModal), go
		]);
		(nm || pw).focus();
	},

	review(bss, key) {
		K.dialog(_('Wireless network: %s').format(bss.ssid), E('div', { 'class': 'w-fgrid', 'style': 'padding-bottom:12px' }, [
			K.field(_('Source WiFi name'), E('input', { 'type': 'text', 'value': bss.ssid, 'readonly': '' }), { rd: 1 }),
			K.field(_('Radio band'), E('input', { 'type': 'text', 'value': band(bss.band), 'readonly': '' }), { rd: 1 })
		]), [
			btn('g', _('Not now'), ui.hideModal),
			btn('p', _('Save'), () => { this.stage(bss, key); ui.hideModal(); this.redraw(); })
		]);
	},

	/* Collect the change: radio, source WiFi interface, its network and firewall zone. */
	stage(bss, key) {
		const mode = encOf(bss.encryption);
		ifaces().filter(i => i.mode == 'sta').forEach(i => this.remove('wireless', i['.name']));

		const dev = bss.dev;
		this.unset('wireless', dev, 'disabled');
		this.set('wireless', dev, 'channel', String(bss.channel));
		// channel width of the source, as the stock "Join network" does it, with the modes this radio offers
		const modes = bss.modes || [];
		if (modes.length) {
			let w = bss.vht_operation ? (bss.vht_operation.channel_width || 20) : (bss.ht_operation && bss.ht_operation.secondary_channel_offset != 'no secondary') ? 40 : 20;
			const pre = bss.band == '2g' ? [ 'HE', 'HT' ] : [ 'HE', 'VHT', 'HT' ];
			let pick = null;
			for (; w >= 20 && !pick; w /= 2)
				for (let i = 0; i < pre.length && !pick; i++)
					if (modes.indexOf(pre[i] + w) >= 0) pick = pre[i] + w;
			if (pick) this.set('wireless', dev, 'htmode', pick);
		}

		const sid = this.add('wireless', 'wifi-iface', 'wiflow_src');
		this.set('wireless', sid, 'device', dev);
		this.set('wireless', sid, 'mode', 'sta');
		this.set('wireless', sid, 'network', 'wwan');
		this.set('wireless', sid, 'ssid', bss.ssid);
		if (bss.hid && bss.bssid) this.set('wireless', sid, 'bssid', bss.bssid);
		this.set('wireless', sid, 'encryption', mode);
		if (mode == 'wep-open') { this.set('wireless', sid, 'key', '1'); this.set('wireless', sid, 'key1', key); }
		else if (mode != 'none') this.set('wireless', sid, 'key', key);

		// the network of the source WiFi: DHCP, in the WAN zone, second to the cable
		if (!uci.get('network', 'wwan')) this.add('network', 'interface', 'wwan');
		this.set('network', 'wwan', 'proto', 'dhcp');
		this.set('network', 'wwan', 'metric', '20');
		const wz = uci.sections('firewall', 'zone').find(z => z.name == 'wan');
		if (wz) {
			const nets = L.toArray(wz.network);
			if (nets.indexOf('wwan') < 0)
				this.set('firewall', wz['.name'], 'network', nets.concat('wwan'));
		}
	},

	reset() {
		const go = () => { this.mem = 0; uci.unload(CONFIGS); return uci.load(CONFIGS).then(() => this.serverCount()).then(() => this.redraw()); };
		if (this.srv > 0) return Promise.all(CONFIGS.map(c => callRevert(c))).then(go, go);
		return go();
	},

	saveOnly() {
		return uci.save().then(() => { this.mem = 0; return this.serverCount(); }).then(() => this.redraw())
			.catch(e => ui.addNotification(null, E('p', {}, String(e && e.message || e)), 'danger'));
	},

	/* Write everything and wait while the router restarts its WiFi (the page may lose contact). */
	apply() {
		const total = 90;
		const msg = E('span', {}, _('Please wait… %d seconds').format(total));
		K.dialog(_('Applying the configuration'), K.waitBox(msg), []);
		const t0 = Date.now();
		const left = () => Math.max(0, total - Math.floor((Date.now() - t0) / 1000));
		const tick = window.setInterval(() => { msg.textContent = _('Please wait… %d seconds').format(left()); }, 1000);
		const finish = () => {
			window.clearInterval(tick);
			this.mem = 0;
			uci.unload(CONFIGS);
			return uci.load(CONFIGS).then(() => Promise.all([ callStatus().then(s => { this.st = s; }, () => {}), this.serverCount() ])).then(() => {
				ui.hideModal();
				this.redraw();
			}, () => { ui.hideModal(); });
		};
		const watch = () => {
			if (left() <= 0) return finish();
			return new Promise(r => setTimeout(r, 3000)).then(callStatus).then(s => {
				const want = staOf();
				if (!want || (s.source && s.source.via == 'wifi' && s.internet && s.internet.online)) return finish();
				return watch();
			}, watch);
		};
		return uci.save().then(() => uci.callApply(0, false)).then(() => new Promise(r => setTimeout(r, 4000)), () => new Promise(r => setTimeout(r, 4000))).then(watch);
	},

	render(st) {
		this.st = st;
		this.body = E('div', {}, this.draw());
		poll.add(() => {
			if (document.body.classList.contains('modal-overlay-active')) return;
			return callStatus().then(s => { this.st = s; this.redraw(); });
		}, 10);
		return this.body;
	},

	handleSave: null, handleSaveApply: null, handleReset: null
});
