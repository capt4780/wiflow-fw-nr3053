'use strict';
'require ui';
'require view';

/* Wiflow login (derived from luci-theme-bootstrap sysauth.js, Apache-2.0).
   The page holds either the access-code gate or the login form; the section's
   data-title gives the card title. */
return view.extend({
	render: function() {
		var section = document.querySelector('section[data-title]'),
		    form = section.querySelector('form'),
		    btn = section.querySelector('section > button'),
		    gate = section.hasAttribute('data-gate');

		var dlg = ui.showModal(
			section.getAttribute('data-title'),
			[].slice.call(section.children),
			'login'
		);

		if (gate)
			dlg.classList.add('wf-gate');

		form.addEventListener('keypress', function(ev) {
			if (ev.key == 'Enter')
				btn.click();
		});

		btn.addEventListener('click', function() {
			dlg.querySelectorAll('*').forEach(function(node) { node.style.display = 'none' });
			dlg.appendChild(E('div', { 'class': 'spinning' }, gate ? _('Checking…') : _('Logging in…')));

			form.submit()
		});

		var first = gate ? form.querySelector('input[name="wf_gate_code"]')
		                 : (function() {
		                 	var pw = form.querySelector('input[type="password"]'),
		                 	    user = form.querySelector('input[name="luci_username"]');
		                 	return (user && !user.value) ? user : pw;
		                 })();
		if (first) first.focus();

		return '';
	},

	addFooter: function() {}
});
