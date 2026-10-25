'use strict';
'require baseclass';
'require rpc';
'require ui';
'require fs';

/* Wiflow Setup shared bits: ubus calls to the wiflow rpcd plugin, the page
   styling (light, same palette as the Wiflow theme) and small view helpers. */

const CSS = `
.wf-page{max-width:980px}
.wf-head{display:flex;align-items:flex-end;justify-content:space-between;gap:12px;flex-wrap:wrap;margin:0 0 16px}
.wf-head h2{margin:0}
.wf-head p{margin:4px 0 0;color:var(--wf-muted);font-size:13.5px}
.wf-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(340px,1fr));gap:16px;margin:0 0 16px;align-items:start}
.wf-card{background:#fff;border:1px solid var(--wf-line);border-radius:18px;padding:18px 20px;min-width:0}
.wf-card h3{display:flex;align-items:center;gap:10px;font-size:15px;margin:0 0 12px}
.wf-card h3 .wf-ico{width:34px;height:34px;border-radius:10px;display:grid;place-items:center;background:var(--wf-blue-soft);color:var(--wf-blue);flex:none}
.wf-card h3 .wf-ico svg{width:18px;height:18px;fill:none;stroke:currentColor;stroke-width:2;stroke-linecap:round;stroke-linejoin:round}
.wf-card h3 .wf-pill{margin-left:auto}
.wf-kv{display:grid;grid-template-columns:minmax(110px,auto) minmax(0,1fr);gap:8px 14px;font-size:13.5px;margin:0}
.wf-kv dt{color:var(--wf-muted);font-weight:400}
.wf-kv dd{margin:0;color:var(--wf-text);font-weight:600;overflow-wrap:anywhere}
.wf-pill{display:inline-flex;align-items:center;gap:6px;height:26px;padding:0 10px;border-radius:999px;font-size:12.5px;font-weight:600;white-space:nowrap}
.wf-pill::before{content:"";width:7px;height:7px;border-radius:50%;background:currentColor}
.wf-pill.ok{background:var(--wf-mint-soft);color:var(--wf-mint)}
.wf-pill.warn{background:var(--wf-amber-soft);color:var(--wf-amber)}
.wf-pill.bad{background:var(--wf-coral-soft);color:var(--wf-coral)}
.wf-pill.idle{background:#EEF1F6;color:var(--wf-muted)}
.wf-actions{display:flex;gap:10px;flex-wrap:wrap;margin-top:16px}
.wf-note{display:flex;gap:10px;align-items:flex-start;padding:12px 14px;border-radius:14px;background:var(--wf-blue-soft);color:#24427A;font-size:13px;line-height:1.5;margin:12px 0 0}
.wf-note svg{width:18px;height:18px;flex:none;margin-top:1px;fill:none;stroke:currentColor;stroke-width:2;stroke-linecap:round;stroke-linejoin:round}
.wf-seg{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:6px;padding:5px;background:#E9EEF5;border-radius:14px}
.wf-seg button{all:unset;box-sizing:border-box;cursor:pointer;text-align:center;padding:10px 8px;border-radius:10px;font-weight:600;font-size:13.5px;color:var(--wf-muted);line-height:1.25}
.wf-seg button small{display:block;font-weight:400;font-size:11.5px;margin-top:2px}
.wf-seg button.on{background:#fff;color:var(--wf-text);box-shadow:0 1px 3px rgba(11,27,58,.12)}
.wf-nets{list-style:none;margin:12px 0 0;padding:0;border:1px solid var(--wf-line);border-radius:14px;overflow:hidden}
.wf-nets li{display:flex;align-items:center;gap:12px;padding:12px 14px;border-top:1px solid var(--wf-line);cursor:pointer}
.wf-nets li:first-child{border-top:0}
.wf-nets li:hover{background:#F7F9FC}
.wf-nets li.on{background:var(--wf-blue-soft)}
.wf-nets .n{flex:1;min-width:0}
.wf-nets .n b{display:block;color:var(--wf-text);font-size:14px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.wf-nets .n span{font-size:12px;color:var(--wf-muted)}
.wf-band{display:inline-block;min-width:34px;text-align:center;padding:2px 6px;border-radius:6px;background:#EEF1F6;color:var(--wf-text);font-size:11.5px;font-weight:600}
.wf-bars{display:inline-flex;align-items:flex-end;gap:2px;height:16px}
.wf-bars i{display:block;width:4px;border-radius:1px;background:#CBD3E0}
.wf-bars i:nth-child(1){height:5px}.wf-bars i:nth-child(2){height:9px}.wf-bars i:nth-child(3){height:13px}.wf-bars i:nth-child(4){height:16px}
.wf-bars i.on{background:var(--wf-blue)}
.wf-lock{width:14px;height:14px;fill:none;stroke:var(--wf-muted);stroke-width:2;stroke-linecap:round;stroke-linejoin:round;flex:none}
.wf-field{margin:14px 0 0}
.wf-field label{display:block;font-weight:600;font-size:13px;margin:0 0 6px}
.wf-field input{width:100%;max-width:420px;height:44px}
.wf-field .wf-hint{font-size:12.5px;color:var(--wf-muted);margin-top:6px}
.wf-code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:.12em;text-transform:uppercase}
.wf-big{font-size:22px;font-weight:600;letter-spacing:-.01em;margin:2px 0 0}
.wf-sub{font-size:12.5px;color:var(--wf-muted)}
.wf-hero{border-color:#BFD3FF;background:linear-gradient(180deg,#F5F8FF,#fff);margin:0 0 16px}
.wf-hero p{margin:0 0 6px;font-size:13.5px;line-height:1.55;color:var(--wf-text)}
.wf-hero ul{margin:6px 0 0 18px;padding:0;font-size:13px;line-height:1.6}
.wf-hero ul li{color:var(--wf-text);list-style:disc}
.wf-hero ul li::marker{color:var(--wf-blue)}
.wf-tag{display:inline-block;padding:1px 7px;border-radius:6px;font-size:11px;font-weight:600;margin-left:6px;vertical-align:1px}
.wf-tag.ok{background:var(--wf-mint-soft);color:var(--wf-mint)}
.wf-tag.warn{background:var(--wf-amber-soft);color:var(--wf-amber)}
.wf-wait{display:flex;align-items:center;gap:14px;padding:6px 0 4px}
.wf-spin{width:22px;height:22px;flex:none;border-radius:50%;border:3px solid var(--wf-blue-soft);border-top-color:var(--wf-blue);animation:wf-spin .8s linear infinite}
@keyframes wf-spin{to{transform:rotate(360deg)}}
@media (max-width:600px){.wf-grid{grid-template-columns:minmax(0,1fr)}.wf-seg{grid-template-columns:1fr}.wf-kv{grid-template-columns:1fr;gap:2px 0}.wf-kv dd{margin-bottom:8px}.wf-card{padding:16px}}
`;

const ICON = {
	globe: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>',
	wifi: '<path d="M2 8.5a15 15 0 0 1 20 0M5 12a10 10 0 0 1 14 0M8.5 15.5a5 5 0 0 1 7 0"/><circle cx="12" cy="19" r="1"/>',
	cloud: '<path d="M7 18h10a4 4 0 0 0 .5-8A6 6 0 0 0 6 9.5 4.3 4.3 0 0 0 7 18Z"/>',
	chip: '<rect x="5" y="5" width="14" height="14" rx="3"/><path d="M9 9h6v6H9z"/>',
	cable: '<path d="M7 3v5M17 3v5M5 8h14v4a7 7 0 0 1-14 0V8ZM12 19v2"/>',
	info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>',
	lock: '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>'
};

let cssDone = false;

return baseclass.extend({
	callStatus: rpc.declare({ object: 'wiflow', method: 'status', expect: { '': {} } }),
	callScan: rpc.declare({ object: 'wiflow', method: 'scan', expect: { '': {} } }),
	callSetUplink: rpc.declare({ object: 'wiflow', method: 'set_uplink', params: [ 'mode', 'ssid', 'bssid', 'band', 'key', 'encryption' ] }),
	callSetGuest: rpc.declare({ object: 'wiflow', method: 'set_guest', params: [ 'ssid' ] }),
	callReconnect: rpc.declare({ object: 'wiflow', method: 'reconnect' }),
	callPair: rpc.declare({ object: 'wiflow', method: 'pair', params: [ 'code' ] }),
	callUnpair: rpc.declare({ object: 'wiflow', method: 'unpair', params: [ 'force' ] }),
	callJobClear: rpc.declare({ object: 'wiflow', method: 'job_clear' }),
	callActivate: rpc.declare({ object: 'wiflow', method: 'activate' }),
	callDiag: rpc.declare({ object: 'wiflow', method: 'diag', params: [ 'send' ] }),

	/* The diagnostic report as a file download. */
	downloadDiag() {
		return fs.read('/tmp/wiflow/diag.txt').then(txt => {
			const a = E('a', { 'href': URL.createObjectURL(new Blob([ txt ], { type: 'text/plain' })), 'download': `wiflow-diag-${new Date().toISOString().slice(0, 16).replace(/[-:T]/g, '')}.txt` });
			document.body.appendChild(a); a.click(); a.remove();
		}, () => this.notify(false, 'Không đọc được báo cáo.'));
	},

	/* Shown on pages that need the WiFi until Wiflow is switched on. */
	activateNote() {
		return this.note(E('span', {}, [ 'Wiflow chưa quản lý WiFi của router. Bấm ', E('a', { 'href': L.url('admin/wiflow/overview') }, '“Bật Wiflow”'), ' ở trang Tổng quan trước.' ]));
	},

	/* Start a background change and follow it in a modal until it is done.
	   Joining a WiFi reloads the radios, so the page may lose the router for
	   a moment: the status is polled again until it answers (2 minutes).
	   Resolves with the finished job ({ state, message }) or null. */
	follow(title, start) {
		const msg = E('p', { 'class': 'wf-sub', 'style': 'margin:0' }, 'Đang bắt đầu…');
		ui.showModal(title, [ E('div', { 'class': 'wf-wait' }, [ E('span', { 'class': 'wf-spin' }), msg ]) ]);

		const deadline = Date.now() + 120000;
		const poll = () => new Promise(res => setTimeout(res, 1500))
			.then(() => this.callStatus())
			.then(s => {
				const j = s?.job;
				if (j && j.state == 'running') {
					msg.textContent = j.message || '…';
					return Date.now() < deadline ? poll() : null;
				}
				return j;
			}, () => {
				msg.textContent = 'Đang chờ router phản hồi…';
				return Date.now() < deadline ? poll() : null;
			});

		return Promise.resolve(start()).then(r => {
			if (!r || r.ok === false) {
				ui.hideModal();
				this.notify(false, r?.error || 'Không thực hiện được.');
				return null;
			}
			return poll().then(j => {
				ui.hideModal();
				if (!j)
					this.notify(false, 'Router chưa trả lời. Tải lại trang sau ít phút để xem kết quả.');
				else
					this.notify(j.state == 'success', j.message);
				return j;
			});
		}, err => {
			ui.hideModal();
			this.notify(false, String(err?.message || err));
			return null;
		});
	},

	css() {
		if (!cssDone) {
			document.head.appendChild(E('style', {}, CSS));
			cssDone = true;
		}
	},

	icon(name, cls) {
		const s = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
		s.setAttribute('viewBox', '0 0 24 24');
		s.setAttribute('aria-hidden', 'true');
		if (cls) s.setAttribute('class', cls);
		s.innerHTML = ICON[name] || ICON.info;
		return s;
	},

	head(title, sub, extra) {
		const kids = [ E('div', {}, sub ? [ E('h2', {}, title), E('p', {}, sub) ] : [ E('h2', {}, title) ]) ];
		if (extra) kids.push(extra);
		return E('div', { 'class': 'wf-head' }, kids);
	},

	card(icon, title, pill, body) {
		const kids = [ E('h3', {}, [ E('span', { 'class': 'wf-ico' }, this.icon(icon)), title, pill || '' ]) ];
		(Array.isArray(body) ? body : [ body ]).forEach(b => { if (b) kids.push(b); });
		return E('div', { 'class': 'wf-card' }, kids);
	},

	pill(kind, text) {
		return E('span', { 'class': 'wf-pill ' + kind }, text);
	},

	kv(rows) {
		const dl = E('dl', { 'class': 'wf-kv' });
		rows.forEach(r => { if (r) { dl.appendChild(E('dt', {}, r[0])); dl.appendChild(E('dd', {}, r[1])); } });
		return dl;
	},

	note(text) {
		return E('div', { 'class': 'wf-note' }, [ this.icon('info'), E('div', {}, text) ]);
	},

	bars(signal) {
		const q = signal >= -55 ? 4 : signal >= -65 ? 3 : signal >= -75 ? 2 : 1;
		return E('span', { 'class': 'wf-bars', 'title': signal + ' dBm' }, [1, 2, 3, 4].map(i => E('i', { 'class': i <= q ? 'on' : '' })));
	},

	band(b) {
		return E('span', { 'class': 'wf-band' }, b == '5g' ? '5G' : '2.4G');
	},

	duration(sec) {
		sec = +sec || 0;
		const d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60);
		return d ? `${d} ngày ${h} giờ` : h ? `${h} giờ ${m} phút` : `${m} phút`;
	},

	ago(ts) {
		if (!ts) return 'chưa có';
		const s = Math.max(0, Math.floor(Date.now() / 1000) - ts);
		return s < 60 ? `${s} giây trước` : s < 3600 ? `${Math.floor(s / 60)} phút trước` : `${Math.floor(s / 3600)} giờ trước`;
	},

	busy(btn, text) {
		btn.disabled = true;
		btn.classList.add('spinning');
		if (text) btn.firstChild.data = text;
	},

	notify(ok, text) {
		ui.addNotification(null, E('p', {}, text), ok ? 'info' : 'danger');
	}
});
