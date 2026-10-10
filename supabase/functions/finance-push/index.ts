import webpush from 'npm:web-push@3.6.7';
import {allowedEndpoint,createHandler,runBatch} from './worker.mjs';

declare const EdgeRuntime:{waitUntil(task:Promise<unknown>):void};
function required(name:string):string{const value=Deno.env.get(name);if(!value)throw Error('Missing server configuration: '+name);return value;}
const project=required('SUPABASE_URL'),serviceKey=required('SUPABASE_SERVICE_ROLE_KEY');
const vapidDetails={subject:required('FINANCE_VAPID_SUBJECT'),publicKey:required('FINANCE_VAPID_PUBLIC_KEY'),privateKey:required('FINANCE_VAPID_PRIVATE_KEY')};
async function rpc(name:string,args:unknown){
 const response=await fetch(project+'/rest/v1/rpc/'+name,{method:'POST',redirect:'error',signal:AbortSignal.timeout(12000),headers:{apikey:serviceKey,Authorization:'Bearer '+serviceKey,'Content-Type':'application/json'},body:JSON.stringify(args)});
 if(!response.ok)throw Error('Queue RPC failed');return response.json();
}
async function send(subscription:any,payload:string,topic:string){
 if(!allowedEndpoint(subscription.endpoint))throw Error('Invalid push service');
 const details=webpush.generateRequestDetails(subscription,payload,{vapidDetails,TTL:86400,urgency:'high',contentEncoding:'aes128gcm',topic});
 return fetch(details.endpoint,{method:'POST',redirect:'error',signal:AbortSignal.timeout(8000),headers:details.headers,body:new Uint8Array(details.body)});
}
Deno.serve(createHandler({secret:required('FINANCE_PUSH_SECRET'),work:()=>runBatch({rpc,send}),waitUntil:(task:Promise<unknown>)=>EdgeRuntime.waitUntil(task),log:(summary:unknown)=>console.log(JSON.stringify(summary))}));
