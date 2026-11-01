'use strict';
'require view';
'require ui';
'require uci';
'require rpc';
'require fs';
'require wiflow.kit as K';

/* System: the device, its health, backup / restore / firmware / restart, the admin password and
   who to contact. */

const chip = K.chip, btn = K.btn, row = K.row, panel = K.panel, svg = K.svg;

const callSetPassword = rpc.declare({ object: 'luci', method: 'setPassword', params: [ 'username', 'password' ], expect: { result: false } });
const callReboot = rpc.declare({ object: 'system', method: 'reboot', expect: { result: 0 } });
const callValidate = rpc.declare({ object: 'system', method: 'validate_firmware_image', params: [ 'path' ], expect: { '': { valid: false, forcable: true } } });
const callStatus = rpc.declare({ object: 'wiflow', method: 'status', expect: { '': {} } });

const LAN = '10.0.0.1';
const PHONE = '0833 880 100', MAIL = 'wiflow@projifylab.com', SITE = 'wiflow.projifylab.com';

function confirmBox(title, text, label, fn, danger) {
	K.dialog(title, E('p', {}, text), [
		btn('g', _('Cancel'), ui.hideModal),
		btn(danger ? 'd' : 'p', label, fn)
	]);
}

function contact(icon, value, href) {
	return E('div', { 'class': 'w-row' }, E('div', { 'class': 'w-k w-ik' }, [ svg(icon), E('a', { 'class': 'w-lk2', 'href': href }, value) ]));
}

return view.extend({
	load() {
		return Promise.all([
			uci.load([ 'rpcd', 'network' ]),
			callStatus().catch(() => ({})),
			fs.read('/sys/class/net/br-lan/address').then(t => String(t || '').trim().toUpperCase(), () => '')
		]).then(r => ({ st: r[1], mac: r[2] }));
	},

	devicePanel(d) {
		const ip = String(uci.get('network', 'lan', 'ipaddr') || LAN).split('/')[0];
		return panel('cpu', _('Device information'), '', [
			row(_('Device name'), (d.st.device || {}).model || '—'),
			row(_('Device ID'), (d.st.device || {}).id || '—'),
			row('Wiflow OS', _('Version %s').format((d.st.device || {}).os || '—')),
			row(_('Platform'), 'OpenWrt'),
			row(_('Version'), 'ImmortalWrt 2.3.6'),
			row(_('IP address'), ip),
			row(_('MAC address'), d.mac || '—'),
			row(_('Time zone'), _('UTC+7 · Vietnam'))
		], 'w-half w-r2');
	},

	healthPanel(d) {
		const m = d.st.metrics || {};
		const mem = m.mem_total_mb ? m.mem_used_mb / m.mem_total_mb * 100 : 0, fl = m.flash_total_mb ? m.flash_used_mb / m.flash_total_mb * 100 : 0;
		return panel('cpu', _('Router health'), '', [
			row('CPU', K.meter(m.cpu ?? 0), { t: 1 }),
			row(_('Memory'), K.meter(mem), { t: 1 }),
			row(_('Storage'), K.meter(fl), { t: 1 })
		], 'w-half');
	},

	maintenancePanel() {
		const item = (k, b) => E('div', { 'class': 'w-row' }, [ E('div', { 'class': 'w-k' }, k), b ]);
		return panel('layers', _('Maintenance'), '', [
			item(_('Backup'), btn('s', _('Download'), () => this.backup(), { sm: true })),
			item(_('Restore'), btn('s', _('Choose file'), b => this.restore(b), { sm: true })),
			item(_('Flash firmware'), btn('s', _('Choose file'), b => this.flash(b), { sm: true })),
			item(_('Router'), btn('d', _('Restart'), () => this.reboot(), { sm: true }))
		], 'w-half');
	},

	passwordPanel() {
		const a = E('input', { 'type': 'password', 'autocomplete': 'new-password', 'aria-label': _('New password') });
		const b = E('input', { 'type': 'password', 'autocomplete': 'new-password', 'aria-label': _('Confirm password') });
		const go = btn('p', _('Save password'), () => {
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
		return panel('shield', _('Admin password'), '', [
			E('div', { 'class': 'w-fgrid', 'style': 'padding-top:8px' }, [ K.field(_('New password'), a, { pw: 1 }), K.field(_('Confirm password'), b, { pw: 1 }) ]),
			E('div', { 'class': 'w-pf' }, go)
		], 'w-half');
	},

	contactPanel() {
		return panel('contact', _('Contact'), '', [
			contact('phone', PHONE, 'tel:+84833880100'),
			contact('mail', MAIL, 'mailto:' + MAIL),
			contact('globe', SITE, 'https://' + SITE),
			E('div', { 'class': 'w-row' }, [
				E('div', { 'class': 'w-k w-dev' }, [
					E('img', { 'src': L.resource('../wiflow/projify-logo.webp'), 'alt': 'Projify Lab' }),
					E('div', {}, [ E('small', {}, _('Developer')), E('span', { 'class': 'w-lk2' }, 'Projify Lab') ])
				]),
				E('a', { 'class': 'w-ib', 'href': 'https://projifylab.com', 'target': '_blank', 'rel': 'noopener', 'aria-label': 'Projify Lab' }, svg('ext'))
			])
		], 'w-half');
	},

	backup() {
		const f = E('form', { 'method': 'post', 'action': L.env.cgi_base + '/cgi-backup', 'style': 'display:none' }, E('input', { 'type': 'hidden', 'name': 'sessionid', 'value': rpc.getSessionID() }));
		document.body.appendChild(f);
		f.submit();
		f.remove();
	},

	restore(b) {
		return ui.uploadFile('/tmp/backup.tar.gz', b).then(() => {
			confirmBox(_('Restore'), _('The settings in the file replace the settings of this router, then the router restarts.'), _('Restore'), () => {
				K.dialog(_('Restoring…'), K.waitBox(_('The router restarts when finished.')), []);
				fs.exec('/sbin/sysupgrade', [ '--restore-backup', '/tmp/backup.tar.gz' ]).then(() => fs.exec('/sbin/reboot'));
				ui.awaitReconnect(LAN);
			});
		}).catch(e => ui.addNotification(null, E('p', {}, String(e && e.message || e)), 'danger'));
	},

	reboot() {
		confirmBox(_('Restart'), _('The router restarts. Guests lose Internet for about a minute.'), _('Restart'), () => {
			K.dialog(_('Restarting…'), K.waitBox(_('Waiting for the router…')), []);
			callReboot().then(() => ui.awaitReconnect());
		}, true);
	},

	flash(b) {
		return ui.uploadFile('/tmp/firmware.bin', b).then(reply => {
			K.dialog(_('Checking the file…'), K.waitBox(_('Checking the file…')), []);
			return Promise.all([ callValidate('/tmp/firmware.bin'), fs.exec('/sbin/sysupgrade', [ '--test', '/tmp/firmware.bin' ]) ]).then(r => [ reply, r[0], r[1] ]);
		}).then(r => {
			const reply = r[0], ok = r[1].valid && r[2].code == 0;
			const keep = E('input', { 'type': 'checkbox' });
			keep.checked = !!r[1].allow_backup;
			keep.disabled = !r[1].allow_backup;
			const go = btn('p', _('Update'), () => {
				K.dialog(_('Updating…'), K.waitBox(_('Do not turn the router off. This takes a few minutes.')), []);
				const keepOn = keep.checked;
				fs.exec('/sbin/sysupgrade', (keepOn ? [] : [ '-n' ]).concat('/tmp/firmware.bin'));
				ui.awaitReconnect(keepOn ? window.location.host : LAN);
			});
			go.disabled = !ok;
			K.dialog(_('Flash firmware'), E('div', {}, [
				E('div', { 'class': 'w-lgl' }, [
					reply.size ? E('div', {}, [ E('b', {}, _('Size')), E('span', {}, '%1024.2mB'.format(reply.size)) ]) : '',
					reply.sha256sum ? E('div', {}, [ E('b', {}, 'SHA256'), E('span', {}, reply.sha256sum) ]) : ''
				]),
				ok ? E('p', { 'style': 'padding-top:12px' }, E('label', {}, [ keep, E('span', {}, _('Keep settings')) ])) : E('p', { 'style': 'padding-top:12px;color:var(--bad)' }, _('This file is not a firmware for this router.'))
			]), [ btn('g', _('Cancel'), () => fs.remove('/tmp/firmware.bin').finally(ui.hideModal)), go ]);
		}).catch(e => {
			ui.hideModal();
			ui.addNotification(null, E('p', {}, String(e && e.message || e)), 'danger');
		});
	},

	render(d) {
		return E('div', {}, [
			K.head(_('System')),
			E('div', { 'class': 'w-gr' }, [ this.devicePanel(d), this.healthPanel(d), this.maintenancePanel(), this.passwordPanel(), this.contactPanel() ])
		]);
	},

	handleSave: null, handleSaveApply: null, handleReset: null
});
