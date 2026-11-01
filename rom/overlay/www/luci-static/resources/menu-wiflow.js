'use strict';
'require baseclass';
'require uci';

/* Wiflow theme: the page frame is drawn by the template (sidebar, icon rail, tab bar);
   this only runs the language menu. The language is stored in luci.main.lang. */

return baseclass.extend({
	__init() {
		document.querySelectorAll('.w-lang').forEach(box => {
			const btn = box.querySelector('.w-lb');

			btn.addEventListener('click', ev => {
				ev.stopPropagation();
				const was = box.classList.contains('w-open');
				this.closeMenus();
				if (!was)
					box.classList.add('w-open');
			});

			box.querySelectorAll('.w-lm button').forEach(b => b.addEventListener('click', ev => {
				ev.stopPropagation();
				this.setLang(b.getAttribute('data-l'), box.getAttribute('data-lang'));
			}));
		});

		document.addEventListener('click', () => this.closeMenus());
		document.addEventListener('keydown', ev => { if (ev.key == 'Escape') this.closeMenus(); });
	},

	closeMenus() {
		document.querySelectorAll('.w-lang.w-open').forEach(b => b.classList.remove('w-open'));
	},

	setLang(lang, cur) {
		this.closeMenus();
		if (!lang || lang == cur)
			return;

		uci.load('luci').then(() => {
			uci.set('luci', 'main', 'lang', lang);
			return uci.save();
		}).then(() => uci.callApply(0, false)).then(() => location.reload(), () => location.reload());
	}
});
