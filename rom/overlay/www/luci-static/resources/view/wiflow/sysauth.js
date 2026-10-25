'use strict';
'require ui';
'require view';

/* Wiflow login (derived from luci-theme-bootstrap sysauth.js, Apache-2.0). */
return view.extend({
	render: function() {
		var form = document.querySelector('form'),
		    btn = document.querySelector('section > button');

		var dlg = ui.showModal(
			'Đăng nhập LuCI',
			[].slice.call(document.querySelectorAll('section > *')),
			'login'
		);

		form.addEventListener('keypress', function(ev) {
			if (ev.key == 'Enter')
				btn.click();
		});

		btn.addEventListener('click', function() {
			dlg.querySelectorAll('*').forEach(function(node) { node.style.display = 'none' });
			dlg.appendChild(E('div', { 'class': 'spinning' }, 'Đang đăng nhập…'));

			form.submit()
		});

		var pw = document.querySelector('input[type="password"]'),
		    user = document.querySelector('input[name="luci_username"]');
		(user && !user.value ? user : pw).focus();

		return '';
	},

	addFooter: function() {}
});
