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

		document.querySelectorAll('.w-lang').forEach(function(box) {
			var cur = box.getAttribute('data-lang');
			box.querySelector('.w-lb').addEventListener('click', function(ev) {
				ev.stopPropagation();
				box.classList.toggle('w-open');
			});
			box.querySelectorAll('.w-lm button').forEach(function(b) {
				b.addEventListener('click', function(ev) {
					ev.stopPropagation();
					var l = b.getAttribute('data-l');
					if (l && l != cur) {
						document.cookie = 'wf_lang=' + l + '; path=/; max-age=31536000; SameSite=Lax';
						location.reload();
					}
					else box.classList.remove('w-open');
				});
			});
		});
		document.addEventListener('click', function() {
			document.querySelectorAll('.w-lang.w-open').forEach(function(b) { b.classList.remove('w-open'); });
		});

		var inputs = form.querySelectorAll('input'), first = inputs[0];
		for (var i = 0; i < inputs.length; i++)
			if (!inputs[i].value) { first = inputs[i]; break; }
		if (first) first.focus();

		return '';
	},

	addFooter: function() {}
});
