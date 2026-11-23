'use strict';
'require baseclass';
'require uci';

/* Wiflow theme: the page frame is drawn by the template (sidebar, icon rail, tab bar);
   this only runs the language menu. The language is stored in luci.main.lang. */

return baseclass.extend({
	__init__() {
		document.querySelectorAll('.w-lang').forEach(box => {
			const btn = box.querySelector('.w-lb');
			const menu = box.querySelector('.w-lm');

			/* standard menu-button semantics for screen readers and the keyboard (no change to the look) */
			btn.setAttribute('aria-haspopup', 'true');
			btn.setAttribute('aria-expanded', 'false');
			menu.setAttribute('role', 'menu');
			menu.querySelectorAll('button').forEach(b => {
				b.setAttribute('role', 'menuitemradio');
				b.setAttribute('aria-checked', b.classList.contains('w-on') ? 'true' : 'false');
			});

			btn.addEventListener('click', ev => {
				ev.stopPropagation();
				const was = box.classList.contains('w-open');
				this.closeMenus();
				if (!was) {
					box.classList.add('w-open');
					btn.setAttribute('aria-expanded', 'true');
				}
			});

			box.addEventListener('keydown', ev => {
				if (!box.classList.contains('w-open'))
					return;
				if (ev.key == 'Escape') {
					ev.stopPropagation();
					this.closeMenus();
					btn.focus();
				}
				else if (ev.key == 'ArrowDown' || ev.key == 'ArrowUp') {
					const items = Array.from(menu.querySelectorAll('button'));
					const i = items.indexOf(document.activeElement);
					ev.preventDefault();
					items[(i + (ev.key == 'ArrowDown' ? 1 : items.length - 1)) % items.length].focus();
				}
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
		/* the sidebar and the top bar swap places when the window is resized: no menu stays open in the hidden one */
		let lw = window.innerWidth;
		window.addEventListener('resize', () => { if (window.innerWidth != lw) { lw = window.innerWidth; this.closeMenus(); } });
	},

	closeMenus() {
		document.querySelectorAll('.w-lang.w-open').forEach(b => {
			b.classList.remove('w-open');
			const t = b.querySelector('.w-lb');
			if (t)
				t.setAttribute('aria-expanded', 'false');
		});
	},

	setLang(lang, cur) {
		this.closeMenus();
		if (!lang || lang == cur || this.busy)
			return;
		this.busy = true;	/* a second click while the change is saved must not start another one */

		/* the sign-in pages show the same language after signing out */
		document.cookie = 'wf_lang=' + lang + '; path=/; max-age=31536000; SameSite=Lax';

		uci.load('luci').then(() => {
			uci.set('luci', 'main', 'lang', lang);
			return uci.save();
		}).then(() => uci.callApply(0, false)).then(() => location.reload(), () => location.reload());
	}
});
