'use strict';
'require view';
'require poll';
'require ui';
'require wiflow.common as wf';

return view.extend({
	load() {
		return wf.callStatus();
	},

	internetCard(s) {
		const n = s.internet || {};
		const via = !n.online ? 'Chưa có'
			: n.via == 'wifi' ? `WiFi nguồn “${n.source?.ssid || ''}”${n.override ? ' (cáp WAN không ra Internet)' : ''}`
			: n.via == 'lan' ? 'Cáp WAN' : 'Chưa có';
		const mode = { auto: 'Tự động (ưu tiên cáp)', lan: 'Chỉ cáp WAN', wifi: 'Chỉ WiFi nguồn' }[n.mode] || '—';
		return wf.card('globe', 'Internet', n.online ? wf.pill('ok', 'Đang có mạng') : wf.pill('bad', 'Mất mạng'), [
			wf.kv([
				[ 'Đang dùng', via ],
				[ 'Chế độ', mode ],
				n.ip ? [ 'Địa chỉ IP', n.ip ] : null,
				n.online ? [ 'Ổn định', wf.duration(n.since_sec) ] : null
			]),
			E('div', { 'class': 'wf-actions' }, [
				E('a', { 'class': 'btn cbi-button', 'href': L.url('admin/wiflow/internet') }, 'Cài Internet nguồn')
			])
		]);
	},

	guestCard(s) {
		const g = s.guest || {};
		const bands = (g.bands || []).map(b => b == '5g' ? '5G' : '2.4G').join(' + ') || '—';
		return wf.card('wifi', 'WiFi khách', !s.activated ? wf.pill('idle', 'Chưa bật') : g.up ? wf.pill('ok', 'Đang phát') : wf.pill('warn', 'Tạm tắt'), [
			wf.kv([
				[ 'Tên WiFi', g.ssid || '—' ],
				[ 'Băng phát', bands ],
				[ 'Khách đang kết nối', String(g.clients ?? 0) ]
			]),
			E('div', { 'class': 'wf-actions' }, [
				E('a', { 'class': 'btn cbi-button', 'href': L.url('admin/wiflow/guest') }, 'Đổi WiFi khách')
			])
		]);
	},

	wpCard(s) {
		const w = s.wp || {};
		let pill = wf.pill('idle', 'Chưa kết nối');
		if (w.paired) pill = w.online ? wf.pill('ok', 'Đang đồng bộ') : wf.pill('warn', 'Mất liên lạc');
		return wf.card('cloud', 'Tài khoản Wiflow', pill, [
			w.paired ? wf.kv([
				[ 'Mã tài khoản', w.account || '—' ],
				[ 'Liên lạc gần nhất', wf.ago(w.last_ok) ],
				(!w.online && w.error) ? [ 'Tình trạng', w.error ] : null
			]) : E('p', { 'class': 'wf-sub' }, 'Router chưa gắn với tài khoản Wiflow. Lấy mã kết nối 12 ký tự trong ứng dụng Wiflow để ghép.'),
			E('div', { 'class': 'wf-actions' }, [
				E('a', { 'class': 'btn cbi-button' + (w.paired ? '' : ' cbi-button-positive important'), 'href': L.url('admin/wiflow/account') }, w.paired ? 'Xem kết nối' : 'Kết nối tài khoản')
			])
		]);
	},

	deviceCard(s) {
		const d = s.device || {};
		return wf.card('chip', 'Thiết bị', '', wf.kv([
			[ 'Mã thiết bị', d.id || '—' ],
			[ 'Model', d.model || '—' ],
			[ 'Phiên bản', `Wiflow OS ${d.os || '?'} · Wiflow ${d.agent || '?'}` ],
			[ 'Thời gian chạy', wf.duration(d.uptime) ]
		]));
	},

	activateCard(s) {
		const ssid = s.guest?.ssid || 'Wiflow';
		const go = () => ui.showModal('Bật Wiflow?', [
			E('p', {}, `WiFi hiện tại của router sẽ tắt và WiFi khách “${ssid}” (mở, mạng riêng 10.10.10.x) sẽ phát ở cả 2 băng.`),
			E('p', {}, [ 'Nếu bạn đang dùng WiFi của router: sau khoảng 30 giây, hãy kết nối vào ', E('b', {}, `“${ssid}”`), ' rồi mở lại ', E('b', {}, 'http://10.0.0.1'), '.' ]),
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'btn cbi-button', 'click': ui.hideModal }, 'Để sau'), ' ',
				E('button', { 'class': 'btn cbi-button-positive important', 'click': () => {
					ui.hideModal();
					return wf.follow('Đang bật Wiflow', () => wf.callActivate()).then(j => { if (j?.state == 'success') location.reload(); });
				} }, 'Bật Wiflow')
			])
		]);
		return E('div', { 'class': 'wf-card wf-hero' }, [
			E('h3', {}, [ E('span', { 'class': 'wf-ico' }, wf.icon('wifi')), 'Bật Wiflow cho router này', wf.pill('idle', 'Chưa bật') ]),
			E('p', {}, `Wiflow Setup đã được cài. Khi bật, Wiflow quản lý WiFi của router:`),
			E('ul', {}, [
				E('li', {}, `WiFi khách “${ssid}” phát ở cả 2 băng, mỗi băng một kênh cố định ít nhiễu.`),
				E('li', {}, 'Khách dùng mạng riêng, không vào được mạng quản trị; trang quản trị vẫn ở http://10.0.0.1.'),
				E('li', {}, 'Bạn chọn được Internet qua cáp WAN, WiFi nguồn hoặc tự động.')
			]),
			E('div', { 'class': 'wf-actions' }, [ E('button', { 'class': 'btn cbi-button-positive important', 'click': go }, 'Bật Wiflow') ])
		]);
	},

	diagCard(s) {
		const run = (send) => wf.follow(send ? 'Gửi báo cáo cho Wiflow' : 'Tạo báo cáo chẩn đoán', () => wf.callDiag(send))
			.then(j => { if (j?.state == 'success' && !send) return wf.downloadDiag(); });
		return wf.card('info', 'Chẩn đoán', '', [
			E('p', { 'class': 'wf-sub', 'style': 'margin:0' }, 'Khi WiFi hoặc Internet có vấn đề, tải báo cáo (trạng thái sóng, kênh, kết nối, nhật ký) để gửi cho kỹ thuật. Báo cáo không chứa mật khẩu.'),
			E('div', { 'class': 'wf-actions' }, [
				E('button', { 'class': 'btn cbi-button', 'click': () => run(false) }, 'Tải báo cáo'),
				s.wp?.paired ? E('button', { 'class': 'btn cbi-button', 'click': () => run(true) }, 'Gửi cho Wiflow') : ''
			])
		]);
	},

	render(s) {
		wf.css();
		const top = E('div');
		const grid = E('div', { 'class': 'wf-grid' });
		const fill = (st) => {
			top.replaceChildren(st.activated ? '' : this.activateCard(st));
			grid.replaceChildren(this.internetCard(st), this.guestCard(st), this.wpCard(st), this.deviceCard(st), this.diagCard(st));
		};
		fill(s);
		poll.add(() => wf.callStatus().then(st => { if (!document.body.classList.contains('modal-overlay-active')) fill(st); }), 10);

		return E('div', { 'class': 'wf-page' }, [
			wf.head('Tổng quan', 'Trạng thái Internet, WiFi khách và kết nối Wiflow của router.'),
			top,
			grid
		]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
