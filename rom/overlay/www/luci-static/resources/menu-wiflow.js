'use strict';
'require baseclass';
'require ui';

/* Wiflow theme menu: the LuCI menu tree as a sidebar (PC), an icon rail (tablet)
   or a floating bar with a More sheet (phone), the page title in the top bar and the
   Bootstrap-compatible third-level tab menu. Structure from menu-bootstrap.js
   (luci-theme-bootstrap, Apache-2.0). */

const ICONS = {
	wiflow: '<path d="M2 8.5a15 15 0 0 1 20 0M5 12a10 10 0 0 1 14 0M8.5 15.5a5 5 0 0 1 7 0"/><circle cx="12" cy="19" r="1"/>',
	status: '<path d="M3 12h4l3-8 4 16 3-8h4"/>',
	system: '<rect x="4" y="4" width="16" height="16" rx="3"/><path d="M9 9h6v6H9zM9 1v3M15 1v3M9 20v3M15 20v3M20 9h3M20 14h3M1 9h3M1 14h3"/>',
	services: '<rect x="3.5" y="3.5" width="7" height="7" rx="2"/><rect x="13.5" y="3.5" width="7" height="7" rx="2"/><rect x="3.5" y="13.5" width="7" height="7" rx="2"/><rect x="13.5" y="13.5" width="7" height="7" rx="2"/>',
	network: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>',
	vpn: '<rect x="5" y="11" width="14" height="10" rx="2.5"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
	nas: '<rect x="4" y="4" width="16" height="7" rx="2"/><rect x="4" y="13" width="16" height="7" rx="2"/><path d="M8 7.5h.01M8 16.5h.01"/>',
	statistics: '<path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/>',
	more: '<circle cx="5" cy="12" r="1.4"/><circle cx="12" cy="12" r="1.4"/><circle cx="19" cy="12" r="1.4"/>',
	logout: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="m16 17 5-5-5-5M21 12H9"/>',
	_: '<circle cx="12" cy="12" r="3"/><circle cx="12" cy="12" r="9"/>'
};
const CHEV = '<svg class="chev" viewBox="0 0 24 24" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg>';

function icon(name) {
	return '<svg viewBox="0 0 24 24" aria-hidden="true">' + (ICONS[name] || ICONS._) + '</svg>';
}

return baseclass.extend({
	__init__() {
		this.bindChrome();
		ui.menu.load().then(L.bind(this.render, this));
	},

	bindChrome() {
		document.addEventListener('keydown', ev => {
			if (ev.key == 'Escape')
				this.closeSheet();
		});
	},

	closeSheet() {
		const sheet = document.querySelector('.wf-sheet');

		if (sheet)
			sheet.classList.remove('open');
	},

	render(tree) {
		let node = tree;
		let url = '';

		this.renderModeMenu(tree);

		if (L.env.dispatchpath.length >= 3) {
			for (var i = 0; i < 3 && node; i++) {
				node = node.children[L.env.dispatchpath[i]];
				url = url + (url ? '/' : '') + L.env.dispatchpath[i];
			}

			if (node)
				this.renderTabMenu(node, url);
		}
	},

	renderTabMenu(tree, url, level) {
		const container = document.querySelector('#tabmenu');
		const ul = E('ul', { 'class': 'tabs' });
		const children = ui.menu.getChildren(tree);
		let activeNode = null;

		children.forEach(child => {
			const isActive = (L.env.dispatchpath[3 + (level || 0)] == child.name);
			const activeClass = isActive ? ' active' : '';
			const className = 'tabmenu-item-%s %s'.format(child.name, activeClass);

			ul.appendChild(E('li', { 'class': className }, [
				E('a', { 'href': L.url(url, child.name) }, [ _(child.title) ] )]));

			if (isActive)
				activeNode = child;
		});

		if (ul.children.length == 0)
			return E([]);

		container.appendChild(ul);
		container.style.display = '';

		if (activeNode)
			this.renderTabMenu(activeNode, url + '/' + activeNode.name, (level || 0) + 1);

		return ul;
	},

	renderMainMenu(tree, url) {
		const ul = document.querySelector('#topmenu');
		const at1 = L.env.dispatchpath[1], at2 = L.env.dispatchpath[2];
		const rail = window.matchMedia('(max-width:1179px)');
		// the pages people use most come first on the phone bar
		const first = [ 'wiflow', 'status', 'network' ];
		const groups = ui.menu.getChildren(tree).filter(g => g.name != 'logout').sort((a, b) => {
			const ia = first.indexOf(a.name), ib = first.indexOf(b.name);
			return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib);
		});
		const sheet = E('div', { 'class': 'wf-sheet' });
		const card = E('div', { 'class': 'wf-sheet-card', 'role': 'dialog' });
		let title = null;

		sheet.appendChild(card);
		sheet.addEventListener('click', ev => { if (ev.target === sheet) this.closeSheet(); });
		document.body.appendChild(sheet);

		const openSheet = (key, fill) => {
			const was = sheet.classList.contains('open') && card.dataset.key == key;

			if (was)
				return this.closeSheet();

			card.dataset.key = key;
			card.textContent = '';
			fill(card);
			sheet.classList.add('open');
		};

		const link = (group, kid) => {
			const k = E('a', { 'href': L.url(url, group.name, kid.name), 'class': (group.name == at1 && kid.name == at2) ? 'on' : '' });
			k.textContent = _(kid.title);
			return k;
		};

		const head = (group) => {
			const h = E('h4');
			h.innerHTML = icon(group.name) + '<span></span>';
			h.querySelector('span').textContent = _(group.title);
			return h;
		};

		const fillGroup = (group, kids) => c => {
			c.appendChild(head(group));
			kids.forEach(kid => c.appendChild(link(group, kid)));
		};

		groups.forEach(group => {
			const kids = ui.menu.getChildren(group);
			const active = (group.name == at1);
			const li = E('li', { 'class': (kids.length ? 'dropdown' : '') + (active ? ' active open' : '') });
			const a = E('a', { 'href': kids.length ? '#' : L.url(url, group.name) });

			a.innerHTML = icon(group.name) + '<span></span>' + (kids.length ? CHEV : '');
			a.querySelector('span').textContent = _(group.title);
			li.appendChild(a);

			if (kids.length) {
				a.className = 'menu';
				a.setAttribute('aria-expanded', active ? 'true' : 'false');
				a.addEventListener('click', ev => {
					ev.preventDefault();

					if (rail.matches) {
						// icon rail: the pages open in a card next to it
						openSheet(group.name, fillGroup(group, kids));
						return;
					}

					const open = !li.classList.contains('open');

					// one group open at a time
					ul.querySelectorAll('li.open').forEach(o => {
						o.classList.remove('open');
						o.firstChild.setAttribute('aria-expanded', 'false');
					});

					li.classList.toggle('open', open);
					a.setAttribute('aria-expanded', open ? 'true' : 'false');
				});

				const sub = E('ul', { 'class': 'dropdown-menu' });

				kids.forEach(kid => {
					const on = active && kid.name == at2;

					sub.appendChild(E('li', { 'class': on ? 'active' : '' }, [
						E('a', { 'href': L.url(url, group.name, kid.name) }, [ _(kid.title) ])
					]));

					if (on)
						title = _(kid.title);
				});

				li.appendChild(sub);
			}
			else if (active) {
				title = _(group.title);
			}

			ul.appendChild(li);
		});

		ul.style.display = '';
		this.renderDock(groups, url, at1, at2, openSheet, head, link);

		const h1 = document.querySelector('#wf-crumb');

		if (h1 && title) {
			h1.textContent = title;

			// the page's own heading repeats the title in the top bar: hide that copy
			const dedupe = () => document.querySelectorAll('#maincontent h2').forEach(h => {
				if (h.textContent.trim() == title)
					h.classList.add('wf-dup');
			});

			new MutationObserver(dedupe).observe(document.querySelector('#maincontent'), { childList: true, subtree: true });
			dedupe();
		}

		return ul;
	},

	/* Phone: floating bar with the first three groups and "More" (everything else). */
	renderDock(groups, url, at1, at2, openSheet, head, link) {
		const dock = E('nav', { 'class': 'wf-dock', 'aria-label': _('Menu') });
		const shown = groups.slice(0, 3), rest = groups.slice(3);

		shown.forEach(group => {
			const kids = ui.menu.getChildren(group);
			const a = E('a', { 'class': group.name == at1 ? 'on' : '', 'href': kids.length ? '#' : L.url(url, group.name) });

			a.innerHTML = icon(group.name) + '<span></span>';
			a.querySelector('span').textContent = _(group.title);

			if (kids.length)
				a.addEventListener('click', ev => {
					ev.preventDefault();
					openSheet(group.name, c => {
						c.appendChild(head(group));
						kids.forEach(kid => c.appendChild(link(group, kid)));
					});
				});

			dock.appendChild(a);
		});

		if (rest.length) {
			const more = E('a', { 'class': rest.some(g => g.name == at1) ? 'on' : '', 'href': '#' });

			more.innerHTML = icon('more') + '<span></span>';
			more.querySelector('span').textContent = _('More');
			more.addEventListener('click', ev => {
				ev.preventDefault();
				openSheet('more', c => {
					rest.forEach(group => {
						const kids = ui.menu.getChildren(group);
						const h = E('h5');

						h.textContent = _(group.title);
						c.appendChild(h);

						if (!kids.length) {
							const k = E('a', { 'href': L.url(url, group.name) });
							k.textContent = _(group.title);
							c.appendChild(k);
						}

						kids.forEach(kid => c.appendChild(link(group, kid)));
					});
				});
			});
			dock.appendChild(more);
		}

		document.body.appendChild(dock);
	},

	renderModeMenu(tree) {
		const ul = document.querySelector('#modemenu');
		const children = ui.menu.getChildren(tree);

		children.forEach((child, index) => {
			const isActive = L.env.requestpath.length
				? child.name === L.env.requestpath[0]
				: index === 0;

			ul.appendChild(E('li', { 'class': isActive ? 'active' : '' }, [
				E('a', { 'href': L.url(child.name) }, [ _(child.title) ])
			]));

			if (isActive)
				this.renderMainMenu(child, child.name);
		});

		if (ul.children.length > 1)
			ul.style.display = '';
	}
});
