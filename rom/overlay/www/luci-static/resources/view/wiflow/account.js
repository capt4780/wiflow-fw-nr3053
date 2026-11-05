'use strict';
'require view';
'require ui';
'require poll';
'require rpc';
'require wiflow.kit as K';

/* Overview: Internet, guests, the last 24 hours, the link to the Wiflow account, the guest page
   and the stability of the router. WiFi and network are set on the Network page. */

const chip = K.chip, btn = K.btn, row = K.row, panel = K.panel, tile = K.tile, svg = K.svg;

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

return view.extend({
	load() {
		return callStatus();
	},

	/* Devices / latency over the last 24 hours. Two switches: in the panel header (tablet, PC)
	   and in the body (phone); only one of them is shown. */
	chartPanel(s) {
		const ser = s.series || {}, dev = ser.devices || [], lat = ser.latency || [];
		const body = E('div');
		const stats = E('div', { 'class': 'w-stats' });
		const real = a => a.filter(v => v != null);
		const avg = a => a.length ? a.reduce((x, y) => x + y, 0) / a.length : 0;
		const sgs = [];
		const mk = cls => {
			const g = E('div', { 'class': 'w-sg ' + cls, 'role': 'tablist' });
			[ [ 'dev', _('Device count') ], [ 'lat', _('Latency') ] ].forEach(k => {
				const b = E('button', { 'type': 'button', 'role': 'tab', 'data-k': k[0] }, k[1]);
				b.addEventListener('click', () => show(k[0]));
				g.appendChild(b);
			});
			sgs.push(g);
			return g;
		};
		const show = which => {
			this.tab = which;
			const d = which == 'dev';
			const v = d ? dev : lat, r = real(v), none = !r.length;
			sgs.forEach(g => g.querySelectorAll('button').forEach(b => b.classList.toggle('w-on', b.dataset.k == which)));
			const u = d ? '' : ' ms';
			const st = (val, label) => E('div', {}, [ E('b', {}, val), E('span', {}, label) ]);
			stats.replaceChildren(
				st(none ? '—' : (d ? String(Math.max.apply(null, r)) : Math.round(avg(r)) + u), d ? _('Peak') : _('Average')),
				st(none ? '—' : (d ? avg(r).toFixed(1) : Math.min.apply(null, r) + u), d ? _('Average') : _('Best')),
				st(none ? '—' : (d ? String(r[r.length - 1]) : Math.max.apply(null, r) + u), d ? _('Now') : _('Worst'))
			);
			body.replaceChildren(K.chart(v, d ? '#0054F0' : '#009AD6', d));
		};
		const th = mk('w-s w-th'), tb = mk('w-full w-tb');
		show(this.tab || 'dev');
		return panel('pulse', _('Last 24 hours'), th, [ tb, stats, body ], 'w-wide');
	},

	/* Linked: account, location, last contact, unlink. Not linked: the connection code box. */
	linkPanel(s) {
		const w = s.wp || {};
		if (w.paired) {
			const unlink = btn('d', _('Unlink account'), () => ui.showModal(_('Unlink account'), [
				E('div', { 'class': 'w-bd' }, E('p', {}, _('This router stops sending data to the Wiflow account. You can link it again at any time.'))),
				E('div', { 'class': 'w-ft' }, [
					btn('g', _('Close dialog'), ui.hideModal),
					btn('d', _('Unlink'), () => this.follow(_('Unlinking…'), () => callUnpair(false)))
				])
			]), { full: true });
			return panel('link', _('Link'), w.online ? chip('ok', _('Linked')) : chip('warn', _('No contact')), [
				row(_('Account ID'), w.account || '—', { t: 1 }),
				row(_('Device'), w.device_name || '—', { t: 1 }),
				row(_('Location'), w.location || '—', { t: 1 }),
				row(_('Last contact'), ago(w.last_ok)),
				E('div', { 'class': 'w-pf' }, unlink)
			], 'w-third');
		}
		const code = E('input', { 'type': 'text', 'maxlength': '14', 'autocomplete': 'off', 'spellcheck': 'false', 'aria-label': _('Connection code'), 'autocapitalize': 'characters' });
		code.addEventListener('input', () => { const v = code.value.toUpperCase(); if (v !== code.value) code.value = v; });
		code.addEventListener('keydown', ev => { if (ev.key == 'Enter') go.click(); });
		const go = btn('p', _('Link'), () => this.follow(_('Linking…'), () => callPair(code.value)), { full: true });
		return panel('link', _('Link'), chip('warn', _('Not linked')), [
			E('div', { 'class': 'w-fld', 'style': 'margin-top:8px' }, [ E('label', {}, _('Connection code')), E('div', { 'class': 'w-in w-cd' }, code) ]),
			E('div', { 'class': 'w-pf', 'style': 'margin-bottom:8px' }, go),
			row(_('Server'), w.server || '—'),
			row(_('Server connection'), (s.internet || {}).online ? chip('ok', _('Ready')) : chip('warn', _('Not ready')))
		], 'w-third');
	},

	/* What the guests see: the state of the content, how it is shown and which content is applied. */
	guestPagePanel(s) {
		const p = s.portal || {}, w = s.wp || {};
		const kinds = { image: _('Images'), video: _('Video'), website: _('Website') };
		let st;
		if (!w.paired) st = chip('warn', _('Not updated'));
		else if (p.state == 'on') st = chip('ok', _('Up to date'));
		else if (p.state == 'safe') st = chip('warn', _('Paused'));
		else if (p.state == 'syncing') st = chip('warn', _('Updating'));
		else if (p.state == 'error') st = chip('warn', _('Content not received'));
		else st = chip('warn', _('Not updated'));
		const live = w.paired && (p.state == 'on' || p.state == 'safe');
		const kind = live && kinds[p.mode] ? chip('', kinds[p.mode]) : '—';
		const name = live && p.content_name ? p.content_name : '—';
		return panel('layers', _('Guest page'), '', [
			row(_('Status'), st),
			row(_('Display type'), kind),
			E('div', { 'class': 'w-row w-nm' }, [ E('div', { 'class': 'w-k' }, _('Content')), E('div', { 'class': 'w-v' }, E('span', { 'class': 'w-nmv', 'title': name }, name)) ])
		], 'w-third');
	},

	guestsPanel(s) {
		const c = s.clients || {};
		return panel('users', _('Guests'), '', [
			row(_('Connected now'), String(c.now ?? 0), { t: 1 }),
			row('2.4 GHz', String(c.band2g ?? 0)),
			row('5 GHz', String(c.band5g ?? 0)),
			row(_('Devices in 24 hours'), String(c.today ?? 0))
		], 'w-third');
	},

	/* Why the router started, what the automatic recovery is doing, guest limit. */
	stabilityPanel(s) {
		const y = s.system || {}, r = y.recovery || {};
		const why = {
			power_or_manual: _('Manually'),
			auto_recovery: _('Automatic (lost Internet)'),
			wp_command: _('From the Wiflow app')
		}[y.boot_reason] || _('Manually');
		const min = Math.floor((+r.offline_s || 0) / 60);
		let st = [ 'ok', _('On') ];
		if (r.stage >= 3) st = [ 'warn', _('Waiting for Internet') ];
		else if (r.stage == 2) st = [ 'warn', _('Restarting the WiFi') ];
		else if (r.stage == 1) st = [ 'warn', _('Renewing the WAN connection') ];
		else if (min >= 1) st = [ 'warn', _('No Internet for %d min').format(min) ];
		return panel('shield', _('Stability'), chip(st[0], st[1]), [
			row(_('Consecutive restarts'), String(y.recovery_reboots ?? 0)),
			row(_('Last start'), why),
			row(_('Command from the app'), s.job && s.job.state == 'running' ? _('Running') : _('No command'))
		], 'w-third');
	},

	draw(s) {
		const inet = s.internet || {}, c = s.clients || {}, d = s.device || {}, src = s.source || {};
		const subNet = inet.online ? ((src.ssid || _('Cable')) + (inet.latency > 0 ? ' · ' + inet.latency + ' ms' : '')) : _('No connection');
		return E('div', {}, [
			K.head(_('Overview')),
			E('div', { 'class': 'w-gr' }, [
				tile('globe', _('Internet'), inet.online ? _('Online') : _('Offline'), subNet),
				tile('users', _('Connected now'), String(c.now ?? 0), _('2.4 GHz: %d · 5 GHz: %d').format(c.band2g ?? 0, c.band5g ?? 0)),
				tile('pulse', _('Today'), String(c.today ?? 0), _('different devices')),
				tile('clock', _('Uptime'), dur(d.uptime), 'Wiflow OS ' + (d.os || '')),
				this.chartPanel(s), this.linkPanel(s), this.guestPagePanel(s), this.guestsPanel(s), this.stabilityPanel(s)
			])
		]);
	},

	/* Pair / unpair run as a background job on the router: follow it until it ends. */
	follow(title, start) {
		const msg = E('span', {}, _('Starting…'));
		K.dialog(title, K.waitBox(msg), []);
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
		this.body = E('div', {}, this.draw(s));
		/* Redraw only while nothing is being typed or shown in a dialog. */
		poll.add(() => callStatus().then(n => {
			if (!n || document.body.classList.contains('modal-overlay-active')) return;
			const a = document.activeElement;
			if (a && a.tagName == 'INPUT' && this.body.contains(a)) return;
			this.body.replaceChildren(this.draw(n));
		}), 10);
		return this.body;
	},

	handleSave: null, handleSaveApply: null, handleReset: null
});
