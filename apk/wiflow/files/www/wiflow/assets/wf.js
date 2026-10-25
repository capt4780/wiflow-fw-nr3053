/* Wiflow Setup 1.0.26 — Trạng thái · Internet · WiFi khách · Hệ thống, plus the
   first setup. Plain JS, no libraries. NR3053 port: data from the router's ubus "wiflow" object. */
(()=>{
'use strict';
const $=(s,r=document)=>r.querySelector(s);
const $$=(s,r=document)=>[...r.querySelectorAll(s)];
const esc=s=>String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
const IC={pulse:'<path d="M3 12h4l3-8 4 16 3-8h4"/>',globe:'<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18a14 14 0 0 1 0-18"/>',
 users:'<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0M16 4.5a3.5 3.5 0 0 1 0 7M18 14.2a6.5 6.5 0 0 1 3.5 5.8"/>',
 sliders:'<path d="M4 6h10M18 6h2M4 12h4M12 12h8M4 18h12"/><circle cx="16" cy="6" r="2"/><circle cx="10" cy="12" r="2"/><circle cx="18" cy="18" r="2"/>',
 wifi:'<path d="M2 8.5a15 15 0 0 1 20 0M5 12a10 10 0 0 1 14 0M8.5 15.5a5 5 0 0 1 7 0"/><circle cx="12" cy="19" r="1"/>',lan:'<rect x="5" y="3" width="14" height="10" rx="3"/><path d="M9 13v3h6v-3M12 16v5"/>',
 refresh:'<path d="M20 11a8 8 0 0 0-14.3-4.9L4 8M4 3v5h5M4 13a8 8 0 0 0 14.3 4.9L20 16M20 21v-5h-5"/>',power:'<path d="M12 3v8M6.3 7.3a8 8 0 1 0 11.4 0"/>',code:'<path d="M8 7l-5 5 5 5M16 7l5 5-5 5"/>',
 send:'<path d="M21 3L10 14M21 3l-7 18-4-7-7-4z"/>',reset:'<path d="M4 4v6h6M5.5 15a8 8 0 1 0 1.9-8.3L4 10"/>',logout:'<path d="M15 4h3a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-3M10 17l-5-5 5-5M5 12h11"/>',
 upload:'<path d="M12 16V4M7 9l5-5 5 5M4 16v3a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-3"/>',lock:'<rect x="5" y="11" width="14" height="10" rx="3"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',check:'<path d="M5 12.5l4.5 4.5L19 7.5"/>',
 phone:'<path d="M5 3h4l2 5-2.5 1.5a11 11 0 0 0 6 6L16 13l5 2v4a2 2 0 0 1-2 2A17 17 0 0 1 3 5a2 2 0 0 1 2-2"/>',mail:'<rect x="3" y="5" width="18" height="14" rx="3"/><path d="M3 7l9 6 9-6"/>',
 link:'<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>',x:'<path d="M6 6l12 12M18 6L6 18"/>',
 eye:'<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',plus:'<path d="M12 5v14M5 12h14"/>',
 key:'<circle cx="8" cy="15" r="4"/><path d="M11 12l9-9M17 6l3 3M15 8l2 2"/>',tool:'<path d="M14.7 6.3a4 4 0 0 0-5.4 5.4L3 18l3 3 6.3-6.3a4 4 0 0 0 5.4-5.4l-2.5 2.5-2.5-.5-.5-2.5z"/>',
 alert:'<path d="M12 9v4M12 17h.01"/><path d="M10.3 3.9L1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/>',clock:'<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',copy:'<rect x="9" y="9" width="11" height="11" rx="3"/><path d="M5 15V6a2 2 0 0 1 2-2h9"/>',download:'<path d="M12 4v12M7 11l5 5 5-5M4 20h16"/>'};
const ico=(n,st='')=>`<svg class="i" viewBox="0 0 24 24"${st?` style="${st}"`:''} aria-hidden="true">${IC[n]||''}</svg>`;
const sleep=ms=>new Promise(r=>setTimeout(r,ms));

/* ---------- state ---------- */
const S={st:null,ov:null,inet:null,guest:null,log:null,page:'',csrf:'',scan:{list:null,busy:false,at:0},pend:'',draft:null,orig:null,card:0,up:null,usageSel:-1,wiz:null,lastRender:''};
const NAV=[['status','Trạng thái','pulse'],['internet','Internet','globe'],['guest','WiFi khách','users'],['system','Hệ thống','sliders']];
const TITLES={status:['Trạng thái','Cập nhật trực tiếp'],internet:['Internet','Dây LAN hoặc WiFi nguồn · tự chuyển khi mất mạng'],guest:['WiFi khách','Tên mạng, giới hạn và giờ phục vụ'],system:['Hệ thống','Thiết bị, cập nhật, thao tác và nhật ký']};

/* ---------- NR3053: the CR6609 api() actions on the router's ubus "wiflow" object ----------
   The page runs on the LuCI session: LuCI's "Wiflow Setup" menu entry hands its session id
   over (sessionStorage) and opens /wiflow/. Long work (scan, join, pair, diag) runs as a job
   on the router; status().job reports it. */
const LUCI='/cgi-bin/luci/admin/status/overview',LOGOUT='/cgi-bin/luci/admin/logout';
const SID=(()=>{const m=location.hash.match(/^#(\w+)\/([0-9a-f]{32})$/);if(m){history.replaceState(null,'','#'+m[1]);try{sessionStorage.setItem('wf-sid',m[2])}catch(e){}return m[2]}try{return sessionStorage.getItem('wf-sid')||''}catch(e){return ''}})();
function relogin(){try{sessionStorage.removeItem('wf-sid');sessionStorage.setItem('wf-page',location.hash.slice(1)||'status')}catch(e){}location.replace('/cgi-bin/luci/admin/wiflow')}
let rid=0;
async function ubus(obj,method,args={},timeout=15000){
  if(!SID){relogin();throw new Error('auth')}
  const c=new AbortController(),t=setTimeout(()=>c.abort(),timeout);
  try{
    const r=await fetch('/ubus',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({jsonrpc:'2.0',id:++rid,method:'call',params:[SID,obj,method,args]}),signal:c.signal,cache:'no-store',credentials:'same-origin'});
    const j=await r.json();
    if(j.error&&j.error.code===-32002){relogin();throw new Error('auth')}
    const res=j.result||[];
    if(res[0]===6){relogin();throw new Error('auth')}
    if(res[0]!==0)throw new Error('Router trả lỗi '+(res[0]??(j.error&&j.error.message)));
    return res[1]||{};
  }finally{clearTimeout(t)}
}
function mapStatus(s){
  const i=s.internet||{},g=s.guest||{},w=s.wp||{},d=s.device||{};
  return {ok:true,device_id:d.id,model:d.model||'Viettel NR3053',version:d.agent,os:d.os,uptime:d.uptime,
    internet_live:i.online?1:0,internet_mode:i.mode,uplink_active:i.online?i.via:'none',
    clients_now:g.clients||0,clients_today:g.clients_today||0,guest_ssid:g.ssid,guest_bands:(g.bands||[]).join(','),
    paired:w.paired?1:0,account_public_id:w.account,wp_online:!!w.online,wp_error:w.error,username:s.login||'wiflow',
    activated:!!s.activated,internet_verified:(i.online||(i.source||{}).ssid)?1:0,safe_mode:0,sched_closed:0,reboot_required:0,raw:s};
}
async function waitJob(kind,max){
  const t0=Date.now();let miss=0;
  for(;;){
    await sleep(1500);
    let s;try{s=await ubus('wiflow','status',{},10000);miss=0}catch(e){if(e.message==='auth')throw e;if(++miss>=8)return {state:'lost'};continue}
    const j=s.job||{};
    if(j.kind!==kind||j.state!=='running'){S.st=mapStatus(s);return j}
    if(Date.now()-t0>(max||120000))return {state:'failed',message:'Quá thời gian chờ.'};
  }
}
async function startJob(method,args,kind,max){
  const r=await ubus('wiflow',method,args);
  if(r.ok===false)return {ok:false,error:r.error};
  const j=await waitJob(kind,max);
  return j.state==='success'?{ok:true,message:j.message,job:j}:{ok:false,error:j.message||'Không thành công',job:j};
}
const ENC_OK=['none','psk','psk2','sae'];
async function api(action,data={},timeout=15000){
  switch(action){
  case 'status':return mapStatus(await ubus('wiflow','status',{},timeout));
  case 'overview':return await ubus('wiflow','overview',{},timeout);
  case 'inet':return await ubus('wiflow','inet',{},timeout);
  case 'log':return await ubus('wiflow','log',{},timeout);
  case 'netcheck':return await ubus('wiflow','netcheck',{},30000);
  case 'scan':{
    const r=await startJob('scan',{band:data.band||''},'scan',60000);
    const nets=(((r.job||{}).networks)||[]).map(n=>({ssid:n.ssid,bssid:n.bssid,band:n.band,signal:n.signal,channel:n.channel,enc:n.encryption,dfs:!!n.dfs,weak:!!n.weak,recommended:!!n.recommended}));
    return {ok:r.ok,networks:nets,error:r.error};
  }
  case 'connect':{
    const a=data.ssid?{mode:data.mode||'auto',ssid:data.ssid,band:data.band||'2g',key:data.password||'',encryption:ENC_OK.includes(data.enc)?data.enc:'psk2'}:{mode:data.mode||'auto'};
    const r=await ubus('wiflow','set_uplink',a);return r.ok===false?{ok:false,error:r.error}:{ok:true};
  }
  case 'job':{
    const s=await ubus('wiflow','status',{},timeout);S.st=mapStatus(s);const j=s.job||{};
    return {job:j.kind==='uplink'?(j.state||'idle'):'idle',phase:j.stage||'',message:j.message,error_code:j.error_code||''};
  }
  case 'guest_get':{const s=S.st||mapStatus(await ubus('wiflow','status'));return {ok:true,guest_ssid:s.guest_ssid,settings:{},clients_now:s.clients_now,time_ok:true}}
  case 'guest_ssid':return await startJob('set_guest',{ssid:data.guest_ssid},'guest',90000);
  case 'pair':return await startJob('pair',{code:data.pairing_code},'pair',60000);
  case 'unpair':return await startJob('unpair',{force:!!data.force},'unpair',40000);
  case 'activate':return await startJob('activate',{ssid:data.ssid||''},'activate',120000);
  case 'diag_send':return await startJob('diag',{send:true},'diag',60000);
  case 'diag_file':{const r=await startJob('diag',{},'diag',60000);if(!r.ok)return r;const f=await ubus('file','read',{path:'/tmp/wiflow/diag.txt'});return {ok:true,text:f.data||''}}
  case 'reset':return await startJob('reset',{},'reset',120000);
  case 'reboot':return await ubus('wiflow','reboot',{});
  case 'change_login':return await ubus('wiflow','change_login',{username:data.new_username,password:data.new_password});
  }
  return {ok:false,error:'Chưa hỗ trợ trên NR3053'};
}

/* ---------- formatting ---------- */
const pad2=n=>String(n).padStart(2,'0');
const hhmm=t=>{const d=new Date(t*1000);return pad2(d.getHours())+':'+pad2(d.getMinutes())};
function ago(t,now){if(!t)return '—';const s=Math.max(0,(now||Date.now()/1000)-t);if(s<60)return Math.round(s)+' giây trước';if(s<3600)return Math.round(s/60)+' phút trước';if(s<86400)return Math.round(s/3600)+' giờ trước';return Math.round(s/86400)+' ngày trước'}
function when(t,now){const n=now||Date.now()/1000,d=new Date(t*1000),today=new Date(n*1000);if(d.toDateString()===today.toDateString())return hhmm(t);const y=new Date(n*1000-86400000);if(d.toDateString()===y.toDateString())return 'Hôm qua '+hhmm(t);return pad2(d.getDate())+'/'+pad2(d.getMonth()+1)+' '+hhmm(t)}
function upt(s){s=+s||0;const d=Math.floor(s/86400),h=Math.floor(s%86400/3600),m=Math.floor(s%3600/60);return d?`${d}n ${h}g`:h?`${h}g ${m}p`:`${m} phút`}
function bytes(n){n=+n||0;if(n>=1e9)return (n/1e9).toFixed(1).replace('.',',')+' GB';if(n>=1e6)return Math.round(n/1e6)+' MB';if(n>=1e3)return Math.round(n/1e3)+' KB';return n+' B'}
function mbps(k){k=+k||0;return k?((k%1000?(k/1000).toFixed(1).replace('.',','):k/1000)+' Mbps'):'Không giới hạn'}
function minutes(m){m=+m||0;if(!m)return 'Không giới hạn';if(m%60===0)return (m/60)+' giờ';return m+' phút'}
const tail6=id=>String(id||'').slice(-6);
/* Full device code (WIFDID-…) after login; the gate page never shows it. */
const devCode=id=>String(id||'')||'NR3053';
/* RAM used / total in one unit, short enough for the small gauge ("120 / 248 MB", "1,0 / 7,8 GB"). */
const memPair=(u,t)=>t>=1024*1000?`${(u/1048576).toFixed(1).replace('.',',')} / ${(t/1048576).toFixed(1).replace('.',',')} GB`:`${Math.round(u/1024)} / ${Math.round(t/1024)} MB`;

/* smooth area/line paths for the small charts */
function path(vals,w,h,max,pad=4){
  const v=vals.map(x=>x==null||isNaN(x)?null:+x);let last=0;const f=v.map(x=>x==null?last:(last=x));
  if(f.length<2)f.push(f[0]??0);
  const n=f.length,sx=w/(n-1),mx=max||Math.max(1,...f);
  const pts=f.map((y,i)=>[+(i*sx).toFixed(1),+(h-(Math.min(y,mx)/mx)*(h-pad)).toFixed(1)]);
  let d='M'+pts[0][0]+' '+pts[0][1];
  for(let i=0;i<n-1;i++){const a=pts[i],b=pts[i+1],cx=(b[0]-a[0])/2;d+=` C${(a[0]+cx).toFixed(1)} ${a[1]} ${(b[0]-cx).toFixed(1)} ${b[1]} ${b[0]} ${b[1]}`}
  const l=pts[n-1];return {line:d,area:d+` L${l[0]} ${h} L0 ${h} Z`};
}
function topo(useWifi,opts={}){
  const lanOn=!useWifi&&opts.online!==false, wifiOn=useWifi&&opts.online!==false, ink=opts.online===false?'#5A6178':useWifi?'#0F8F64':'#3550E8';
  const flow=on=>on?' class="flow"':'';
  return `<svg class="chart" viewBox="0 0 290 130" style="height:${opts.h||130}px" role="img" aria-label="${useWifi?'Router đang dùng WiFi nguồn':'Router dùng dây LAN'}">
  <path${flow(lanOn)} d="M48 32 C100 32 100 65 145 65" fill="none" stroke="${lanOn?'#fff':'rgba(255,255,255,.25)'}" stroke-width="3" stroke-dasharray="6 6" stroke-linecap="round"/>
  <path${flow(wifiOn)} d="M48 98 C100 98 100 65 145 65" fill="none" stroke="${wifiOn?'#fff':'rgba(255,255,255,.25)'}" stroke-width="3" stroke-dasharray="6 6" stroke-linecap="round"/>
  <path${flow(opts.online!==false)} d="M145 65 L242 65" fill="none" stroke="#fff" stroke-width="3" stroke-dasharray="6 6" stroke-linecap="round"/>
  <circle cx="32" cy="32" r="19" fill="${lanOn?'#fff':'rgba(255,255,255,.2)'}"/><g transform="translate(22 22) scale(.84)" fill="none" stroke="${lanOn?ink:'rgba(255,255,255,.7)'}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${IC.lan}</g>
  <circle cx="32" cy="98" r="19" fill="${wifiOn?'#fff':'rgba(255,255,255,.2)'}"/><g transform="translate(22 88) scale(.84)" fill="none" stroke="${wifiOn?ink:'rgba(255,255,255,.7)'}" stroke-width="2" stroke-linecap="round"><path d="M2 8.5a15 15 0 0 1 20 0M5 12a10 10 0 0 1 14 0M8.5 15.5a5 5 0 0 1 7 0"/></g>
  <circle cx="145" cy="65" r="26" fill="#fff"/><g transform="translate(131 51) scale(1.17)" fill="none" stroke="${ink}" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="13" width="18" height="7" rx="3"/><path d="M8 9a5.5 5.5 0 0 1 8 0M5.5 6.5a9 9 0 0 1 13 0"/></g>
  <circle cx="258" cy="65" r="19" fill="#fff"/><g transform="translate(248 55) scale(.84)" fill="none" stroke="${ink}" stroke-width="2" stroke-linecap="round">${IC.users}</g>
  <text x="32" y="64" text-anchor="middle" font-size="10" fill="rgba(255,255,255,.85)">Dây LAN</text><text x="32" y="128" text-anchor="middle" font-size="10" fill="rgba(255,255,255,.85)">WiFi nguồn</text>
  <text x="258" y="98" text-anchor="middle" font-size="10" fill="rgba(255,255,255,.85)">${esc(opts.guests??'Khách')}</text></svg>`;
}
function donut(val,max,label){const p=max>0?Math.min(1,val/max):Math.min(1,val/50);return `<svg width="112" height="112" viewBox="0 0 112 112" role="img" aria-label="${esc(label)}" style="flex:none"><circle cx="56" cy="56" r="46" fill="none" stroke="#EEF1FE" stroke-width="12"/><circle cx="56" cy="56" r="46" fill="none" stroke="#4360F5" stroke-width="12" stroke-linecap="round" stroke-dasharray="${(289*p).toFixed(1)} 289" transform="rotate(-90 56 56)" style="transition:stroke-dasharray .6s ease"/><text x="56" y="58" text-anchor="middle" font-family="Lexend,sans-serif" font-size="28" font-weight="500" fill="#1B2036">${val}</text><text x="56" y="76" text-anchor="middle" font-size="11" fill="#6A7189">/ ${max>0?max:'∞'} khách</text></svg>`}
function gauge(pct,color,v,l,s,limit){const a=(214*Math.min(100,Math.max(0,pct))/100).toFixed(1);let ln='';if(limit){const ang=(-90+360*limit/100)*Math.PI/180;ln=`<line x1="${(42+27*Math.cos(ang)).toFixed(1)}" y1="${(42+27*Math.sin(ang)).toFixed(1)}" x2="${(42+41*Math.cos(ang)).toFixed(1)}" y2="${(42+41*Math.sin(ang)).toFixed(1)}" stroke="#1B2036" stroke-width="2" stroke-linecap="round"/>`}
  return `<div style="display:flex;flex-direction:column;align-items:center;gap:4px;min-width:0"><svg width="84" height="84" viewBox="0 0 84 84" role="img" aria-label="${esc(l)} ${esc(v)}"><circle cx="42" cy="42" r="34" fill="none" stroke="#F2F4F8" stroke-width="9"/><circle cx="42" cy="42" r="34" fill="none" stroke="${color}" stroke-width="9" stroke-linecap="round" stroke-dasharray="${a} 214" transform="rotate(-90 42 42)"/>${ln}<text x="42" y="47" text-anchor="middle" font-family="Lexend,sans-serif" font-size="17" font-weight="500" fill="#1B2036">${esc(v)}</text></svg><div style="font-size:12px;font-weight:500">${esc(l)}</div><div style="font-size:10px;color:var(--mute);text-align:center">${esc(s)}</div></div>`}
function sigBars(dbm){if(dbm==null)return '<span class="sig"><i></i><i></i><i></i><i></i></span>';const l=dbm>=-58?4:dbm>=-67?3:dbm>=-76?2:1;return `<span class="sig l${l}" aria-label="Sóng ${l}/4"><i></i><i></i><i></i><i></i></span>`}

/* ---------- toast, sheet ---------- */
let toastT=0;
function toast(msg,err){const old=$('#toast');if(old)old.remove();clearTimeout(toastT);const d=document.createElement('div');d.id='toast';d.className='toast'+(err?' err':'');d.setAttribute('role','status');d.innerHTML=ico(err?'alert':'check')+`<span>${esc(msg)}</span>`;document.body.appendChild(d);toastT=setTimeout(()=>d.remove(),3600)}
function sheet(html,onClose){
  closeSheet();const w=document.createElement('div');w.className='sheet';w.id='sheet';w.innerHTML=`<div class="sheet-card" role="dialog" aria-modal="true">${html}</div>`;
  w.addEventListener('click',e=>{if(e.target===w&&!w.dataset.lock)closeSheet()});document.body.appendChild(w);w._close=onClose;
  const f=$('input,button.btn.pri',w);if(f&&window.innerWidth>=720)setTimeout(()=>f.focus(),60);return $('.sheet-card',w);
}
function closeSheet(){const w=$('#sheet');if(w){const c=w._close;w.remove();if(c)c()}}
document.addEventListener('keydown',e=>{if(e.key==='Escape'){const w=$('#sheet');if(w&&!w.dataset.lock)closeSheet()}});
function confirmSheet(o){return new Promise(res=>{const c=sheet(`<span class="ic" style="width:52px;height:52px;background:${o.tint||'var(--accS)'};color:${o.ink||'var(--acc)'}">${ico(o.icon||'alert','width:24px;height:24px')}</span><div class="h" style="font-size:22px">${esc(o.title)}</div><div style="font-size:14px;color:var(--ink2);line-height:1.55">${esc(o.text)}</div><div class="two"><button class="btn" data-no>Huỷ</button><button class="btn ${o.danger?'danger':'pri'}" data-yes>${esc(o.ok||'Đồng ý')}</button></div>`,()=>res(false));$('[data-no]',c).onclick=()=>closeSheet();$('[data-yes]',c).onclick=()=>{const w=$('#sheet');w._close=null;w.remove();res(true)}})}

/* ---------- shell ---------- */
function shell(){
  const nav=NAV.map(([id,l,i])=>`<button type="button" data-go="${id}"${S.page===id?' class="on" aria-current="page"':''}><span class="ib">${ico(i)}</span><span class="l">${l}</span></button>`).join('');
  $('#sideNav').innerHTML=nav;
  $('#tabbar').innerHTML=NAV.map(([id,l,i])=>`<button type="button" data-go="${id}" aria-label="${l}"${S.page===id?' class="on" aria-current="page"':''}>${ico(i,'width:21px;height:21px')}<span>${l}</span></button>`).join('');
  $$('[data-go]').forEach(b=>b.onclick=()=>go(b.dataset.go));
  head();
}
function livePill(){
  const st=S.st||{},h=(S.ov||{}).health||{};
  if(st.safe_mode)return ['Chế độ an toàn','warn'];
  if(!+st.internet_live)return ['Mất Internet','bad'];
  if(st.sched_closed)return ['Ngoài giờ phục vụ','warn'];
  if(st.internet_mode==='auto'&&st.uplink_active==='wifi')return ['Dự phòng',''];
  return ['Hoạt động',''];
}
function head(){
  const st=S.st||{},t=TITLES[S.page]||['Wiflow',''],[pt,pc]=livePill();
  let sub=t[1];if(S.page==='status'&&S.ov)sub=`Cập nhật trực tiếp · tự kiểm tra lúc ${hhmm(S.ov.now)}`;
  $('#dTitle').textContent=t[0];$('#dSub').textContent=sub;
  $('#mTitle').textContent=S.page==='status'?'Wiflow':t[0];$('#mSub').textContent=devCode(st.device_id);
  ['#dPill','#mPill'].forEach(s=>{const p=$(s);p.className='pill'+(pc?' '+pc:'');p.innerHTML=`<span class="dot${pc?' '+(pc==='bad'?'bad':'warn'):''}"></span><span>${pt}</span>`});
  $('#devName').textContent=devCode(st.device_id);$('#devVer').textContent=`Wiflow ${st.version||''}${st.os?' · Wiflow OS '+st.os:''}`;
  $('#devDot').className='dot'+(pc?' '+(pc==='bad'?'bad':'warn'):'');
  document.title=t[0]+' · Wiflow';
}
function go(p,force){
  if(S.page==='guest'&&S.draft&&dirty()&&p!=='guest'&&!force){confirmSheet({title:'Bỏ thay đổi?',text:'Cài đặt WiFi khách chưa lưu sẽ mất.',ok:'Bỏ thay đổi',danger:true}).then(y=>{if(y){S.draft=null;go(p,true)}});return}
  if(location.hash!=='#'+p)history.replaceState(null,'','#'+p);
  const changed=S.page!==p;S.page=p;if(changed){S.draft=null;$('#body').scrollTop=0}
  shell();render(true);
  if(p==='internet'){loadInet();if(!S.scan.list||Date.now()-S.scan.at>120000)scan()}
  if(p==='guest')loadGuest();
  if(p==='system')loadLog();
}
function render(enter){
  if(S.wiz){renderWizard();return}
  $('#shell').classList.remove('wizmode');
  const v=$('#view');const f={status:vStatus,internet:vInternet,guest:vGuest,system:vSystem}[S.page]||vStatus;
  const html=f();if(!enter&&html===S.lastRender)return;S.lastRender=html;
  const sc=$('#body').scrollTop,rail=$('.rail',v),rs=rail?rail.scrollLeft:0;
  v.style.animation=enter?'':'none';v.innerHTML=html;if(enter){void v.offsetWidth;v.style.animation=''}
  $('#body').scrollTop=sc;const r2=$('.rail',v);if(r2&&!enter)r2.scrollLeft=rs;
  bind[S.page]&&bind[S.page](v);
  $$('[data-luci]',v).forEach(a=>a.onclick=e=>{e.preventDefault();location.href=LUCI});
}
const bind={};

/* ---------- data ---------- */
async function refreshStatus(){try{const s=await api('status',{},10000);S.st=s;S.csrf=s.csrf||S.csrf;head();return s}catch(e){if(e.message==='auth')throw e;return null}}
async function refreshOverview(){try{const o=await api('overview',{},15000);if(o&&o.ok){S.ov=o;head()}}catch(e){}}
async function loadInet(){try{const r=await api('inet',{},10000);if(r.ok){S.inet=r;if(S.page==='internet')render()}}catch(e){}}
async function loadGuest(){try{const r=await api('guest_get',{},10000);if(r.ok){S.guest=r;if(!S.draft||!dirty())S.draft=draftFrom(r);if(S.page==='guest')render()}}catch(e){}}
async function loadLog(){try{const r=await api('log',{},10000);if(r.ok){S.log=r.log;if(S.page==='system')render()}}catch(e){}}
function editing(){const a=document.activeElement;return $('#sheet')||(a&&/INPUT|TEXTAREA|SELECT/.test(a.tagName))}
let tick=0;
async function loop(){
  for(;;){
    await sleep(5000);if(document.hidden)continue;tick++;
    await refreshStatus();
    if(tick%6===0)await refreshOverview();
    if(S.page==='internet'&&tick%3===0)await loadInet();
    if(S.page==='guest'&&tick%3===0&&S.guest){try{const r=await api('guest_get',{},8000);if(r.ok)S.guest=r}catch(e){}}
    if(S.page==='system'&&tick%6===0)await loadLog();
    if(!editing()&&!S.wiz)render();
  }
}

/* ================= TRẠNG THÁI ================= */
function vStatus(){
  const st=S.st||{},ov=S.ov||{},h=ov.health||{},g=ov.guest||{},mins=ov.minutes||[],day=ov.day||{runs:[],q:[]};
  const online=!!+st.internet_live,wifi=st.uplink_active==='wifi'||(st.internet_mode==='wifi'),guests=+st.clients_now||0,max=+g.max||0;
  const cls=!online?'off':wifi?'wifi':'';
  const title=!online?'Mất Internet':wifi?'Qua WiFi nguồn':'Qua dây LAN';
  const pings=mins.map(m=>m.p),lastPing=h.ping_ms||pings.filter(x=>x!=null).slice(-1)[0];
  const pp=path(pings.length?pings:[0,0],290,40,Math.max(40,...pings.filter(x=>x!=null)),4);
  const banners=[];
  if(st.safe_mode)banners.push(['warn','Chế độ an toàn','Cổng chào gặp lỗi, khách đang được dùng Internet trực tiếp. Wiflow sẽ tự bật lại sau ít phút.']);
  if(st.sched_closed)banners.push(['warn','Ngoài giờ phục vụ','Khách vẫn bắt được WiFi nhưng Internet đang tạm dừng theo lịch.']);
  if(!+st.paired)banners.push(['info','Chưa liên kết tài khoản','Liên kết để theo dõi và điều khiển router từ app Wiflow.','system']);
  if(st.reboot_required)banners.push(['info','Đã cài bản Wiflow mới','Khởi động lại router để chạy bản mới.','system']);
  // guests by hour today
  const now=ov.now||Date.now()/1000,mid=new Date(now*1000);mid.setHours(0,0,0,0);const m0=mid.getTime()/1000;
  // guests per hour, last 12 hours (peak of each hour)
  const hl=[];for(let k=11;k>=0;k--){const t=Math.floor(now/3600)*3600-k*3600,x=(ov.hours||[]).find(y=>+y.hour===t);hl.push({t,v:x?+x.peak:0})}
  const gh=path(hl.map(x=>x.v),290,70,Math.max(4,...hl.map(x=>x.v)),6);
  const ghAxis=[0,3,6,9,11].map(i=>`<span>${new Date(hl[i].t*1000).getHours()}h</span>`).join('');
  // 24h timeline
  const runs=day.runs||[],span=runs.length?runs[runs.length-1].to-runs[0].from:0;
  const colOf=u=>u==='lan'?'#4360F5':u==='wifi'?'#1BAF7A':'#F2A15C';
  const tl=runs.map(r=>`<span title="${r.u==='lan'?'Dây LAN':r.u==='wifi'?'WiFi nguồn':'Mất mạng'} · ${hhmm(r.from)}–${hhmm(r.to)}" style="flex:${Math.max(1,r.to-r.from)};background:${colOf(r.u)}"></span>`).join('')||'<span style="flex:1;background:#EEF1FE"></span>';
  const upSec=runs.filter(r=>r.u!=='none').reduce((a,r)=>a+(r.to-r.from),0),upPct=span?Math.round(upSec*100/span):100;
  const evs=(ov.log||[]).filter(l=>['uplink','content','safe','watchdog'].includes(l.a)).slice(0,3);
  const evc={uplink:'#F2A15C',content:'#8B7BF0',safe:'#E5484D',watchdog:'#34C08A'};
  // usage bars by hour (last 9 hours)
  const hrs=(ov.hours||[]).slice(-9),umax=Math.max(1,...hrs.map(x=>+x.rx+ +x.tx)),uH=window.innerWidth<720?96:130,sel=S.usageSel;
  const total=(ov.hours||[]).filter(x=>x.hour>=m0).reduce((a,x)=>a+ +x.rx+ +x.tx,0);
  const usage=hrs.map((x,i)=>`<button type="button" data-u="${i}" class="${sel===i?'on':''}" aria-label="${new Date(x.hour*1000).getHours()}h: ${bytes(+x.rx+ +x.tx)}"><span style="height:${Math.max(3,Math.round((+x.rx+ +x.tx)/umax*(uH-4)))}px"></span></button>`).join('');
  const ucap=sel>=0&&hrs[sel]?`${new Date(hrs[sel].hour*1000).getHours()}h · ${bytes(+hrs[sel].rx+ +hrs[sel].tx)}`:`Hôm nay ${bytes(total)}`;
  const mem=h.mem_total_kb?Math.round((h.mem_total_kb-h.mem_free_kb)*100/h.mem_total_kb):0,stg=ov.storage||{},mediaPct=stg.total?Math.round((stg.total-stg.free)*100/stg.total):0;
  const cpu=Math.min(100,Math.round((+h.load||0)*25)),incidents=+h.watchdog_restarts||0;
  const healthChip=st.safe_mode?'<span class="chip warn">An toàn</span>':incidents?'<span class="chip warn">Đã tự sửa</span>':'<span class="chip">Ổn định</span>';
  return `
  ${banners.map(b=>`<div class="banner ${b[0]==='info'?'info':''}"${b[3]?` data-go2="${b[3]}" style="cursor:pointer"`:''}>${ico(b[0]==='info'?'link':'alert')}<div><b>${esc(b[1])}</b><span>${esc(b[2])}</span></div></div>`).join('')}
  <div>
   <div class="rail" id="rail">
    <div class="card blue net ${cls}">
      <div class="ch"><div><div class="w8" style="font-size:13px">Internet</div><div class="num" style="font-size:24px">${title}</div></div><div style="text-align:right"><div class="num" style="font-size:24px">${online&&lastPing?lastPing+' ms':'—'}</div><div class="w8" style="font-size:11px">độ trễ</div></div></div>
      ${topo(wifi,{online,guests:guests+' khách',h:window.innerWidth>=720&&window.innerWidth<1180?170:130})}
      <div class="ch" style="flex-wrap:nowrap"><div class="w8" style="font-size:12px;flex:1;min-width:0">${st.internet_mode==='auto'?'Tự động · dây trước, WiFi dự phòng':st.internet_mode==='wifi'?'Chỉ WiFi nguồn':st.internet_mode==='lan'?'Chỉ dây LAN':'Chưa cấu hình'}</div><div class="w8" style="font-size:12px;flex:none;white-space:nowrap">Độ trễ 60 phút</div></div>
      <svg class="chart" viewBox="0 0 290 40" preserveAspectRatio="none" style="height:42px" role="img" aria-label="Độ trễ 60 phút qua"><path d="${pp.area}" fill="rgba(255,255,255,.14)"/><path d="${pp.line}" fill="none" stroke="#fff" stroke-width="2" vector-effect="non-scaling-stroke"/></svg>
    </div>
    <div class="card">
      <div class="ch"><div class="k">Khách</div>${st.sched_closed?'<span class="chip warn">Ngoài giờ</span>':''}</div>
      <div style="display:flex;align-items:center;gap:14px 18px;flex-wrap:wrap">${donut(guests,max,`${guests} khách đang dùng`)}
        <div style="display:flex;flex-direction:column;gap:10px;min-width:0;flex:1 1 128px"><div><div class="num" style="font-size:24px">${+st.clients_today||0}</div><div class="note" style="padding:0">lượt hôm nay</div></div>
        <div><div class="num" style="font-size:16px">${g.down_kbps||g.session_min?`${g.down_kbps?mbps(g.down_kbps):'Không giới hạn'} · ${g.session_min?minutes(g.session_min):'không giới hạn'}`:'Không giới hạn'}</div><div class="note" style="padding:0">${g.down_kbps||g.session_min?'mỗi khách · mỗi lượt':'tốc độ và thời gian'}</div></div></div></div>
      <svg class="chart" viewBox="0 0 290 70" preserveAspectRatio="none" style="height:70px" role="img" aria-label="Khách theo giờ, 12 giờ qua"><path d="${gh.area}" fill="rgba(67,96,245,.12)"/><path d="${gh.line}" fill="none" stroke="#4360F5" stroke-width="2.5" vector-effect="non-scaling-stroke"/></svg>
      <div class="axis">${ghAxis}</div>
    </div>
    <div class="card">
      <div class="ch"><div class="k">Sức khỏe router</div>${healthChip}</div>
      <div class="row3" style="gap:6px">${gauge(mem,'#4360F5',mem+'%','RAM',h.mem_total_kb?memPair(h.mem_total_kb-h.mem_free_kb,h.mem_total_kb):'')}${gauge(mediaPct,'#7B61FF',mediaPct+'%','Bộ nhớ',stg.total?'còn '+bytes(stg.free):'')}${gauge(cpu,'#1BAF7A',cpu+'%','CPU','TB 1 phút')}</div>
      <div class="row2"><div class="stat"><b>${upt(st.uptime)}</b><span>Hoạt động liên tục</span></div><div class="stat"><b>${incidents} sự cố</b><span>Tự sửa · từ khi khởi động</span></div></div>
    </div>
   </div>
   <div class="dots" id="dots">${[0,1,2].map(i=>`<i class="${S.card===i?'on':''}"></i>`).join('')}</div>
  </div>
  <div class="grid">
    <div class="card s2">
      <div class="ch"><h3>Kết nối 24 giờ</h3><div class="note">Có mạng ${upPct}%</div></div>
      <div class="timeline">${tl}</div>
      <div class="axis"><span>${runs.length?when(runs[0].from,now):''}</span><span>Bây giờ</span></div>
      <div class="legend"><span><i style="background:#4360F5"></i>Dây LAN</span><span><i style="background:#1BAF7A"></i>WiFi nguồn</span><span><i style="background:#F2A15C"></i>Mất mạng</span></div>
      <div style="height:1px;background:var(--line)"></div>
      ${evs.length?evs.map(e=>`<div class="ev"><i style="background:${evc[e.a]}"></i><div>${esc(e.m)}</div><small>${when(e.t,now)}</small></div>`).join(''):'<div class="note">Chưa có sự kiện nào.</div>'}
    </div>
    <div class="card">
      <div class="ch"><h3>Dữ liệu khách dùng</h3><div class="note" id="ucap">${ucap}</div></div>
      <div class="bars${sel>=0?' sel':''}" id="usage" style="height:${uH}px">${usage||'<div class="note">Chưa có dữ liệu</div>'}</div>
      <div class="axis">${hrs.length?[0,Math.floor(hrs.length/2),hrs.length-1].map(i=>`<span>${new Date(hrs[i].hour*1000).getHours()}h</span>`).join(''):''}</div>
    </div>
    <div class="quick mt">
      <button type="button" data-q="check"><span class="ic" style="background:var(--accS);color:var(--acc)">${ico('refresh','width:19px;height:19px')}</span>Kiểm tra</button>
      <button type="button" data-q="reboot"><span class="ic" style="background:var(--bg)">${ico('power','width:19px;height:19px')}</span>Khởi động lại</button>
      <button type="button" data-q="luci"><span class="ic" style="background:var(--lilac);color:var(--lilacI)">${ico('code','width:19px;height:19px')}</span>Nâng cao</button>
    </div>
  </div>`;
}
bind.status=v=>{
  const rail=$('#rail',v);if(rail)rail.onscroll=()=>{if(window.innerWidth>=720)return;const w=rail.firstElementChild.getBoundingClientRect().width+12,i=Math.round(rail.scrollLeft/w);if(i!==S.card){S.card=i;$$('#dots i',v).forEach((d,k)=>d.classList.toggle('on',k===i))}};
  $$('[data-u]',v).forEach(b=>{const f=()=>{S.usageSel=+b.dataset.u;render()};b.onmouseenter=f;b.onclick=f});
  const u=$('#usage',v);if(u)u.onmouseleave=()=>{if(S.usageSel>=0){S.usageSel=-1;render()}};
  $$('[data-go2]',v).forEach(b=>b.onclick=()=>go(b.dataset.go2));
  $$('[data-q]',v).forEach(b=>b.onclick=()=>{const q=b.dataset.q;if(q==='luci')location.href=LUCI;else if(q==='reboot')go('system');else netCheck()});
};
async function netCheck(){
  toast('Đang kiểm tra Internet…');
  try{const r=await api('netcheck',{},20000);if(r.internet)toast(`Internet ổn · ${r.ping} ms · ${r.loss}% mất gói · DNS ${r.dns?'ổn':'lỗi'}`);else toast('Chưa ra được Internet. Kiểm tra modem hoặc WiFi nguồn.',true);refreshStatus()}catch(e){toast('Không kiểm tra được',true)}
}

/* ================= INTERNET ================= */
function modeIdx(m){return m==='auto'?0:m==='lan'?1:m==='wifi'?2:-1}
function vInternet(){
  const st=S.st||{},inet=S.inet||{},ov=S.ov||{},mins=ov.minutes||[];
  const m=S.pend&&S.pend!=='wifi-pick'?modeIdx(S.pend):modeIdx(st.internet_mode),useWifi=m===2||(m===0&&st.uplink_active==='wifi'),online=!!+st.internet_live;
  const hints=['Có dây thì dùng dây. Mất dây hoặc dây mất Internet thì tự chuyển WiFi nguồn, có lại thì tự quay về.','Chỉ dùng dây LAN cắm vào cổng WAN. Mất dây thì router báo mất Internet.','Chỉ dùng WiFi nguồn, không dùng cổng WAN.'];
  const pv=mins.map(x=>x.p).filter(x=>x!=null).slice(-15),avg=pv.length?Math.round(pv.reduce((a,b)=>a+b,0)/pv.length):null;
  const jit=pv.length>1?Math.round(pv.slice(1).reduce((a,b,i)=>a+Math.abs(b-pv[i]),0)/(pv.length-1)):null;
  const lossN=mins.slice(-15).filter(x=>x.p==null).length,loss=mins.length?Math.round(lossN*100/Math.min(15,mins.length)):0;
  const q=S.nc||{ping:avg,jitter:jit,loss};
  const score=!online||q.ping==null?0:Math.max(0,Math.min(100,Math.round(100-Math.max(0,(q.ping||0)-15)*.6-(q.jitter||0)*1.5-(q.loss||0)*2)));
  const wan=inet.wan||{},wwan=inet.wwan||{},saved=inet.wifi_ssid||'';
  const lanChip=m===2?['Tắt','off']:wan.up?[st.uplink_active==='lan'?(m===0?'Đang dùng · ưu tiên 1':'Đang dùng'):'Sẵn sàng','']:['Chưa cắm dây','off'];
  const nets=(S.scan.list||[]);
  const day=ov.day||{q:[]},lq=day.q||[],lv=lq.map(x=>x.p),lmax=Math.max(40,...lv.filter(x=>x!=null)),lp=path(lv.length>1?lv:[0,0],600,120,lmax,6);
  const t0=lq.length?lq[0].t:0,t1=lq.length?lq[lq.length-1].t:1,sw=(day.runs||[]).slice(1).filter(r=>r.u!=='none').map(r=>((r.from-t0)/Math.max(1,t1-t0)*600).toFixed(1));
  const lavg=lv.filter(x=>x!=null);const lav=lavg.length?Math.round(lavg.reduce((a,b)=>a+b,0)/lavg.length):0;
  return `
  <div class="grid">
    <div class="card blue s2 ${useWifi?'wifi':''} ${online?'':'off'}" style="gap:14px">
      <div class="seg" role="radiogroup" aria-label="Cách kết nối">${['Tự động','Chỉ dây','Chỉ WiFi'].map((l,i)=>`<button type="button" role="radio" aria-checked="${m===i}" data-mode="${['auto','lan','wifi'][i]}">${l}</button>`).join('')}</div>
      <div style="font-size:13px;color:rgba(255,255,255,.85)">${m>=0?hints[m]:'Chọn cách router lấy Internet.'}${S.pend==='auto'&&!saved?' Chọn một WiFi nguồn bên dưới làm dự phòng.':''}</div>
      <div class="inet-row">
        <div style="flex:1;min-width:0;width:100%">${topo(useWifi,{online,h:window.innerWidth<720?130:180})}</div>
        <div class="gauge"><svg width="200" height="116" viewBox="0 0 200 116" role="img" aria-label="Chất lượng kết nối ${score} trên 100"><path d="M20 100 A80 80 0 0 1 180 100" fill="none" stroke="rgba(255,255,255,.18)" stroke-width="16" stroke-linecap="round"/><path d="M20 100 A80 80 0 0 1 180 100" fill="none" stroke="#fff" stroke-width="16" stroke-linecap="round" stroke-dasharray="${(252*score/100).toFixed(1)} 252" style="transition:stroke-dasharray .4s ease"/><text x="100" y="88" text-anchor="middle" font-family="Lexend,sans-serif" font-size="34" font-weight="500" fill="#fff">${online&&q.ping!=null?score:'—'}</text><text x="100" y="108" text-anchor="middle" font-size="11" fill="rgba(255,255,255,.8)">chất lượng / 100</text></svg>
          <button type="button" class="wbtn" id="recheck">${ico('refresh','width:14px;height:14px')}Kiểm tra lại</button></div>
      </div>
      <div class="row3"><div class="stat"><b>${q.ping!=null&&online?q.ping+' ms':'—'}</b><span>Độ trễ</span></div><div class="stat"><b>${q.jitter!=null&&online?q.jitter+' ms':'—'}</b><span>Dao động</span></div><div class="stat"><b>${online?(q.loss||0)+'%':'—'}</b><span>Mất gói</span></div></div>
    </div>
    <div class="card ${m===2?'muted-card':''}">
      <div style="display:flex;align-items:center;gap:8px 12px;flex-wrap:wrap"><span class="ic" style="width:44px;height:44px;background:var(--accS);color:var(--acc)">${ico('lan')}</span><div style="flex:1 1 120px;min-width:0"><div style="font-size:16px;font-weight:500">Dây LAN</div><div class="note" style="padding:0">Cắm vào cổng WAN</div></div><span class="chip ${lanChip[1]}">${lanChip[0]}</span></div>
      ${[['Địa chỉ',wan.addr||'—'],['Cổng mặc định',wan.gw||'—'],['DNS',wan.dns||'Tự động'],['Tốc độ cổng',wan.speed?(wan.speed>=1000?wan.speed/1000+' Gbps':wan.speed+' Mbps'):'—']].map(r=>`<div class="kv"><span>${r[0]}</span><span>${esc(r[1])}</span></div>`).join('')}
      ${m!==1?`<button class="btn sm" data-mode="lan" style="align-self:flex-start">Chỉ dùng dây</button>`:''}
    </div>
    <div class="card ${m===1?'muted-card':''}" style="padding:18px 10px 10px;gap:4px">
      <div style="display:flex;align-items:center;gap:12px;padding:0 8px 10px"><span class="ic" style="width:44px;height:44px;background:var(--mint);color:var(--mintI)">${ico('wifi')}</span><div style="flex:1;min-width:0"><div style="font-size:16px;font-weight:500">WiFi nguồn</div><div class="note" style="padding:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${saved?`Đã lưu “${esc(saved)}”${inet.wifi_signal!=null?` · ${inet.wifi_signal} dBm`:''}`:'Chạm một mạng để kết nối'}</div></div><button type="button" class="btn ghost" id="rescan" style="color:var(--acc);height:36px;padding:0 6px">${S.scan.busy?'<span class="spin"></span>':'Quét lại'}</button></div>
      <div class="nets">${nets.length?nets.map((n,i)=>{const cur=saved&&n.ssid===saved&&(!inet.wifi_band||n.band===inet.wifi_band);return `<button type="button" class="net-i${cur?' on':''}" data-net="${i}">${sigBars(n.signal)}<div class="n"><b>${esc(n.ssid)}</b><span>${cur?`Đã lưu · ${m===1?'tắt':m===2?'đang dùng':st.uplink_active==='wifi'?'đang dùng':'dự phòng'}`:n.enc==='none'?'Mạng mở':'Có mật khẩu'} · ${n.band==='5g'?'5 GHz':'2.4 GHz'}${n.recommended?' · <em class="rec">Nên dùng</em>':''}${n.dfs?' · DFS':''}${n.weak?' · Sóng yếu':''}</span></div><span class="db">${n.signal!=null?n.signal+' dBm':''}</span><span class="tick">${ico(cur?'check':n.enc==='none'?'wifi':'lock')}</span></button>`}).join(''):`<div class="note" style="padding:10px 12px">${S.scan.busy?'Đang tìm WiFi xung quanh…':'Chưa thấy mạng nào. Bấm Quét lại.'}</div>`}
        <button type="button" class="net-i" data-net="hidden"><span class="sig" style="opacity:.4"><i></i><i></i><i></i><i></i></span><div class="n"><b>Mạng ẩn</b><span>Tự nhập tên WiFi</span></div><span class="tick">${ico('plus')}</span></button>
      </div>
    </div>
    <div class="card s2">
      <div class="ch"><h3>Độ trễ 24 giờ</h3><div class="note">${lav?`TB ${lav} ms · `:''}vạch cam là lúc đổi đường</div></div>
      <div style="position:relative"><svg class="chart" viewBox="0 0 600 120" preserveAspectRatio="none" style="height:${window.innerWidth<720?110:150}px" role="img" aria-label="Độ trễ 24 giờ qua">
        <line x1="0" y1="40" x2="600" y2="40" stroke="#EEF0F4" vector-effect="non-scaling-stroke"/><line x1="0" y1="80" x2="600" y2="80" stroke="#EEF0F4" vector-effect="non-scaling-stroke"/>
        ${sw.map(x=>`<line x1="${x}" y1="0" x2="${x}" y2="120" stroke="#F2A15C" stroke-width="2" stroke-dasharray="4 4" vector-effect="non-scaling-stroke"/>`).join('')}
        <path d="${lp.area}" fill="rgba(67,96,245,.10)"/><path d="${lp.line}" fill="none" stroke="#4360F5" stroke-width="2" vector-effect="non-scaling-stroke"/></svg>
        <span style="position:absolute;right:0;top:0;font-size:10px;color:var(--mute)">${lmax} ms</span></div>
      <div class="axis"><span>${lq.length?when(lq[0].t,ov.now):''}</span><span>Bây giờ</span></div>
    </div>
  </div>`;
}
bind.internet=v=>{
  $$('[data-mode]',v).forEach(b=>b.onclick=()=>pickMode(b.dataset.mode));
  $('#rescan',v).onclick=()=>scan();
  $('#recheck',v).onclick=async()=>{const b=$('#recheck');b.disabled=true;b.innerHTML='<span class="spin" style="border-color:rgba(255,255,255,.3);border-top-color:#fff"></span>Đang đo';try{const r=await api('netcheck',{},20000);S.nc=r.internet?r:null;toast(r.internet?`Chất lượng ổn · ${r.ping} ms`:'Chưa ra được Internet',!r.internet)}catch(e){}render()};
  $$('[data-net]',v).forEach(b=>b.onclick=()=>{const k=b.dataset.net;wifiSheet(k==='hidden'?null:S.scan.list[+k])});
};
async function scan(){
  if(S.scan.busy)return;S.scan.busy=true;if(S.page==='internet')render();
  const seen={},all=[];
  const put=()=>{all.sort((a,b)=>(b.current-a.current)||((b.signal??-200)-(a.signal??-200)));const sn={};return all.filter(n=>{const k=n.ssid+'|'+n.band;if(sn[k])return false;sn[k]=1;return true}).slice(0,24)};
  for(const band of ['5g','2g']){try{const r=await api('scan',{band},70000);if(r.ok===false&&r.error)toast(r.error,true);(r.networks||[]).forEach(n=>{if(n.ssid&&n.ssid!==(S.st||{}).guest_ssid)all.push(n)});if(band==='5g'&&all.length){S.scan.list=put();if((S.page==='internet'||S.wiz)&&!editing())render()}}catch(e){if(e.message==='auth')return}}
  all.sort((a,b)=>(b.current-a.current)||((b.signal??-200)-(a.signal??-200)));
  S.scan.list=put();S.scan.busy=false;S.scan.at=Date.now();
  if(S.page==='internet'||S.wiz)render();
}
async function pickMode(mode){
  const st=S.st||{},saved=(S.inet||{}).wifi_ssid||'';
  if(mode===st.internet_mode&&!S.pend)return;
  if(mode==='lan'){if(await confirmSheet({title:'Chỉ dùng dây LAN?',text:'Router chỉ lấy Internet qua dây cắm vào cổng WAN. WiFi nguồn đã lưu được giữ lại nhưng tắt.',ok:'Dùng dây LAN',icon:'lan'}))runConnect({mode:'lan'},'lan');return}
  if(saved){if(await confirmSheet({title:mode==='auto'?'Bật Internet tự động?':'Chỉ dùng WiFi nguồn?',text:mode==='auto'?`Dây LAN được ưu tiên. Mất dây hoặc dây mất Internet thì dùng WiFi “${saved}”.`:`Router chỉ dùng WiFi “${saved}”, không dùng cổng WAN.`,ok:'Áp dụng',icon:mode==='auto'?'globe':'wifi'}))runConnect({mode},mode);return}
  S.pend=mode;toast('Chọn một WiFi nguồn trong danh sách');render();
  const l=$('.nets');if(l)l.scrollIntoView({behavior:'smooth',block:'center'});
}
function wifiSheet(n){
  const open=n&&n.enc==='none',guest=(S.st||{}).guest_ssid||'';
  const c=sheet(`<div class="hd"><span class="ic" style="width:48px;height:48px;background:var(--mint);color:var(--mintI)">${ico(n?'wifi':'plus','width:22px;height:22px')}</span><div style="min-width:0"><b>${n?esc(n.ssid):'Mạng ẩn'}</b><span>${open?'Mạng mở':'Nhập mật khẩu mạng nguồn'}</span></div></div>
   ${n?'':`<input class="in" id="wSsid" placeholder="Tên WiFi" autocapitalize="none" spellcheck="false">`}
   ${open?'':`<div class="in-wrap"><input class="in" id="wPass" type="password" style="padding:0 52px 0 16px" placeholder="Mật khẩu" autocomplete="off"><button type="button" class="eye" id="wEye" aria-label="Hiện mật khẩu">${ico('eye')}</button></div>`}
   ${n&&n.dfs?`<div class="msg warn">Kênh DFS (${n.channel}): khi gặp radar router phải chờ khoảng 1 phút hoặc đổi kênh, WiFi khách 5 GHz ngắt theo. Nếu modem có cả 2.4 GHz, nên chọn 2.4 GHz.</div>`:''}
   ${n&&n.weak&&!n.dfs?`<div class="msg warn">Sóng yếu (${n.signal} dBm), dễ chập chờn. Nên đặt router gần modem hơn.</div>`:''}
   ${n&&n.ssid===guest?`<div class="msg warn">Mạng này trùng tên WiFi khách. Wiflow sẽ đổi WiFi khách thành “${esc(guest)} Free”.</div>`:''}
   <div class="msg info" style="font-size:12.5px">${ico('alert','width:16px;height:16px')}<span>Lần đầu bắt WiFi nguồn, WiFi của router khởi động lại khoảng 30 giây. Nếu bạn đang dùng WiFi khách, hãy kết nối lại rồi mở 10.0.0.1.</span></div>
   <div class="two"><button class="btn" data-no>Huỷ</button><button class="btn pri" data-yes>Kết nối</button></div>`);
  const eye=$('#wEye',c);if(eye)eye.onclick=()=>{const i=$('#wPass',c);i.type=i.type==='password'?'text':'password'};
  $('[data-no]',c).onclick=closeSheet;
  const go2=()=>{const ssid=n?n.ssid:($('#wSsid',c).value||'').trim(),pass=open?'':($('#wPass',c)||{}).value||'';
    if(!ssid){$('#wSsid',c).focus();return}if(!open&&pass.length<8){toast('Mật khẩu WiFi tối thiểu 8 ký tự',true);return}
    const st=S.st||{};let mode=S.pend==='auto'||S.pend==='wifi'?S.pend:(st.internet_mode==='wifi'?'wifi':'auto');if(S.wiz)mode=S.wiz.mode||'auto';
    runConnect({mode,band:n?n.band:'5g',radio:n?n.radio:'',ssid,bssid:n?n.bssid:'',password:pass,enc:n?n.enc:'psk2',guest_ssid:n&&n.ssid===guest?guest+' Free':''},'wifi',ssid)};
  $('[data-yes]',c).onclick=go2;$$('input',c).forEach(i=>i.onkeydown=e=>{if(e.key==='Enter')go2()});
}
const PH={wifi:[['preparing','Chuẩn bị'],['associating','Kết nối WiFi nguồn'],['dhcp','Nhận địa chỉ mạng'],['internet_check','Kiểm tra Internet']],lan:[['preparing','Chuẩn bị'],['dhcp','Nhận địa chỉ qua dây'],['internet_check','Kiểm tra Internet']]};
function stages(kind,phase,state){const list=PH[kind]||PH.wifi;let at=list.findIndex(p=>p[0]===phase);if(at<0)at=0;
  return `<ol class="stages">${list.map(([k,t],i)=>{let c='';if(state==='success'||i<at)c='done';else if(i===at)c=state==='failed'?'fail':'now';return `<li class="${c}"><span class="sd">${c==='done'?ico('check'):c==='fail'?ico('x'):c==='now'?'<span class="spin" style="width:14px;height:14px;border-width:2px"></span>':''}</span>${t}</li>`}).join('')}</ol>`}
async function runConnect(data,kind,ssid){
  const c=sheet(`<div class="hd"><span class="ic" style="width:48px;height:48px;background:var(--accS);color:var(--acc)">${ico(kind==='lan'?'lan':'wifi','width:22px;height:22px')}</span><div style="min-width:0"><b>${kind==='lan'?'Kiểm tra dây LAN':ssid?esc(ssid):'Đổi kiểu kết nối'}</b><span>Đang kết nối Internet</span></div></div><div id="stg">${stages(kind,'preparing','running')}</div><div id="jm" class="note">Giữ trang này mở. Nếu mất kết nối, hãy kết nối lại WiFi rồi mở 10.0.0.1.</div>`);
  $('#sheet').dataset.lock='1';S.pend='';
  const fail=(msg,code)=>{const tips={wifi_auth_failed:'Kiểm tra lại mật khẩu (phân biệt chữ hoa, chữ thường).',wifi_not_found:'Đặt router gần modem hơn hoặc thử băng tần khác.',internet_failed:'Modem có thể đang mất Internet.',dhcp_failed:'Khởi động lại modem rồi thử lại.',source_subnet_conflict:'Đổi dải địa chỉ modem nguồn.',no_backup_wifi:'Chọn một WiFi nguồn trước.'};
    $('#jm',c).outerHTML=`<div class="msg err">${esc(msg)}${tips[code]?' '+tips[code]:''}</div><div class="two"><button class="btn pri" data-close>Đóng</button></div>`;delete $('#sheet').dataset.lock;$('[data-close]',c).onclick=closeSheet};
  try{const r=await api('connect',data,10000);if(r.ok===false){$('#stg',c).innerHTML=stages(kind,'preparing','failed');fail(r.error||'Không bắt đầu được');return}}catch(e){}
  const t0=Date.now();
  for(;;){
    await sleep(2000);if(!$('#sheet'))return;
    try{const j=await api('job',{},8000);
      if(j.job==='success'){$('#stg',c).innerHTML=stages(kind,'internet_check','success');delete $('#sheet').dataset.lock;await refreshStatus();await loadInet();closeSheet();toast(j.message||'Đã kết nối Internet');if(S.wiz){S.wiz.step=3;renderWizard()}else render();return}
      if(j.job==='failed'){$('#stg',c).innerHTML=stages(kind,j.phase&&j.phase!=='failed'?j.phase:'preparing','failed');fail(j.message||'Không kết nối được',j.error_code);await refreshStatus();return}
      $('#stg',c).innerHTML=stages(kind,j.phase||'preparing','running');
      if(j.job==='idle'&&Date.now()-t0>20000){fail('Router chưa bắt đầu kết nối. Thử lại.');return}
    }catch(e){if(e.message==='auth')return}
    if(Date.now()-t0>200000){fail('Quá thời gian chờ. Kiểm tra lại kết nối.');return}
  }
}

/* ================= WIFI KHÁCH ================= */
const SPEEDS=[[5000,'5'],[10000,'10'],[20000,'20'],[0,'Tắt']],SESS=[[30,'30p'],[60,'1g'],[120,'2g'],[240,'4g'],[0,'Tắt']];
const PRESETS=['07:00-22:00','08:00-23:00','06:00-24:00','all','off'];
const DAYS=['T2','T3','T4','T5','T6','T7','CN'];
function weekFrom(g){
  if(g.sched_week)return g.sched_week.split(',').slice(0,7);
  const w=[],days=g.sched_days||'1234567',e=(g.sched_from||'07:00')+'-'+(g.sched_to||'22:00');for(let i=1;i<=7;i++)w.push(days.includes(String(i))?e:'off');return w;
}
function draftFrom(r){const g=r.settings||{};return {ssid:r.guest_ssid||'',down:+g.down_kbps||0,session:+g.session_min||0,max:+g.max||0,on:!!g.sched_enabled,week:weekFrom(g)}}
function dirty(){if(!S.draft||!S.guest)return false;return JSON.stringify(S.draft)!==JSON.stringify(draftFrom(S.guest))}
function dayLabel(e){if(e==='all')return 'Cả ngày';if(e==='off')return 'Nghỉ';const [a,b]=e.split('-');return a.replace(/^0/,'')+'–'+b.replace(/^0/,'')}
function dayBar(e){if(e==='all')return [[0,100]];if(e==='off')return [];const [a,b]=e.split('-').map(x=>{const [h,m]=x.split(':');return (+h*60+ +m)/14.4});return a<b?[[a,b-a]]:[[a,100-a],[0,b]]}
/* Guest WiFi bands: with a source WiFi the guests are only on the other band. */
const BAND={'2g':'2.4 GHz','5g':'5 GHz'};
function bandNote(st){const b=String(st.guest_bands||'').split(',').filter(x=>BAND[x]);if(!b.length)return '';
  const txt=b.length>1?'Phát ở 2.4 GHz và 5 GHz':`Phát ở ${BAND[b[0]]} · ${BAND[b[0]==='5g'?'2g':'5g']} dùng để bắt WiFi nguồn`;
  return `<div class="note gband" data-wrap-ok>${txt}</div>`}
function vGuest(){
  const r=S.guest,d=S.draft,st=S.st||{},ov=S.ov||{};
  if(!r||!d)return `<div class="card" style="flex-direction:row;align-items:center"><span class="spin"></span>Đang tải</div>`;
  const live=(ov.minutes||[]).map(x=>x.g),g60=path(live.length>1?live:[0,0],290,64,Math.max(4,Math.ceil(Math.max(...live,0)*1.25)),6);
  const sp=SPEEDS.find(x=>x[0]===d.down),ss=SESS.find(x=>x[0]===d.session);
  const chip=(list,cur,key)=>list.map(([v,l])=>`<button type="button" aria-pressed="${v===cur}" data-${key}="${v}">${l}</button>`).join('');
  let qr='';try{qr=WFQR.svg(WFQR.wifi(d.ssid||'Wiflow'),{label:'Mã QR WiFi khách',quiet:1})}catch(e){}
  return `
  <div class="grid">
    <div class="card s2 gname">
      <div class="gname-in">
        <label class="lbl" for="ssid">Tên WiFi khách</label>
        <input id="ssid" class="in" maxlength="32" value="${esc(d.ssid)}" style="font-weight:500">
        <div class="note" data-wrap-ok>Mạng mở · khách vào thẳng Internet, không thấy nhau và không vào được mạng quản trị</div>${bandNote(st)}
      </div>
      <div class="gname-qr"><button type="button" class="qr" id="qrBig" style="border:0;cursor:pointer" aria-label="Phóng to mã QR">${qr}</button><span style="font-size:11px;color:var(--acc);font-weight:500">Mã QR</span></div>
    </div>
    <div class="card blue" style="gap:10px">
      <div class="ch"><div class="w8" style="font-size:13px">Đang dùng · 60 phút</div><div style="display:flex;align-items:center;gap:6px;font-size:12px"><span class="dot" style="background:#6EE7B7"></span>Trực tiếp</div></div>
      <div style="display:flex;align-items:baseline;gap:8px"><div class="num" style="font-size:42px;font-weight:400;line-height:1">${r.clients_now||0}</div><div class="w8" style="font-size:13px">/ ${d.max||'∞'} khách</div></div>
      <svg class="chart" viewBox="0 0 290 64" preserveAspectRatio="none" style="height:64px" role="img" aria-label="Số khách 60 phút qua"><path d="${g60.area}" fill="rgba(255,255,255,.16)"/><path d="${g60.line}" fill="none" stroke="#fff" stroke-width="2.5" vector-effect="non-scaling-stroke"/></svg>
    </div>
    <div class="banner info full">${ico('clock')}<div><b>Giới hạn và giờ phục vụ: sắp có</b><span>Cần trang chào Wiflow, có ở bản cập nhật sau. Hiện khách dùng không giới hạn.</span></div></div>
    <div class="card na">
      <div class="ch"><div class="lbl" style="padding:0">Tốc độ mỗi khách</div><div class="num" style="font-size:20px">${mbps(d.down)}</div></div>
      <div class="chips">${chip(SPEEDS,sp?d.down:-1,'down')}</div>
      <div class="meter"><span style="flex:${d.down?Math.min(100,d.down/1000):100};background:#4360F5"></span><span style="flex:${d.down?100-Math.min(100,d.down/1000)+.01:.01};background:#EEF1FE"></span></div>
      <div class="note">Tải lên bằng nửa tốc độ tải xuống · thanh so với đường truyền 100 Mbps</div>
    </div>
    <div class="card na">
      <div class="ch"><div class="lbl" style="padding:0">Thời gian mỗi lượt</div><div class="num" style="font-size:20px">${minutes(d.session)}</div></div>
      <div class="chips">${chip(SESS,ss?d.session:-1,'sess')}</div>
      <div class="meter"><span style="flex:${d.session?Math.min(240,d.session):240};background:#4360F5"></span><span style="flex:${d.session?240-Math.min(240,d.session)+.01:.01};background:#EEF1FE"></span></div>
      <div class="note">Hết giờ khách xác nhận lại trên trang chào${r.time_ok?'':' · chờ đồng bộ giờ'}</div>
    </div>
    <div class="card na">
      <div class="ch"><div class="lbl" style="padding:0">Số khách tối đa</div><div class="note" style="padding:0">cùng lúc</div></div>
      <div class="stepper wide"><button type="button" id="mxDec" aria-label="Giảm">−</button><b id="mxV">${d.max||'∞'}</b><button type="button" id="mxInc" aria-label="Tăng">+</button></div>
    </div>
    <div class="card full na">
      <div style="display:flex;align-items:center;gap:12px"><div style="flex:1"><h3>Giờ phục vụ WiFi khách</h3><div class="note" style="padding:0">Chạm từng ngày để đổi giờ · ngoài giờ khách vẫn thấy WiFi nhưng tạm dừng Internet${r.time_ok?'':' · đang chờ đồng bộ giờ, chưa áp dụng'}</div></div>
        <button type="button" class="sw" role="switch" aria-checked="${d.on}" aria-label="Bật giờ phục vụ" id="schedSw"></button></div>
      <div class="week" style="opacity:${d.on?1:.45}">
        <span></span><div class="axis"><span>0h</span><span>6h</span><span>12h</span><span>18h</span><span>24h</span></div><span></span>
        ${d.week.map((e,i)=>`<span class="d">${DAYS[i]}</span><button type="button" class="bar" data-day="${i}" aria-label="${DAYS[i]}: ${dayLabel(e)}, chạm để đổi">${dayBar(e).map(b=>`<span style="left:${b[0].toFixed(1)}%;width:${b[1].toFixed(1)}%"></span>`).join('')}</button><span class="lab">${dayLabel(e)}</span>`).join('')}
      </div>
      <button type="button" class="btn sm" id="custom" style="align-self:flex-start">${ico('clock','width:16px;height:16px')}Đặt giờ tùy chỉnh</button>
    </div>
  </div>
  ${dirty()?`<div class="savebar" id="savebar"><div>Có thay đổi chưa lưu</div><button class="btn x" id="gUndo">Huỷ</button><button class="btn pri" id="gSave">Lưu</button></div>`:''}`;
}
bind.guest=v=>{
  if(!S.draft)return;
  $$('.na button,.na input',v).forEach(b=>{b.disabled=true;b.tabIndex=-1});
  const upd=()=>{const sc=$('#body').scrollTop;render();$('#body').scrollTop=sc};
  const i=$('#ssid',v);if(i){i.oninput=()=>{S.draft.ssid=i.value;const sb=!!$('#savebar');if(sb!==dirty()){upd();const j=$('#ssid');j.focus();j.setSelectionRange(j.value.length,j.value.length)}else{const q=$('#qrBig');try{q.innerHTML=WFQR.svg(WFQR.wifi(S.draft.ssid||'Wiflow'),{quiet:1})}catch(e){}}}}
  $$('[data-down]',v).forEach(b=>b.onclick=()=>{S.draft.down=+b.dataset.down;upd()});
  $$('[data-sess]',v).forEach(b=>b.onclick=()=>{S.draft.session=+b.dataset.sess;upd()});
  $('#mxDec',v).onclick=()=>{S.draft.max=S.draft.max<=5?0:S.draft.max-5;upd()};
  $('#mxInc',v).onclick=()=>{S.draft.max=S.draft.max>=250?250:(S.draft.max?S.draft.max+5:5);upd()};
  $('#schedSw',v).onclick=()=>{S.draft.on=!S.draft.on;upd()};
  $$('[data-day]',v).forEach(b=>b.onclick=()=>{const k=+b.dataset.day,c=PRESETS.indexOf(S.draft.week[k]);S.draft.week[k]=PRESETS[(c+1)%PRESETS.length];if(!S.draft.on)S.draft.on=true;upd()});
  $('#custom',v).onclick=customHours;
  $('#qrBig',v).onclick=()=>{let q='';try{q=WFQR.svg(WFQR.wifi(S.draft.ssid||'Wiflow'),{quiet:2})}catch(e){}sheet(`<div class="h" style="font-size:20px;text-align:center">${esc(S.draft.ssid)}</div><div style="width:min(280px,70vw);margin:0 auto">${q}</div><div class="note" style="text-align:center">Khách quét mã bằng camera để vào WiFi</div><button class="btn" data-no>Đóng</button>`);$('#sheet [data-no]').onclick=closeSheet};
  const u=$('#gUndo',v);if(u)u.onclick=()=>{S.draft=draftFrom(S.guest);upd()};
  const s=$('#gSave',v);if(s)s.onclick=saveGuest;
};
function customHours(){
  const c=sheet(`<div class="hd"><span class="ic" style="width:48px;height:48px;background:var(--accS);color:var(--acc)">${ico('clock','width:22px;height:22px')}</span><div><b>Giờ tùy chỉnh</b><span>Áp dụng cho các ngày đã chọn</span></div></div>
   <div class="row2"><div><label class="lbl">Mở lúc</label><input class="in" id="hFrom" type="time" value="07:00"></div><div><label class="lbl">Tắt lúc</label><input class="in" id="hTo" type="time" value="22:00"></div></div>
   <div class="chips" style="grid-template-columns:repeat(7,minmax(0,1fr))">${DAYS.map((x,i)=>`<button type="button" aria-pressed="true" data-dd="${i}">${x}</button>`).join('')}</div>
   <div class="note">Giờ tắt nhỏ hơn giờ mở nghĩa là qua đêm (vd 18:00 → 02:00).</div>
   <div class="two"><button class="btn" data-no>Huỷ</button><button class="btn pri" data-yes>Áp dụng</button></div>`);
  $$('[data-dd]',c).forEach(b=>b.onclick=()=>b.setAttribute('aria-pressed',b.getAttribute('aria-pressed')==='true'?'false':'true'));
  $('[data-no]',c).onclick=closeSheet;
  $('[data-yes]',c).onclick=()=>{const f=$('#hFrom',c).value,t=$('#hTo',c).value;if(!/^\d\d:\d\d$/.test(f)||!/^\d\d:\d\d$/.test(t)){toast('Giờ không hợp lệ',true);return}
    $$('[data-dd]',c).forEach(b=>{if(b.getAttribute('aria-pressed')==='true')S.draft.week[+b.dataset.dd]=f===t?'all':f+'-'+(t==='00:00'?'24:00':t)});S.draft.on=true;closeSheet();render()};
}
async function saveGuest(){
  const d=S.draft,r=S.guest,b=$('#gSave');if(b){b.disabled=true;b.innerHTML='<span class="spin" style="border-color:rgba(255,255,255,.3);border-top-color:#fff"></span>'}
  const back=()=>{if(b){b.disabled=false;b.textContent='Lưu'}};
  try{
    const ssid=d.ssid.trim();if(!ssid||new TextEncoder().encode(ssid).length>32){toast('Tên WiFi khách 1–32 ký tự',true);back();return}
    if(ssid===r.guest_ssid){S.draft=draftFrom(S.guest);render();return}
    toast('Đang đổi tên WiFi khách…');
    const x=await api('guest_ssid',{guest_ssid:ssid});if(!x.ok){toast(x.error||'Không đổi được tên WiFi',true);back();return}
    await refreshStatus();await loadGuest();S.draft=draftFrom(S.guest);toast('Đã lưu · WiFi khách khởi động lại vài giây');render();
  }catch(e){toast(e.message&&e.message!=='auth'?e.message:'Không lưu được',true);back()}
}

/* ================= HỆ THỐNG ================= */
const LOGK={uplink:['Mạng','var(--peach)','var(--peachI)'],watchdog:['Tự sửa','var(--mint)','var(--mintI)'],safe:['An toàn','var(--redS)','#9B1C24'],guest:['Khách','var(--accS)','var(--acc2)'],content:['Nội dung','var(--lilac)','var(--lilacI)'],security:['Bảo mật','var(--redS)','#9B1C24'],system:['Hệ thống','var(--bg)','var(--ink2)']};
function vSystem(){
  const st=S.st||{},ov=S.ov||{},stg=ov.storage||{},q=(ov.day||{}).q||[];
  const tot=+stg.total||1,used=Math.max(0,tot-(+stg.free||0));
  const rv=q.map(x=>x.m),rp=path(rv.length>1?rv:[0,0],290,50,100,4),rmin=rv.length?Math.min(...rv):0,rmax=rv.length?Math.max(...rv):0;
  const paired=!!+st.paired,up=S.up;
  const logs=(S.log||(ov.log||[])).slice(0,40);
  return `
  <div class="grid">
    <div class="card" style="gap:14px">
      <div style="display:flex;align-items:center;gap:12px"><img src="/wiflow/assets/wiflow-icon.png" alt="" style="width:46px;height:46px;border-radius:14px"><div style="min-width:0"><h3>${esc(st.model||'Viettel NR3053')}</h3><div class="note" style="padding:0">Wiflow ${esc(st.version||'')}${st.os?' · Wiflow OS '+esc(st.os):''}</div></div></div>
      <div class="idrow"><div><span>Mã thiết bị</span><code id="devCode">${esc(st.device_id||'—')}</code></div><button type="button" class="btn sm" id="copyDev" aria-label="Chép mã thiết bị">${ico('copy','width:16px;height:16px')}<span>Chép</span></button></div>
      <div style="display:flex;flex-direction:column;gap:6px"><div class="axis" style="font-size:12px"><span>Bộ nhớ flash</span><span>${stg.total?bytes(stg.free)+' trống':''}</span></div>
        ${stg.total?`<div class="store"><span style="flex:${used||1};background:#1B2036"></span><span style="flex:${Math.max(.01,tot-used)};background:#EEF1FE"></span></div>
        <div class="legend"><span><i style="background:#1B2036"></i>Đã dùng ${Math.round(used*100/tot)}%</span><span><i style="background:#EEF1FE"></i>Trống ${bytes(stg.free)}</span></div>`:'<div class="note" style="padding:0">Chưa đọc được</div>'}</div>
      <div style="display:flex;flex-direction:column;gap:6px"><div class="axis" style="font-size:12px;color:var(--ink)"><span style="font-weight:500">RAM 24 giờ</span><span class="mute">${rv.length?`${rmin}–${rmax}%`:'đang thu thập'}</span></div>
        <svg class="chart" viewBox="0 0 290 50" preserveAspectRatio="none" style="height:50px" role="img" aria-label="RAM 24 giờ"><path d="${rp.area}" fill="rgba(67,96,245,.10)"/><path d="${rp.line}" fill="none" stroke="#4360F5" stroke-width="2" vector-effect="non-scaling-stroke"/></svg></div>
    </div>
    <div class="card">
      <div class="ch"><h3>Cập nhật Wiflow</h3><span class="chip">Bản ${esc(st.version||'')}</span></div>
      <label class="drop" id="drop"><input type="file" id="ipk" accept=".apk" hidden><span class="ic" style="width:46px;height:46px;background:var(--accS);color:var(--acc)">${ico('upload')}</span><span style="font-size:14px;font-weight:500">Kéo thả file .apk hoặc bấm để chọn</span><span class="note">Giữ nguyên cấu hình · gói wiflow-setup</span></label>
      ${up?`<div style="display:flex;flex-direction:column;gap:6px"><div class="axis" style="font-size:12px;color:var(--ink)"><span style="font-weight:500;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${esc(up.name)}</span><span class="mute">${esc(up.label)}</span></div><div class="prog"><i style="width:${up.pct}%"></i></div>${up.done?`<button class="btn pri sm" id="upReload">${ico('refresh','width:16px;height:16px')}Tải lại trang</button>`:''}${up.err?`<div class="msg err">${esc(up.err)}</div>`:''}</div>`:''}
    </div>
    <div class="card w2">
      <div class="ch"><h3>Ghép nối</h3>${paired?(st.wp_online?'<span class="chip">Đã ghép</span>':'<span class="chip warn">Mất liên lạc</span>'):'<span class="chip off">Chưa ghép</span>'}</div>
      ${paired?`<div style="display:flex;align-items:center;gap:12px"><div class="avatar">${esc((st.account_public_id||'WF').slice(-2))}</div><div style="min-width:0;flex:1"><div style="font-size:15px;font-weight:500">${esc(st.account_public_id||'Tài khoản Wiflow')}</div><div class="note" style="padding:0">wiflow.projifylab.com · ${ov.wp_last_ok?'liên lạc '+ago(ov.wp_last_ok,ov.now):'chưa liên lạc'}</div></div></div>${st.wp_error?`<div class="msg warn">${esc(st.wp_error)}</div>`:''}<button class="btn sm" id="unpair" style="align-self:flex-start">Rời tài khoản</button>`
       :`<div class="note" style="padding:0">Lấy mã 12 ký tự trong app Wiflow (Thiết bị → Thêm thiết bị).</div><input class="in" id="pairCode" maxlength="14" placeholder="Mã liên kết" autocapitalize="characters" spellcheck="false" style="letter-spacing:.1em"><button class="btn pri sm" id="pairGo">${ico('link','width:16px;height:16px')}Liên kết</button>`}
      <a href="tel:0833880100" style="display:flex;align-items:center;gap:10px;font-size:13px;color:inherit;text-decoration:none">${ico('phone','width:16px;height:16px;color:#127A55')}0833 880 100</a>
      <a href="mailto:wiflow@projifylab.com" style="display:flex;align-items:center;gap:10px;font-size:13px;color:inherit;text-decoration:none">${ico('mail','width:16px;height:16px;color:#4360F5')}wiflow@projifylab.com</a>
    </div>
    <div class="acts full">
      <button type="button" class="act" id="hold"><span class="hold"><svg class="r" viewBox="0 0 48 48" aria-hidden="true"><circle cx="24" cy="24" r="21" fill="#F2F4F8"/><circle id="holdArc" cx="24" cy="24" r="21" fill="none" stroke="#1B2036" stroke-width="3" stroke-linecap="round" stroke-dasharray="0 132" stroke-opacity="0" transform="rotate(-90 24 24)"/></svg>${ico('power','position:relative')}</span><div style="flex:1;min-width:0"><b>Khởi động lại</b><span class="s" id="holdHint">Bấm giữ 2 giây</span></div></button>
      <button type="button" class="act" id="diag"><span class="ic" style="background:var(--mint);color:var(--mintI)">${ico('send')}</span><div><b>Gửi chẩn đoán</b><span class="s">${paired?'Cho bộ phận hỗ trợ':'Cần liên kết tài khoản'}</span></div></button>
      <button type="button" class="act" id="diagDl"><span class="ic" style="background:var(--accS);color:var(--acc)">${ico('download')}</span><div><b>Tải báo cáo</b><span class="s">File văn bản, không có mật khẩu</span></div></button>
      <a class="act" href="${LUCI}" data-luci><span class="ic" style="background:var(--lilac);color:var(--lilacI)">${ico('code')}</span><div><b>Nâng cao (LuCI)</b><span class="s">Cùng phiên đăng nhập</span></div></a>
      <button type="button" class="act" id="pw"><span class="ic" style="background:var(--accS);color:var(--acc)">${ico('key')}</span><div><b>Đổi mật khẩu</b><span class="s">Tài khoản ${esc(st.username||'wiflow')}</span></div></button>
      <button type="button" class="act" id="reset"><span class="ic" style="background:var(--peach);color:var(--peachI)">${ico('reset')}</span><div><b style="color:var(--peachI)">Reset Wiflow</b><span class="s">Giữ gói, xoá cấu hình</span></div></button>
      <a class="act" href="${LOGOUT}" data-logout><span class="ic" style="background:var(--bg)">${ico('logout')}</span><div><b>Đăng xuất</b><span class="s">Thoát cả Wiflow và LuCI</span></div></a>
    </div>
    <div class="card full">
      <h3>Nhật ký hệ thống</h3>
      ${logs.length?logs.map(l=>{const k=LOGK[l.a]||LOGK.system;return `<div class="log"><span class="k" style="background:${k[1]};color:${k[2]}">${k[0]}</span><div data-wrap-ok>${esc(l.m)}</div><small>${when(l.t,ov.now)}</small></div>`}).join(''):'<div class="note">Chưa có sự kiện.</div>'}
    </div>
  </div>`;
}
bind.system=v=>{
  // hold to reboot (2 s)
  const hb=$('#hold',v);let hv=0,ht=0;const arc=()=>$('#holdArc'),hint=()=>$('#holdHint');
  const start=e=>{e.preventDefault();clearInterval(ht);arc().setAttribute('stroke-opacity','1');ht=setInterval(async()=>{hv=Math.min(100,hv+5);arc().setAttribute('stroke-dasharray',(132*hv/100).toFixed(1)+' 132');hint().textContent=hv>=100?'Đang khởi động lại…':'Giữ tiếp… '+hv+'%';if(hv>=100){clearInterval(ht);doReboot()}},100)};
  const end=()=>{clearInterval(ht);if(hv<100){hv=0;arc().setAttribute('stroke-dasharray','0 132');arc().setAttribute('stroke-opacity','0');hint().textContent='Bấm giữ 2 giây'}};
  hb.addEventListener('pointerdown',start);['pointerup','pointerleave','pointercancel'].forEach(t=>hb.addEventListener(t,end));
  hb.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' ')confirmSheet({title:'Khởi động lại router?',text:'Khách mất WiFi khoảng 1–2 phút.',ok:'Khởi động lại',icon:'power'}).then(y=>{if(y)doReboot()})});
  {const cp=$('#copyDev',v);if(cp)cp.onclick=()=>{const t=String(S.st?.device_id||'');(navigator.clipboard?.writeText(t)||Promise.reject()).then(()=>toast('Đã chép mã thiết bị')).catch(()=>{const r=document.createRange();r.selectNodeContents($('#devCode',v));const w=getSelection();w.removeAllRanges();w.addRange(r);toast('Đã chọn mã, nhấn giữ để chép')})};}
  $('#diag',v).onclick=async()=>{if(!+(S.st||{}).paired){toast('Liên kết tài khoản trước, hoặc bấm Tải báo cáo',true);return}toast('Đang gửi chẩn đoán…');try{const r=await api('diag_send');r.ok?toast('Đã gửi chẩn đoán cho bộ phận hỗ trợ'):toast(r.error||'Không gửi được',true)}catch(e){toast('Không gửi được',true)}};
  $('#diagDl',v).onclick=async()=>{toast('Đang tạo báo cáo…');try{const r=await api('diag_file');if(!r.ok){toast(r.error||'Không tạo được báo cáo',true);return}
    const d=new Date(),n=`wiflow-diag-${d.getFullYear()}${pad2(d.getMonth()+1)}${pad2(d.getDate())}${pad2(d.getHours())}${pad2(d.getMinutes())}.txt`,a=document.createElement('a');a.href=URL.createObjectURL(new Blob([r.text],{type:'text/plain'}));a.download=n;document.body.appendChild(a);a.click();setTimeout(()=>{URL.revokeObjectURL(a.href);a.remove()},1000);toast('Đã tải '+n)}catch(e){toast('Không tạo được báo cáo',true)}};
  $('#pw',v).onclick=passwordSheet;
  $('#reset',v).onclick=async()=>{if(!await confirmSheet({title:'Reset Wiflow?',text:'Xoá WiFi nguồn và ghép nối, WiFi khách về tên “Wiflow”, Internet về tự động. Mật khẩu Wiflow Setup về wiflow / wiflow. Gói Wiflow vẫn giữ.',ok:'Reset',danger:true,icon:'reset',tint:'var(--peach)',ink:'var(--peachI)'}))return;
    toast('Đang reset Wiflow…');try{const r=await api('reset');if(!r.ok){toast(r.error||'Không reset được',true);return}toast('Đã reset Wiflow');setTimeout(()=>location.replace(LOGOUT),1500)}catch(e){toast('Không reset được',true)}};
  const un=$('#unpair',v);if(un)un.onclick=async()=>{if(!await confirmSheet({title:'Rời tài khoản Wiflow?',text:'App Wiflow sẽ không còn quản lý router này. WiFi khách vẫn phát bình thường.',ok:'Rời tài khoản',danger:true,icon:'link'}))return;
    try{let r=await api('unpair');if(!r.ok&&await confirmSheet({title:'Không liên lạc được máy chủ',text:(r.error||'')+' Vẫn rời tài khoản trên router?',ok:'Vẫn rời',danger:true}))r=await api('unpair',{force:true});if(r.ok){await refreshStatus();toast('Router đã rời tài khoản Wiflow');render()}else if(r.error)toast(r.error,true)}catch(e){toast('Không thực hiện được',true)}};
  const pg=$('#pairGo',v);if(pg)pg.onclick=pairNow;
  const pc=$('#pairCode',v);if(pc)pc.onkeydown=e=>{if(e.key==='Enter')pairNow()};
  const ipk=$('#ipk',v),drop=$('#drop',v);
  ipk.onchange=()=>{if(ipk.files[0])upload(ipk.files[0])};
  ['dragenter','dragover'].forEach(t=>drop.addEventListener(t,e=>{e.preventDefault();drop.classList.add('over')}));
  ['dragleave','drop'].forEach(t=>drop.addEventListener(t,e=>{e.preventDefault();drop.classList.remove('over')}));
  drop.addEventListener('drop',e=>{const f=e.dataTransfer.files[0];if(f)upload(f)});
  const rl=$('#upReload',v);if(rl)rl.onclick=()=>location.reload();
  $$('[data-logout]',v).forEach(a=>a.onclick=e=>{e.preventDefault();try{sessionStorage.removeItem('wf-sid')}catch(x){}location.href=LOGOUT});
};
async function doReboot(){try{const r=await api('reboot');if(r.ok===false){toast(r.error||'Chưa khởi động lại được',true);return}}catch(e){}rebooting()}
function rebooting(){sheet(`<div class="done-hero"><span class="spin" style="width:42px;height:42px;border-width:4px"></span><div class="h" style="font-size:22px">Đang khởi động lại</div><div class="note">Khoảng 1–2 phút. Trang tự mở lại khi router sẵn sàng.</div></div>`);$('#sheet').dataset.lock='1';
  const t0=Date.now();setTimeout(async function w(){try{const r=await fetch('/wiflow/index.html',{cache:'no-store'});if(r.ok&&Date.now()-t0>45000){relogin();return}}catch(e){}setTimeout(w,4000)},25000)}
function passwordSheet(){
  const st=S.st||{};const c=sheet(`<div class="hd"><span class="ic" style="width:48px;height:48px;background:var(--accS);color:var(--acc)">${ico('key','width:22px;height:22px')}</span><div><b>Đổi mật khẩu</b><span>Dùng cho Wiflow Setup và LuCI</span></div></div>
   <input class="in" id="cpUser" value="${esc(st.username||'wiflow')}" placeholder="Tên đăng nhập" autocapitalize="none" spellcheck="false">
   <input class="in" id="cpNew" type="password" placeholder="Mật khẩu mới (từ 8 ký tự)" autocomplete="new-password">
   <input class="in" id="cpNew2" type="password" placeholder="Nhập lại mật khẩu mới" autocomplete="new-password">
   <div class="note">Tài khoản root của LuCI không đổi.</div>
   <div id="cpMsg"></div><div class="two"><button class="btn" data-no>Huỷ</button><button class="btn pri" data-yes>Lưu</button></div>`);
  $('[data-no]',c).onclick=closeSheet;
  $('[data-yes]',c).onclick=async()=>{const m=$('#cpMsg',c),u=$('#cpUser',c).value.trim(),p=$('#cpNew',c).value;
    if(!/^[A-Za-z0-9._-]{3,32}$/.test(u)||u==='root'){m.innerHTML='<div class="msg err">Tên đăng nhập 3–32 ký tự: chữ, số, . _ - (không dùng root)</div>';return}
    if(p.length<8){m.innerHTML='<div class="msg err">Mật khẩu mới tối thiểu 8 ký tự</div>';return}
    if(p!==$('#cpNew2',c).value){m.innerHTML='<div class="msg err">Hai mật khẩu mới không giống nhau</div>';return}
    try{const r=await api('change_login',{new_username:u,new_password:p});
      if(!r.ok){m.innerHTML=`<div class="msg err">${esc(r.error||'Không lưu được')}</div>`;return}
      closeSheet();toast('Đã đổi mật khẩu');refreshStatus()}catch(e){m.innerHTML='<div class="msg err">Không lưu được</div>'}};
}
async function pairNow(){
  const i=$('#pairCode'),code=(i.value||'').toUpperCase().replace(/[^A-Z0-9]/g,'');if(code.length!==12){toast('Mã liên kết gồm 12 ký tự',true);i.focus();return}
  const b=$('#pairGo');b.disabled=true;b.innerHTML='<span class="spin" style="border-color:rgba(255,255,255,.3);border-top-color:#fff"></span>Đang liên kết';
  try{const r=await api('pair',{pairing_code:code});if(!r.ok){toast(r.error||'Không liên kết được',true);b.disabled=false;b.textContent='Liên kết';return false}
    await refreshStatus();toast(r.message||'Đã liên kết tài khoản Wiflow');if(S.wiz){S.wiz.step=4;renderWizard()}else render();return true}catch(e){toast('Không liên kết được',true);b.disabled=false;b.textContent='Liên kết';return false}
}
/* .apk upload: LuCI's upload endpoint, then the router's package manager (same as System → Software). */
async function upload(f){
  if(!/\.apk$/i.test(f.name)){toast('Chọn file .apk của Wiflow Setup',true);return}
  if(f.size>8388608){toast('File quá lớn (tối đa 8 MB)',true);return}
  S.up={name:f.name,pct:0,label:'Đang tải lên'};render();
  const fd=new FormData();fd.append('sessionid',SID);fd.append('filename','/tmp/upload.apk');fd.append('filedata',f);
  const x=new XMLHttpRequest();x.open('POST','/cgi-bin/cgi-upload');
  x.upload.onprogress=e=>{if(e.lengthComputable){S.up.pct=Math.round(e.loaded*60/e.total);S.up.label=Math.round(e.loaded*100/e.total)+'%';const p=$('.prog i');if(p)p.style.width=S.up.pct+'%'}};
  x.onload=async()=>{
    if(x.status!==200){S.up.err='Tải lên không thành công';S.up.label='Lỗi';render();return}
    S.up.pct=70;S.up.label='Đang cài';render();
    try{const r=await ubus('file','exec',{command:'/usr/libexec/package-manager-call',params:['install','/tmp/upload.apk']},120000);
      if(r.code!==0){S.up.err='Cài không thành công: '+String(r.stderr||r.stdout||'').trim().split('\n').slice(-2).join(' ');S.up.label='Lỗi';render();return}
      S.up.pct=100;S.up.label='Đã cài xong';S.up.done=true;render();toast('Đã cài gói mới · tải lại trang sau vài giây')}
    catch(e){S.up.pct=100;S.up.label='Đã cài, đang khởi động lại dịch vụ';S.up.done=true;render()}
  };
  x.onerror=()=>{S.up.err='Tải lên bị gián đoạn';render()};x.send(fd);
}

/* ================= FIRST SETUP ================= */
/* NR3053: 1 · WiFi khách (Bật Wiflow) → 2 · Internet nguồn → 3 · Liên kết → 4 · Hoàn tất */
function renderWizard(){
  const w=S.wiz,st=S.st||{},v=$('#view');$('#shell').classList.add('wizmode');
  $('#dTitle').textContent='Cài đặt Wiflow';$('#dSub').textContent=`Bước ${w.step}/4`;$('#mTitle').textContent='Cài đặt Wiflow';
  const bar=`<div class="wiz-steps" aria-hidden="true">${[1,2,3,4].map(i=>`<span class="${i<=w.step?'on':''}"></span>`).join('')}</div><div class="note" id="stepLabel" style="padding:0">Bước ${w.step}/4 · ${['WiFi khách','Internet nguồn','Liên kết tài khoản','Hoàn tất'][w.step-1]}</div>`;
  let h='';
  if(w.step===1){
    h=`${bar}<h1>WiFi khách</h1><p class="lead">Router sẽ đổi WiFi đang phát thành WiFi khách mở cho khách hàng, ở cả 2.4 GHz và 5 GHz, mỗi băng một kênh ít nhiễu. Trang quản trị vẫn là 10.0.0.1.</p>
     <div class="card"><label class="lbl" for="wGuest">Tên WiFi khách</label><input class="in" id="wGuest" maxlength="32" value="${esc(st.guest_ssid||'Wiflow')}" style="font-weight:500">
     <div class="msg info" style="font-size:12.5px">${ico('alert','width:16px;height:16px')}<span>Nếu bạn đang dùng WiFi của router, sau khoảng 30 giây hãy kết nối vào WiFi khách rồi mở lại 10.0.0.1.</span></div>
     <button class="btn pri" id="wAct">Bật Wiflow</button></div>`;
  }else if(w.step===2){
    const nets=S.scan.list||[];
    h=`${bar}<h1>Internet nguồn</h1><p class="lead">Router lấy Internet từ đâu?</p>
     <div class="pick" role="radiogroup"><button type="button" role="radio" aria-checked="${w.src==='wifi'}" data-src="wifi"><span class="ic" style="background:var(--mint);color:var(--mintI)">${ico('wifi')}</span><b>WiFi của modem</b><span class="s">Không cần dây. Sau này cắm dây, router tự ưu tiên dây.</span></button>
      <button type="button" role="radio" aria-checked="${w.src==='lan'}" data-src="lan"><span class="ic" style="background:var(--accS);color:var(--acc)">${ico('lan')}</span><b>Dây LAN</b><span class="s">Dây từ modem cắm vào cổng WAN</span></button></div>
     ${w.src==='lan'?`<div class="card"><div class="note" style="padding:0">Cắm dây mạng từ modem vào cổng WAN của router rồi bấm kiểm tra.</div><button class="btn pri" id="lanGo">Kiểm tra dây LAN</button></div>`:''}
     ${w.src==='wifi'?`<div class="card" style="padding:18px 10px 10px;gap:4px"><div style="display:flex;align-items:center;padding:0 8px 8px"><b style="flex:1;font-weight:500">Chọn WiFi của modem</b><button type="button" class="btn ghost" id="rescan" style="color:var(--acc);height:36px">${S.scan.busy?'<span class="spin"></span>':'Quét lại'}</button></div><div class="nets">${nets.length?nets.map((n,i)=>`<button type="button" class="net-i" data-net="${i}">${sigBars(n.signal)}<div class="n"><b>${esc(n.ssid)}</b><span>${n.enc==='none'?'Mạng mở':'Có mật khẩu'} · ${n.band==='5g'?'5 GHz':'2.4 GHz'}${n.recommended?' · <em class="rec">Nên dùng</em>':''}${n.dfs?' · DFS':''}${n.weak?' · Sóng yếu':''}</span></div><span class="db">${n.signal!=null?n.signal+' dBm':''}</span><span class="tick">${ico(n.enc==='none'?'wifi':'lock')}</span></button>`).join(''):`<div class="note" style="padding:10px 12px">${S.scan.busy?'Đang tìm WiFi xung quanh… (5 GHz cần khoảng 15 giây)':'Chưa thấy mạng nào.'}</div>`}<button type="button" class="net-i" data-net="hidden"><span class="sig" style="opacity:.4"><i></i><i></i><i></i><i></i></span><div class="n"><b>Mạng ẩn</b><span>Tự nhập tên WiFi</span></div><span class="tick">${ico('plus')}</span></button></div></div>`:''}
     <button class="btn ghost" id="skip2">Để sau</button>`;
  }else if(w.step===3){
    h=`${bar}<h1>Liên kết tài khoản</h1><p class="lead">Gắn router vào app Wiflow để theo dõi khách, nhận sự kiện và điều khiển từ xa.</p>
     <div class="card"><div class="note" style="padding:0">Mở app Wiflow → Thiết bị → Thêm thiết bị để lấy mã 12 ký tự.</div><input class="in" id="pairCode" maxlength="14" placeholder="Mã liên kết" autocapitalize="characters" spellcheck="false" style="letter-spacing:.1em"><button class="btn pri" id="pairGo">${ico('link','width:16px;height:16px')}Liên kết</button><button class="btn ghost" id="skip">Để sau</button></div>`;
  }else{
    h=`${bar}<div class="card done-hero"><span class="ok">${ico('check')}</span><h1>Wiflow đã sẵn sàng</h1><p class="lead">WiFi khách “${esc(st.guest_ssid||'Wiflow')}” đang phát. ${+st.paired?'Router đã gắn với tài khoản Wiflow.':'Bạn có thể liên kết tài khoản sau trong Hệ thống.'}</p><button class="btn pri" id="finish">Vào trang quản trị</button></div>`;
  }
  const anim=w.shown!==w.step;w.shown=w.step;
  v.innerHTML=`<div class="wiz"${anim?'':' style="animation:none"'}>${h}</div>`;
  const wa=$('#wAct',v);if(wa)wa.onclick=async()=>{const n=$('#wGuest').value.trim();if(!n||new TextEncoder().encode(n).length>32){toast('Tên WiFi khách 1–32 ký tự',true);return}
    wa.disabled=true;wa.innerHTML='<span class="spin" style="border-color:rgba(255,255,255,.3);border-top-color:#fff"></span>Đang bật WiFi khách';
    try{const r=await api('activate',{ssid:n});
      if(r.job&&r.job.state==='lost'){sheet(`<div class="done-hero"><span class="ok">${ico('wifi')}</span><div class="h" style="font-size:22px">Kết nối lại WiFi</div><div class="note">WiFi của router vừa đổi thành “${esc(n)}”. Kết nối vào WiFi này (hoặc dùng dây LAN) rồi mở lại http://10.0.0.1.</div></div>`);$('#sheet').dataset.lock='1';return}
      if(!r.ok){toast(r.error||'Chưa bật được Wiflow',true);wa.disabled=false;wa.textContent='Bật Wiflow';return}
      await refreshStatus();toast(r.message||'Đã bật Wiflow');w.step=+(S.st||{}).internet_verified?(+(S.st||{}).paired?4:3):2;if(w.step===2){w.src='wifi';scan()}renderWizard()}
    catch(e){if(e.message!=='auth'){wa.disabled=false;wa.textContent='Bật Wiflow'}}};
  $$('[data-src]',v).forEach(b=>b.onclick=()=>{w.src=b.dataset.src;w.mode='auto';if(w.src==='wifi'&&!S.scan.list)scan();renderWizard()});
  const lg=$('#lanGo',v);if(lg)lg.onclick=()=>runConnect({mode:'auto'},'lan');
  const rs=$('#rescan',v);if(rs)rs.onclick=()=>scan();
  $$('[data-net]',v).forEach(b=>b.onclick=()=>{const k=b.dataset.net;wifiSheet(k==='hidden'?null:S.scan.list[+k])});
  const s2=$('#skip2',v);if(s2)s2.onclick=()=>{w.step=+st.paired?4:3;renderWizard()};
  const pg=$('#pairGo',v);if(pg)pg.onclick=pairNow;
  const sk=$('#skip',v);if(sk)sk.onclick=()=>{try{localStorage.setItem('wf-skip-pair','1')}catch(e){}w.step=4;renderWizard()};
  const fi=$('#finish',v);if(fi)fi.onclick=()=>{S.wiz=null;try{localStorage.setItem('wf-skip-pair','1')}catch(e){}go('status')};
}

/* ================= start ================= */
async function init(){
  let s;try{s=await refreshStatus()}catch(e){return}
  if(!s){$('#view').innerHTML=`<div class="card"><div class="msg err">Không tải được dữ liệu. Kiểm tra bạn vẫn kết nối WiFi của router hoặc dây LAN, và gói Wiflow Setup đang chạy.</div><button class="btn pri" onclick="location.reload()">Tải lại</button></div>`;return}
  let skip=false;try{skip=localStorage.getItem('wf-skip-pair')==='1'}catch(e){}
  if(!s.activated)S.wiz={step:1,src:'',mode:'auto'};
  else if(!+s.internet_verified&&!+s.paired)S.wiz={step:2,src:'',mode:'auto'};
  else if(!+s.paired&&!skip)S.wiz={step:3};
  const h=location.hash.slice(1);S.page=NAV.some(n=>n[0]===h)?h:'status';
  shell();
  if(S.wiz){renderWizard()}else render(true);
  refreshOverview().then(()=>{if(!S.wiz&&!editing())render()});
  if(!S.wiz)go(S.page);
  try{const j=await api('job',{},8000);if(j.job==='running'){toast('Đang có một thay đổi Internet chạy dở…')}}catch(e){}
  loop();
}
window.addEventListener('hashchange',()=>{const h=location.hash.slice(1);if(!S.wiz&&NAV.some(n=>n[0]===h)&&h!==S.page)go(h)});
window.addEventListener('resize',()=>{clearTimeout(window.__rz);window.__rz=setTimeout(()=>{if(!editing())render()},200)});
init();
})();
