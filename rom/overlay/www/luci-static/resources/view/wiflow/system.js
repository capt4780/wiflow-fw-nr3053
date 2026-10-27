'use strict';
'require view';
'require ui';
'require uci';
'require rpc';
'require fs';
'require wiflow.kit as K';

/* System: login password, firmware, restart. */

const svg = K.svg, card = K.card;

const callSetPassword = rpc.declare({ object: 'luci', method: 'setPassword', params: [ 'username', 'password' ], expect: { result: false } });
const callReboot = rpc.declare({ object: 'system', method: 'reboot', expect: { result: 0 } });
const callValidate = rpc.declare({ object: 'system', method: 'validate_firmware_image', params: [ 'path' ], expect: { '': { valid: false, forcable: true } } });
const callStatus = rpc.declare({ object: 'wiflow', method: 'status', expect: { '': {} } });

const LAN = '10.0.0.1';

function opt(icon, title, sub, fn, cls) {
	const b = E('button', { 'class': 'wa-opt ' + (cls || ''), 'type': 'button' }, [
		E('span', { 'class': 'wa-ico' }, svg(icon)),
		E('div', { 'class': 'wa-t' }, sub ? [ title, E('span', {}, sub) ] : title)
	]);
	b.addEventListener('click', ev => fn(ev.currentTarget));
	return b;
}

function button(cls, text, fn) {
	const b = E('button', { 'class': 'wa-btn ' + cls, 'type': 'button' }, text);
	b.addEventListener('click', fn);
	return b;
}

function confirmBox(title, text, label, fn, danger) {
	ui.showModal(title, [
		text ? E('p', {}, text) : '',
		E('div', { 'class': 'right' }, [
			E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')), ' ',
			E('button', { 'class': 'btn ' + (danger ? 'cbi-button-negative' : 'cbi-button-action') + ' important', 'click': fn }, label)
		])
	]);
}

return view.extend({
	load() {
		return Promise.all([ uci.load('rpcd'), callStatus().catch(() => ({})) ]).then(r => r[1]);
	},

	passwordCard() {
		const a = E('input', { 'type': 'password', 'autocomplete': 'new-password', 'id': 'wa-pw1' });
		const b = E('input', { 'type': 'password', 'autocomplete': 'new-password', 'id': 'wa-pw2' });
		const go = button('pri', _('Save'), () => {
			if (a.value.length < 6)
				return ui.addNotification(null, E('p', {}, _('The password needs at least 6 characters.')), 'danger');
			if (a.value != b.value)
				return ui.addNotification(null, E('p', {}, _('The two passwords do not match.')), 'danger');
			go.disabled = true;
			// one password for both logins: root, and wiflow which follows root
			return callSetPassword('root', a.value).then(ok => {
				if (!ok) throw new Error(_('Could not change the password.'));
				const lg = uci.sections('rpcd', 'login').find(l => l.username == 'wiflow');
				if (lg && lg.password != '$p$root') {
					uci.set('rpcd', lg['.name'], 'password', '$p$root');
					return uci.save().then(() => uci.callApply(0, false));
				}
			}).then(() => {
				a.value = b.value = '';
				ui.addNotification(null, E('p', {}, _('Password changed.')), 'info');
			}).catch(e => ui.addNotification(null, E('p', {}, String(e && e.message || e)), 'danger')).finally(() => { go.disabled = false; });
		});
		return card('wa-c6', 'lock', _('Login password'), null, [
			E('div', { 'class': 'wa-pws' }, [
				E('div', {}, [ E('label', { 'for': 'wa-pw1' }, _('New password')), a ]),
				E('div', {}, [ E('label', { 'for': 'wa-pw2' }, _('Confirm password')), b ])
			]),
			E('div', { 'class': 'wa-btns' }, [ go ])
		]);
	},

	routerCard(st) {
		const os = st && st.device && st.device.os;
		return card('wa-c6', 'chip', _('Router'), null, [
			E('div', { 'class': 'wa-opts' }, [
				opt('download', _('Update firmware'), os ? 'Wiflow OS ' + os : '', b => this.flash(b)),
				opt('power', _('Restart'), '', () => this.reboot()),
				opt('unlink', _('Factory reset'), '', () => this.reset(), 'neg')
			])
		]);
	},

	reboot() {
		confirmBox(_('Restart'), '', _('Restart'), () => {
			ui.showModal(_('Restarting…'), [ E('p', { 'class': 'spinning' }, _('Waiting for the router…')) ]);
			callReboot().then(() => ui.awaitReconnect());
		});
	},

	reset() {
		confirmBox(_('Factory reset'), _('All settings are erased and the router restarts.'), _('Erase all'), () => {
			ui.showModal(_('Factory reset'), [ E('p', { 'class': 'spinning' }, _('The router restarts when finished.')) ]);
			fs.exec('/sbin/firstboot', [ '-r', '-y' ]);
			ui.awaitReconnect(LAN);
		}, true);
	},

	flash(btn) {
		return ui.uploadFile('/tmp/firmware.bin', btn).then(reply => {
			ui.showModal(_('Checking the file…'), [ E('p', { 'class': 'spinning' }, _('Checking the file…')) ]);
			return Promise.all([ callValidate('/tmp/firmware.bin'), fs.exec('/sbin/sysupgrade', [ '--test', '/tmp/firmware.bin' ]) ]).then(r => [ reply, r[0], r[1] ]);
		}).then(r => {
			const reply = r[0], ok = r[1].valid && r[2].code == 0;
			const keep = E('input', { 'type': 'checkbox' });
			keep.checked = !!r[1].allow_backup;
			keep.disabled = !r[1].allow_backup;
			const go = E('button', { 'class': 'btn cbi-button-action important', 'disabled': ok ? null : '' }, _('Update'));
			go.addEventListener('click', () => {
				ui.showModal(_('Updating…'), [ E('p', { 'class': 'spinning' }, _('Do not turn the router off. This takes a few minutes.')) ]);
				const keepOn = keep.checked;
				fs.exec('/sbin/sysupgrade', (keepOn ? [] : [ '-n' ]).concat('/tmp/firmware.bin'));
				ui.awaitReconnect(keepOn ? window.location.host : LAN);
			});
			ui.showModal(_('Update firmware'), [
				E('ul', {}, [ reply.size ? E('li', {}, '%s: %1024.2mB'.format(_('Size'), reply.size)) : '', reply.sha256sum ? E('li', { 'style': 'overflow-wrap:anywhere' }, 'SHA256: ' + reply.sha256sum) : '' ]),
				ok ? E('p', {}, E('label', {}, [ keep, ' ', _('Keep settings') ])) : E('p', { 'class': 'alert-message danger' }, _('This file is not a firmware for this router.')),
				E('div', { 'class': 'right' }, [
					E('button', { 'class': 'btn', 'click': () => fs.remove('/tmp/firmware.bin').finally(ui.hideModal) }, _('Cancel')), ' ', go
				])
			]);
		}).catch(e => {
			ui.hideModal();
			ui.addNotification(null, E('p', {}, String(e && e.message || e)), 'danger');
		});
	},

	render(st) {
		return E('div', { 'class': 'wa' }, [
			E('div', { 'class': 'wa-grid' }, [ this.passwordCard(), this.routerCard(st) ])
		]);
	},

	handleSave: null, handleSaveApply: null, handleReset: null
});
