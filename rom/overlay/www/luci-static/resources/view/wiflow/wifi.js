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
const callSpeed = rpc.declare({ object: 'wiflow', method: 'speed', expect: { '': {} } });
const callSpeedtest = rpc.declare({ object: 'wiflow', method: 'speedtest', expect: { '': {} } });
const callGuestLimit = rpc.declare({ object: 'wiflow', method: 'guest_limit', params: [ 'down', 'up' ], expect: { '': {} } });
const callGuestAuto = rpc.declare({ object: 'wiflow', method: 'guest_auto', params: [ 'on' ], expect: { '': {} } });
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
	log: [],

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
			].concat(this.scanRows()), 'w-half');

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
		if (changed) { state = chip('warn', _('Waiting to save')); state.classList.add('w-clk'); state.setAttribute('role', 'button'); state.addEventListener('click', () => this.applyStep()); }
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
		return panel('wifi', _('Source WiFi'), state, rows.concat(this.scanRows()), 'w-half');
	},

	/* Scanning for a source WiFi belongs to the source card: one row per band. */
	scanRows() {
		const one = b => E('div', { 'class': 'w-row' }, [
			E('span', { 'class': 'w-bandi' }, svg('band')), E('div', { 'class': 'w-k' }, _('Scan %s').format(band(b))),
			btn('p', _('Scan now'), () => this.scan(b), { sm: true })
		]);
		return [ '2g', '5g' ].filter(b => uci.sections('wireless', 'wifi-device').some(d => d.band == b)).map(one);
	},

	guestPanel() {
		const nets = this.st.networks || [];
		const aps = ifaces().filter(i => i.mode == 'ap');
		// one name on both bands is one row ("auto 2.4 / 5 GHz"), as in the mockup
		const groups = [];
		aps.forEach(a => {
			const g = groups.find(x => x.ssid == a.ssid);
			if (g) { g.bands.push(bandOf(a.device)); g.off = g.off && a.disabled == '1'; }
			else groups.push({ ssid: a.ssid, bands: [ bandOf(a.device) ], off: a.disabled == '1' });
		});
		const rows = groups.map(g => row(g.ssid, g.off ? chip('', _('Off')) : chip('ok', _('Broadcasting')),
			{ sub: g.bands.length > 1 ? _('Auto 2.4 / 5 GHz') : band(g.bands[0]) }));
		rows.push(row(_('Connected now'), String((this.st.clients || {}).now ?? 0), { t: 1 }));
		const sp = this.speedBody();
		return panel('users', _('Guest WiFi'), sp.tgl, rows.concat(sp.body), 'w-half');
	},

	/* Guest speed: one card with two bars (download, upload; the end of the bar is the speed of the
	   Internet line from the last speed test), the speed test button and the fixed speed per guest.
	   The balance switch decides which of the two is in use; the other one is dimmed. */
	speedBody() {
		const sp = this.sp || {};
		const sw = E('button', { 'class': 'w-tg', 'type': 'button', 'role': 'switch', 'aria-label': _('Balance') });
		sw.onclick = () => {
			const on = sw.getAttribute('aria-checked') != 'true';
			sw.setAttribute('aria-checked', on); sw.disabled = true;
			callGuestAuto(on).then(() => callSpeed().then(s => { this.sp = s; this.paintSpeed(); })).finally(() => { sw.disabled = false; });
		};
		const bar = (cls, label) => {
			const v = E('b', {}), mx = E('span', { 'class': 'w-mx' }), fill = E('i', {});
			return { v, mx, fill, el: E('div', { 'class': 'w-sr ' + cls }, [
				E('div', { 'class': 'w-srh' }, [ E('span', { 'class': 'w-srl' }, label), E('span', {}, [ v, mx ]) ]),
				E('div', { 'class': 'w-bar' }, fill) ]) };
		};
		const dn = bar('w-dn', '\u2193 ' + _('Download speed')), up = bar('w-up', '\u2191 ' + _('Upload'));
		const info = E('span', { 'class': 'w-si' }), again = btn('s', _('Measure'), b => this.measure(b), { sm: true, cls: 'w-fit w-meas' });
		const warn = E('div', { 'class': 'w-sw' });
		const card = E('div', { 'class': 'w-spc' }, [ dn.el, up.el, E('div', { 'class': 'w-sf' }, [ info, again ]), warn ]);
		const lim = this.lim = this.lim || { dn: sp.fixed_down > 0 ? String(Math.round(sp.fixed_down / 1000)) : '', up: sp.fixed_up > 0 ? String(Math.round(sp.fixed_up / 1000)) : '', dirty: {} };
		const inp = (k, label) => {
			const i = E('input', { 'type': 'number', 'min': '0', 'max': '1000', 'step': '1', 'inputmode': 'numeric', 'placeholder': '\u2014', 'aria-label': label, 'value': lim[k] });
			i.addEventListener('input', () => { lim[k] = i.value; lim.dirty[k] = true; });
			return { i, el: E('div', { 'class': 'w-lf' }, [ E('div', { 'class': 'w-in' }, [ i, E('span', { 'class': 'w-lu' }, label + ' Mbps') ]) ]) };
		};
		const ld = inp('dn', '\u2193'), lu = inp('up', '\u2191');
		const save = btn('p', _('Save'), b => this.saveLimit(b), { sm: true, cls: 'w-fit' });
		const limits = E('div', { 'class': 'w-lim' }, [ E('div', { 'class': 'w-ll' }, _('Speed limit per guest') + ' \u00b7 ' + _('empty = no limit')), E('div', { 'class': 'w-lr' }, [ ld.el, lu.el, save ]) ]);
		this.sv = { sw, dn, up, info, again, warn, card, limits, inputs: [ ld.i, lu.i ], keys: [ 'dn', 'up' ], save };
		this.paintSpeed();
		return { tgl: E('span', { 'class': 'w-tgl' }, [ _('Balance'), sw ]), body: [ E('div', { 'class': 'w-sub' }, _('Guest speed')), card, limits ] };
	},

	paintSpeed() {
		const v = this.sv, sp = this.sp || {};
		if (!v) return;
		const mb = k => (k / 1000).toFixed(k >= 100000 ? 0 : 1);
		const ln = sp.line || {}, on = !!sp.active, auto = !!sp.auto;
		v.sw.setAttribute('aria-checked', auto);
		// end of the bar: the speed of the Internet line (last test), else what the balance may give
		const mxd = ln.down > 0 ? ln.down : (on ? sp.down_limit || 0 : 0), mxu = ln.up > 0 ? ln.up : (on ? sp.up_limit || 0 : 0);
		const set = (b, now, mx) => {
			b.v.textContent = on ? mb(now || 0) : '\u2014';
			b.mx.textContent = (mx > 0 ? ' / ' + mb(mx) : '') + ' Mbps';
			b.fill.style.width = (on && mx > 0 ? Math.min(100, (now || 0) / mx * 100) : 0) + '%';
		};
		set(v.dn, sp.down_now, mxd); set(v.up, sp.up_now, mxu);
		const t = ln.at > 0 ? new Date(ln.at * 1000) : null;
		const hm = t ? ('0' + t.getHours()).slice(-2) + ':' + ('0' + t.getMinutes()).slice(-2) : '';
		const phase = { ping: _('Testing latency…'), down: _('Testing download…'), up: _('Testing upload…') }[ln.phase];
		let txt;
		if (ln.running) txt = phase || _('Testing latency…');
		else if (ln.phase == 'failed') txt = _('Could not measure');
		else {
			const parts = [];
			if (ln.phase == 'done') { if (ln.rtt > 0) parts.push(ln.rtt + ' ms'); if (hm) parts.push(hm); }
			else parts.push(_('Not measured yet'));
			if (auto && on && sp.guests > 0) parts.push(_('%d guests').format(sp.guests));
			txt = parts.join(' \u00b7 ');
		}
		v.info.textContent = txt;
		v.again.disabled = !!ln.running; v.again.textContent = ln.running ? _('Measuring…') : _('Measure');
		v.warn.textContent = !ln.running && sp.guests > 0 ? _('Guests are online: the test takes about 20 seconds and may slow them down.') : '';
		// balance on: the fixed speed is dimmed; balance off: the sharing numbers are
		v.limits.classList.toggle('w-dim', auto);
		v.inputs.forEach((i, n) => {
			i.disabled = auto;
			const k = v.keys[n], fx = k == 'dn' ? sp.fixed_down : sp.fixed_up;
			if (this.lim && !this.lim.dirty[k] && document.activeElement !== i && sp.fixed_down != null) { this.lim[k] = fx > 0 ? String(Math.round(fx / 1000)) : ''; i.value = this.lim[k]; }
		});
		v.save.disabled = auto;
		v.card.classList.toggle('w-balo', !auto);
	},

	measure(b) {
		b.disabled = true;
		callSpeedtest().then(() => callSpeed().then(s => { this.sp = s; this.paintSpeed(); }), () => { b.disabled = false; });
	},

	saveLimit(b) {
		const num = v => v === '' ? 0 : Number(v);
		const d = num(this.lim.dn), u = num(this.lim.up);
		if (!Number.isInteger(d) || !Number.isInteger(u) || d < 0 || u < 0 || d > 1000 || u > 1000) {
			b.textContent = _('0 to 1000 Mbps'); window.setTimeout(() => { b.textContent = _('Save'); }, 2500); return;
		}
		b.disabled = true;
		callGuestLimit(d * 1000, u * 1000).then(r => {
			if (r && r.ok) this.lim.dirty = {};
			b.textContent = r && r.ok ? _('Saved') : _('Not saved');
		}, () => { b.textContent = _('Not saved'); }).finally(() => window.setTimeout(() => { b.disabled = !!(this.sp || {}).auto; b.textContent = _('Save'); }, 1800));
	},

	/* The two steps of a change: 1 = the form, 2 = review and apply. */
	stepper(at) {
		const dot = (n, t) => E('span', { 'class': 'w-stpi' + (at == n ? ' w-on' : '') }, [ E('i', {}, at > n ? '\u2713' : String(n)), t ]);
		return E('div', { 'class': 'w-stp' }, [ dot(1, _('Details')), E('span', { 'class': 'w-ln' }), dot(2, _('Apply')) ]);
	},

	/* Step 2: what is about to be written, then Save & apply. */
	applyStep() {
		const rows = this.log.map(l => E('div', { 'class': 'w-cr' }, [ E('span', {}, l[0]), E('b', {}, l[1]) ]));
		if (this.srv > 0) rows.push(E('div', { 'class': 'w-cr' }, [ E('span', {}, _('Changes saved on the router')), E('b', {}, String(this.srv)) ]));
		const n = rows.length;
		if (!n) return ui.hideModal();
		K.dialog(_('Apply changes'), [
			this.stepper(2),
			E('div', { 'class': 'w-cn' }, _('%d changes not applied yet').format(n)),
			E('div', { 'class': 'w-cl' }, rows),
			E('div', { 'class': 'w-note' }, _('Applying makes the WiFi drop for a few seconds, then it reconnects.')),
			E('div', {}, btn('t', _('Reset changes'), () => { ui.hideModal(); this.reset(); }, { sm: true, cls: 'w-fit w-l0' }))
		], [
			btn('g', _('Go back'), ui.hideModal),
			btn('p', _('Save & apply'), () => this.apply())
		]);
	},

	/* The change was collected: continue straight to step 2. */
	staged(what, value) {
		if (what) this.log.push([ what, value ]);
		ui.hideModal();
		this.redraw();
		this.applyStep();
	},

	draw() {
		const inet = this.st.internet || {};
		return E('div', {}, [
			K.head(_('Internet'), this.pending() ? btn('s', _('%d changes not applied yet').format(this.log.length + (this.srv > 0 ? 1 : 0)), () => this.applyStep(), { sm: true, cls: 'w-fit' }) : (inet.online ? chip('ok', _('Has Internet')) : null)),
			E('div', { 'class': 'w-gr' }, [ this.flowPanel(), this.sourcePanel(), this.guestPanel() ])
		]);
	},

	redraw() {
		if (this.body) this.body.replaceChildren(this.draw());
	},

	/* ---- changes ---- */

	toggle(sta) {
		const was = sta.disabled == '1';
		if (was) this.unset('wireless', sta['.name'], 'disabled');
		else this.set('wireless', sta['.name'], 'disabled', '1');
		this.staged(_('Source WiFi'), (was ? _('Turn on') : _('Disable')) + ' \u00b7 ' + sta.ssid);
	},

	drop(sta) {
		K.dialog(_('Remove WiFi'), [ this.stepper(1), E('p', {}, _('Remove the source WiFi %s from this router?').format(sta.ssid)) ], [
			btn('g', _('Close dialog'), ui.hideModal),
			btn('p', _('Continue'), () => { this.remove('wireless', sta['.name']); this.staged(_('Source WiFi'), _('Remove WiFi') + ' \u00b7 ' + sta.ssid); })
		]);
	},

	edit(sta) {
		const pw = E('input', { 'type': 'password', 'autocomplete': 'off', 'placeholder': _('Leave empty to keep it'), 'aria-label': _('WPA password') });
		K.dialog(_('Wireless network: %s').format(sta.ssid), [ this.stepper(1), E('div', { 'class': 'w-fgrid', 'style': 'padding-bottom:12px' }, [
			K.field(_('Source WiFi name'), E('input', { 'type': 'text', 'value': sta.ssid, 'readonly': '' }), { rd: 1 }),
			K.field(_('Radio band'), E('input', { 'type': 'text', 'value': band(bandOf(sta.device)), 'readonly': '' }), { rd: 1 }),
			K.field(_('WPA password'), pw, { pw: 1 })
		]) ], [
			btn('g', _('Not now'), ui.hideModal),
			btn('p', _('Continue'), () => {
				if (pw.value) {
					if (pw.value.length < 8) return ui.addNotification(null, E('p', {}, _('The password needs at least 8 characters.')), 'danger');
					this.set('wireless', sta['.name'], 'key', pw.value);
				}
				this.staged(_('Source WiFi'), pw.value ? _('Password changed') : sta.ssid);
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
		// like the stock scan page: results are kept by BSSID, an entry that is missed once stays (dimmed) and is dropped after 3 misses
		const cache = {};
		const list = rows => {
			if (!rows.length) { body.replaceChildren(K.waitBox(_('No networks found'))); return; }
			body.replaceChildren(E('div', {}, rows.map(r => E('div', { 'class': 'w-net' + (r.ssid ? '' : ' w-hid') + (r.miss ? ' w-stale' : '') }, [
				E('div', { 'class': 'w-i' }, [
					E('div', { 'class': 'w-n' }, r.ssid || _('Hidden network')),
					E('div', { 'class': 'w-m' }, [ sig(r.signal || -90), E('span', {}, (r.signal || -90) + ' dBm · CH ' + r.channel + ' · ' + encLabel(r.encryption)) ])
				]),
				btn('p', _('Join'), () => { halt(); this.join(r); }, { sm: true })
			]))));
		};
		const run = () => network.getWifiDevices().then(devs => Promise.all(devs.filter(d => bandOf(d.getName()) == b).map(d =>
			d.getScanList().then(l => l.map(r => Object.assign({}, r, { dev: d.getName(), band: b, modes: d.getHTModes() || [] })), () => [])
		))).then(all => {
			if (stopped) return;
			const own = ownSsids(), seen = {};
			[].concat.apply([], all).forEach(r => {
				if (!r.bssid || (r.ssid && own.indexOf(r.ssid) >= 0)) return;
				seen[r.bssid] = 1;
				cache[r.bssid] = Object.assign(r, { miss: 0 });
			});
			Object.keys(cache).forEach(k => { if (!seen[k] && ++cache[k].miss > 3) delete cache[k]; });
			list(Object.keys(cache).map(k => cache[k]).sort((x, y) => (y.signal || -200) - (x.signal || -200)));
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
		K.dialog(_('Wireless network: %s').format(bss.ssid), [ this.stepper(1), E('div', { 'class': 'w-fgrid', 'style': 'padding-bottom:12px' }, [
			K.field(_('Source WiFi name'), E('input', { 'type': 'text', 'value': bss.ssid, 'readonly': '' }), { rd: 1 }),
			K.field(_('Radio band'), E('input', { 'type': 'text', 'value': band(bss.band), 'readonly': '' }), { rd: 1 })
		]) ], [
			btn('g', _('Not now'), ui.hideModal),
			btn('p', _('Continue'), () => { this.stage(bss, key); this.staged(_('Source WiFi'), bss.ssid + ' \u00b7 ' + band(bss.band)); })
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
		const go = () => { this.mem = 0; this.log = []; uci.unload(CONFIGS); return uci.load(CONFIGS).then(() => this.serverCount()).then(() => this.redraw()); };
		if (this.srv > 0) return Promise.all(CONFIGS.map(c => callRevert(c))).then(go, go);
		return go();
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
			this.mem = 0; this.log = [];
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
		this.st = st; this.sp = st.speed;
		this.body = E('div', {}, this.draw());
		poll.add(() => {
			if (document.body.classList.contains('modal-overlay-active') || document.hidden) return;
			return callSpeed().then(s => { this.sp = s; this.paintSpeed(); }, () => {});
		}, 2);
		poll.add(() => {
			if (document.body.classList.contains('modal-overlay-active') || (document.activeElement && document.activeElement.closest && document.activeElement.closest('.w-lim'))) return;
			return callStatus().then(s => { this.st = s; this.sp = s.speed || this.sp; this.redraw(); });
		}, 10);
		return this.body;
	},

	handleSave: null, handleSaveApply: null, handleReset: null
});
