// Local schema-only integration stack only. Never use production credentials.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { createHmac, randomUUID } from 'node:crypto';
const config=JSON.parse(readFileSync('/tmp/personal-isolation-stack-status.json','utf8'));
const api=new URL(config.API_URL);
assert.ok(['127.0.0.1','localhost'].includes(api.hostname),'Local stack required');
assert.equal(api.port,'56321','Dedicated test stack required');
const dbURL='postgresql://postgres:postgres@127.0.0.1:56322/postgres';
function sql(query){return execFileSync('psql',[dbURL,'-X','-v','ON_ERROR_STOP=1','-At','-c',query],{encoding:'utf8',stdio:['ignore','pipe','pipe']});}
const a=randomUUID(),b=randomUUID(),w=randomUUID(),ca=randomUUID(),cb=randomUUID(),ta=randomUUID(),tb=randomUUID();
function token(user){const encode=value=>Buffer.from(JSON.stringify(value)).toString('base64url');
 const payload=encode({alg:'HS256',typ:'JWT'})+'.'+encode({sub:user,role:'authenticated',aud:'authenticated',exp:Math.floor(Date.now()/1000)+600});
 return payload+'.'+createHmac('sha256',config.JWT_SECRET).update(payload).digest('base64url');}
async function query(user,params,service=false){const url=new URL('/rest/v1/communication_threads',api);url.search=new URLSearchParams(params).toString();
 const response=await fetch(url,{headers:{apikey:config.ANON_KEY,Authorization:`Bearer ${service?config.SERVICE_ROLE_KEY:token(user)}`}});
 const body=await response.json();assert.equal(response.status,200,JSON.stringify(body));return body;}
try {
 sql(`INSERT INTO auth.users(id,email) VALUES ('${a}','${a}@example.test'),('${b}','${b}@example.test');
 INSERT INTO public.workspaces(id,name,owner_id) VALUES ('${w}','Personal isolation fixture','${a}');
 INSERT INTO public.workspace_members(workspace_id,user_id,role) VALUES ('${w}','${a}','owner'),('${w}','${b}','member') ON CONFLICT DO NOTHING;
 INSERT INTO public.sales_contacts(id,workspace_id,owner_user_id,name) VALUES ('${ca}','${w}','${a}','A contact'),('${cb}','${w}','${b}','B private contact');
 INSERT INTO public.communication_threads(id,workspace_id,assigned_user_id,sales_contact_id) VALUES ('${ta}','${w}','${a}','${ca}'),('${tb}','${w}','${b}','${cb}');
 INSERT INTO public.communication_events(workspace_id,thread_id,actor_user_id,channel,direction,event_kind,body) VALUES ('${w}','${ta}','${a}','email','inbound','email_received','A message'),('${w}','${tb}','${b}','email','inbound','email_received','B message');`);
 for(const [user,thread] of [[a,ta],[b,tb]]) {
  const rows=await query(user,{select:'id,sales_contacts(id,name),communication_events(body)',workspace_id:`eq.${w}`});
  assert.deepEqual(rows.map(row=>row.id),[thread]);
 }
 // Model historical bad linkage. Restore enforcement before any HTTP query.
 sql(`BEGIN; ALTER TABLE public.communication_threads DISABLE TRIGGER personal_communication_thread_references;
 UPDATE public.communication_threads SET sales_contact_id='${cb}' WHERE id='${ta}';
 ALTER TABLE public.communication_threads ENABLE TRIGGER personal_communication_thread_references; COMMIT;`);
 const serviceRows=await query(a,{select:'id,sales_contacts(id,name),communication_events(body)',workspace_id:`eq.${w}`,assigned_user_id:`eq.${a}`,'sales_contacts.owner_user_id':`eq.${a}`,'sales_contacts.workspace_id':`eq.${w}`},true);
 assert.equal(serviceRows.length,1);assert.equal(serviceRows[0].sales_contacts,null);
 assert.equal(JSON.stringify(serviceRows).includes('B private contact'),false);
 console.log('PASS: real PostgREST RLS isolates two coworkers including a workspace owner; service-role embedded-owner filters remove foreign contact details while preserving the personal thread.');
} finally {
 sql(`DELETE FROM public.workspaces WHERE id='${w}'; DELETE FROM auth.users WHERE id IN ('${a}','${b}');`);
}
