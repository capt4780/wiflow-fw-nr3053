'use strict';
'require view';
'require ui';
'require wiflow.common as wf';

return view.extend({
	load() {
		return wf.callStatus();
	},

	pairedView(s) {
		const w = s.wp || {};
		const unpair = E('button', { 'class': 'btn cbi-button-negative', 'click': () => {
			ui.showModal('Ngắt kết nối Wiflow?', [
				E('p', {}, 'Router sẽ rời khỏi tài khoản Wiflow. Internet và WiFi khách vẫn chạy bình thường, nhưng không nhận nội dung và lệnh từ ứng dụng nữa.'),
				E('div', { 'class': 'right' }, [
					E('button', { 'class': 'btn cbi-button', 'click': ui.hideModal }, 'Hủy'),
					' ',
					E('button', { 'class': 'btn cbi-button-negative important', 'click': () => {
						ui.hideModal();
						return this.unpair(false);
					} }, 'Ngắt kết nối')
				])
			]);
		} }, 'Ngắt kết nối');

		return E('div', { 'class': 'wf-grid' }, [
			wf.card('cloud', 'Tài khoản Wiflow', w.online ? wf.pill('ok', 'Đang đồng bộ') : wf.pill('warn', 'Mất liên lạc'), [
				E('div', { 'class': 'wf-sub' }, 'Mã tài khoản'),
				E('div', { 'class': 'wf-big wf-code' }, w.account || '—'),
				E('div', { 'style': 'height:12px' }),
				wf.kv([
					[ 'Liên lạc gần nhất', wf.ago(w.last_ok) ],
					w.error ? [ 'Lỗi gần nhất', w.error ] : null
				]),
				E('div', { 'class': 'wf-actions' }, [ unpair ])
			]),
			wf.card('chip', 'Thiết bị này', '', [
				wf.kv([
					[ 'Mã thiết bị', s.device?.id || '—' ],
					[ 'Máy chủ', 'wiflow.projifylab.com' ]
				]),
				wf.note('Nội dung trang chào và lệnh từ ứng dụng Wiflow được đồng bộ tự động khi router có Internet.')
			])
		]);
	},

	pairView(s) {
		const codeIn = E('input', { 'type': 'text', 'class': 'wf-code', 'maxlength': '14', 'placeholder': 'XXXX XXXX XXXX', 'autocomplete': 'off', 'spellcheck': 'false', 'autocapitalize': 'characters' });
		const err = E('div', { 'class': 'wf-hint', 'style': 'color:var(--wf-coral);display:none' });
		const online = !!s.internet?.online;

		const go = E('button', { 'class': 'btn cbi-button-positive important', 'disabled': online ? null : '', 'click': () => {
			const code = codeIn.value.toUpperCase().replace(/[^A-Z0-9]/g, '');
			if (code.length != 12) { err.textContent = 'Mã kết nối gồm 12 chữ và số.'; err.style.display = ''; return; }
			err.style.display = 'none';
			return wf.follow('Kết nối tài khoản Wiflow', () => wf.callPair(code)).then(j => {
				if (j?.state == 'success') location.reload();
				else if (j) { err.textContent = j.message; err.style.display = ''; }
			});
		} }, 'Kết nối');

		return E('div', { 'class': 'wf-grid' }, [
			wf.card('cloud', 'Kết nối tài khoản Wiflow', wf.pill('idle', 'Chưa kết nối'), [
				E('p', { 'class': 'wf-sub', 'style': 'margin:0' }, 'Mở ứng dụng Wiflow → Thiết bị → Thêm thiết bị để lấy mã kết nối 12 ký tự, rồi nhập vào đây.'),
				E('div', { 'class': 'wf-field' }, [ E('label', {}, 'Mã kết nối'), codeIn, err ]),
				E('div', { 'class': 'wf-actions' }, [ go ]),
				online ? '' : wf.note('Router cần có Internet để kết nối tài khoản. Hãy cài Internet nguồn trước.')
			]),
			wf.card('chip', 'Thiết bị này', '', wf.kv([
				[ 'Mã thiết bị', s.device?.id || '—' ],
				[ 'Model', s.device?.model || '—' ]
			]))
		]);
	},

	unpair(force) {
		return wf.follow('Ngắt kết nối Wiflow', () => wf.callUnpair(force)).then(j => {
			if (j?.state == 'success') return location.reload();
			if (!j || force) return;
			ui.showModal('Chưa ngắt được trên máy chủ', [
				E('p', {}, 'Router chưa báo được cho máy chủ Wiflow. Bạn có thể chỉ gỡ trên router; khi đó hãy xóa router này trong ứng dụng Wiflow.'),
				E('div', { 'class': 'right' }, [
					E('button', { 'class': 'btn cbi-button', 'click': ui.hideModal }, 'Để sau'),
					' ',
					E('button', { 'class': 'btn cbi-button-negative important', 'click': () => { ui.hideModal(); return this.unpair(true); } }, 'Chỉ gỡ trên router')
				])
			]);
		});
	},

	render(s) {
		wf.css();
		return E('div', { 'class': 'wf-page' }, [
			wf.head('Kết nối Wiflow', 'Gắn router với tài khoản Wiflow để nhận nội dung trang chào và quản lý từ xa.'),
			s.wp?.paired ? this.pairedView(s) : this.pairView(s)
		]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
