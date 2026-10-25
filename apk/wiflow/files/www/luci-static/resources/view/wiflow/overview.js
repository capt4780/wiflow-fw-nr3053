'use strict';
'require view';
'require poll';
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
		return wf.card('wifi', 'WiFi khách', g.up ? wf.pill('ok', 'Đang phát') : wf.pill('warn', 'Tạm tắt'), [
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

	render(s) {
		wf.css();
		const grid = E('div', { 'class': 'wf-grid' });
		const fill = (st) => {
			grid.replaceChildren(this.internetCard(st), this.guestCard(st), this.wpCard(st), this.deviceCard(st));
		};
		fill(s);
		poll.add(() => wf.callStatus().then(fill), 10);

		return E('div', { 'class': 'wf-page' }, [
			wf.head('Tổng quan', 'Trạng thái Internet, WiFi khách và kết nối Wiflow của router.'),
			grid
		]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
