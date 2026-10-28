'use strict';
'require baseclass';

/* Shared pieces of the Wiflow pages (Wiflow App, WiFi, System). */

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
	lock: '<rect x="5" y="11" width="14" height="10" rx="2.5"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
	power: '<path d="M12 3v9M6.4 6.6a8 8 0 1 0 11.2 0"/>',
	cable: '<path d="M9 3v5M15 3v5M7 8h10v4a5 5 0 0 1-10 0V8ZM12 17v4"/>',
	download: '<path d="M12 4v10M8 10l4 4 4-4M5 19h14"/>',
	search: '<circle cx="11" cy="11" r="6"/><path d="m20 20-4-4"/>',
	link: '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>',
	lan: '<rect x="4" y="4" width="16" height="11" rx="3"/><path d="M8 15v3M12 15v3M16 15v3M7 21h10M8 8v3M12 8v3M16 8v3"/>',
	router: '<rect x="3" y="12" width="18" height="7" rx="3"/><path d="M7 15.5h.01M11 15.5h.01M8 12V8M16 12V8M5.5 5.5a4 4 0 0 1 5 0M13.5 5.5a4 4 0 0 1 5 0"/>'
};

function svg(name) {
	const s = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
	s.setAttribute('viewBox', '0 0 24 24');
	s.setAttribute('aria-hidden', 'true');
	s.innerHTML = IC[name] || IC.globe;
	return s;
}

function band(b) { return b == '5g' ? '5 GHz' : '2.4 GHz'; }

function chip(kind, text) { return E('span', { 'class': 'wa-chip ' + kind }, text); }

function card(cls, icon, title, right, body) {
	const h = [ E('span', { 'class': 'wa-ico' }, svg(icon)), title ];
	if (right) h.push(right);
	return E('section', { 'class': 'wa-card ' + cls }, [ E('h3', {}, h) ].concat(body));
}

function signalBars(dbm) {
	const q = dbm >= -55 ? 4 : dbm >= -65 ? 3 : dbm >= -75 ? 2 : 1;
	return E('span', { 'class': 'wa-bars', 'title': dbm + ' dBm' }, [ 1, 2, 3, 4 ].map(i => E('i', { 'class': i <= q ? 'on' : '' })));
}


/* Internet source as a branch: the sources (WiFi, LAN cable) join in the router
   (Wiflow), which hands the Internet on to the guests (2.4 GHz, 5 GHz). A source
   that carries the traffic gets a flowing line, an unused one a dashed grey line.
   o: { via: 'wifi' | 'lan' | 'none', ssid, saved, band, cable, online, clients: { band2g, band5g } } */
function flow(o) {
	const ns = 'http://www.w3.org/2000/svg';
	const wifiOn = o.via == 'wifi', lanOn = o.via == 'lan', up = o.via != 'none' && o.online !== false;
	const path = (d, on) => on
		? `<path class="b" d="${d}"/><path class="f" d="${d}"/>`
		: `<path class="o" d="${d}"/>`;
	const curve = (vb, html) => {
		const s = document.createElementNS(ns, 'svg');
		s.setAttribute('viewBox', vb);
		s.setAttribute('preserveAspectRatio', 'none');
		s.setAttribute('aria-hidden', 'true');
		s.innerHTML = html;
		return s;
	};
	const tag = (txt, on) => E('span', { 'class': 'wa-tg' + (on ? ' on' : '') }, txt);
	const src = (icon, name, sub, t, on) => E('div', { 'class': 'wa-sr' + (on ? ' on' : '') }, [
		E('span', { 'class': 'wa-ti' }, svg(icon)),
		E('div', { 'class': 'wa-tx' }, [ E('div', { 'class': 'wa-nm' }, name), E('div', { 'class': 'wa-sb' }, sub) ]),
		tag(t, on)
	]);
	const saved = o.saved || '';
	const wifi = src('wifi', saved ? _('WiFi · %s').format(saved) : _('WiFi'),
		wifiOn ? _('%s · Connected').format(band(o.band)) : saved ? _('Not connected') : _('No network chosen'),
		wifiOn ? _('In use') : saved ? (lanOn ? _('Standby') : _('Lost')) : _('Empty'), wifiOn);
	const lan = src('lan', _('LAN cable'),
		lanOn ? _('WAN port · Connected') : o.cable ? _('WAN port · Cable plugged in') : _('WAN port · No cable'),
		lanOn ? _('In use') : o.cable ? _('Plugged in') : _('Empty'), lanOn);
	const rt = E('div', { 'class': 'wa-rt' }, [ E('span', { 'class': 'wa-nd' }, svg('router')), E('b', {}, _('Router Wiflow')) ]);
	const cl = o.clients || {};
	const gt = (name, n) => E('div', { 'class': 'wa-gt' }, [
		E('span', { 'class': 'wa-ti' }, svg('wifi')),
		E('div', { 'class': 'wa-tx' }, [ E('div', { 'class': 'wa-nm' }, name), E('div', { 'class': 'wa-sb' }, _('Devices')) ]),
		E('span', { 'class': 'wa-cn' }, String(n ?? 0))
	]);
	const L = path('M0 38C55 38 45 82 100 82', wifiOn) + path('M0 126C55 126 45 82 100 82', lanOn);
	const R = path('M0 82C55 82 45 38 100 38', up) + path('M0 82C55 82 45 126 100 126', up);
	const wide = E('div', { 'class': 'wa-flow' }, [
		E('div', { 'class': 'wa-c1 r1' }, wifi), E('div', { 'class': 'wa-c1 r2' }, lan),
		E('div', { 'class': 'wa-cv-box c2' }, curve('0 0 100 164', L)),
		rt,
		E('div', { 'class': 'wa-cv-box c4 wa-g' }, curve('0 0 100 164', R)),
		E('div', { 'class': 'wa-c5 r1 wa-g' }, gt('2.4 GHz', cl.band2g)), E('div', { 'class': 'wa-c5 r2 wa-g' }, gt('5 GHz', cl.band5g))
	]);
	/* narrow: sources side by side, the router under them, the guests under it */
	const tile = (icon, name, sub, t, on, guest) => E('div', { 'class': 'wa-mt' + (on ? ' on' : '') + (guest ? ' g' : '') }, [
		E('span', { 'class': 'wa-ti' }, svg(icon)), E('div', { 'class': 'wa-nm' }, name), E('div', { 'class': 'wa-sb' }, sub), t ? tag(t, on) : ''
	]);
	const narrow = E('div', { 'class': 'wa-flowm' }, [
		E('div', { 'class': 'wa-m2' }, [
			tile('wifi', saved ? _('WiFi · %s').format(saved) : _('WiFi'), wifiOn ? band(o.band) : saved ? _('Not connected') : _('No network chosen'), wifiOn ? _('In use') : saved ? (lanOn ? _('Standby') : _('Lost')) : _('Empty'), wifiOn),
			tile('lan', _('LAN cable'), lanOn ? _('Connected') : o.cable ? _('Cable plugged in') : _('No cable'), lanOn ? _('In use') : o.cable ? _('Plugged in') : _('Empty'), lanOn)
		]),
		curve('0 0 100 44', path('M25 0C25 26 50 18 50 44', wifiOn) + path('M75 0C75 26 50 18 50 44', lanOn)),
		E('div', { 'class': 'wa-mr' }, [ E('span', { 'class': 'wa-nd' }, svg('router')), _('Router Wiflow') ]),
		curve('0 0 100 44', path('M50 0C50 26 25 18 25 44', up) + path('M50 0C50 26 75 18 75 44', up)),
		E('div', { 'class': 'wa-m2' }, [
			tile('wifi', '2.4 GHz', _('%d devices').format(cl.band2g ?? 0), null, false, true),
			tile('wifi', '5 GHz', _('%d devices').format(cl.band5g ?? 0), null, false, true)
		])
	]);
	return E('div', { 'class': 'wa-flowbox' }, [ wide, narrow ]);
}

return baseclass.extend({
	svg: svg, chip: chip, card: card, band: band, signalBars: signalBars, flow: flow
});
