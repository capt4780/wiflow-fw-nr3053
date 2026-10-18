'use strict';
'require baseclass';
'require ui';

/* Wiflow theme menu: the LuCI menu tree as a sidebar (groups with icons,
   the open group shows its pages), a breadcrumb in the top bar and the
   Bootstrap-compatible third-level tab menu. Structure from menu-bootstrap.js
   (luci-theme-bootstrap, Apache-2.0). */

const ICONS = {
	status: '<path d="M3 12h4l3-8 4 16 3-8h4"/>',
	system: '<rect x="4" y="4" width="16" height="16" rx="3"/><path d="M9 9h6v6H9zM9 1v3M15 1v3M9 20v3M15 20v3M20 9h3M20 14h3M1 9h3M1 14h3"/>',
	services: '<rect x="3.5" y="3.5" width="7" height="7" rx="2"/><rect x="13.5" y="3.5" width="7" height="7" rx="2"/><rect x="3.5" y="13.5" width="7" height="7" rx="2"/><rect x="13.5" y="13.5" width="7" height="7" rx="2"/>',
	network: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>',
	vpn: '<rect x="5" y="11" width="14" height="10" rx="2.5"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
	nas: '<rect x="4" y="4" width="16" height="7" rx="2"/><rect x="4" y="13" width="16" height="7" rx="2"/><path d="M8 7.5h.01M8 16.5h.01"/>',
	statistics: '<path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/>',
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
		const burger = document.querySelector('#wf-burger');
		const close = () => {
			document.body.classList.remove('wf-menu-open');
			if (burger) burger.setAttribute('aria-expanded', 'false');
		};

		if (burger)
			burger.addEventListener('click', ev => {
				ev.stopPropagation();
				const open = document.body.classList.toggle('wf-menu-open');
				burger.setAttribute('aria-expanded', open ? 'true' : 'false');
			});

		document.addEventListener('click', ev => {
			if (document.body.classList.contains('wf-menu-open') && !ev.target.closest('#wf-side'))
				close();
		});

		document.addEventListener('keydown', ev => {
			if (ev.key == 'Escape')
				close();
		});
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
		const groups = ui.menu.getChildren(tree);
		const at1 = L.env.dispatchpath[1], at2 = L.env.dispatchpath[2];
		let crumb = null;

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
					a.setAttribute('aria-expanded', li.classList.toggle('open') ? 'true' : 'false');
				});

				const sub = E('ul', { 'class': 'dropdown-menu' });

				kids.forEach(kid => {
					const on = active && kid.name == at2;

					sub.appendChild(E('li', { 'class': on ? 'active' : '' }, [
						E('a', { 'href': L.url(url, group.name, kid.name) }, [ _(kid.title) ])
					]));

					if (on)
						crumb = [ _(group.title), _(kid.title) ];
				});

				li.appendChild(sub);
			}
			else if (active) {
				crumb = [ _(group.title) ];
			}

			ul.appendChild(li);
		});

		ul.style.display = '';

		const box = document.querySelector('#wf-crumb');

		if (box && crumb) {
			box.textContent = '';

			if (crumb.length > 1)
				box.appendChild(document.createTextNode(crumb[0] + ' › '));

			box.appendChild(E('b', {}, [ crumb[crumb.length - 1] ]));
		}

		return ul;
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
