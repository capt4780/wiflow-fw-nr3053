'use strict';
'require baseclass';
'require uci';

/* Wiflow theme: the page frame is drawn by the template (sidebar, icon rail, tab bar);
   this only runs the language menu. The language is stored in luci.main.lang. */

return baseclass.extend({
	__init__() {
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

		/* The gate and sign-in pages keep the language in a cookie (nothing can be written to the router
		   before sign-in): the first page after sign-in copies it into the router's setting. Tried once
		   per choice, so a failed write cannot loop. */
		const first = document.querySelector('.w-lang');
		const ck = document.cookie.match(/(?:^|;\s*)wf_lang=(vi|en)/);
		if (first && ck) {
			const have = first.getAttribute('data-lang');
			let tried = '';
			try { tried = sessionStorage.getItem('wf_lang_sync') || ''; } catch (e) {}
			if (have == ck[1]) {
				try { sessionStorage.removeItem('wf_lang_sync'); } catch (e) {}
			}
			else if (tried != ck[1]) {
				try { sessionStorage.setItem('wf_lang_sync', ck[1]); } catch (e) {}
				this.setLang(ck[1], have);
				return;
			}
		}

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

		/* the sign-in pages show the same language after signing out */
		document.cookie = 'wf_lang=' + lang + '; path=/; max-age=31536000; SameSite=Lax';

		uci.load('luci').then(() => {
			uci.set('luci', 'main', 'lang', lang);
			return uci.save();
		}).then(() => uci.callApply(0, false)).then(() => location.reload(), () => location.reload());
	}
});
