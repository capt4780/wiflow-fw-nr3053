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
	link: '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>'
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


return baseclass.extend({
	svg: svg, chip: chip, card: card, band: band, signalBars: signalBars
});
