/* Push only. No fetch handler, cache, session token, or financial snapshot. */
'use strict';
self.addEventListener('install',event=>event.waitUntil(self.skipWaiting()));
self.addEventListener('activate',event=>event.waitUntil(self.clients.claim()));
const financeAppURL=()=>new URL('./?notification=movement',self.registration.scope).href;
const financeClient=client=>{try{const url=new URL(client.url),scope=new URL(self.registration.scope);return url.origin===scope.origin&&url.pathname.startsWith(scope.pathname);}catch{return false;}};
function financePushBody(data){
 if(Number.isInteger(data.count)&&data.count>1)return 'Hay cambios en los movimientos de tu hogar. Abre FINANCE para revisarlos.';
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
