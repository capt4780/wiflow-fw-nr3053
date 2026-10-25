'use strict';
'require view';
'require ui';
'require wiflow.common as wf';

const MODES = [
	[ 'auto', 'Tự động', 'Cáp trước, WiFi dự phòng' ],
	[ 'lan', 'Chỉ cáp WAN', 'Không dùng WiFi nguồn' ],
	[ 'wifi', 'Chỉ WiFi nguồn', 'Không dùng cáp' ]
];

return view.extend({
	load() {
		return wf.callStatus();
	},

	render(s) {
		wf.css();
		const n = s.internet || {};
		const src = n.source || {};
		let mode = n.mode || 'auto';
		let picked = null;

		/* ---- mode ---- */
		const seg = E('div', { 'class': 'wf-seg', 'role': 'radiogroup' });
		MODES.forEach(([ id, title, sub ]) => {
			const b = E('button', { 'type': 'button', 'role': 'radio', 'class': id == mode ? 'on' : '', 'aria-checked': id == mode ? 'true' : 'false',
				'click': () => {
					mode = id;
					seg.querySelectorAll('button').forEach(x => { x.classList.toggle('on', x === b); x.setAttribute('aria-checked', x === b ? 'true' : 'false'); });
					wifiCard.style.display = (mode == 'lan') ? 'none' : '';
				} }, [ title, E('small', {}, sub) ]);
			seg.appendChild(b);
		});

		const saveMode = E('button', { 'class': 'btn cbi-button-positive important', 'click': () => {
			return wf.follow('Đổi chế độ kết nối', () => wf.callSetUplink(mode)).then(j => { if (j) location.reload(); });
		} }, 'Lưu chế độ');

		const modeCard = wf.card('globe', 'Chế độ kết nối', n.online ? wf.pill('ok', 'Đang có mạng') : wf.pill('bad', 'Mất mạng'), [
			seg,
			E('div', { 'class': 'wf-actions' }, [ saveMode ])
		]);

		/* ---- cable ---- */
		const cableCard = wf.card('cable', 'Cáp WAN', n.wan_link ? wf.pill('ok', 'Đã cắm cáp') : wf.pill('idle', 'Chưa cắm cáp'), [
			wf.kv([
				[ 'Trạng thái', n.mode == 'wifi' ? 'Không dùng (chế độ Chỉ WiFi nguồn)'
					: n.override ? 'Có cáp nhưng không ra Internet, đang dùng WiFi nguồn'
					: n.via == 'lan' ? 'Đang dùng làm Internet'
					: (n.wan_link ? 'Đã cắm, chưa có Internet' : 'Không có tín hiệu') ],
				n.wan_ip ? [ 'Địa chỉ IP', n.wan_ip ] : null,
				n.wan_gateway ? [ 'Gateway', n.wan_gateway ] : null
			])
		]);

		/* ---- source WiFi ---- */
		const list = E('ul', { 'class': 'wf-nets', 'style': 'display:none' });
		const keyIn = E('input', { 'type': 'password', 'autocomplete': 'off', 'placeholder': 'Mật khẩu WiFi nguồn' });
		const keyErr = E('div', { 'class': 'wf-hint', 'style': 'color:var(--wf-coral);display:none' }, 'Mật khẩu WiFi cần từ 8 đến 63 ký tự.');
		const joinBox = E('div', { 'style': 'display:none' }, [
			E('div', { 'class': 'wf-field' }, [
				E('label', {}, 'Mật khẩu'),
				keyIn,
				E('div', { 'class': 'wf-hint' }, 'Mật khẩu của WiFi nguồn (8–63 ký tự).'),
				keyErr
			]),
			E('div', { 'class': 'wf-actions' }, [
				E('button', { 'class': 'btn cbi-button-positive important', 'click': () => {
					if (!picked) return;
					const key = keyIn.disabled ? '' : keyIn.value;
					if (!keyIn.disabled && (key.length < 8 || key.length > 63)) {
						keyErr.style.display = '';
						keyIn.focus();
						return;
					}
					keyErr.style.display = 'none';
					const net = picked;
					const join = () => wf.follow(`Kết nối “${net.ssid}”`, () => wf.callSetUplink(mode == 'lan' ? 'auto' : mode, net.ssid, net.bssid, net.band, key, net.encryption))
						.then(j => { if (j?.state == 'success') location.reload(); });
					const why = [];
					if (net.dfs) why.push(`“${net.ssid}” dùng kênh ${net.channel} (kênh DFS). Router có thể phải chờ 1 phút hoặc đổi kênh khi gặp radar, WiFi khách băng 5G sẽ ngắt theo.`);
					if (net.weak) why.push(`Sóng ${net.signal} dBm là yếu, kết nối dễ chập chờn. Nên đặt router gần nguồn hơn (từ −65 dBm trở lên).`);
					const alt = currentNets.find(n => n.ssid == net.ssid && n !== net && n.recommended);
					if (alt) why.push(`Cùng mạng này ở băng ${alt.band == '5g' ? '5G' : '2.4G'} ổn định hơn.`);
					if (!why.length) return join();
					ui.showModal('Kết nối có thể không ổn định', [
						...why.map(t => E('p', {}, t)),
						E('div', { 'class': 'right' }, [
							E('button', { 'class': 'btn cbi-button', 'click': ui.hideModal }, 'Chọn mạng khác'), ' ',
							E('button', { 'class': 'btn cbi-button-positive important', 'click': () => { ui.hideModal(); return join(); } }, 'Vẫn kết nối')
						])
					]);
				} }, 'Kết nối')
			])
		]);

		let currentNets = [];
		const showNets = (nets) => {
			currentNets = nets;
			list.replaceChildren();
			nets.forEach(net => {
				const li = E('li', { 'click': () => {
					picked = net;
					list.querySelectorAll('li').forEach(x => x.classList.toggle('on', x === li));
					joinBox.style.display = '';
					keyIn.value = '';
					keyIn.disabled = !net.encryption || net.encryption == 'none';
					keyIn.placeholder = keyIn.disabled ? 'WiFi này không đặt mật khẩu' : 'Mật khẩu WiFi nguồn';
					keyErr.style.display = 'none';
					if (!keyIn.disabled) keyIn.focus();
				} }, [
					wf.bars(net.signal),
					E('div', { 'class': 'n' }, [
						E('b', {}, [ net.ssid || '(ẩn)',
							net.recommended ? E('span', { 'class': 'wf-tag ok' }, 'Nên dùng') : '',
							net.dfs ? E('span', { 'class': 'wf-tag warn' }, 'Kênh DFS') : '',
							net.weak ? E('span', { 'class': 'wf-tag warn' }, 'Sóng yếu') : '' ]),
						E('span', {}, `${net.signal} dBm · kênh ${net.channel}`) ]),
					net.encryption && net.encryption != 'none' ? wf.icon('lock', 'wf-lock') : '',
					wf.band(net.band)
				]);
				list.appendChild(li);
			});
			list.style.display = nets.length ? '' : 'none';
		};

		const scanBtn = E('button', { 'class': 'btn cbi-button', 'click': ev => {
			const b = ev.currentTarget;
			const reset = () => { b.disabled = false; b.classList.remove('spinning'); b.firstChild.data = 'Quét lại'; };
			wf.busy(b, 'Đang quét…');
			const deadline = Date.now() + 45000;
			const poll = () => new Promise(res => setTimeout(res, 1500)).then(() => wf.callStatus()).then(st => {
				const j = st?.job;
				if (j?.kind == 'scan' && j.state != 'running') return j;
				return Date.now() < deadline ? poll() : null;
			}, () => Date.now() < deadline ? poll() : null);
			return wf.callScan().then(r => {
				if (!r?.ok) { reset(); wf.notify(false, r?.error || 'Không quét được.'); return; }
				return poll().then(j => {
					reset();
					const nets = j?.networks || [];
					showNets(nets);
					if (!j) wf.notify(false, 'Quét WiFi quá lâu, thử lại.');
					else if (!nets.length) wf.notify(false, 'Không tìm thấy WiFi nào.');
				});
			}, reset);
		} }, 'Quét WiFi');

		const wifiCard = wf.card('wifi', 'WiFi nguồn', src.connected ? wf.pill('ok', 'Đã kết nối') : (src.ssid ? wf.pill('warn', 'Đang thử lại') : wf.pill('idle', 'Chưa chọn')), [
			src.ssid ? wf.kv([
				[ 'Đang bắt', E('span', {}, [ src.ssid, ' ', wf.band(src.band) ]) ],
				src.connected ? [ 'Tín hiệu', E('span', {}, [ wf.bars(src.signal), ` ${src.signal} dBm` ]) ] : null,
				n.via == 'wifi' && n.ip ? [ 'Địa chỉ IP', n.ip ] : null
			]) : E('p', { 'class': 'wf-sub' }, 'Chưa chọn WiFi nguồn. Bấm “Quét WiFi” rồi chọn mạng để bắt.'),
			E('div', { 'class': 'wf-actions' }, [ scanBtn ]),
			list,
			joinBox,
			wf.note('Nên dùng WiFi nguồn 5G kênh thường (36–48, 149–165) có sóng từ −65 dBm. WiFi khách vẫn phát cả 2 băng; băng đang bắt nguồn chạy theo kênh của nguồn, băng còn lại giữ kênh cố định.')
		]);
		if (mode == 'lan') wifiCard.style.display = 'none';
		if (!s.activated) {
			scanBtn.disabled = true;
			wifiCard.appendChild(wf.activateNote());
		}

		this.showNets = showNets;

		return E('div', { 'class': 'wf-page' }, [
			wf.head('Internet nguồn', 'Chọn cách router lấy Internet: cáp WAN, WiFi nguồn, hoặc cả hai.'),
			modeCard,
			E('div', { 'class': 'wf-grid', 'style': 'margin-top:16px' }, [ cableCard, wifiCard ])
		]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
