// Small, independently testable dispatcher. Queue rows are the only source of payloads.
export function allowedEndpoint(value) {
 try {
  // Check the original authority before URL normalizes default ports,
  // whitespace or backslashes. Keep this aligned with valid_push_endpoint SQL.
  if(typeof value!=='string'||new TextEncoder().encode(value).length>2048||/[\s\u0000-\u001f\u007f-\u009f\\#]/u.test(value))return false;
  const raw=/^https:\/\/([a-z0-9.-]+)(\/[^#]*)$/.exec(value);
  if(!raw||raw[1].length>253||!/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$/.test(raw[1]))return false;
  const u=new URL(value),h=u.hostname;
  return h===raw[1]&&u.protocol==='https:'&&!u.username&&!u.password&&!u.port&&!u.hash&&(
   h==='fcm.googleapis.com'||h.endsWith('.fcm.googleapis.com')||h==='updates.push.services.mozilla.com'||h.endsWith('.updates.push.services.mozilla.com')||
   h==='web.push.apple.com'||h.endsWith('.push.apple.com')||h.endsWith('.notify.windows.com'));
 }catch{return false;}
}
export function payloadFor(row) {
 const eventId=/^[0-9a-f-]{36}$/i.test(row.event_id||'')?row.event_id:'movement';
 const kind=['created','updated','deleted','batch'].includes(row.kind)?row.kind:'batch';
 const txType=['income','expense','saving','transfer'].includes(row.tx_type)?row.tx_type:null;
 const count=Number.isSafeInteger(row.count)&&row.count>0?row.count:1;
 const payload={eventId,kind,txType,count},d=row.details;
 const label=value=>typeof value==='string'?Array.from(value.replace(/[\p{Cc}\p{Cf}]/gu,' ').replace(/\s+/g,' ').trim()).slice(0,80).join('').trim():'';
 // Details are an immutable server snapshot, not the current balance or a client message.
 if(count===1&&kind!=='batch'&&txType&&d&&typeof d==='object'&&!Array.isArray(d)&&
   Number.isSafeInteger(d.amountCents)&&d.amountCents>=0&&d.amountCents<=100000000000&&
   ['es','us'].includes(d.format)&&label(d.accountLabel)){
  const details={amountCents:d.amountCents,accountLabel:label(d.accountLabel),format:d.format};
  if(txType==='transfer'){
   if(label(d.fromLabel)&&label(d.toLabel)){details.fromLabel=label(d.fromLabel);details.toLabel=label(d.toLabel);payload.details=details;}
  }else payload.details=details;
 }
 return JSON.stringify(payload);
}
export async function runBatch({rpc,send}) {
 const rows=await rpc('finance_push_claim',{p_limit:20});
 if(!Array.isArray(rows))throw Error('Invalid claim response');
 const counts={claimed:rows.length,sent:0,retry:0,gone:0,unacknowledged:0};let cursor=0;
 await Promise.all(Array.from({length:Math.min(4,rows.length)},async()=>{
  while(cursor<rows.length){
   const row=rows[cursor++];let outcome='retry';
   if(!allowedEndpoint(row.subscription?.endpoint))outcome='gone';
   else try{
    const response=await send(row.subscription,payloadFor(row),String(row.event_id).replace(/-/g,''));
    outcome=response.status>=200&&response.status<300?'sent':[404,410].includes(response.status)?'gone':'retry';
   }catch{/* Network failure: the durable queue owns retries. */}
   try{
    const ack=await rpc('finance_push_finish',{p_id:row.id,p_lease:row.lease,p_outcome:outcome});
    if(ack?.finished)counts[outcome]++;else counts.unacknowledged++;
   }catch{counts.unacknowledged++;}
  }
 }));return counts;
}
async function equalSecret(actual,expected){
 if(typeof actual!=='string'||actual.length<32||actual.length>512||typeof expected!=='string'||expected.length<32)return false;
 const hashes=await Promise.all([actual,expected].map(s=>crypto.subtle.digest('SHA-256',new TextEncoder().encode(s))));
 const a=new Uint8Array(hashes[0]),b=new Uint8Array(hashes[1]);let difference=0;
 for(let i=0;i<a.length;i++)difference|=a[i]^b[i];return difference===0;
}
export function createHandler({secret,work,waitUntil,log=()=>{}}){
 return async request=>{
  if(request.method!=='POST')return new Response('Method not allowed',{status:405,headers:{Allow:'POST'}});
  if(!await equalSecret(request.headers.get('x-finance-dispatch-secret'),secret))return new Response('Unauthorized',{status:401});
  // Never process caller-supplied recipients, endpoints, amounts or messages.
  const task=Promise.resolve().then(()=>work()).then(result=>log({event:'batch',...result})).catch(()=>log({event:'dispatch_failed'}));
  waitUntil(task);return new Response('Accepted',{status:202});
 };
}
