/* Wiflow 1.0.26 — first-time setup (Internet, link) then the Wiflow home; LuCI under Nâng cao. */
(()=>{
'use strict';
const $=s=>document.querySelector(s);
const app=$('#app');
let csrf='',cur={},band='5g',nets=[],pick=null,mode='',pollT=null,jobLoop=null,dash=false;
const JOBKEY='wiflow_job_mode';
const jobMode=v=>{try{if(v===undefined)return sessionStorage.getItem(JOBKEY)||'';if(v)sessionStorage.setItem(JOBKEY,v);else sessionStorage.removeItem(JOBKEY)}catch(e){}return ''};
const esc=s=>String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
const P={wifi:'<path d="M2 8.8a15 15 0 0 1 20 0"/><path d="M5 12.3a10 10 0 0 1 14 0"/><path d="M8.5 15.8a5 5 0 0 1 7 0"/><path d="M12 20h.01"/>',
 lan:'<rect x="3" y="14" width="18" height="7" rx="2"/><path d="M7 14v-3h10v3M12 11V4M9 4h6"/>',
 lock:'<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
 check:'<path d="M5 12.5 9.5 17 19 7"/>',x:'<path d="M6 6l12 12M18 6 6 18"/>',
 alert:'<path d="M12 9v4M12 17h.01"/><path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/>',
 info:'<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>',chev:'<path d="m9 6 6 6-6 6"/>',
 eye:'<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
 eyeoff:'<path d="M3 3l18 18M10.6 5.1A10 10 0 0 1 12 5c6.5 0 10 7 10 7a17 17 0 0 1-3.2 4M6.6 6.6C3.8 8.3 2 12 2 12s3.5 7 10 7a9.8 9.8 0 0 0 5.4-1.6"/><path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"/>',
 refresh:'<path d="M21 12a9 9 0 1 1-2.6-6.4L21 8"/><path d="M21 3v5h-5"/>',plus:'<path d="M12 5v14M5 12h14"/>',
 key:'<circle cx="8" cy="15" r="4"/><path d="m11 12 9-9M17 6l3 3M15 8l2 2"/>',home:'<path d="M4 13h6V4H4zM14 20h6V11h-6zM4 20h6v-3H4zM14 7h6V4h-6z"/>',guest:'<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c.8-3.6 3.2-5.5 6.5-5.5s5.7 1.9 6.5 5.5M16 4.5a3.5 3.5 0 0 1 0 7M18 14.6c2 .7 3.2 2.5 3.5 5.4"/>',portal:'<rect x="3.5" y="4" width="17" height="16" rx="2"/><path d="M7 8h10M7 12h6M7 16h8"/>',gear:'<circle cx="12" cy="12" r="3"/><path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M5.3 18.7l2.1-2.1M16.6 7.4l2.1-2.1"/>',sliders:'<path d="M4 7h10M18 7h2M4 17h4M12 17h8"/><circle cx="16" cy="7" r="2"/><circle cx="10" cy="17" r="2"/>',back:'<path d="m15 6-6 6 6 6"/>',power:'<path d="M12 3v9"/><path d="M18.4 6.6a9 9 0 1 1-12.8 0"/>',ext:'<path d="M14 4h6v6M20 4l-9 9M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/>',link:'<path d="M10 14a5 5 0 0 0 7 0l3-3a5 5 0 0 0-7-7l-1 1"/><path d="M14 10a5 5 0 0 0-7 0l-3 3a5 5 0 0 0 7 7l1-1"/>'};
const ico=n=>`<svg class="ico" viewBox="0 0 24 24" aria-hidden="true">${P[n]||''}</svg>`;
const STEPS=[['internet','Internet nguồn','WiFi modem hoặc cáp mạng'],['link','Liên kết tài khoản','Gắn router vào app Wiflow'],['done','Hoàn tất','Wiflow phát WiFi khách']];
/* Wiflow home: menu (PC side bar) and the view each step name belongs to. */
const NAV=[['home','Tổng quan','home'],['internet','Internet nguồn','wifi'],['guest','WiFi khách','guest'],['portal','Captive portal','portal'],['link','Ghép nối tài khoản','link'],['system','Hệ thống','gear']];
const NAV_OF={done:'home',home:'home',internet:'internet',guest:'guest',portal:'portal',link:'link',security:'system',system:'system'};
const TITLE_OF={home:'Tổng quan',internet:'Internet nguồn',guest:'WiFi khách',portal:'Captive portal',link:'Ghép nối tài khoản',system:'Hệ thống'};

async function api(action,data={},timeout=15000){
  const c=new AbortController(),t=setTimeout(()=>c.abort(),timeout);
  try{
    const r=await fetch('/cgi-bin/api',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({action,...data}),signal:c.signal,cache:'no-store',credentials:'same-origin'});
    const j=await r.json();
    if(j.error==='unauthorized'){location='/login.html';throw new Error('auth')}
    if(j.error==='security_gate'){location='/';throw new Error('gate')}
    return j;
  }finally{clearTimeout(t)}
}
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
function stopPoll(){if(pollT){clearInterval(pollT);pollT=null}}
function render(step,html){stopPoll();app.innerHTML=html;app.classList.toggle('cx-home',step==='home');document.body.classList.toggle('cx-dash',dash);setStep(step);const f=app.querySelector('[autofocus]');if(f&&window.innerWidth>=900)f.focus()}
function head(t,p){return `<div class="sx-h"><h1>${t}</h1>${p?`<p>${p}</p>`:''}</div>`}
function alertBox(kind,title,text=''){const i={ok:'check',err:'alert',warn:'alert',info:'info'}[kind];return `<div class="al ${kind}" role="${kind==='err'?'alert':'status'}">${ico(i)}<div>${title?`<b>${esc(title)}</b>`:''}${esc(text)}</div></div>`}
function busy(t){return `<div class="busy"><span class="spin"></span>${esc(t)}</div>`}

/* Step indicators: side panel (desktop) + progress bar (mobile) */
function stepState(){return {internet:Number(cur.paired)===1||Number(cur.internet_ready)===1||Number(cur.internet_verified)===1,link:Number(cur.paired)===1}}
function setStep(now){
  if(dash){setNav(NAV_OF[now]||'home');return}
  $('#nav').hidden=true;$('#steps').hidden=false;$('#progress').hidden=false;
  const st=stepState(),idx=STEPS.findIndex(s=>s[0]===now);
  $('#steps').innerHTML=STEPS.map(([k,t,d],i)=>{const done=k==='done'?Number(cur.paired)===1&&now==='done':st[k]&&k!==now;const cls=k===now?'now':done?'done':'';return `<li class="${cls}"${k===now?' aria-current="step"':''}><span class="n">${done?ico('check'):i+1}</span><div><b>${t}</b><span>${d}</span></div></li>`}).join('');
  [...$('#progress').children].forEach((el,i)=>{el.className=i<idx?'done':i===idx?'now':''});
  $('#topTitle').textContent='Cài đặt Wiflow';
  $('#stepLabel').textContent=idx>=0?`Bước ${idx+1}/${STEPS.length} · ${STEPS[idx][1]}`:'';
}
function setNav(at){
  $('#steps').hidden=true;$('#progress').hidden=true;const nav=$('#nav');nav.hidden=false;
  nav.innerHTML=NAV.map(([k,t,i])=>`<a href="#" data-nav="${k}" class="${k===at?'on':''}"${k===at?' aria-current="page"':''}>${ico(i)}<span>${t}</span></a>`).join('')+`<a href="/cgi-bin/luci/" class="adv">${ico('sliders')}<span>Nâng cao (LuCI)</span>${ico('ext')}</a>`;
  nav.querySelectorAll('[data-nav]').forEach(a=>a.onclick=e=>{e.preventDefault();go(a.dataset.nav)});
  $('#topTitle').textContent=TITLE_OF[at]||'Wiflow';
  $('#stepLabel').textContent=cur.device_id?`ID ${String(cur.device_id).slice(-6)}`:'';
  document.body.classList.toggle('cx-sub',at!=='home');
}
function go(k){({home:vHome,internet:()=>{mode='';vInternet()},guest:vGuest,portal:vPortal,link:()=>Number(cur.paired)===1?vLinkInfo():vLink(),system:vSystem})[k]?.()}
function backHome(){return dash?`<button class="cx-back" type="button" data-home>${ico('back')}Tổng quan</button>`:''}
function bindBack(){app.querySelectorAll('[data-home]').forEach(b=>b.onclick=vHome)}
function showDid(id){document.querySelectorAll('[data-did]').forEach(e=>e.textContent=id||'—')}
function pwField(id,label,ac,extra=''){return `<label class="f">${label}<span class="f-in"><input id="${id}" type="password" class="has-eye" autocomplete="${ac}" ${extra}><button type="button" class="eye" data-eye="${id}" aria-label="Hiện mật khẩu">${ico('eye')}</button></span></label>`}
function bindEyes(root=document){root.querySelectorAll('[data-eye]').forEach(b=>b.onclick=()=>{const i=document.getElementById(b.dataset.eye),show=i.type==='password';i.type=show?'text':'password';b.innerHTML=ico(show?'eyeoff':'eye');b.setAttribute('aria-label',show?'Ẩn mật khẩu':'Hiện mật khẩu')})}
const onEnter=(el,fn)=>el&&el.addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();fn()}});

async function init(){
  try{
    const s=await api('status');csrf=s.csrf||'';cur=s;showDid(s.device_id);if(s.model)document.querySelectorAll('[data-host]').forEach(e=>e.textContent=s.model);
    try{const j=await api('job',{},8000);if(j.job==='running'){vProgress(jobMode()||'wifi');pollJob();return}}catch(e){}
    if(Number(s.paired)===1){dash=true;vHome();return}
    if(Number(s.pair_required)===1){vLink();return}
    if(Number(s.setup_step)>=3||Number(s.internet_verified)===1||Number(s.internet_ready)===1){vInternetReady();return}
    vInternet();
  }catch(e){if(!/auth|gate/.test(e.message))render('internet',head('Không tải được dữ liệu')+alertBox('err','','Kiểm tra bạn vẫn đang kết nối WiFi Wiflow hoặc cáp LAN, rồi tải lại trang.')+`<div class="acts"><button class="btn pri" onclick="location.reload()">Tải lại</button></div>`)}
}

/* Admin account (Wiflow + LuCI) */
function vSecurity(){
  render('security',backHome()+head('Tài khoản quản trị','Đổi tên đăng nhập, mật khẩu.')+
  pwField('cpCur','Mật khẩu hiện tại','current-password')+
  `<label class="f">Tên đăng nhập<input id="cpUser" value="${esc(cur.username||'wiflow')}" autocomplete="username" autocapitalize="none" spellcheck="false"><small>3–32 ký tự: chữ, số, dấu . _ -</small></label>`+
  pwField('cpNew','Mật khẩu mới','new-password')+pwField('cpNew2','Nhập lại mật khẩu mới','new-password')+
  `<div id="cpMsg"></div><div class="acts"><button class="btn pri" id="cpSave">Lưu</button><button class="btn sec" id="cpBack">Hủy</button></div>`);
  bindEyes(app);bindBack();$('#cpSave').onclick=()=>saveLogin(false);onEnter($('#cpNew2'),()=>saveLogin(false));$('#cpBack').onclick=vSystem;
  if(window.innerWidth>=900)$('#cpCur').focus();
}
async function saveLogin(first){
  const box=$('#cpMsg'),u=$('#cpUser').value.trim(),p=$('#cpNew').value,p2=$('#cpNew2').value,c=first?'wiflow':$('#cpCur').value;
  if(!/^[A-Za-z0-9._-]{3,32}$/.test(u)){box.innerHTML=alertBox('err','','Tên đăng nhập 3–32 ký tự: chữ, số, dấu . _ -');return}
  if(p.length<8){box.innerHTML=alertBox('err','','Mật khẩu mới cần ít nhất 8 ký tự.');return}
  if(p!==p2){box.innerHTML=alertBox('err','','Hai mật khẩu mới không giống nhau.');return}
  const btn=$('#cpSave');btn.disabled=true;box.innerHTML=busy('Đang lưu');
  try{
    const r=await api('change_login',{csrf,current_password:c,new_username:u,new_password:p},10000);
    if(!r.ok){box.innerHTML=alertBox('err','',r.error||'Không lưu được.');btn.disabled=false;return}
    if(r.session&&r.csrf){csrf=r.csrf;cur.username=u;box.innerHTML=alertBox('ok','Đã lưu tài khoản quản trị','');await sleep(700);vSystem();return}
    box.innerHTML=alertBox('ok','Đã lưu','Đăng nhập lại bằng tài khoản mới.');setTimeout(()=>location='/login.html',1200);
  }catch(e){box.innerHTML=alertBox('err','','Không lưu được. Thử lại.');btn.disabled=false}
}

/* 2. Internet source */
function sourceText(s=cur){if(s.internet_mode==='wifi'&&s.source_ssid)return `WiFi “${s.source_ssid}”`;if(s.internet_mode==='lan')return 'Cáp mạng';return ''}
function vInternet(){
  const src=sourceText();
  render('internet',backHome()+head('Internet nguồn','Router lấy Internet từ đâu?')+(src?alertBox('info','Đang dùng: '+src,''):'')+
  `<div class="choices" role="radiogroup" aria-label="Nguồn Internet">
    <button class="choice" role="radio" aria-checked="${mode==='wifi'}" data-mode="wifi"><span class="choice-ico">${ico('wifi')}</span><span class="choice-t"><b>WiFi của modem <span class="chip">Khuyên dùng</span></b><span>Bắt WiFi modem, không cần dây</span></span><span class="radio"></span></button>
    <button class="choice" role="radio" aria-checked="${mode==='lan'}" data-mode="lan"><span class="choice-ico">${ico('lan')}</span><span class="choice-t"><b>Cáp mạng</b><span>Dây từ modem cắm vào cổng WAN</span></span><span class="radio"></span></button>
  </div><div id="step"></div>`);
  bindBack();app.querySelectorAll('[data-mode]').forEach(b=>b.onclick=()=>{mode=b.dataset.mode;app.querySelectorAll('[data-mode]').forEach(x=>x.setAttribute('aria-checked',String(x===b)));mode==='wifi'?vWifi():vLan()});
  if(mode==='wifi')vWifi();else if(mode==='lan')vLan();
}
function vLan(){$('#step').innerHTML=`<p class="sx-sec">Cắm dây mạng từ modem vào cổng WAN của router rồi bấm kiểm tra.</p><div class="acts"><button class="btn pri" id="lanGo">Kiểm tra cáp mạng</button></div>`;$('#lanGo').onclick=connectLan}
async function connectLan(){jobMode('lan');vProgress('lan');try{const r=await api('connect',{csrf,mode:'lan'},8000);if(r.ok===false){jobFail({error_code:'',message:r.error||'Không bắt đầu được.'},'lan');return}pollJob()}catch(e){jobMode(null);jobFail({message:'Không bắt đầu kiểm tra cáp mạng được.'},'lan')}}
function vWifi(){
  $('#step').innerHTML=`<div class="seg" role="group" aria-label="Băng tần"><button data-band="5g" aria-pressed="${band==='5g'}"><b>5 GHz</b><span>Nhanh, đặt gần modem</span></button><button data-band="2g" aria-pressed="${band==='2g'}"><b>2.4 GHz</b><span>Xa modem, xuyên tường</span></button></div><div id="scan"></div>`;
  $('#step').querySelectorAll('[data-band]').forEach(b=>b.onclick=()=>{band=b.dataset.band;$('#step').querySelectorAll('[data-band]').forEach(x=>x.setAttribute('aria-pressed',String(x===b)));scan()});
  scan();
}
function bars(sig){if(sig===null||sig===undefined)return '<span class="bars" aria-label="Không rõ sóng"><i></i><i></i><i></i><i></i></span>';const l=sig>=-55?4:sig>=-65?3:sig>=-75?2:1;return `<span class="bars l${l}" aria-label="Sóng ${['','yếu','trung bình','tốt','rất tốt'][l]}"><i></i><i></i><i></i><i></i></span>`}
async function scan(){
  const area=$('#scan');if(!area)return;area.innerHTML=busy('Đang tìm WiFi xung quanh');
  try{
    const r=await api('scan',{band},12000);if(!$('#scan'))return;
    const seen={};nets=(r.networks||[]).filter(n=>n.ssid).sort((a,b)=>(b.current-a.current)||((b.signal??-200)-(a.signal??-200))).filter(n=>{const k=n.ssid;if(seen[k])return false;seen[k]=1;return true});
    area.innerHTML=`<p class="sx-sec">Chọn WiFi của modem${nets.length?` · ${nets.length} mạng`:''}</p>`+(nets.length?`<div class="wl">${nets.map((n,i)=>`<button class="wi" data-i="${i}">${bars(n.signal)}<span class="wi-t"><b>${esc(n.ssid)}</b>${n.current?'<span class="cur">Đang dùng</span>':`<span>${n.enc==='none'?'Mạng mở':'Có mật khẩu'}</span>`}</span>${n.enc==='none'?ico('chev'):ico('lock')}</button>`).join('')}</div>`:`<div class="wl"><div class="empty">Không thấy WiFi ở băng tần ${band==='5g'?'5 GHz':'2.4 GHz'}. Thử băng tần còn lại hoặc đặt router gần modem hơn.</div></div>`)+
    `<div class="wl-acts"><button class="btn ghost" id="hid">${ico('plus')}Mạng ẩn</button><button class="btn ghost" id="rescan">${ico('refresh')}Quét lại</button></div>`;
    area.querySelectorAll('[data-i]').forEach(b=>b.onclick=()=>sheetWifi(nets[Number(b.dataset.i)]));
    $('#hid').onclick=()=>sheetWifi(null);$('#rescan').onclick=scan;
  }catch(e){if($('#scan'))area.innerHTML=alertBox('err','Không quét được WiFi','Thử lại sau vài giây.')+`<div class="wl-acts"><button class="btn ghost" id="hid">${ico('plus')}Mạng ẩn</button><button class="btn ghost" id="rescan">${ico('refresh')}Quét lại</button></div>`,$('#hid').onclick=()=>sheetWifi(null),$('#rescan').onclick=scan}
}
function openSheet(html){const s=$('#sheet');$('#sheetCard').innerHTML=html;s.hidden=false;s.onclick=e=>{if(e.target===s)closeSheet()};document.addEventListener('keydown',escClose)}
function closeSheet(){$('#sheet').hidden=true;document.removeEventListener('keydown',escClose)}
function escClose(e){if(e.key==='Escape')closeSheet()}
function sheetWifi(n){
  pick=n?{...n,manual:false}:{radio:'',band,ssid:'',bssid:'',enc:'psk2',manual:true};
  const open=n&&n.enc==='none',needGuest=n&&n.ssid==='Wiflow';
  openSheet(`<h2>${ico(n?'wifi':'plus')}${n?esc(n.ssid):'Mạng ẩn'}</h2>${n?`<p>${open?'Mạng mở, không cần mật khẩu.':'Nhập mật khẩu WiFi của modem.'}</p>`:''}
   ${n?'':`<label class="f">Tên WiFi<input id="wSsid" autocomplete="off" autocapitalize="none" spellcheck="false"></label>`}
   ${open?'':pwField('wPass','Mật khẩu WiFi','new-password')}
   <div id="guestWrap" ${needGuest?'':'hidden'}><label class="f">Tên WiFi khách<input id="wGuest" value="" placeholder="Ví dụ: Quán An Nhiên Free WiFi" autocomplete="off"><small>WiFi nguồn đang tên “Wiflow”, WiFi khách cần tên khác.</small></label></div>
   <div id="wErr"></div>
   ${alertBox('warn','','Điện thoại có thể mất kết nối với router vài giây khi đổi nguồn. Trang sẽ tự cập nhật.')}
   <div class="acts"><button class="btn pri" id="wGo">Kết nối</button><button class="btn sec" id="wCancel">Hủy</button></div>`);
  bindEyes($('#sheetCard'));$('#wCancel').onclick=closeSheet;$('#wGo').onclick=submitWifi;onEnter($('#wPass'),submitWifi);
  setTimeout(()=>{const f=$('#wSsid')||$('#wPass');if(f)f.focus()},50);
}
async function submitWifi(){
  const ssid=pick.manual?$('#wSsid').value.trim():pick.ssid,pass=$('#wPass')?$('#wPass').value:'',err=$('#wErr');
  if(!ssid){err.innerHTML=alertBox('err','','Nhập tên WiFi.');return}
  let guest='';if(ssid==='Wiflow'){$('#guestWrap').hidden=false;guest=$('#wGuest').value.trim();if(!guest||guest==='Wiflow'){err.innerHTML=alertBox('err','','Đặt tên WiFi khách khác “Wiflow”.');return}}
  if(pick.enc!=='none'&&pass.length&&pass.length<8){err.innerHTML=alertBox('err','','Mật khẩu WiFi có ít nhất 8 ký tự.');return}
  pick.ssid=ssid;closeSheet();jobMode('wifi');vProgress('wifi');
  try{const r=await api('connect',{csrf,mode:'wifi',band:pick.band||band,radio:pick.radio,ssid,bssid:pick.bssid||'',password:pass,guest_ssid:guest,enc:pick.enc||'psk2'},8000);if(r.ok===false){jobMode(null);jobFail({message:r.error||'Không bắt đầu kết nối được.'},'wifi');return}pollJob()}
  catch(e){pollJob()}
}

/* Connection progress */
const PH_WIFI=[['preparing','Chuẩn bị','Lưu cấu hình hiện tại để khôi phục nếu lỗi'],['associating','Kết nối WiFi modem',''],['dhcp','Nhận địa chỉ mạng','Modem cấp địa chỉ cho router'],['internet_check','Kiểm tra Internet','']];
const PH_LAN=[['preparing','Chuẩn bị','Lưu cấu hình hiện tại để khôi phục nếu lỗi'],['dhcp','Nhận địa chỉ mạng','Qua cáp nối với modem'],['internet_check','Kiểm tra Internet','']];
function stagesHtml(m,phase,state){const list=m==='lan'?PH_LAN:PH_WIFI;let at=list.findIndex(p=>p[0]===phase);if(at<0)at=0;
  return `<ol class="stages">${list.map(([k,t,d],i)=>{let c='';if(state==='success'||i<at)c='done';else if(i===at)c=state==='failed'?'fail':'now';const dot=c==='done'?ico('check'):c==='fail'?ico('x'):c==='now'?'<span class="spin"></span>':'';const desc=k==='associating'&&pick&&pick.ssid?`“${esc(pick.ssid)}”`:esc(d);return `<li class="${c}"><span class="st-dot">${dot}</span><div><b>${t}</b>${desc?`<span>${desc}</span>`:''}</div></li>`}).join('')}</ol>`}
function vProgress(m,phase='preparing'){render('internet',head('Đang kết nối Internet',m==='lan'?'Qua cáp mạng':pick&&pick.ssid?`Qua WiFi “${esc(pick.ssid)}”`:'Qua WiFi modem')+`<div id="stg">${stagesHtml(m,phase,'running')}</div><div id="jobMsg">${m==='wifi'?alertBox('info','','Nếu trang không tự cập nhật sau 1 phút: kết nối lại WiFi Wiflow rồi mở 10.0.0.1.'):''}</div>`)}
function pollJob(){
  if(jobLoop)clearTimeout(jobLoop);
  const m=jobMode()||'wifi',t0=Date.now();
  const loop=async()=>{
    if(!$('#stg')){vProgress(m)}
    try{
      const r=await api('job',{},8000);
      if(r.job==='success'){jobMode(null);$('#stg').innerHTML=stagesHtml(m,'internet_check','success');try{const s=await api('status');cur=s;showDid(s.device_id)}catch(e){}await sleep(700);vInternetReady(true);return}
      if(r.job==='failed'){jobMode(null);jobFail(r,m);return}
      if(r.job==='idle'&&Date.now()-t0>20000){jobMode(null);jobFail({message:'Router chưa bắt đầu kết nối. Thử lại.'},m);return}
      if(r.job==='running'||r.job==='idle'){$('#stg').innerHTML=stagesHtml(m,r.phase||'preparing','running')}
    }catch(e){/* the admin's own link may drop while the radio restarts */}
    jobLoop=setTimeout(loop,2000);
  };loop();
}
function jobFail(r,m){
  const code=r.error_code||'',msg=r.message||'Không kết nối được Internet.';
  if(!$('#stg'))vProgress(m);
  $('#stg').innerHTML=stagesHtml(m,r.phase&&r.phase!=='failed'?r.phase:(code==='wifi_auth_failed'||code==='wifi_not_found'?'associating':code==='dhcp_failed'?'dhcp':code==='internet_failed'?'internet_check':'preparing'),'failed');
  const tips={wifi_auth_failed:'Kiểm tra lại mật khẩu WiFi của modem (phân biệt chữ hoa, chữ thường).',wifi_not_found:'Đặt router gần modem hơn hoặc thử băng tần còn lại.',internet_failed:'Modem có thể đang mất Internet. Kiểm tra bằng điện thoại kết nối thẳng vào modem.',dhcp_failed:'Khởi động lại modem rồi thử lại.',source_subnet_conflict:'Đổi dải địa chỉ của modem hoặc dùng nguồn mạng khác.'};
  const again=code==='wifi_auth_failed'&&pick&&!pick.manual?'<button class="btn pri" id="retryPw">Nhập lại mật khẩu</button>':'<button class="btn pri" id="retry">Thử lại</button>';
  $('#jobMsg').innerHTML=alertBox('err',msg,tips[code]?' '+tips[code]:'')+`<div class="acts">${again}<button class="btn sec" id="other">Chọn nguồn khác</button></div>`;
  const a=$('#retryPw');if(a)a.onclick=()=>{vInternet();sheetWifi(pick)};
  const b=$('#retry');if(b)b.onclick=()=>{if(m==='lan')connectLan();else{vInternet()}};
  $('#other').onclick=()=>{mode='';vInternet()};
  $('.sx-h h1').textContent='Chưa kết nối được';
}
function vInternetReady(fresh){
  const src=sourceText()||'Internet';
  render('internet',backHome()+head(fresh?'Đã có Internet':'Internet nguồn','')+`<div class="hero"><span class="hero-ico">${ico('check')}</span><div><b>${esc(src)}</b><span>Router đã truy cập được Internet</span></div></div><div class="acts"><button class="btn pri" id="next">${dash?'Về Tổng quan':'Tiếp tục'}</button><button class="btn sec" id="change">Đổi nguồn mạng</button></div>`);
  bindBack();$('#next').onclick=dash?vHome:vLink;$('#change').onclick=()=>{mode='';vInternet()};
}

/* 3. Link account */
function vLink(){
  render('link',head('Liên kết tài khoản','Gắn router vào tài khoản Wiflow để quản lý nội dung và xem thống kê.')+
  `<div class="hint"><b>Lấy mã kết nối trong app Wiflow</b><ol><li>Mở app Wiflow, vào mục Thiết bị</li><li>Bấm Thêm (hoặc chọn thiết bị chưa kết nối)</li><li>Bấm Lấy mã kết nối, mã có hiệu lực 10 phút</li></ol></div>
  <label class="f">Mã kết nối<input id="code" class="code-in" placeholder="XXXX-XXXX-XXXX" maxlength="14" autocomplete="one-time-code" autocapitalize="characters" spellcheck="false" inputmode="text" autofocus></label>
  <div id="pairMsg"></div><div class="acts"><button class="btn pri" id="pair">Liên kết</button><button class="btn sec" id="back">Quay lại</button></div>`);
  const i=$('#code');i.addEventListener('input',()=>{const v=i.value.toUpperCase().replace(/[^A-Z0-9]/g,'').slice(0,12);i.value=v.slice(0,4)+(v.length>4?'-'+v.slice(4,8):'')+(v.length>8?'-'+v.slice(8,12):'')});
  onEnter(i,pair);$('#pair').onclick=pair;$('#back').onclick=()=>vInternetReady(false);
}
async function waitPaired(ms=15000){const end=Date.now()+ms;while(Date.now()<end){try{const s=await api('status',{},4000);if(Number(s.paired)===1)return s}catch(e){}await sleep(800)}return null}
async function pair(){
  const raw=$('#code').value.toUpperCase().replace(/[^A-Z0-9]/g,''),box=$('#pairMsg'),btn=$('#pair');
  if(!/^[A-Z0-9]{12}$/.test(raw)){box.innerHTML=alertBox('err','','Mã kết nối gồm 12 ký tự chữ và số.');return}
  btn.disabled=true;box.innerHTML=busy('Đang liên kết với tài khoản');
  try{const r=await api('pair',{csrf,pairing_code:raw},35000);if(!r.ok){box.innerHTML=alertBox('err','Chưa liên kết được',' '+(r.error||'Máy chủ từ chối kết nối.'));btn.disabled=false;return}
    cur={...cur,...r,paired:1};vDone();api('status',{},6000).then(x=>{if(Number(x.paired)===1)cur=x}).catch(()=>{});}
  catch(e){const s=await waitPaired();if(s){cur=s;vDone();return}box.innerHTML=alertBox('err','Máy chủ không phản hồi','Kiểm tra Internet nguồn rồi thử lại.');btn.disabled=false}
}

/* 3. Done (first setup) */
function liveState(s){if(Number(s.internet_live)===1)return['ok','Đã có Internet'];return['bad','Mất Internet']}
function vDone(){
  render('done',head('Hoàn tất cài đặt','')+`<div class="hero"><span class="hero-ico">${ico('check')}</span><div><b>Wiflow đang hoạt động</b><span>Khách bắt WiFi “${esc(cur.guest_ssid||'Wiflow')}” sẽ thấy trang chào.</span></div></div><div class="acts"><button class="btn pri" id="toHome">Vào Tổng quan</button></div>`);
  $('#toHome').onclick=()=>{dash=true;vHome()};
}

/* Wiflow home */
function upFor(sec){sec=Number(sec)||0;const d=Math.floor(sec/86400),h=Math.floor(sec%86400/3600),m=Math.floor(sec%3600/60);return d?`${d} ngày`:h?`${h} giờ`:`${m} phút`}
const MODE_VI={website:'Website',image:'Hình ảnh',video:'Video'};
function item(k,icon,tone,title,sub){return `<a class="cx-item" href="#" data-go="${k}"><span class="cx-ic ${tone}">${ico(icon)}</span><span class="cx-t"><b>${title}</b><span>${sub}</span></span>${ico('chev')}</a>`}
function heroHtml(s){const ok=Number(s.internet_live)===1;return `<section class="cx-hero${ok?'':' bad'}" id="cxHero"><div class="cx-hero-h"><span class="cx-dot"></span><div><b>${ok?'Đang hoạt động':'Mất Internet'}</b><span>${esc(s.internet?('Internet: '+String(s.internet).replace(/^WiFi: /,'')):'Chưa có Internet nguồn')}</span></div></div><div class="cx-stats"><div class="cx-stat"><span>Đang dùng</span><b>${Number(s.clients_now)||0}</b></div><div class="cx-stat"><span>Hôm nay</span><b>${Number(s.clients_today)||0}</b></div><div class="cx-stat"><span>Hoạt động</span><b>${upFor(s.uptime)}</b></div></div></section>`}
function vHome(){
  dash=true;
  render('home',heroHtml(cur)+`<div class="cx-list"><div class="cx-sec">Cài đặt</div>`+
   item('internet','wifi','','Internet nguồn','Kết nối WiFi hoặc cáp cấp Internet')+item('guest','guest','mint','WiFi khách','Tên WiFi cho khách')+
   item('portal','portal','amber','Captive portal','Trang chào khi khách kết nối')+item('link','link','','Ghép nối tài khoản','Liên kết router với app Wiflow')+
   `<div class="cx-sec">Hệ thống</div>`+item('security','lock','ink','Tài khoản quản trị','Đổi tên đăng nhập, mật khẩu')+item('system','refresh','ink','Khởi động lại · Cập nhật','Khởi động lại router, cập nhật Wiflow')+
   `<a class="cx-item adv" href="/cgi-bin/luci/"><span class="cx-ic ink">${ico('sliders')}</span><span class="cx-t"><b>Nâng cao (LuCI)</b><span>Cấu hình OpenWrt</span></span>${ico('chev')}</a></div>`);
  app.querySelectorAll('[data-go]').forEach(a=>a.onclick=e=>{e.preventDefault();const k=a.dataset.go;k==='security'?vSecurity():go(k)});
  pollT=setInterval(async()=>{try{const x=await api('status',{},4000);cur=x;if(Number(x.paired)!==1){dash=false;vLink();return}const h=$('#cxHero');if(h)h.outerHTML=heroHtml(x)}catch(e){}},5000);
}
function rowsHtml(rows){return `<div class="rows">${rows.map(([k,v,c])=>`<div class="row"><span>${k}</span><b${c?` class="${c}"`:''}>${esc(v)}</b></div>`).join('')}</div>`}
function vGuest(){
  render('guest',backHome()+head('WiFi khách','Tên WiFi cho khách.')+`<label class="f">Tên WiFi khách<input id="gName" maxlength="32" value="${esc(cur.guest_ssid||'Wiflow')}" autocomplete="off" spellcheck="false"><small>1–32 ký tự, khác tên WiFi nguồn</small></label>`+alertBox('warn','','Thiết bị đang dùng WiFi khách sẽ mất kết nối vài giây khi đổi tên.')+`<div id="gMsg"></div><div class="acts"><button class="btn pri" id="gSave">Lưu</button></div>`);
  bindBack();const save=async()=>{const v=$('#gName').value.trim(),box=$('#gMsg');if(!v){box.innerHTML=alertBox('err','','Nhập tên WiFi khách.');return}const b=$('#gSave');b.disabled=true;box.innerHTML=busy('Đang lưu');try{const r=await api('guest_ssid',{csrf,guest_ssid:v},10000);if(!r.ok){box.innerHTML=alertBox('err','',r.error||'Không lưu được.');b.disabled=false;return}cur.guest_ssid=v;box.innerHTML=alertBox('ok','Đã lưu','WiFi khách đổi tên sau vài giây.');b.disabled=false}catch(e){box.innerHTML=alertBox('err','','Không lưu được. Thử lại.');b.disabled=false}};
  $('#gSave').onclick=save;onEnter($('#gName'),save);
}
function vPortal(){
  const on=Number(cur.portal_enabled)===1;
  render('portal',backHome()+head('Captive portal','Trang chào khi khách kết nối.')+rowsHtml([['Trạng thái',on?'Đang bật':'Đang tắt',on?'ok':'bad'],['Kiểu trang chào',MODE_VI[cur.portal_mode]||'—'],['Bản nội dung',Number(cur.portal_revision)?String(cur.portal_revision):'—']])+alertBox('info','','Nội dung trang chào cập nhật trong app Wiflow.'));
  bindBack();
}
function vLinkInfo(){
  render('link',backHome()+head('Ghép nối tài khoản','Liên kết router với app Wiflow.')+rowsHtml([['Trạng thái','Đã liên kết','ok'],['Tài khoản',cur.account_public_id||'—'],['ID thiết bị',cur.device_id||'—']])+
  `<div class="danger"><div><b>Đặt lại Wiflow</b><span>Gỡ liên kết tài khoản, cài lại từ đầu</span></div><button class="btn" id="mReset">Đặt lại</button></div>`);
  bindBack();$('#mReset').onclick=sheetReset;
}
function vSystem(){
  render('system',backHome()+head('Hệ thống','')+rowsHtml([['Phiên bản Wiflow',cur.version||'—'],['Hoạt động',upFor(cur.uptime)],['Tài khoản quản trị',cur.username||'wiflow']])+
  `<div class="menu"><button class="mi" id="sAcc"><span class="mi-ico">${ico('lock')}</span><span><b>Tài khoản quản trị</b><span>Đổi tên đăng nhập, mật khẩu</span></span>${ico('chev')}</button><a class="mi" href="/cgi-bin/luci/admin/system/package-manager"><span class="mi-ico">${ico('refresh')}</span><span><b>Cập nhật Wiflow</b><span>Cài gói Wiflow mới</span></span>${ico('chev')}</a><button class="mi" id="sReboot"><span class="mi-ico">${ico('power')}</span><span><b>Khởi động lại</b><span>Khởi động lại router</span></span>${ico('chev')}</button></div>`);
  bindBack();$('#sAcc').onclick=vSecurity;$('#sReboot').onclick=sheetReboot;
}
function sheetReboot(){
  openSheet(`<h2>${ico('power')}Khởi động lại router?</h2><p>Khách mất WiFi khoảng 1–2 phút.</p><div id="rbErr"></div><div class="acts"><button class="btn pri" id="rbGo">Khởi động lại</button><button class="btn sec" id="rbNo">Hủy</button></div>`);
  $('#rbNo').onclick=closeSheet;$('#rbGo').onclick=async()=>{const b=$('#rbGo');b.disabled=true;try{await api('reboot',{csrf},8000);$('#sheetCard').innerHTML=`<h2>${ico('refresh')}Đang khởi động lại</h2><p>Mở lại 10.0.0.1 sau khoảng 2 phút.</p>`}catch(e){b.disabled=false;$('#rbErr').innerHTML=alertBox('err','','Không khởi động lại được. Thử lại.')}};
}
function sheetReset(){
  openSheet(`<h2>${ico('alert')}Đặt lại Wiflow?</h2><p>Router sẽ gỡ liên kết khỏi tài khoản, tắt trang chào và quay về bước cài đặt đầu. Khách sẽ không vào mạng qua Wiflow cho tới khi cài lại.</p><div id="rErr"></div><div class="acts"><button class="btn dan" id="rGo">Đặt lại</button><button class="btn sec" id="rNo">Hủy</button></div>`);
  $('#rNo').onclick=closeSheet;$('#rGo').onclick=async()=>{const b=$('#rGo');b.disabled=true;try{await api('reset',{csrf},15000);location='/'}catch(e){b.disabled=false;$('#rErr').innerHTML=alertBox('err','','Không đặt lại được. Thử lại.')}};
}

/* One logout for Wiflow and LuCI: LuCI ends its session at /cgi-bin/luci/admin/logout. */
document.querySelectorAll('[data-logout]').forEach(a=>a.onclick=async e=>{e.preventDefault();try{await fetch('/cgi-bin/luci/admin/logout',{credentials:'same-origin',redirect:'manual',cache:'no-store'})}catch(_e){}location='/cgi-bin/logout'});
init();
})();
