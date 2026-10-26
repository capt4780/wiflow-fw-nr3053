/* Wiflow QR (byte mode, ECC L/M/Q/H, versions 1-10). Based on the public QR Code
   specification (ISO/IEC 18004) as laid out by Project Nayuki's reference
   implementation (MIT). WFQR.svg(text) -> '<svg>…</svg>' */
(function(g){
'use strict';
var ECC={L:[[-1,7,10,15,20,26,18,20,24,30,18],[-1,1,1,1,1,1,2,2,2,2,4]],M:[[-1,10,16,26,18,24,16,18,22,22,26],[-1,1,1,1,2,2,4,4,4,5,5]],Q:[[-1,13,22,18,26,18,24,18,22,20,24],[-1,1,1,2,2,4,4,6,6,8,8]],H:[[-1,17,28,22,16,22,28,26,26,24,28],[-1,1,1,2,4,4,4,5,6,8,8]]};
var FB={L:1,M:0,Q:3,H:2};
function numRaw(v){var r=(16*v+128)*v+64;if(v>=2){var n=Math.floor(v/7)+2;r-=(25*n-10)*n-55;if(v>=7)r-=36;}return r;}
function dataCw(v,e){return Math.floor(numRaw(v)/8)-ECC[e][0][v]*ECC[e][1][v];}
function mul(x,y){var z=0;for(var i=7;i>=0;i--){z=(z<<1)^((z>>>7)*0x11D);z^=((y>>>i)&1)*x;}return z;}
function divisor(d){var r=[],i,j,root=1;for(i=0;i<d;i++)r.push(0);r[d-1]=1;for(i=0;i<d;i++){for(j=0;j<d;j++){r[j]=mul(r[j],root);if(j+1<d)r[j]^=r[j+1];}root=mul(root,2);}return r;}
function rem(data,div){var r=div.map(function(){return 0;});data.forEach(function(b){var f=b^r.shift();r.push(0);div.forEach(function(c,i){r[i]^=mul(c,f);});});return r;}
function utf8(s){var o=[];for(var i=0;i<s.length;i++){var c=s.charCodeAt(i);if(c>=0xD800&&c<0xDC00&&i+1<s.length){c=0x10000+((c-0xD800)<<10)+(s.charCodeAt(++i)-0xDC00);}
 if(c<0x80)o.push(c);else if(c<0x800)o.push(0xC0|c>>6,0x80|c&63);else if(c<0x10000)o.push(0xE0|c>>12,0x80|c>>6&63,0x80|c&63);else o.push(0xF0|c>>18,0x80|c>>12&63,0x80|c>>6&63,0x80|c&63);}return o;}
function bit(x,i){return ((x>>>i)&1)!==0;}
function encode(text,ecl){
 ecl=ecl||'M';var bytes=utf8(String(text)),v,cap;
 for(v=1;v<=10;v++){cap=dataCw(v,ecl)*8;if(4+(v<10?8:16)+bytes.length*8<=cap)break;}
 if(v>10)throw new Error('QR: text too long');
 var bb=[];function push(val,len){for(var i=len-1;i>=0;i--)bb.push((val>>>i)&1);}
 push(4,4);push(bytes.length,v<10?8:16);bytes.forEach(function(b){push(b,8);});
 push(0,Math.min(4,cap-bb.length));push(0,(8-bb.length%8)%8);
 for(var p=0xEC;bb.length<cap;p^=0xEC^0x11)push(p,8);
 var data=[];for(var i=0;i<bb.length;i+=8){var x=0;for(var k=0;k<8;k++)x=(x<<1)|bb[i+k];data.push(x);}
 var nb=ECC[ecl][1][v],ecLen=ECC[ecl][0][v],raw=Math.floor(numRaw(v)/8),nShort=nb-raw%nb,shortLen=Math.floor(raw/nb),div=divisor(ecLen),blocks=[],off=0;
 for(i=0;i<nb;i++){var dat=data.slice(off,off+shortLen-ecLen+(i<nShort?0:1));off+=dat.length;var e=rem(dat,div);if(i<nShort)dat.push(0);blocks.push(dat.concat(e));}
 var all=[];for(i=0;i<blocks[0].length;i++)for(var j=0;j<blocks.length;j++)if(i!==shortLen-ecLen||j>=nShort)all.push(blocks[j][i]);
 var size=v*4+17,m=[],fn=[];for(i=0;i<size;i++){m.push(new Array(size).fill(false));fn.push(new Array(size).fill(false));}
 function set(x,y,d){m[y][x]=d;fn[y][x]=true;}
 for(i=0;i<size;i++){set(6,i,i%2===0);set(i,6,i%2===0);}
 [[3,3],[size-4,3],[3,size-4]].forEach(function(c){for(var dy=-4;dy<=4;dy++)for(var dx=-4;dx<=4;dx++){var xx=c[0]+dx,yy=c[1]+dy,d=Math.max(Math.abs(dx),Math.abs(dy));if(xx>=0&&xx<size&&yy>=0&&yy<size)set(xx,yy,d!==2&&d!==4);}});
 var al=[];if(v>1){var na=Math.floor(v/7)+2,step=Math.ceil((v*4+4)/(na*2-2))*2;al=[6];for(var q=0,pos=v*4+10;q<na-1;q++,pos-=step)al.splice(1,0,pos);}
 for(i=0;i<al.length;i++)for(j=0;j<al.length;j++){if((i===0&&j===0)||(i===0&&j===al.length-1)||(i===al.length-1&&j===0))continue;for(var ay=-2;ay<=2;ay++)for(var ax=-2;ax<=2;ax++)set(al[i]+ax,al[j]+ay,Math.max(Math.abs(ax),Math.abs(ay))!==1);}
 function fmt(mask){var d=FB[ecl]<<3|mask,r=d;for(var t=0;t<10;t++)r=(r<<1)^((r>>>9)*0x537);var b=(d<<10|r)^0x5412,t2;
  for(t2=0;t2<=5;t2++)set(8,t2,bit(b,t2));set(8,7,bit(b,6));set(8,8,bit(b,7));set(7,8,bit(b,8));for(t2=9;t2<15;t2++)set(14-t2,8,bit(b,t2));
  for(t2=0;t2<8;t2++)set(size-1-t2,8,bit(b,t2));for(t2=8;t2<15;t2++)set(8,size-15+t2,bit(b,t2));set(8,size-8,true);}
 fmt(0);
 if(v>=7){var r7=v;for(i=0;i<12;i++)r7=(r7<<1)^((r7>>>11)*0x1F25);var vb=v<<12|r7;for(i=0;i<18;i++){var a=size-11+i%3,bq=Math.floor(i/3);set(a,bq,bit(vb,i));set(bq,a,bit(vb,i));}}
 var n=0;for(var right=size-1;right>=1;right-=2){if(right===6)right=5;for(var vert=0;vert<size;vert++)for(j=0;j<2;j++){var x2=right-j,up=((right+1)&2)===0,y2=up?size-1-vert:vert;if(!fn[y2][x2]&&n<all.length*8){m[y2][x2]=bit(all[n>>>3],7-(n&7));n++;}}}
 function maskFn(k,x,y){switch(k){case 0:return (x+y)%2===0;case 1:return y%2===0;case 2:return x%3===0;case 3:return (x+y)%3===0;case 4:return (Math.floor(x/3)+Math.floor(y/2))%2===0;case 5:return x*y%2+x*y%3===0;case 6:return (x*y%2+x*y%3)%2===0;default:return ((x+y)%2+x*y%3)%2===0;}}
 function apply(k){for(var y=0;y<size;y++)for(var x=0;x<size;x++)if(!fn[y][x]&&maskFn(k,x,y))m[y][x]=!m[y][x];}
 function penalty(){var s=0,x,y,run,dark=0;
  for(y=0;y<size;y++){run=1;for(x=1;x<size;x++){if(m[y][x]===m[y][x-1]){run++;if(run===5)s+=3;else if(run>5)s++;}else run=1;}}
  for(x=0;x<size;x++){run=1;for(y=1;y<size;y++){if(m[y][x]===m[y-1][x]){run++;if(run===5)s+=3;else if(run>5)s++;}else run=1;}}
  for(y=0;y<size-1;y++)for(x=0;x<size-1;x++){var c=m[y][x];if(c===m[y][x+1]&&c===m[y+1][x]&&c===m[y+1][x+1])s+=3;}
  for(y=0;y<size;y++)for(x=0;x<size;x++)if(m[y][x])dark++;
  return s+Math.floor(Math.abs(dark*20-size*size*10)/(size*size))*10;}
 var best=0,bp=1e9;for(var k=0;k<8;k++){apply(k);fmt(k);var pv=penalty();if(pv<bp){bp=pv;best=k;}apply(k);}
 apply(best);fmt(best);return m;
}
function svg(text,opt){opt=opt||{};var m=encode(text,opt.ecl||'M'),q=opt.quiet===undefined?2:opt.quiet,n=m.length+q*2,d='';
 for(var y=0;y<m.length;y++)for(var x=0;x<m.length;x++)if(m[y][x])d+='M'+(x+q)+' '+(y+q)+'h1v1h-1z';
 return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 '+n+' '+n+'" shape-rendering="crispEdges" role="img" aria-label="'+(opt.label||'Mã QR')+'"><rect width="'+n+'" height="'+n+'" fill="#fff"/><path d="'+d+'" fill="'+(opt.color||'#1B2036')+'"/></svg>';}
/* WiFi join text (open network); ; , : \ " escaped as the WiFi QR format asks. */
function wifi(ssid){return 'WIFI:T:nopass;S:'+String(ssid).replace(/([\\;,:"])/g,'\\$1')+';;';}
g.WFQR={encode:encode,svg:svg,wifi:wifi};
})(typeof window!=='undefined'?window:this);
