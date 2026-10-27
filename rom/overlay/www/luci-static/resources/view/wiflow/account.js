'use strict';
'require view';
'require ui';
'require poll';
'require rpc';
'require wiflow.kit as K';

const svg = K.svg, chip = K.chip, card = K.card, band = K.band, signalBars = K.signalBars;

/* Wiflow App: the router's link to the Wiflow account (WordPress) and a
   live summary of the router. WiFi and network are configured in LuCI. */

const callStatus = rpc.declare({ object: 'wiflow', method: 'status', expect: { '': {} } });
const callPair = rpc.declare({ object: 'wiflow', method: 'pair', params: [ 'code' ] });
const callUnpair = rpc.declare({ object: 'wiflow', method: 'unpair', params: [ 'force' ] });
const callJobClear = rpc.declare({ object: 'wiflow', method: 'job_clear' });

function ago(t) {
	t = +t || 0;
	if (!t) return _('never');
	const d = Math.max(0, Math.floor(Date.now() / 1000) - t);
	if (d < 60) return _('just now');
	if (d < 3600) return _('%d min ago').format(Math.floor(d / 60));
	if (d < 86400) return _('%d h ago').format(Math.floor(d / 3600));
	return _('%d d ago').format(Math.floor(d / 86400));
}

function dur(sec) {
	sec = +sec || 0;
	const d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60);
	return d ? _('%dd %dh').format(d, h) : h ? _('%dh %dm').format(h, m) : _('%dm').format(m);
}

/* Messages the router writes into its own log: shown in the language of the page. */
function logText(m) {
	let k;
	if ((k = m.match(/^Command from the app: (.+)$/))) return _('Command from the app: %s').format(k[1]);
	if ((k = m.match(/^Linked to Wiflow account (.*)$/))) return _('Linked to Wiflow account %s').format(k[1]);
	if ((k = m.match(/^Wiflow (\S+) started$/))) return _('Wiflow %s started').format(k[1]);
	return _(m);
}

function tile(icon, label, value, unit, sub, right) {
	return E('section', { 'class': 'wa-card wa-tile wa-c3' }, [
		E('div', { 'class': 'wa-top' }, [ E('span', { 'class': 'wa-ico' }, svg(icon)), label, right || '' ]),
		E('div', { 'class': 'wa-val' }, unit ? [ value, E('small', {}, unit) ] : value),
		E('div', { 'class': 'wa-sub' }, sub)
	]);
}

function meter(label, text, pct) {
	return E('div', { 'class': 'wa-meter' }, [
		E('div', { 'class': 'wa-row' }, [ E('span', {}, label), E('b', {}, text) ]),
		E('div', { 'class': 'wa-bar', 'role': 'img', 'aria-label': `${label} ${text}` }, E('i', { 'class': pct > 85 ? 'hot' : '', 'style': `width:${Math.max(2, Math.min(100, pct))}%` }))
	]);
}

/* Area chart: values 0..N across the width, labels drawn in HTML so the
   SVG can stretch without distorting text. */
function chart(vals, unit, color, floorZero) {
	const W = 600, H = 150, n = vals.length;
	const real = vals.filter(v => v != null);
	if (real.length < 1)
		return E('div', { 'class': 'wa-empty' }, _('No data yet'));
	let max = Math.max.apply(null, real), min = floorZero ? 0 : Math.min.apply(null, real);
	max = floorZero ? Math.max(4, Math.ceil(max / 2) * 2) : Math.ceil((max + 4) / 10) * 10;
	if (!floorZero) min = Math.floor((min - 4) / 10) * 10;
	const x = i => i * W / (n - 1), y = v => H - (v - min) / (max - min) * H;
	const first = vals.findIndex(v => v != null);
	const pts = [];
	vals.forEach((v, i) => { if (v != null) pts.push(`${x(i).toFixed(1)},${y(v).toFixed(1)}`); });
	const lastX = x(vals.length - 1 - [].concat(vals).reverse().findIndex(v => v != null));
	const ticks = [ max, (max + min) / 2, min ];
	const ns = 'http://www.w3.org/2000/svg';
	const s = document.createElementNS(ns, 'svg');
	s.setAttribute('viewBox', `0 0 ${W} ${H}`);
	s.setAttribute('preserveAspectRatio', 'none');
	s.setAttribute('role', 'img');
	s.setAttribute('aria-label', `${unit}, ${_('last 24 hours')}`);
	s.innerHTML = ticks.map(t => `<line x1="0" x2="${W}" y1="${y(t)}" y2="${y(t)}" stroke="#E6E9F0" stroke-width="1" vector-effect="non-scaling-stroke"/>`).join('')
		+ `<polygon points="${x(first).toFixed(1)},${H} ${pts.join(' ')} ${lastX.toFixed(1)},${H}" fill="${color}" fill-opacity=".1"/>`
		+ `<polyline points="${pts.join(' ')}" fill="none" stroke="${color}" stroke-width="2.4" stroke-linejoin="round" stroke-linecap="round" vector-effect="non-scaling-stroke"/>`;
	const plot = E('div', { 'class': 'wa-plot' }, [ s ]);
	ticks.forEach(t => plot.appendChild(E('span', { 'class': 'wa-yl', 'style': `top:${y(t) / H * 100}%` }, String(Math.round(t)))));
	return E('div', {}, [ plot, E('div', { 'class': 'wa-xl' }, [ _('24 h ago'), '18 h', '12 h', '6 h', _('now') ].map(t => E('span', {}, t))) ]);
}

return view.extend({
	load() {
		return callStatus();
	},

	chartCard(s) {
		const ser = s.series || {}, dev = ser.devices || [], lat = ser.latency || [];
		const body = E('div');
		const stats = E('div', { 'class': 'wa-stats' });
		const seg = E('div', { 'class': 'wa-seg', 'role': 'tablist' });
		const real = a => a.filter(v => v != null);
		const avg = a => a.length ? a.reduce((x, y) => x + y, 0) / a.length : 0;
		const show = which => {
			this.tab = which;
			const d = which == 'dev';
			const v = d ? dev : lat, r = real(v);
			seg.querySelectorAll('button').forEach(b => { b.classList.toggle('on', b.dataset.k == which); b.setAttribute('aria-selected', b.dataset.k == which ? 'true' : 'false'); });
			const none = !r.length;
			const u = d ? '' : ' ms';
			stats.replaceChildren(
				E('div', {}, [ E('b', {}, none ? '—' : (d ? String(Math.max.apply(null, r)) : Math.round(avg(r)) + u)), d ? _('Peak') : _('Average') ]),
				E('div', {}, [ E('b', {}, none ? '—' : (d ? avg(r).toFixed(1) : Math.min.apply(null, r) + u)), d ? _('Average') : _('Best') ]),
				E('div', {}, [ E('b', {}, none ? '—' : (d ? String(r[r.length - 1]) : Math.max.apply(null, r) + u)), d ? _('Now') : _('Worst') ])
			);
			body.replaceChildren(chart(v, d ? _('Connected devices') : _('Latency (ms)'), d ? '#0054F0' : '#009AD6', d));
		};
		[ [ 'dev', _('Devices') ], [ 'lat', _('Latency') ] ].forEach(k => {
			const b = E('button', { 'type': 'button', 'role': 'tab', 'data-k': k[0] }, k[1]);
			b.addEventListener('click', () => show(k[0]));
			seg.appendChild(b);
		});
		show(this.tab || 'dev');
		return card('wa-c8', 'pulse', _('Last 24 hours'), seg, [ stats, body ]);
	},

	accountCard(s) {
		const w = s.wp || {}, d = s.device || {};
		const unlink = E('button', { 'class': 'wa-btn neg', 'type': 'button' }, [ svg('unlink'), _('Unlink account') ]);
		unlink.addEventListener('click', () => ui.showModal(_('Unlink account'), [
			E('p', {}, _('This router stops sending data to the Wiflow account. You can link it again at any time.')),
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')), ' ',
				E('button', { 'class': 'btn cbi-button-negative important', 'click': () => this.follow(_('Unlinking…'), () => callUnpair(false)) }, _('Unlink'))
			])
		]));
		return card('wa-c4', 'cloud', _('Account'), w.online ? chip('ok', _('Connected')) : chip('warn', _('No contact')), [
			E('div', { 'class': 'wa-id' }, [
				E('img', { 'src': L.resource('../wiflow/favicon.png'), 'alt': '' }),
				E('div', { 'style': 'min-width:0' }, [ E('div', { 'class': 'wa-l' }, _('Account ID')), E('div', { 'class': 'wa-v' }, w.account || '—') ])
			]),
			E('dl', { 'class': 'wa-kv' }, [
				E('dt', {}, _('Linked')), E('dd', {}, ago(w.since)),
				E('dt', {}, _('Last contact')), E('dd', {}, ago(w.last_ok)),
				E('dt', {}, _('Server')), E('dd', {}, 'wiflow.projifylab.com'),
				E('dt', {}, _('Device ID')), E('dd', {}, d.id || '—')
			]),
			E('div', { 'class': 'wa-btns' }, [ unlink ])
		]);
	},

	sourceCard(s) {
		const src = s.source || {}, inet = s.internet || {};
		const wifi = !!src.ssid;
		const btn = E('a', { 'class': 'wa-btn sm wa-r', 'href': L.url('admin/wifi'), 'style': 'text-decoration:none' }, _('Change'));
		return card('wa-c4', wifi ? 'wifi' : 'cable', _('Internet source'), btn, [
			E('dl', { 'class': 'wa-kv' }, [
				E('dt', {}, _('Source')), E('dd', {}, wifi ? src.ssid + (src.band ? ' · ' + band(src.band) : '') : _('WAN cable')),
				wifi && src.signal ? E('dt', {}, _('Signal')) : '', wifi && src.signal ? E('dd', {}, [ signalBars(src.signal), ' ' + src.signal + ' dBm' ]) : '',
				E('dt', {}, _('IP address')), E('dd', {}, src.ip || '—'),
				E('dt', {}, _('Gateway')), E('dd', {}, src.gateway || '—')
			])
		]);
	},

	healthCard(s) {
		const m = s.metrics || {};
		const mem = m.mem_total_mb ? m.mem_used_mb / m.mem_total_mb * 100 : 0, fl = m.flash_total_mb ? m.flash_used_mb / m.flash_total_mb * 100 : 0;
		return card('wa-c4', 'chip', _('Router health'), null, [
			meter('CPU', (m.cpu ?? 0) + '%', m.cpu ?? 0),
			meter(_('Memory'), `${m.mem_used_mb} / ${m.mem_total_mb} MB`, mem),
			meter(_('Storage'), `${m.flash_used_mb} / ${m.flash_total_mb} MB`, fl),
			E('div', { 'class': 'wa-mini' }, [ E('div', {}, [ E('b', {}, (m.temp ?? '—') + ' °C'), _('Temperature') ]), E('div', {}, [ E('b', {}, String(m.load ?? '—')), _('Load') ]) ])
		]);
	},

	logCard(s) {
		const rows = (s.log || []).map(r => E('li', {}, [ E('time', {}, ago(r.t)), E('span', {}, logText(String(r.m))) ]));
		return card('wa-c12', 'list', _('Activity'), null, [ E('ul', { 'class': 'wa-log' }, rows) ]);
	},

	/* Why the router started, what the automatic recovery is doing, guest limit. */
	systemCard(s) {
		const y = s.system || {}, r = y.recovery || {};
		const why = {
			power_or_manual: _('Power on or manual restart'),
			auto_recovery: _('Automatic restart after losing Internet'),
			wp_command: _('Restart from the Wiflow app')
		}[y.boot_reason] || _('Power on or manual restart');
		const min = Math.floor((+r.offline_s || 0) / 60);
		let st = [ 'ok', _('Normal') ];
		if (r.stage >= 3) st = [ 'bad', _('Restart done, waiting for Internet') ];
		else if (r.stage == 2) st = [ 'warn', _('Restarting the WiFi') ];
		else if (r.stage == 1) st = [ 'warn', _('Renewing the WAN connection') ];
		else if (min >= 1) st = [ 'warn', _('No Internet for %d min').format(min) ];
		return card('wa-c4', 'pulse', _('Stability'), chip(st[0], st[1]), [
			E('dl', { 'class': 'wa-kv' }, [
				E('dt', {}, _('Last start')), E('dd', {}, why),
				E('dt', {}, _('Automatic restarts in a row')), E('dd', {}, String(y.recovery_reboots ?? 0)),
				E('dt', {}, _('Guests at most')), E('dd', {}, y.guest_max > 0 ? String(y.guest_max) : _('No limit'))
			])
		]);
	},

	portalText(p) {
		p = p || {};
		const net = {
			guest: _('Guest WiFi network: OK'),
			lan: _('Guest WiFi network: WiFi is on the LAN, not on the guest network'),
			mixed: _('Guest WiFi network: one WiFi is on the LAN'),
			missing: _('Guest WiFi network: not set up')
		}[p.network] || '';
		const st = {
			off: _('Portal off: no content published for this router yet'),
			syncing: _('Portal: downloading content'),
			on: _('Portal on: content revision %s').format(p.revision),
			safe: _('Portal paused (safe mode): guests have Internet'),
			error: _('Portal: content not received (%s)').format(p.error || _('error'))
		}[p.state] || '';
		return st + (net ? ' · ' + net : '');
	},

	portalCard(s) {
		return E('section', { 'class': 'wa-card wa-c12' }, E('div', { 'class': 'wa-link' }, [
			E('span', { 'class': 'wa-ico' }, svg('users')),
			E('div', { 'class': 'wa-t' }, [ _('Portal, content and guests'), E('span', {}, this.portalText((s || {}).portal)) ]),
			E('a', { 'class': 'wa-btn pri', 'href': 'https://wiflow.projifylab.com', 'target': '_blank', 'rel': 'noopener', 'style': 'text-decoration:none' }, [ _('Open Wiflow'), svg('ext') ])
		]));
	},

	linked(s) {
		const inet = s.internet || {}, c = s.clients || {}, d = s.device || {}, src = s.source || {};
		return E('div', {}, [
			E('div', { 'class': 'wa-grid' }, [
				tile('globe', _('Internet'), inet.online ? _('Online') : _('Offline'), null, inet.online ? `${src.ssid || _('Cable')}${inet.latency > 0 ? ' · ' + inet.latency + ' ms' : ''}` : _('No connection'), null),
				tile('users', _('Devices now'), String(c.now ?? 0), null, _('%d on 2.4 GHz · %d on 5 GHz').format(c.band2g ?? 0, c.band5g ?? 0)),
				tile('pulse', _('Today'), String(c.today ?? 0), null, _('unique devices')),
				tile('clock', _('Uptime'), dur(d.uptime), null, `Wiflow OS ${d.os || ''}`)
			]),
			E('div', { 'class': 'wa-grid' }, [ this.chartCard(s), this.accountCard(s) ]),
			E('div', { 'class': 'wa-grid' }, [ this.sourceCard(s), this.healthCard(s), this.systemCard(s) ]),
			E('div', { 'class': 'wa-grid' }, [ this.logCard(s) ]),
			E('div', { 'class': 'wa-grid' }, [ this.portalCard(s) ])
		]);
	},

	unlinked(s) {
		const d = s.device || {};
		const code = E('input', { 'type': 'text', 'maxlength': '14', 'placeholder': 'XXXX XXXX XXXX', 'autocomplete': 'off', 'spellcheck': 'false', 'aria-label': _('Link code') });
		const go = E('button', { 'class': 'wa-btn pri', 'type': 'button' }, [ svg('link'), _('Link account') ]);
		go.addEventListener('click', () => this.follow(_('Linking…'), () => callPair(code.value)));
		return E('div', { 'class': 'wa-grid' }, [
			card('wa-c7', 'link', _('Link to your Wiflow account'), chip('', _('Not linked')), [
				E('ol', { 'class': 'wa-steps' }, [
					E('li', {}, _('Open the Wiflow app and go to Devices › Add device.')),
					E('li', {}, _('Copy the 12-character code it shows.')),
					E('li', {}, _('Enter the code below.'))
				]),
				E('div', { 'class': 'wa-field' }, [ E('label', {}, _('Link code')), code ]),
				E('div', { 'class': 'wa-btns' }, [ go ])
			]),
			card('wa-c5', 'chip', _('This router'), s.internet?.online ? chip('ok', _('Online')) : chip('warn', _('No Internet')), [
				E('dl', { 'class': 'wa-kv' }, [
					E('dt', {}, _('Device ID')), E('dd', {}, d.id || '—'),
					E('dt', {}, _('Model')), E('dd', {}, d.model || '—'),
					E('dt', {}, 'Wiflow OS'), E('dd', {}, d.os || '—'),
					E('dt', {}, _('Uptime')), E('dd', {}, dur(d.uptime))
				])
			])
		]);
	},

	/* Pair / unpair run as a background job on the router: follow it until it ends. */
	follow(title, start) {
		const msg = E('p', { 'style': 'margin:0' }, _('Starting…'));
		ui.showModal(title, [ msg ]);
		const deadline = Date.now() + 90000;
		const poll1 = () => new Promise(r => setTimeout(r, 1200)).then(callStatus).then(st => {
			const j = st && st.job;
			if (j && j.state == 'running') {
				msg.textContent = j.message || '…';
				return Date.now() < deadline ? poll1() : null;
			}
			return j;
		}, () => (Date.now() < deadline ? poll1() : null));
		return Promise.resolve(start()).then(r => {
			if (!r || r.ok === false) {
				ui.hideModal();
				ui.addNotification(null, E('p', {}, (r && r.error) || _('Could not start.')), 'danger');
				return;
			}
			return poll1().then(j => {
				ui.hideModal();
				callJobClear();
				if (j && j.state == 'success')
					location.reload();
				else
					ui.addNotification(null, E('p', {}, (j && j.message) || _('The router did not answer. Reload the page in a minute.')), 'danger');
			});
		});
	},

	render(s) {
		const linked = !!(s.wp && s.wp.paired);
		const body = E('div', {}, linked ? this.linked(s) : this.unlinked(s));
		if (linked)
			poll.add(() => callStatus().then(n => { if (n && n.wp && n.wp.paired) body.replaceChildren(this.linked(n)); }), 10);
		return E('div', { 'class': 'wa' }, [ body ]);
	},

	handleSave: null, handleSaveApply: null, handleReset: null
});
