'use strict';
'require view';
'require wiflow.common as wf';

return view.extend({
	load() {
		return wf.callStatus();
	},

	render(s) {
		wf.css();
		const g = s.guest || {};
		const src = s.internet?.source || {};
		const bands = (g.bands || []).map(b => b == '5g' ? '5G' : '2.4G').join(' + ') || '—';
		const follows = g.follows ? (g.follows == '5g' ? '5G' : '2.4G') : null;

		const ssidIn = E('input', { 'type': 'text', 'maxlength': '32', 'value': g.ssid || '', 'autocomplete': 'off', 'spellcheck': 'false' });
		const err = E('div', { 'class': 'wf-hint', 'style': 'color:var(--wf-coral);display:none' });

		const save = E('button', { 'class': 'btn cbi-button-positive important', 'click': () => {
			const v = ssidIn.value.trim();
			const len = new TextEncoder().encode(v).length;
			if (len < 1 || len > 32) { err.textContent = 'Tên WiFi khách cần từ 1 đến 32 ký tự.'; err.style.display = ''; return; }
			if (src.ssid && v == src.ssid) { err.textContent = 'Tên WiFi khách phải khác WiFi nguồn.'; err.style.display = ''; return; }
			if (v == g.ssid) { err.textContent = 'Tên mới giống tên đang dùng.'; err.style.display = ''; return; }
			err.style.display = 'none';
			return wf.follow('Đổi tên WiFi khách', () => wf.callSetGuest(v)).then(j => { if (j?.state == 'success') location.reload(); });
		} }, 'Lưu tên WiFi');

		if (!s.activated)
			return E('div', { 'class': 'wf-page' }, [ wf.head('WiFi khách', 'WiFi mở cho khách, tách riêng khỏi mạng quản trị của router.'), wf.activateNote() ]);

		return E('div', { 'class': 'wf-page' }, [
			wf.head('WiFi khách', 'WiFi mở cho khách, tách riêng khỏi mạng quản trị của router.'),
			E('div', { 'class': 'wf-grid' }, [
				wf.card('wifi', 'Tên WiFi khách', g.up ? wf.pill('ok', 'Đang phát') : wf.pill('warn', 'Tạm tắt'), [
					E('div', { 'class': 'wf-field', 'style': 'margin-top:0' }, [
						E('label', {}, 'Tên WiFi'),
						ssidIn,
						E('div', { 'class': 'wf-hint' }, 'Khách thấy tên này trong danh sách WiFi. Không đặt mật khẩu.'),
						err
					]),
					E('div', { 'class': 'wf-actions' }, [ save ])
				]),
				wf.card('globe', 'Đang phát', '', [
					wf.kv([
						[ 'Băng phát', bands ],
						[ 'Kênh', ['2g', '5g'].filter(b => g.channels?.[b]).map(b => `${b == '5g' ? '5G' : '2.4G'} ${g.channels[b] == 'auto' ? 'theo WiFi nguồn' : 'kênh ' + g.channels[b]}`).join(' · ') || '—' ],
						[ 'Khách đang kết nối', String(g.clients ?? 0) ],
						[ 'Mạng khách', g.subnet || '10.10.10.0/24' ],
						[ 'Bảo mật', 'Mở, khách không thấy nhau' ]
					]),
					wf.note(follows
						? `Băng ${follows} đang dùng chung sóng với WiFi nguồn nên phát theo kênh của WiFi nguồn. Khách vẫn vào được Wiflow Setup tại 10.0.0.1.`
						: 'Khách dùng mạng riêng 10.10.10.x, không vào được mạng quản trị. Riêng trang Wiflow Setup (10.0.0.1) vẫn mở được từ WiFi khách.')
				])
			])
		]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
