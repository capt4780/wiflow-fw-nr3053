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

		form.addEventListener('submit', function() {
			button.disabled = true;
			button.textContent = button.getAttribute('data-busy') || '…';
		});

		var inputs = form.querySelectorAll('input'), first = inputs[0];
		for (var i = 0; i < inputs.length; i++)
			if (!inputs[i].value) { first = inputs[i]; break; }
		if (first) first.focus();

		return '';
	},

	addFooter: function() {}
});
