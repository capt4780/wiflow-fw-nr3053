'use strict';
'require ui';
'require view';

/* Wiflow login (derived from luci-theme-bootstrap sysauth.js, Apache-2.0): the page holds either
   the security-code form or the sign-in form; this only focuses the first empty field and shows
   progress while the form is sent. */
return view.extend({
	render: function() {
		var form = document.querySelector('form.w-f'),
		    button = form.querySelector('button');

		var gc = form.querySelector('#wf_gate_code');
		if (gc) gc.addEventListener('input', function() { var v = gc.value.toUpperCase(); if (v !== gc.value) gc.value = v; });

		form.addEventListener('submit', function() {
			button.disabled = true;
			button.textContent = button.getAttribute('data-busy') || '…';
		});

		function closeAll() {
			document.querySelectorAll('.w-lang.w-open').forEach(function(b) {
				b.classList.remove('w-open');
				b.querySelector('.w-lb').setAttribute('aria-expanded', 'false');
			});
		}

		document.querySelectorAll('.w-lang').forEach(function(box) {
			var cur = box.getAttribute('data-lang'), btn = box.querySelector('.w-lb'), menu = box.querySelector('.w-lm');
			/* standard menu-button semantics (no change to the look) */
			btn.setAttribute('aria-haspopup', 'true');
			btn.setAttribute('aria-expanded', 'false');
			menu.setAttribute('role', 'menu');
			menu.querySelectorAll('button').forEach(function(b) {
				b.setAttribute('role', 'menuitemradio');
				b.setAttribute('aria-checked', b.classList.contains('w-on') ? 'true' : 'false');
			});
			btn.addEventListener('click', function(ev) {
				ev.stopPropagation();
				var was = box.classList.contains('w-open');
				closeAll();
				if (!was) {
					box.classList.add('w-open');
					btn.setAttribute('aria-expanded', 'true');
				}
			});
			box.addEventListener('keydown', function(ev) {
				if (ev.key == 'Escape' && box.classList.contains('w-open')) {
					ev.stopPropagation();
					closeAll();
					btn.focus();
				}
			});
			box.querySelectorAll('.w-lm button').forEach(function(b) {
				b.addEventListener('click', function(ev) {
					ev.stopPropagation();
					var l = b.getAttribute('data-l');
					if (l && l != cur) {
						document.cookie = 'wf_lang=' + l + '; path=/; max-age=31536000; SameSite=Lax';
						location.reload();
					}
					else closeAll();
				});
			});
		});
		document.addEventListener('click', closeAll);
		document.addEventListener('keydown', function(ev) { if (ev.key == 'Escape') closeAll(); });
		var lw = window.innerWidth;
		window.addEventListener('resize', function() { if (window.innerWidth != lw) { lw = window.innerWidth; closeAll(); } });

		var inputs = form.querySelectorAll('input'), first = inputs[0];
		for (var i = 0; i < inputs.length; i++)
			if (!inputs[i].value) { first = inputs[i]; break; }
		if (first) first.focus();

		return '';
	},

	addFooter: function() {}
});
