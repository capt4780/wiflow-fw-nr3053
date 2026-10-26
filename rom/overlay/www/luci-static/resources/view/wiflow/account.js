'use strict';
'require view';
'require ui';
'require poll';
'require rpc';

/* Wiflow App: the router's link to the Wiflow account (WordPress) and a
   live summary of the router. WiFi and network are configured in LuCI. */

const CSS = `
.wa{max-width:1120px}
.wa-grid{display:grid;grid-template-columns:repeat(12,minmax(0,1fr));gap:18px;margin:0 0 18px}
.wa-c3{grid-column:span 3}.wa-c4{grid-column:span 4}.wa-c5{grid-column:span 5}.wa-c6{grid-column:span 6}.wa-c7{grid-column:span 7}.wa-c8{grid-column:span 8}.wa-c12{grid-column:span 12}
.wa-card{background:#fff;border-radius:28px;padding:22px 24px;min-width:0;box-shadow:var(--sh)}
.wa-card>h3{display:flex;align-items:center;gap:12px;margin:0 0 16px;font-size:16px;font-weight:600;color:var(--ink)}
.wa-card>h3 .wa-chip,.wa-card>h3 .wa-seg{margin-left:auto}
.wa-ico{width:36px;height:36px;border-radius:50%;display:grid;place-items:center;flex:none;background:var(--soft);color:var(--acc)}
.wa-ico svg{width:18px;height:18px;fill:none;stroke:currentColor;stroke-width:1.9;stroke-linecap:round;stroke-linejoin:round}
.wa-chip{display:inline-flex;align-items:center;gap:8px;height:28px;padding:0 12px;border-radius:999px;font-size:13px;font-weight:600;white-space:nowrap;background:var(--bg);color:var(--ink2)}
.wa-chip::before{content:"";width:8px;height:8px;border-radius:50%;background:currentColor}
.wa-chip.ok{background:var(--oksoft);color:var(--okink)}.wa-chip.ok::before{background:var(--ok)}
.wa-chip.warn{background:var(--warnsoft);color:var(--warn)}.wa-chip.bad{background:var(--badsoft);color:var(--bad)}
.wa-chip.plain::before{display:none}
.wa-tile{display:flex;flex-direction:column;gap:2px}
.wa-tile .wa-top{display:flex;align-items:center;gap:10px;margin-bottom:12px;color:var(--ink2);font-size:14px;font-weight:500}
.wa-tile .wa-val{font-size:34px;line-height:1.1;font-weight:600;letter-spacing:-.03em;color:var(--ink)}
.wa-tile .wa-val small{font-size:15px;font-weight:500;color:var(--muted);margin-left:4px;letter-spacing:0}
.wa-tile .wa-sub{font-size:13px;color:var(--muted);overflow-wrap:anywhere}
.wa-seg{display:inline-flex;padding:4px;gap:2px;background:var(--bg);border-radius:999px}
.wa-seg button{all:unset;box-sizing:border-box;cursor:pointer;padding:6px 14px;border-radius:999px;font-size:13px;font-weight:500;color:var(--ink2)}
.wa-seg button.on{background:var(--acc);color:#fff;box-shadow:0 6px 14px var(--glow)}
.wa-seg button:focus-visible{outline:2px solid var(--acc);outline-offset:2px}
.wa-stats{display:flex;gap:30px;flex-wrap:wrap;margin:0 0 8px}
.wa-stats div{font-size:13px;color:var(--muted)}
.wa-stats b{display:block;font-size:22px;letter-spacing:-.01em;color:var(--ink);font-weight:600}
.wa-plot{position:relative;margin:6px 0 0 34px}
.wa-plot svg{display:block;width:100%;height:150px;overflow:visible}
.wa-yl{position:absolute;left:-34px;width:28px;text-align:right;font-size:11px;color:var(--muted);transform:translateY(-50%)}
.wa-empty{display:grid;place-items:center;height:150px;color:var(--muted);font-size:13px}
.wa-xl{display:flex;justify-content:space-between;margin:6px 0 0 34px;font-size:11px;color:var(--muted)}
.wa-kv{display:grid;grid-template-columns:minmax(96px,auto) minmax(0,1fr);gap:0;margin:0;font-size:14px}
.wa-kv dt,.wa-kv dd{padding:10px 0;border-top:1px solid var(--line)}
.wa-kv dt:first-of-type,.wa-kv dd:first-of-type{border-top:0;padding-top:0}
.wa-kv dt{color:var(--muted)}.wa-kv dd{margin:0;padding-left:16px;font-weight:600;color:var(--ink);overflow-wrap:anywhere;text-align:right}
.wa-id{display:flex;align-items:center;gap:12px;margin:0 0 14px;padding:12px 14px;border-radius:20px;background:var(--soft)}
.wa-id img{width:36px;height:36px;border-radius:10px;flex:none}
.wa-id .wa-l{font-size:12px;color:var(--ink2)}
.wa-id .wa-v{font-weight:600;font-size:15px;color:var(--accink);letter-spacing:.03em;overflow-wrap:anywhere}
.wa-btns{display:flex;gap:10px;flex-wrap:wrap;margin-top:18px}
.wa-btn{all:unset;box-sizing:border-box;cursor:pointer;display:inline-flex;align-items:center;justify-content:center;gap:8px;min-height:42px;padding:0 20px;border-radius:999px;background:var(--soft);color:var(--accink);font-weight:500;font-size:14px;transition:background .2s,transform .15s}
.wa-btn:hover{background:var(--soft2)}
.wa-btn:active{transform:scale(.97)}
.wa-btn:focus-visible{outline:2px solid var(--acc);outline-offset:2px}
.wa-btn.pri{color:#fff;background:var(--acc);box-shadow:0 10px 22px var(--glow)}
.wa-btn.pri:hover{background:var(--acc2)}
.wa-btn.neg{color:var(--bad);background:var(--badsoft)}
.wa-btn.neg:hover{background:#FADADD}
.wa-btn svg{width:16px;height:16px;fill:none;stroke:currentColor;stroke-width:2;stroke-linecap:round;stroke-linejoin:round}
.wa-tbl{width:100%;border-collapse:collapse;font-size:14px}
.wa-tbl th{text-align:left;font-size:13px;font-weight:500;color:var(--muted);padding:0 10px 10px 0;border-bottom:1px solid var(--line)}
.wa-tbl td{padding:12px 10px 12px 0;border-bottom:1px solid var(--line);color:var(--ink);vertical-align:middle}
.wa-tbl tr:last-child td{border-bottom:0;padding-bottom:0}
.wa-tbl td b{font-weight:600}
.wa-band{display:inline-block;min-width:44px;text-align:center;padding:3px 10px;border-radius:999px;background:var(--soft);color:var(--accink);font-size:12px;font-weight:600}
.wa-band.g5{background:#DDF3FB;color:#075B7A}
.wa-meter{margin:0 0 16px}
.wa-meter:last-of-type{margin-bottom:0}
.wa-meter .wa-row{display:flex;justify-content:space-between;gap:10px;font-size:13.5px;margin:0 0 7px;color:var(--muted)}
.wa-meter .wa-row b{color:var(--ink);font-weight:600}
.wa-bar{height:8px;border-radius:999px;background:var(--bg);overflow:hidden}
.wa-bar i{display:block;height:100%;border-radius:999px;background:var(--acc)}
.wa-bar i.hot{background:#E08A00}
.wa-mini{display:flex;gap:10px;margin-top:18px}
.wa-mini div{flex:1;min-width:0;padding:12px 14px;border-radius:20px;background:var(--bg);font-size:12.5px;color:var(--muted)}
.wa-mini b{display:block;font-size:18px;color:var(--ink);font-weight:600}
.wa-log{list-style:none;margin:0;padding:0}
.wa-log li{display:flex;gap:14px;padding:10px 0;border-top:1px solid var(--line);font-size:14px;color:var(--ink)}
.wa-log li:first-child{border-top:0;padding-top:0}
.wa-log li:last-child{padding-bottom:0}
.wa-log time{flex:none;width:92px;color:var(--muted);font-size:13px}
.wa-log span{min-width:0;overflow-wrap:anywhere}
.wa-bars{display:inline-flex;align-items:flex-end;gap:2px;height:15px;vertical-align:-2px}
.wa-bars i{display:block;width:4px;border-radius:1px;background:#CBD3E6}
.wa-bars i:nth-child(1){height:5px}.wa-bars i:nth-child(2){height:8px}.wa-bars i:nth-child(3){height:11px}.wa-bars i:nth-child(4){height:15px}
.wa-bars i.on{background:var(--acc)}
.wa-link{display:flex;align-items:center;gap:14px;flex-wrap:wrap}
.wa-link .wa-t{flex:1;min-width:200px;font-weight:600;color:var(--ink)}
.wa-link .wa-t span{display:block;font-weight:400;font-size:13px;color:var(--muted);margin-top:2px}
.wa-field{margin:0 0 4px}
.wa-field label{display:block;font-size:13px;font-weight:500;margin:0 0 6px;color:var(--ink2)}
.wa-field input{width:100%;max-width:360px;height:50px;letter-spacing:.14em;text-transform:uppercase;font-weight:600}
.wa-steps{margin:0 0 18px;padding:0;list-style:none;display:grid;gap:12px;counter-reset:s}
.wa-steps li{display:flex;gap:12px;align-items:flex-start;font-size:14px;color:var(--ink);counter-increment:s}
.wa-steps li::before{content:counter(s);flex:none;width:26px;height:26px;border-radius:50%;display:grid;place-items:center;background:var(--soft);color:var(--accink);font-weight:600;font-size:13px}
.wa-sys{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:0 40px}
@media (max-width:1100px){.wa-c3{grid-column:span 6}.wa-c4,.wa-c5,.wa-c6,.wa-c7,.wa-c8{grid-column:span 12}}
@media (max-width:720px){.wa-grid{gap:14px}.wa-card{padding:18px;border-radius:24px}.wa-tile .wa-val{font-size:26px}.wa-stats{gap:20px}.wa-log time{width:72px}.wa-tbl .wa-hide{display:none}.wa-sys{grid-template-columns:minmax(0,1fr)}}
@media (max-width:380px){.wa-c3{grid-column:span 12}}
`;

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

const IC = {
	globe: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>',
	users: '<circle cx="9" cy="8" r="3.2"/><path d="M3 20a6 6 0 0 1 12 0M16 4.5a3.2 3.2 0 0 1 0 6M18 14.5a6 6 0 0 1 3 5.5"/>',
	clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
	cloud: '<path d="M7 18h10a4 4 0 0 0 .5-8A6 6 0 0 0 6 9.5 4.3 4.3 0 0 0 7 18Z"/>',
	chip: '<rect x="5" y="5" width="14" height="14" rx="3"/><path d="M9 9h6v6H9zM9 2v3M15 2v3M9 19v3M15 19v3M2 9h3M2 15h3M19 9h3M19 15h3"/>',
	wifi: '<path d="M2 8.5a15 15 0 0 1 20 0M5 12a10 10 0 0 1 14 0M8.5 15.5a5 5 0 0 1 7 0"/><circle cx="12" cy="19" r="1"/>',
	pulse: '<path d="M3 12h4l3-8 4 16 3-8h4"/>',
	list: '<path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/>',
	ext: '<path d="M14 4h6v6M20 4l-9 9M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/>',
	unlink: '<path d="M9 15l6-6M11 6l1-1a4.2 4.2 0 0 1 6 6l-1 1M13 18l-1 1a4.2 4.2 0 0 1-6-6l1-1"/>',
	link: '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>'
};

function svg(name) {
	const s = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
	s.setAttribute('viewBox', '0 0 24 24');
	s.setAttribute('aria-hidden', 'true');
	s.innerHTML = IC[name] || IC.globe;
	return s;
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

function band(b) { return b == '5g' ? '5 GHz' : '2.4 GHz'; }

function chip(kind, text) { return E('span', { 'class': 'wa-chip ' + kind }, text); }

function card(cls, icon, title, right, body) {
	const h = [ E('span', { 'class': 'wa-ico' }, svg(icon)), title ];
	if (right) h.push(right);
	return E('section', { 'class': 'wa-card ' + cls }, [ E('h3', {}, h) ].concat(body));
}

function tile(icon, label, value, unit, sub, right) {
	return E('section', { 'class': 'wa-card wa-tile wa-c3' }, [
		E('div', { 'class': 'wa-top' }, [ E('span', { 'class': 'wa-ico' }, svg(icon)), label, right || '' ]),
		E('div', { 'class': 'wa-val' }, unit ? [ value, E('small', {}, unit) ] : value),
		E('div', { 'class': 'wa-sub' }, sub)
	]);
}

function signalBars(dbm) {
	const q = dbm >= -55 ? 4 : dbm >= -65 ? 3 : dbm >= -75 ? 2 : 1;
	return E('span', { 'class': 'wa-bars', 'title': dbm + ' dBm' }, [ 1, 2, 3, 4 ].map(i => E('i', { 'class': i <= q ? 'on' : '' })));
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
		const ok = inet.online;
		return card('wa-c4', 'globe', _('Internet source'), ok ? chip('ok', _('Online')) : chip('bad', _('Offline')), [
			E('dl', { 'class': 'wa-kv' }, [
				E('dt', {}, _('Network')), E('dd', {}, src.ssid || _('Cable (WAN)')),
				src.band ? E('dt', {}, _('WiFi band')) : '', src.band ? E('dd', {}, band(src.band)) : '',
				src.signal ? E('dt', {}, _('Signal')) : '', src.signal ? E('dd', {}, [ signalBars(src.signal), ' ' + src.signal + ' dBm' ]) : '',
				E('dt', {}, _('IP address')), E('dd', {}, src.ip || '—'),
				E('dt', {}, _('Gateway')), E('dd', {}, src.gateway || '—')
			]),
			E('div', { 'class': 'wa-btns' }, [ E('a', { 'class': 'wa-btn', 'href': L.url('admin/network/wireless'), 'style': 'text-decoration:none' }, [ _('Open Wireless'), svg('ext') ]) ])
		]);
	},

	netCard(s) {
		const nets = s.networks || [];
		const rows = nets.map(n => E('tr', {}, [
			E('td', {}, E('b', {}, n.ssid)),
			E('td', {}, E('span', { 'class': 'wa-band' + (n.band == '5g' ? ' g5' : '') }, band(n.band))),
			E('td', { 'class': 'wa-hide' }, _('Ch %s').format(n.channel)),
			E('td', {}, String(n.clients)),
			E('td', { 'class': 'wa-hide' }, n.enc)
		]));
		return card('wa-c8', 'wifi', _('Your WiFi networks'), chip('plain', _('%d active').format(nets.length)), [
			E('table', { 'class': 'wa-tbl' }, [
				E('thead', {}, E('tr', {}, [ E('th', {}, _('Name')), E('th', {}, _('WiFi band')), E('th', { 'class': 'wa-hide' }, _('Channel')), E('th', {}, _('Devices')), E('th', { 'class': 'wa-hide' }, _('Security')) ])),
				E('tbody', {}, rows)
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
		return card('wa-c8', 'list', _('Activity'), null, [ E('ul', { 'class': 'wa-log' }, rows) ]);
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
		return card('wa-c12', 'pulse', _('Stability'), chip(st[0], st[1]), [
			E('div', { 'class': 'wa-sys' }, [
				E('dl', { 'class': 'wa-kv' }, [
					E('dt', {}, _('Last start')), E('dd', {}, why),
					E('dt', {}, _('Automatic restarts in a row')), E('dd', {}, String(y.recovery_reboots ?? 0))
				]),
				E('dl', { 'class': 'wa-kv' }, [
					E('dt', {}, _('Automatic recovery')), E('dd', {}, _('3 min · 15 min · 30 min')),
					E('dt', {}, _('Guests at most')), E('dd', {}, y.guest_max > 0 ? String(y.guest_max) : _('No limit'))
				])
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
			E('div', { 'class': 'wa-grid' }, [ this.netCard(s), this.sourceCard(s) ]),
			E('div', { 'class': 'wa-grid' }, [ this.logCard(s), this.healthCard(s) ]),
			E('div', { 'class': 'wa-grid' }, [ this.systemCard(s) ]),
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
		document.head.appendChild(E('style', {}, CSS));
		const linked = !!(s.wp && s.wp.paired);
		const body = E('div', {}, linked ? this.linked(s) : this.unlinked(s));
		if (linked)
			poll.add(() => callStatus().then(n => { if (n && n.wp && n.wp.paired) body.replaceChildren(this.linked(n)); }), 10);
		return E('div', { 'class': 'wa' }, [ body ]);
	},

	handleSave: null, handleSaveApply: null, handleReset: null
});
