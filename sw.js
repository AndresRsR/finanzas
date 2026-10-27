/* Push only. No fetch handler, cache, session token, or stored financial state. */
'use strict';
self.addEventListener('install',event=>event.waitUntil(self.skipWaiting()));
self.addEventListener('activate',event=>event.waitUntil(self.clients.claim()));
const financeAppURL=()=>new URL('./?notification=movement',self.registration.scope).href;
const financeClient=client=>{try{const url=new URL(client.url),scope=new URL(self.registration.scope);return url.origin===scope.origin&&url.pathname.startsWith(scope.pathname);}catch{return false;}};
function financePushLabel(value){
 if(typeof value!=='string')return '';
 // Notification bodies are plain text; strip controls (including bidi overrides).
 return Array.from(value.replace(/[\p{Cc}\p{Cf}]/gu,' ').replace(/\s+/gu,' ').trim()).slice(0,80).join('').trim();
}
function financePushDetail(data){
 const details=data.details;
 if(!details||typeof details!=='object'||Array.isArray(details)||!Number.isSafeInteger(details.amountCents)||details.amountCents<0||details.amountCents>1e11||!['es','us'].includes(details.format))return '';
 const account=financePushLabel(details.accountLabel),from=financePushLabel(details.fromLabel),to=financePushLabel(details.toLabel);
 if(!account)return '';
 const names={income:'Ingreso',expense:'Gasto',saving:'Aporte',transfer:'Transferencia'};
 if(!Object.hasOwn(names,data.txType))return '';
 const operation=['delete','deleted','removed'].includes(data.kind)?'delete':['update','updated','edited'].includes(data.kind)?'update':['create','created','added','insert'].includes(data.kind)?'create':'';
 if(!operation||(data.txType==='transfer'&&(!from||!to)))return '';
 const amount='$'+new Intl.NumberFormat(details.format==='us'?'en-US':'es-ES',{minimumFractionDigits:2,maximumFractionDigits:2}).format(details.amountCents/100);
 const destination=data.txType==='transfer'?'de '+from+' a '+to:data.txType==='expense'?'desde '+account:'a '+account;
 const suffix=data.txType==='transfer'?'a':'o';
 const prefix=operation==='create'?names[data.txType]+' de ':names[data.txType]+(operation==='update'?' actualizad':' eliminad')+suffix+': ';
 return prefix+amount+' '+destination+'.';
}
function financePushBody(data){
 if(Number.isInteger(data.count)&&data.count>1)return 'Hay cambios en los movimientos de tu hogar. Abre FINANCE para revisarlos.';
 const detail=financePushDetail(data);if(detail)return detail;
 const names={income:'un ingreso',expense:'un gasto',saving:'un aporte',transfer:'una transferencia'};
 const type=Object.hasOwn(names,data.txType)?names[data.txType]:'un movimiento';
 if(['delete','deleted','removed'].includes(data.kind))return 'Se eliminó '+type+' de tu hogar. Abre FINANCE para revisarlo.';
 if(['update','updated','edited'].includes(data.kind))return 'Se actualizó '+type+' de tu hogar. Abre FINANCE para revisarlo.';
 if(['create','created','added','insert'].includes(data.kind))return 'Se registró '+type+' en tu hogar. Abre FINANCE para revisarlo.';
 return 'Hay novedades en los movimientos de tu hogar. Abre FINANCE para revisarlas.';
}
self.addEventListener('push',event=>{
 let data={};try{const value=event.data?.json();if(value&&typeof value==='object'&&!Array.isArray(value))data=value;}catch{}
 const id=typeof data.eventId==='string'&&/^[a-zA-Z0-9_-]{1,128}$/.test(data.eventId)?data.eventId:'movement';
 event.waitUntil(self.registration.showNotification('FINANCE',{
  body:financePushBody(data),tag:'finance:'+id,renotify:false,
  icon:new URL('assets/finance-icon-192-v2.png',self.registration.scope).href,
  badge:new URL('assets/finance-icon-32-v2.png',self.registration.scope).href,
  data:{route:'movements'}
 }));
});
self.addEventListener('notificationclick',event=>{
 event.notification.close();
 event.waitUntil((async()=>{
  const target=financeAppURL(),windows=await self.clients.matchAll({type:'window',includeUncontrolled:true});
  const existing=windows.filter(financeClient).sort((a,b)=>Number(b.focused)-Number(a.focused))[0];
  if(existing){
   // The app defers navigation until login and any unfinished form are resolved.
   try{await existing.focus();}catch{}
   existing.postMessage({type:'FINANCE_OPEN_MOVEMENTS'});
  }else await self.clients.openWindow(target);
 })());
});
self.addEventListener('pushsubscriptionchange',event=>{
 // Rebinding requires a signed-in user and an explicit activation in the app.
 event.waitUntil(self.clients.matchAll({type:'window',includeUncontrolled:true}).then(windows=>{
  for(const client of windows.filter(financeClient))client.postMessage({type:'FINANCE_PUSH_SUBSCRIPTION_CHANGED'});
 }));
});
