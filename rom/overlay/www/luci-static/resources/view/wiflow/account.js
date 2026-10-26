'use strict';
'require view';
'require ui';
'require poll';
'require rpc';

/* Wiflow App: the router's link to the Wiflow account (WordPress) and a
   live summary of the router. WiFi and network are configured in LuCI. */

const CSS = `
.wa{max-width:1120px}
.wa-head{display:flex;align-items:center;gap:12px;flex-wrap:wrap;margin:0 0 18px}
.wa-head h2{margin:0}
.wa-head .wa-sp{flex:1}
.wa-upd{font-size:12.5px;color:var(--wf-muted)}
.wa-grid{display:grid;grid-template-columns:repeat(12,minmax(0,1fr));gap:16px;margin:0 0 16px}
.wa-c3{grid-column:span 3}.wa-c4{grid-column:span 4}.wa-c5{grid-column:span 5}.wa-c7{grid-column:span 7}.wa-c8{grid-column:span 8}.wa-c12{grid-column:span 12}
.wa-card{background:#fff;border:1px solid #E1E7F2;border-radius:14px;padding:18px 20px;min-width:0;box-shadow:0 1px 2px rgba(0,16,51,.04)}
.wa-card>h3{display:flex;align-items:center;gap:10px;margin:0 0 14px;font-size:15px;font-weight:600;color:#001033}
.wa-card>h3 .wa-chip{margin-left:auto}
.wa-ico{width:34px;height:34px;border-radius:10px;display:grid;place-items:center;flex:none;background:#EAF1FF;color:#0054F0}
.wa-ico svg{width:18px;height:18px;fill:none;stroke:currentColor;stroke-width:1.9;stroke-linecap:round;stroke-linejoin:round}
.wa-chip{display:inline-flex;align-items:center;gap:6px;height:24px;padding:0 9px;border-radius:6px;font-size:12px;font-weight:600;white-space:nowrap;background:#EDF1F8;color:#4B5877}
.wa-chip::before{content:"";width:6px;height:6px;border-radius:50%;background:currentColor}
.wa-chip.ok{background:#E3F6EF;color:#0A7F61}.wa-chip.warn{background:#FFF3DA;color:#9A6200}.wa-chip.bad{background:#FDEAEC;color:#B8303B}
.wa-chip.plain::before{display:none}
.wa-tile{display:flex;flex-direction:column;gap:2px}
.wa-tile .wa-top{display:flex;align-items:center;gap:10px;margin-bottom:10px;color:#5A6785;font-size:13px;font-weight:600}
.wa-tile .wa-val{font-size:28px;line-height:1.15;font-weight:600;letter-spacing:-.02em;color:#001033}
.wa-tile .wa-val small{font-size:14px;font-weight:600;color:#5A6785;margin-left:4px;letter-spacing:0}
.wa-tile .wa-sub{font-size:12.5px;color:#5A6785;overflow-wrap:anywhere}
.wa-tile .wa-chip{margin-left:auto}
.wa-seg{display:inline-flex;padding:3px;gap:2px;background:#EDF1F8;border-radius:10px;margin-left:auto}
.wa-seg button{all:unset;box-sizing:border-box;cursor:pointer;padding:5px 12px;border-radius:8px;font-size:12.5px;font-weight:600;color:#5A6785}
.wa-seg button.on{background:#fff;color:#0054F0;box-shadow:0 1px 2px rgba(0,16,51,.12)}
.wa-seg button:focus-visible{outline:2px solid #0054F0;outline-offset:1px}
.wa-stats{display:flex;gap:28px;flex-wrap:wrap;margin:0 0 6px}
.wa-stats div{font-size:12.5px;color:#5A6785}
.wa-stats b{display:block;font-size:20px;letter-spacing:-.01em;color:#001033;font-weight:600}
.wa-plot{position:relative;margin:6px 0 0 34px}
.wa-plot svg{display:block;width:100%;height:150px;overflow:visible}
.wa-yl{position:absolute;left:-34px;width:28px;text-align:right;font-size:11px;color:#7A86A3;transform:translateY(-50%)}
.wa-empty{display:grid;place-items:center;height:150px;color:#7A86A3;font-size:13px}
.wa-xl{display:flex;justify-content:space-between;margin:6px 0 0 34px;font-size:11px;color:#7A86A3}
.wa-kv{display:grid;grid-template-columns:minmax(96px,auto) minmax(0,1fr);gap:9px 14px;margin:0;font-size:13.5px}
.wa-kv dt{color:#5A6785}.wa-kv dd{margin:0;font-weight:600;color:#001033;overflow-wrap:anywhere}
.wa-id{display:flex;align-items:center;gap:12px;margin:0 0 14px;padding:12px 14px;border-radius:10px;background:#EAF1FF}
.wa-id img{width:36px;height:36px;border-radius:9px;flex:none}
.wa-id .wa-l{font-size:12px;color:#5A6785}
.wa-id .wa-v{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-weight:600;font-size:15px;color:#001033;letter-spacing:.04em;overflow-wrap:anywhere}
.wa-btns{display:flex;gap:10px;flex-wrap:wrap;margin-top:16px}
.wa-btn{all:unset;box-sizing:border-box;cursor:pointer;display:inline-flex;align-items:center;justify-content:center;gap:8px;min-height:40px;padding:0 16px;border-radius:10px;border:1px solid #D3DCEB;background:#fff;color:#001033;font-weight:600;font-size:14px}
.wa-btn:hover{border-color:#0054F0;color:#0054F0}
.wa-btn:focus-visible{outline:2px solid #0054F0;outline-offset:2px}
.wa-btn.pri{border:0;color:#fff;background:#0054F0}
.wa-btn.pri:hover{color:#fff;background:#0044C4}
.wa-btn.neg{color:#B8303B;border-color:#F0C4C8}
.wa-btn.neg:hover{background:#FDEAEC;border-color:#B8303B;color:#B8303B}
.wa-btn svg{width:16px;height:16px;fill:none;stroke:currentColor;stroke-width:2;stroke-linecap:round;stroke-linejoin:round}
.wa-tbl{width:100%;border-collapse:collapse;font-size:13.5px}
.wa-tbl th{text-align:left;font-size:12px;font-weight:600;color:#7A86A3;padding:0 10px 8px 0;border-bottom:1px solid #E1E7F2}
.wa-tbl td{padding:11px 10px 11px 0;border-bottom:1px solid #EEF2F8;color:#001033;vertical-align:middle}
.wa-tbl tr:last-child td{border-bottom:0;padding-bottom:0}
.wa-tbl td b{font-weight:600}
.wa-band{display:inline-block;min-width:44px;text-align:center;padding:2px 7px;border-radius:6px;background:#EAF1FF;color:#0054F0;font-size:12px;font-weight:600}
.wa-band.g5{background:#E0F6FF;color:#006C99}
.wa-meter{margin:0 0 14px}
.wa-meter:last-of-type{margin-bottom:0}
.wa-meter .wa-row{display:flex;justify-content:space-between;gap:10px;font-size:13px;margin:0 0 6px;color:#5A6785}
.wa-meter .wa-row b{color:#001033;font-weight:600}
.wa-bar{height:8px;border-radius:4px;background:#EDF1F8;overflow:hidden}
.wa-bar i{display:block;height:100%;border-radius:4px;background:#0054F0}
.wa-bar i.hot{background:#E08A00}
.wa-mini{display:flex;gap:10px;margin-top:16px}
.wa-mini div{flex:1;min-width:0;padding:10px 12px;border-radius:10px;background:#F3F6FB;font-size:12px;color:#5A6785}
.wa-mini b{display:block;font-size:17px;color:#001033;font-weight:600}
.wa-log{list-style:none;margin:0;padding:0}
.wa-log li{display:flex;gap:14px;padding:9px 0;border-bottom:1px solid #EEF2F8;font-size:13.5px;color:#001033}
.wa-log li:last-child{border-bottom:0;padding-bottom:0}
.wa-log time{flex:none;width:78px;color:#7A86A3;font-size:12.5px}
.wa-log span{min-width:0;overflow-wrap:anywhere}
.wa-bars{display:inline-flex;align-items:flex-end;gap:2px;height:15px;vertical-align:-2px}
.wa-bars i{display:block;width:4px;border-radius:1px;background:#CBD6EA}
.wa-bars i:nth-child(1){height:5px}.wa-bars i:nth-child(2){height:8px}.wa-bars i:nth-child(3){height:11px}.wa-bars i:nth-child(4){height:15px}
.wa-bars i.on{background:#0054F0}
.wa-link{display:flex;align-items:center;gap:14px;flex-wrap:wrap}
.wa-link .wa-t{flex:1;min-width:200px;font-weight:600;color:#001033}
.wa-link .wa-t span{display:block;font-weight:400;font-size:13px;color:#5A6785;margin-top:2px}
.wa-field{margin:0 0 4px}
.wa-field label{display:block;font-size:13px;font-weight:600;margin:0 0 6px;color:#001033}
.wa-field input{width:100%;max-width:360px;height:44px;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:.14em;text-transform:uppercase}
.wa-steps{margin:0 0 16px;padding:0;list-style:none;display:grid;gap:10px;counter-reset:s}
.wa-steps li{display:flex;gap:12px;align-items:flex-start;font-size:13.5px;color:#001033;counter-increment:s}
.wa-steps li::before{content:counter(s);flex:none;width:24px;height:24px;border-radius:7px;display:grid;place-items:center;background:#EAF1FF;color:#0054F0;font-weight:600;font-size:12.5px}
@media (max-width:1100px){.wa-c3{grid-column:span 6}.wa-c4,.wa-c5,.wa-c7,.wa-c8{grid-column:span 12}}
@media (max-width:640px){.wa-grid{gap:12px}.wa-c3{grid-column:span 6}.wa-card{padding:16px}.wa-tile .wa-val{font-size:24px}.wa-stats{gap:20px}.wa-log time{width:64px}.wa-tbl .wa-hide{display:none}}
@media (max-width:380px){.wa-c3{grid-column:span 12}}
`;

const callStatus = rpc.declare({ object: 'wiflow', method: 'status', expect: { '': {} } });
const callPair = rpc.declare({ object: 'wiflow', method: 'pair', params: [ 'code' ] });
const callUnpair = rpc.declare({ object: 'wiflow', method: 'unpair', params: [ 'force' ] });
const callJobClear = rpc.declare({ object: 'wiflow', method: 'job_clear' });

function ago(t) {
	t = +t || 0;
	if (!t) return 'never';
	const d = Math.max(0, Math.floor(Date.now() / 1000) - t);
	if (d < 60) return 'just now';
	if (d < 3600) return Math.floor(d / 60) + ' min ago';
	if (d < 86400) return Math.floor(d / 3600) + ' h ago';
	return Math.floor(d / 86400) + ' d ago';
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
	return d ? `${d}d ${h}h` : h ? `${h}h ${m}m` : `${m}m`;
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
		return E('div', { 'class': 'wa-empty' }, 'No data yet');
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
	s.setAttribute('aria-label', `${unit}, last 24 hours`);
	s.innerHTML = ticks.map(t => `<line x1="0" x2="${W}" y1="${y(t)}" y2="${y(t)}" stroke="#E7ECF5" stroke-width="1" vector-effect="non-scaling-stroke"/>`).join('')
		+ `<polygon points="${x(first).toFixed(1)},${H} ${pts.join(' ')} ${lastX.toFixed(1)},${H}" fill="${color}" fill-opacity=".1"/>`
		+ `<polyline points="${pts.join(' ')}" fill="none" stroke="${color}" stroke-width="2.4" stroke-linejoin="round" stroke-linecap="round" vector-effect="non-scaling-stroke"/>`;
	const plot = E('div', { 'class': 'wa-plot' }, [ s ]);
	ticks.forEach(t => plot.appendChild(E('span', { 'class': 'wa-yl', 'style': `top:${y(t) / H * 100}%` }, String(Math.round(t)))));
	return E('div', {}, [ plot, E('div', { 'class': 'wa-xl' }, [ '24 h ago', '18 h', '12 h', '6 h', 'now' ].map(t => E('span', {}, t))) ]);
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
				E('div', {}, [ E('b', {}, none ? '—' : (d ? String(Math.max.apply(null, r)) : Math.round(avg(r)) + u)), d ? 'Peak' : 'Average' ]),
				E('div', {}, [ E('b', {}, none ? '—' : (d ? avg(r).toFixed(1) : Math.min.apply(null, r) + u)), d ? 'Average' : 'Best' ]),
				E('div', {}, [ E('b', {}, none ? '—' : (d ? String(r[r.length - 1]) : Math.max.apply(null, r) + u)), d ? 'Now' : 'Worst' ])
			);
			body.replaceChildren(chart(v, d ? 'Connected devices' : 'Latency (ms)', d ? '#0054F0' : '#009AD6', d));
		};
		[ [ 'dev', 'Devices' ], [ 'lat', 'Latency' ] ].forEach(k => {
			const b = E('button', { 'type': 'button', 'role': 'tab', 'data-k': k[0] }, k[1]);
			b.addEventListener('click', () => show(k[0]));
			seg.appendChild(b);
		});
		show(this.tab || 'dev');
		return card('wa-c8', 'pulse', 'Last 24 hours', seg, [ stats, body ]);
	},

	accountCard(s) {
		const w = s.wp || {}, d = s.device || {};
		const unlink = E('button', { 'class': 'wa-btn neg', 'type': 'button' }, [ svg('unlink'), 'Unlink account' ]);
		unlink.addEventListener('click', () => ui.showModal('Unlink account', [
			E('p', {}, 'This router stops sending data to the Wiflow account. You can link it again at any time.'),
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'btn', 'click': ui.hideModal }, 'Cancel'), ' ',
				E('button', { 'class': 'btn cbi-button-negative', 'click': () => this.follow('Unlinking…', () => callUnpair(false)) }, 'Unlink')
			])
		]));
		return card('wa-c4', 'cloud', 'Account', w.online ? chip('ok', 'Connected') : chip('warn', 'No contact'), [
			E('div', { 'class': 'wa-id' }, [
				E('img', { 'src': L.resource('../wiflow/favicon.png'), 'alt': '' }),
				E('div', { 'style': 'min-width:0' }, [ E('div', { 'class': 'wa-l' }, 'Account ID'), E('div', { 'class': 'wa-v' }, w.account || '—') ])
			]),
			E('dl', { 'class': 'wa-kv' }, [
				E('dt', {}, 'Linked'), E('dd', {}, ago(w.since)),
				E('dt', {}, 'Last contact'), E('dd', {}, ago(w.last_ok)),
				E('dt', {}, 'Server'), E('dd', {}, 'wiflow.projifylab.com'),
				E('dt', {}, 'Device ID'), E('dd', {}, d.id || '—')
			]),
			E('div', { 'class': 'wa-btns' }, [ unlink ])
		]);
	},

	sourceCard(s) {
		const src = s.source || {}, inet = s.internet || {};
		const ok = inet.online;
		return card('wa-c4', 'globe', 'Internet source', ok ? chip('ok', 'Online') : chip('bad', 'Offline'), [
			E('dl', { 'class': 'wa-kv' }, [
				E('dt', {}, 'Network'), E('dd', {}, src.ssid || 'Cable (WAN)'),
				src.band ? E('dt', {}, 'Band') : '', src.band ? E('dd', {}, band(src.band)) : '',
				src.signal ? E('dt', {}, 'Signal') : '', src.signal ? E('dd', {}, [ signalBars(src.signal), ' ' + src.signal + ' dBm' ]) : '',
				E('dt', {}, 'IP address'), E('dd', {}, src.ip || '—'),
				E('dt', {}, 'Gateway'), E('dd', {}, src.gateway || '—')
			]),
			E('div', { 'class': 'wa-btns' }, [ E('a', { 'class': 'wa-btn', 'href': L.url('admin/network/wireless'), 'style': 'text-decoration:none' }, [ 'Open Wireless', svg('ext') ]) ])
		]);
	},

	netCard(s) {
		const nets = s.networks || [];
		const rows = nets.map(n => E('tr', {}, [
			E('td', {}, E('b', {}, n.ssid)),
			E('td', {}, E('span', { 'class': 'wa-band' + (n.band == '5g' ? ' g5' : '') }, band(n.band))),
			E('td', { 'class': 'wa-hide' }, 'Ch ' + n.channel),
			E('td', {}, String(n.clients)),
			E('td', { 'class': 'wa-hide' }, n.enc)
		]));
		return card('wa-c8', 'wifi', 'Your WiFi networks', chip('plain', nets.length + ' active'), [
			E('table', { 'class': 'wa-tbl' }, [
				E('thead', {}, E('tr', {}, [ E('th', {}, 'Name'), E('th', {}, 'Band'), E('th', { 'class': 'wa-hide' }, 'Channel'), E('th', {}, 'Devices'), E('th', { 'class': 'wa-hide' }, 'Security') ])),
				E('tbody', {}, rows)
			])
		]);
	},

	healthCard(s) {
		const m = s.metrics || {};
		const mem = m.mem_total_mb ? m.mem_used_mb / m.mem_total_mb * 100 : 0, fl = m.flash_total_mb ? m.flash_used_mb / m.flash_total_mb * 100 : 0;
		return card('wa-c4', 'chip', 'Router health', null, [
			meter('CPU', (m.cpu ?? 0) + '%', m.cpu ?? 0),
			meter('Memory', `${m.mem_used_mb} / ${m.mem_total_mb} MB`, mem),
			meter('Storage', `${m.flash_used_mb} / ${m.flash_total_mb} MB`, fl),
			E('div', { 'class': 'wa-mini' }, [ E('div', {}, [ E('b', {}, (m.temp ?? '—') + ' °C'), 'Temperature' ]), E('div', {}, [ E('b', {}, String(m.load ?? '—')), 'Load' ]) ])
		]);
	},

	logCard(s) {
		const rows = (s.log || []).map(r => E('li', {}, [ E('time', {}, ago(r.t)), E('span', {}, r.m) ]));
		return card('wa-c8', 'list', 'Activity', null, [ E('ul', { 'class': 'wa-log' }, rows) ]);
	},

	portalCard() {
		return E('section', { 'class': 'wa-card wa-c12' }, E('div', { 'class': 'wa-link' }, [
			E('span', { 'class': 'wa-ico' }, svg('users')),
			E('div', { 'class': 'wa-t' }, [ 'Portal, content and guests', E('span', {}, 'Managed in your Wiflow account.') ]),
			E('a', { 'class': 'wa-btn pri', 'href': 'https://wiflow.projifylab.com', 'target': '_blank', 'rel': 'noopener', 'style': 'text-decoration:none' }, [ 'Open Wiflow', svg('ext') ])
		]));
	},

	linked(s) {
		const inet = s.internet || {}, c = s.clients || {}, d = s.device || {}, src = s.source || {};
		return E('div', {}, [
			E('div', { 'class': 'wa-grid' }, [
				tile('globe', 'Internet', inet.online ? 'Online' : 'Offline', null, inet.online ? `${src.ssid || 'Cable'}${inet.latency > 0 ? ' · ' + inet.latency + ' ms' : ''}` : 'No connection', null),
				tile('users', 'Devices now', String(c.now ?? 0), null, `${c.band2g ?? 0} on 2.4 GHz · ${c.band5g ?? 0} on 5 GHz`),
				tile('pulse', 'Today', String(c.today ?? 0), null, 'unique devices'),
				tile('clock', 'Uptime', dur(d.uptime), null, `Wiflow OS ${d.os || ''}`)
			]),
			E('div', { 'class': 'wa-grid' }, [ this.chartCard(s), this.accountCard(s) ]),
			E('div', { 'class': 'wa-grid' }, [ this.netCard(s), this.sourceCard(s) ]),
			E('div', { 'class': 'wa-grid' }, [ this.logCard(s), this.healthCard(s) ]),
			E('div', { 'class': 'wa-grid' }, [ this.portalCard() ])
		]);
	},

	unlinked(s) {
		const d = s.device || {};
		const code = E('input', { 'type': 'text', 'maxlength': '14', 'placeholder': 'XXXX XXXX XXXX', 'autocomplete': 'off', 'spellcheck': 'false', 'aria-label': 'Link code' });
		const go = E('button', { 'class': 'wa-btn pri', 'type': 'button' }, [ svg('link'), 'Link account' ]);
		go.addEventListener('click', () => this.follow('Linking…', () => callPair(code.value)));
		return E('div', { 'class': 'wa-grid' }, [
			card('wa-c7', 'link', 'Link to your Wiflow account', chip('', 'Not linked'), [
				E('ol', { 'class': 'wa-steps' }, [
					E('li', {}, 'Open the Wiflow app and go to Devices › Add device.'),
					E('li', {}, 'Copy the 12-character code it shows.'),
					E('li', {}, 'Enter the code below.')
				]),
				E('div', { 'class': 'wa-field' }, [ E('label', {}, 'Link code'), code ]),
				E('div', { 'class': 'wa-btns' }, [ go ])
			]),
			card('wa-c5', 'chip', 'This router', s.internet?.online ? chip('ok', 'Online') : chip('warn', 'No Internet'), [
				E('dl', { 'class': 'wa-kv' }, [
					E('dt', {}, 'Device ID'), E('dd', {}, d.id || '—'),
					E('dt', {}, 'Model'), E('dd', {}, d.model || '—'),
					E('dt', {}, 'Wiflow OS'), E('dd', {}, d.os || '—'),
					E('dt', {}, 'Uptime'), E('dd', {}, dur(d.uptime))
				])
			])
		]);
	},

	/* Pair / unpair run as a background job on the router: follow it until it ends. */
	follow(title, start) {
		const msg = E('p', { 'style': 'margin:0' }, 'Starting…');
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
				ui.addNotification(null, E('p', {}, (r && r.error) || 'Could not start.'), 'danger');
				return;
			}
			return poll1().then(j => {
				ui.hideModal();
				callJobClear();
				if (j && j.state == 'success')
					location.reload();
				else
					ui.addNotification(null, E('p', {}, (j && j.message) || 'The router did not answer. Reload the page in a minute.'), 'danger');
			});
		});
	},

	render(s) {
		document.head.appendChild(E('style', {}, CSS));
		const linked = !!(s.wp && s.wp.paired);
		const body = E('div', {}, linked ? this.linked(s) : this.unlinked(s));
		if (linked)
			poll.add(() => callStatus().then(n => { if (n && n.wp && n.wp.paired) body.replaceChildren(this.linked(n)); }), 10);
		return E('div', { 'class': 'wa' }, [
			E('div', { 'class': 'wa-head' }, [ E('h2', {}, 'Wiflow App') ]),
			body
		]);
	},

	handleSave: null, handleSaveApply: null, handleReset: null
});
