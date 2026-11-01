'use strict';
'require baseclass';
'require ui';

/* Shared pieces of the Wiflow pages (Overview, Network, System): flat rows, panels, tiles,
   chips, buttons, the 24 h chart and dialogs, built to the firmware mockup. */

const IC = {
	pulse: '<path d="M3 12h4l3-8 4 16 3-8h4"/>',
	globe: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>',
	cpu: '<rect x="6" y="6" width="12" height="12" rx="2"/><rect x="9.5" y="9.5" width="5" height="5" rx="1"/><path d="M9 2v4M15 2v4M9 18v4M15 18v4M2 9h4M2 15h4M18 9h4M18 15h4"/>',
	phone: '<path d="M5 4h4l2 5-2.5 1.5a11 11 0 0 0 5 5L15 13l5 2v4a1 1 0 0 1-1 1A15 15 0 0 1 4 5a1 1 0 0 1 1-1z"/>',
	mail: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3 7 9 6 9-6"/>',
	contact: '<rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="9" cy="11" r="2"/><path d="M5.5 16a3.5 3.5 0 0 1 7 0M14.5 10h3.5M14.5 14h3.5"/>',
	router: '<rect x="3" y="14" width="18" height="6" rx="2"/><path d="M7 17h.01M11 17h.01M7 14V8M17 14V8"/>',
	lan: '<rect x="9" y="3" width="6" height="5" rx="1"/><rect x="3" y="16" width="6" height="5" rx="1"/><rect x="15" y="16" width="6" height="5" rx="1"/><path d="M12 8v4M6 16v-4h12v4"/>',
	eye: '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
	band: '<path d="M5 12.5a10 10 0 0 1 14 0M8.5 16a5 5 0 0 1 7 0"/><circle cx="12" cy="19.2" r="1" fill="currentColor"/>',
	users: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0M16 4.6a3.5 3.5 0 0 1 0 6.8M18 14.2A6.5 6.5 0 0 1 21.5 20"/>',
	link: '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>',
	clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
	shield: '<path d="M12 3l7 3v5c0 5-3 8-7 10-4-2-7-5-7-10V6z"/><path d="M9 12l2 2 4-4"/>',
	layers: '<path d="M12 3l9 5-9 5-9-5z"/><path d="M3 13l9 5 9-5"/>',
	ext: '<path d="M14 4h6v6M20 4l-9 9M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/>',
	wifi: '<path d="M5 12.5a10 10 0 0 1 14 0M8.5 16a5 5 0 0 1 7 0"/><circle cx="12" cy="19.2" r="1" fill="currentColor"/><path d="M2 9a14 14 0 0 1 20 0"/>'
};

function svg(name) {
	const s = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
	s.setAttribute('viewBox', '0 0 24 24');
	s.setAttribute('aria-hidden', 'true');
	s.innerHTML = IC[name] || IC.globe;
	return s;
}

function band(b) { return b == '5g' ? '5 GHz' : '2.4 GHz'; }

function chip(kind, text) { return E('span', { 'class': 'w-chip' + (kind ? ' w-' + kind : '') }, text); }

function sig(dbm) {
	const q = dbm >= -55 ? 4 : dbm >= -65 ? 3 : dbm >= -75 ? 2 : 1;
	return E('span', { 'class': 'w-sig', 'title': dbm + ' dBm' }, [ 1, 2, 3, 4 ].map(i => E('i', { 'class': i <= q ? 'w-on' : '' })));
}

/* A button. kind: p (primary) | s (soft) | g (outline) | d (danger) | t (text); o.sm, o.full */
function btn(kind, text, fn, o) {
	o = o || {};
	const b = E('button', { 'class': 'w-btn w-' + (kind == 't' ? 'txt' : kind) + (o.sm ? ' w-sm' : '') + (o.full ? ' w-full' : ''), 'type': 'button' }, text);
	if (fn) b.addEventListener('click', ev => fn(ev.currentTarget, ev));
	return b;
}

/* A list row: key (with an optional small line), value (right). o.t = value in ink, bold. */
function row(k, v, o) {
	o = o || {};
	const cells = [ E('div', { 'class': 'w-k' }, o.sub ? [ k, E('small', {}, o.sub) ] : k) ];
	if (v != null && v !== '')
		cells.push(E('div', { 'class': 'w-v' + (o.t ? ' w-t' : '') }, v));
	return E('div', { 'class': 'w-row' }, cells);
}

function panel(icon, title, right, body, cls) {
	return E('section', { 'class': 'w-pn ' + (cls || '') }, [
		E('div', { 'class': 'w-ph' }, [ E('span', { 'class': 'w-pi' }, svg(icon)), E('h2', {}, title), E('span', { 'class': 'w-sp' }), right || '' ])
	].concat(body));
}

function tile(icon, label, value, sub) {
	return E('div', { 'class': 'w-pn w-tile' }, [
		E('div', { 'class': 'w-tl' }, [ E('span', { 'class': 'w-pi' }, svg(icon)), E('span', {}, label) ]),
		E('div', { 'class': 'w-tv' }, value), E('div', { 'class': 'w-ts' }, sub)
	]);
}

function meter(pct) {
	pct = Math.max(0, Math.min(100, Math.round(pct)));
	return [ E('span', { 'class': 'w-mt' }, E('i', { 'style': 'width:' + pct + '%' })), pct + '%' ];
}

function head(title, right) {
	return E('div', { 'class': 'w-hd' }, [ E('h1', {}, title), E('span', { 'class': 'w-sp' }), right || '' ]);
}

function field(label, input, o) {
	o = o || {};
	return E('div', { 'class': 'w-fld' }, [ E('label', {}, label), E('div', { 'class': 'w-in' + (o.rd ? ' w-rd' : '') + (o.pw ? ' w-pw' : '') }, [ input ].concat(o.pw ? [ eyeBtn(input) ] : [])) ]);
}

function eyeBtn(input) {
	const b = E('button', { 'class': 'w-ib', 'type': 'button', 'aria-label': _('Show password') }, svg('eye'));
	b.addEventListener('click', () => { input.type = input.type == 'password' ? 'text' : 'password'; });
	return b;
}

/* A dialog: title, body and buttons in the dialog footer. o.wide for lists. */
function dialog(title, body, foot, o) {
	o = o || {};
	const kids = [ E('div', { 'class': 'w-bd' }, body) ];
	if (foot && foot.length)
		kids.push(E('div', { 'class': 'w-ft' }, foot));
	return ui.showModal(title, kids, o.wide ? 'w-wide' : '');
}

function waitBox(text) {
	return E('div', { 'class': 'w-wait' }, [ E('span', { 'class': 'w-spin' }), E('span', {}, text) ]);
}

/* 24 h area chart; labels are HTML so the SVG can stretch without distorting text. */
function chart(vals, color, zero) {
	const W = 600, H = 150, n = vals.length;
	const real = vals.filter(v => v != null);
	if (real.length < 1)
		return E('div', { 'class': 'w-emp' }, [ E('b', {}, _('No data yet')) ]);
	let max = Math.max.apply(null, real), min = zero ? 0 : Math.min.apply(null, real);
	max = zero ? Math.max(4, Math.ceil(max / 2) * 2) : Math.ceil((max + 4) / 10) * 10;
	if (!zero) min = Math.floor((min - 4) / 10) * 10;
	const x = i => i * W / (n - 1), y = v => H - (v - min) / (max - min) * H;
	const first = vals.findIndex(v => v != null);
	const pts = [];
	vals.forEach((v, i) => { if (v != null) pts.push(x(i).toFixed(1) + ',' + y(v).toFixed(1)); });
	const lastX = x(vals.length - 1 - [].concat(vals).reverse().findIndex(v => v != null));
	const ticks = [ max, (max + min) / 2, min ];
	const s = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
	s.setAttribute('viewBox', '0 0 ' + W + ' ' + H);
	s.setAttribute('preserveAspectRatio', 'none');
	s.setAttribute('role', 'img');
	s.setAttribute('aria-label', _('Last 24 hours'));
	s.innerHTML = ticks.map(t => '<line x1="0" x2="' + W + '" y1="' + y(t) + '" y2="' + y(t) + '" stroke="#E6E9F0" stroke-width="1" vector-effect="non-scaling-stroke"/>').join('')
		+ '<polygon points="' + x(first).toFixed(1) + ',' + H + ' ' + pts.join(' ') + ' ' + lastX.toFixed(1) + ',' + H + '" fill="' + color + '" fill-opacity=".1"/>'
		+ '<polyline points="' + pts.join(' ') + '" fill="none" stroke="' + color + '" stroke-width="2.4" stroke-linejoin="round" stroke-linecap="round" vector-effect="non-scaling-stroke"/>';
	const plot = E('div', { 'class': 'w-plot' }, [ s ]);
	ticks.forEach(t => plot.appendChild(E('span', { 'class': 'w-yl', 'style': 'top:' + (y(t) / H * 100) + '%' }, String(Math.round(t)))));
	return E('div', {}, [ plot, E('div', { 'class': 'w-xl' }, [ _('24 h ago'), _('18 h'), _('12 h'), _('6 h'), _('now') ].map(t => E('span', {}, t))) ]);
}

/* Internet source as a branch: LAN cable and source WiFi join in the router, which hands the
   Internet on to the guest WiFi. A source that carries the traffic gets a flowing line, an idle
   one a dashed grey line. o: { via: 'wifi' | 'lan' | 'none', saved: ssid, band, cable, online, guests, guestName } */
function flow(o) {
	const wifiOn = o.via == 'wifi', lanOn = o.via == 'lan', up = (wifiOn || lanOn) && o.online !== false;
	const P = (d, a) => a ? '<path class="w-b" d="' + d + '"/><path class="w-f" d="' + d + '"/>' : '<path class="w-o" d="' + d + '"/>';
	const curve = (cls, vb, html) => {
		const s = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
		s.setAttribute('class', cls);
		s.setAttribute('viewBox', vb);
		s.setAttribute('preserveAspectRatio', 'none');
		s.setAttribute('aria-hidden', 'true');
		s.innerHTML = html;
		return s;
	};
	const T = (cls, icon, name, sub, on) => E('div', { 'class': 'w-fnn ' + cls }, [
		E('span', { 'class': 'w-fni' }, svg(icon)), E('div', { 'class': 'w-fnt' }, [ E('div', { 'class': 'w-fna' }, name), E('div', { 'class': 'w-fnb' }, sub) ])
	]);
	const lan = T(lanOn ? 'w-on' : '', 'lan', _('LAN cable'), lanOn ? _('WAN port') : o.cable ? _('Cable plugged in') : _('No cable'));
	const wifi = T(wifiOn ? 'w-on' : '', 'wifi', o.saved || _('Source WiFi'), o.saved ? (o.band ? band(o.band) : _('Not connected')) : _('No network chosen'));
	const merge = E('span', { 'class': 'w-fm' }, [
		curve('w-mp', '0 0 100 32', P('M25 0C25 18 50 12 50 32', lanOn) + P('M75 0C75 18 50 12 50 32', wifiOn)),
		curve('w-mw', '0 0 56 196', P('M0 46C28 46 28 98 56 98', lanOn) + P('M0 150C28 150 28 98 56 98', wifiOn))
	]);
	const vt = E('span', { 'class': 'w-fv' }, curve('', '0 0 2 28', P('M1 0V28', up)));
	const hz = E('span', { 'class': 'w-fh' }, curve('', '0 0 56 2', P('M0 1H56', up)));
	const rt = T('w-rt w-ln' + (up ? ' w-on' : ''), 'router', _('Router Wiflow'), o.lanIp || '10.0.0.1');
	const gs = T('w-ln' + (up ? ' w-on' : ''), 'users', _('Guest WiFi'), (o.guestName || 'Wiflow') + ' · ' + _('%d devices').format(o.guests || 0));
	return E('div', { 'class': 'w-fn' }, [ E('div', { 'class': 'w-fs' }, [ lan, wifi ]), merge, rt, vt, hz, gs ]);
}

return baseclass.extend({
	svg: svg, band: band, chip: chip, sig: sig, btn: btn, row: row, panel: panel, tile: tile, meter: meter,
	head: head, field: field, dialog: dialog, waitBox: waitBox, chart: chart, flow: flow
});
