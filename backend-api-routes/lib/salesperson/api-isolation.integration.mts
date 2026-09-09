// Run with tsx from backend-api-routes; dedicated localhost database only.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { createRequire } from 'node:module';
import vm from 'node:vm';
import ts from 'typescript';
import { NextRequest } from 'next/server';
import { createClient } from '@supabase/supabase-js';
const config=JSON.parse(readFileSync('/tmp/personal-isolation-stack-status.json','utf8'));
assert.equal(config.API_URL,'http://127.0.0.1:56321');
const admin=createClient(config.API_URL,config.SERVICE_ROLE_KEY,{auth:{persistSession:false}});
const sql=(query:string)=>execFileSync('psql',['postgresql://postgres:postgres@127.0.0.1:56322/postgres','-X','-v','ON_ERROR_STOP=1','-At','-c',query],{encoding:'utf8',stdio:['ignore','pipe','pipe']});
const a=randomUUID(),b=randomUUID(),fresh=randomUUID(),w=randomUUID(),ca=randomUUID(),cb=randomUUID(),taskA=randomUUID(),taskB=randomUUID();
const require=createRequire(import.meta.url);
const { recordDemoOpenInPipeline, applyEmailSignupMatch } = require('../sales-pipeline/server.ts');
const { loadSalespersonStripeRevenue, saveRevenueSnapshot, loadRevenueSnapshotNear } = require('./revenue-snapshots.ts');
const { loadPersonalOutreach } = require('./outreach-metrics.ts');
const { requirePersonalReferences } = require('../sales-pro/personal-references.ts');
const listA=randomUUID(),listB=randomUUID();
const campaignA=randomUUID(),campaignB=randomUUID();
const leadA=randomUUID(),leadB=randomUUID();
const salespersonA=randomUUID(),salespersonB=randomUUID();
const bookingA=randomUUID(),bookingB=randomUUID(),threadA=randomUUID(),threadB=randomUUID();
let userId=a;
function load(route:string){
 const source=readFileSync(new URL('../../app/api/'+route+'/route.ts',import.meta.url),'utf8') + (route==='salesperson/messenger'?'\nexport { resolveActiveSalesperson };':'');
 const compiled=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
 const module={exports:{} as any};
 const overrides:Record<string,unknown>={
  '@/lib/supabase/server':{createAdminClient:()=>admin},
  '@/app/api/_utils/request-user':{resolveUserFromRequest:async()=>({id:userId})},
  '@/app/api/_utils/workspace':{resolveWorkspaceIdForUser:async()=>({workspaceId:w})},
  '@/lib/sales-pro/context':{requireSalesProContext:async()=>({admin,userId,workspaceId:w,role:'owner'}),cleanText:(v:unknown)=>typeof v==='string'?v.trim()||null:null,clampLimit:()=>100,decodeCursor:()=>null,encodeCursor:()=>null},
  '@/lib/sales-pro/personal-references':{requirePersonalReferences},
  '@/lib/sales-pro/automation-trigger':{triggerSalesAutomations:async()=>{throw new Error('Unexpected automation');}},
  '@/lib/integrations/auto-push':{},
  '@/lib/email/resend':{},
  '@/lib/meetings/invitations':{parseEmailRecipients:()=>({invalid:[],recipients:[]}),parsePhoneRecipients:()=>({invalid:[],recipients:[]})},
  '@/lib/meetings/calendar':{},
  '@/lib/meetings/reminders':{},
  '@/lib/dialer/server':{getDialerRequestContext:async()=>({admin,requestUser:{id:userId},workspaceId:w,role:'owner',salesperson:null})},
  '@/lib/zoom':{zoomAccessTokenForUser:async()=>{throw new Error('Unexpected Zoom access');}},
  '@/lib/sales-pro/communications':{appendCommunication:async()=>{throw new Error('Unexpected communication write');}},
  '@/lib/sales-pro/notifications':{notifySalesUser:async()=>{throw new Error('Unexpected notification');}},
 };
 vm.runInNewContext(compiled,{exports:module.exports,module,require:(id:string)=>overrides[id]??require(id),console,process,Date});return module.exports;
}
try {
 for(const [signature,roles] of [
   ['public.create_sales_booking_hold(uuid,timestamptz,timestamptz,text,text,text,text,text)',['anon','authenticated']],
   ['public.ensure_social_workspace(uuid,text)',['anon']],
   ...['claim_due_company_research_jobs','claim_due_social_posts','claim_due_social_targets','claim_due_sales_automation_executions'].map(name=>[`public.${name}(integer)`,['anon','authenticated']] as const),
 ] as const) {
   for(const role of roles) assert.equal(sql(`SELECT has_function_privilege('${role}','${signature}','EXECUTE')`).trim(),'f');
   assert.equal(sql(`SELECT has_function_privilege('service_role','${signature}','EXECUTE')`).trim(),'t');
 }
 sql(`INSERT INTO auth.users(id,email) VALUES ('${a}','${a}@example.test'),('${b}','${b}@example.test'),('${fresh}','${fresh}@example.test');
 INSERT INTO workspaces(id,name,owner_id) VALUES ('${w}','API isolation fixture','${a}');
 INSERT INTO workspace_members(workspace_id,user_id,role) VALUES ('${w}','${a}','owner'),('${w}','${b}','member'),('${w}','${fresh}','member') ON CONFLICT DO NOTHING;
 INSERT INTO sales_contacts(id,workspace_id,owner_user_id,name) VALUES ('${ca}','${w}','${a}','A contact'),('${cb}','${w}','${b}','B private contact');
 INSERT INTO contacts(id,user_id,workspace_id,full_name,address) VALUES ('${ca}','${a}','${w}','A legacy',''),('${cb}','${b}','${w}','B legacy','');
 INSERT INTO smart_lists(id,workspace_id,created_by_user_id,name,criteria) VALUES ('${listA}','${w}','${a}','A list','{}'),('${listB}','${w}','${b}','B private list','{}');
 INSERT INTO campaigns(id,workspace_id,owner_id,title,name,description) VALUES ('${campaignA}','${w}','${a}','A campaign','A campaign','Synthetic'),('${campaignB}','${w}','${b}','B private campaign','B private campaign','Synthetic');
 INSERT INTO sales_contact_campaigns(workspace_id,sales_contact_id,campaign_id) VALUES ('${w}','${ca}','${campaignA}'),('${w}','${ca}','${campaignB}');
 INSERT INTO sales_leads(id,workspace_id,assigned_user_id,name) VALUES ('${leadA}','${w}','${a}','A lead'),('${leadB}','${w}','${b}','B lead');
 INSERT INTO sales_tasks(id,workspace_id,assigned_user_id,sales_contact_id,title,status) VALUES ('${taskA}','${w}','${a}','${ca}','A task','open'),('${taskB}','${w}','${b}','${cb}','B private task','open');
 INSERT INTO sales_bookings(id,workspace_id,assigned_user_id,sales_contact_id,guest_name,guest_email,starts_at,ends_at,cancellation_token_hash) VALUES
 ('${bookingA}','${w}','${a}','${ca}','A guest','a@example.test',now(),now()+interval '1 hour','${bookingA}'),
 ('${bookingB}','${w}','${b}','${cb}','B guest','b@example.test',now(),now()+interval '1 hour','${bookingB}');
 INSERT INTO communication_threads(id,workspace_id,assigned_user_id,sales_contact_id,subject) VALUES
 ('${threadA}','${w}','${a}','${ca}','A inbox'),('${threadB}','${w}','${b}','${cb}','B private inbox');
 INSERT INTO salespeople(id,user_id,workspace_id,full_name,email,status) VALUES
 ('${salespersonA}','${a}','${w}','Daniel A','${a}@example.test','active'),
 ('${salespersonB}','${b}','${w}','Daniel B','${b}@example.test','active');
 INSERT INTO communication_events(workspace_id,thread_id,actor_user_id,channel,direction,event_kind,body,status) VALUES
 ('${w}','${threadA}','${a}','sms','outbound','demo_sent','https://wolfgrid.app/demo100','sent'),
 ('${w}','${threadB}','${b}','email','outbound','demo_sent','https://wolfgrid.app/demo100','sent');
 INSERT INTO communication_events(workspace_id,thread_id,actor_user_id,channel,direction,event_kind,provider,provider_event_id,status)
 VALUES ('${w}','${threadA}','${a}','sms','inbound','message_received','telnyx','${threadA}','received');
 INSERT INTO dialer_inbound_messages(workspace_id,owner_user_id,from_number_e164,to_number_e164,body,telecom_provider,provider_message_id)
 VALUES ('${w}','${a}','+15555550001','+15555550002','Synthetic fixture','telnyx','${threadA}');`);
 for(const [user,contact,task,booking,thread] of [[a,ca,taskA,bookingA,threadA],[b,cb,taskB,bookingB,threadB],[fresh,null,null,null,null]]) {
  userId=user!;
  for(const [route,key,expected] of [['crm/contacts','contacts',contact],['contacts',null,contact],['tasks','tasks',task],['bookings','bookings',booking],['inbox/threads','threads',thread]] as const){
   const response=await load(route).GET(new NextRequest(`http://localhost/api/${route}?workspaceId=${w}`));
   const body=await response.json();assert.equal(response.status,200,route+': '+JSON.stringify(body));
   const rows=key?body[key]:body;assert.deepEqual(rows.map((r:any)=>r.id),expected?[expected]:[],route);
  }
 }
 userId=a;
 const timeline=load('crm/timeline');
 const timelineResponse=await timeline.GET(new NextRequest(`http://localhost/api/crm/timeline?contactId=${ca}`));
 const timelineBody=await timelineResponse.json();assert.equal(timelineResponse.status,200,JSON.stringify(timelineBody));
 assert.deepEqual(timelineBody.timeline.filter((row:any)=>row.timelineKind==='campaign').map((row:any)=>row.note),['A campaign']);
 assert.equal((await timeline.GET(new NextRequest(`http://localhost/api/crm/timeline?contactId=${cb}`))).status,404);
 assert.equal((await timeline.POST(new NextRequest('http://localhost/api/crm/timeline',{method:'POST',body:JSON.stringify({contactId:cb,note:'Unauthorized note'})}))).status,404);
 for(const [user,expected] of [[a,listA],[b,listB],[fresh,null]]) {
  userId=user!;
  const response=await load('dialer/smart-list-imports').GET(new NextRequest('http://localhost/api/dialer/smart-list-imports'));
  const body=await response.json();assert.equal(response.status,200,JSON.stringify(body));
  assert.deepEqual(body.lists.map((row:any)=>row.id),expected?[expected]:[]);
 }
 userId=a;
 const messenger=load('salesperson/messenger');
 assert.equal((await messenger.resolveActiveSalesperson(admin,{id:a,email:`${b}@example.test`},w)).id,salespersonA);
 assert.equal(await messenger.resolveActiveSalesperson(admin,{id:fresh,email:null},w),null);
 assert.equal(await messenger.resolveActiveSalesperson(admin,{id:fresh,email:`${a}@example.test`},w),null);
 for(const [user,sms,email,demos] of [[a,1,0,1],[b,0,1,1],[fresh,0,0,0]]) {
   const metrics=await loadPersonalOutreach(admin,{userId:user,workspaceId:w,start:'2020-01-01T00:00:00Z',end:'2100-01-01T00:00:00Z'});
   assert.deepEqual(metrics,{inboundMessages:user===a?1:0,outboundMessages:sms,emails:email,demosSent:demos});
 }
 sql(`UPDATE sales_leads SET contact_id='${ca}' WHERE id IN ('${leadA}','${leadB}');`);
 await recordDemoOpenInPipeline({admin,link:{id:randomUUID(),salesperson_id:salespersonA,workspace_id:w,contact_id:ca,dialler_lead_id:null,referral_code:'FIXTURE'},openedAt:new Date().toISOString(),followUpDueAt:new Date(Date.now()+86400000).toISOString()});
 assert.equal(sql(`SELECT last_touch_summary FROM sales_leads WHERE id='${leadA}'`).trim(),'Opened tracked demo link');
 assert.notEqual(sql(`SELECT last_touch_summary FROM sales_leads WHERE id='${leadB}'`).trim(),'Opened tracked demo link');
 assert.equal(sql(`SELECT actor_user_id FROM sales_activities WHERE sales_lead_id='${leadA}' AND activity_type='demo_opened'`).trim(),a);
 const referralCode='TEST'+salespersonA.replaceAll('-','').toUpperCase();
 sql(`UPDATE salespeople SET referral_code='${referralCode}' WHERE id='${salespersonA}'; UPDATE sales_leads SET email_normalized='shared@example.test',assigned_salesperson_id='${salespersonA}',pipeline_owner_id='${a}' WHERE id IN ('${leadA}','${leadB}');`);
 await applyEmailSignupMatch({admin,referralCode,recipientEmail:'shared@example.test',convertedUserId:fresh,convertedWorkspaceId:w});
 assert.equal(sql(`SELECT signed_up_user_id FROM sales_leads WHERE id='${leadA}'`).trim(),fresh);
 assert.equal(sql(`SELECT signed_up_user_id IS NULL FROM sales_leads WHERE id='${leadB}'`).trim(),'t');
 const badLink=await admin.from('sales_tasks').update({sales_contact_id:cb}).eq('id',taskA);
 assert.equal(badLink.error?.code,'42501');
 const badBookingLink=await admin.from('sales_bookings').update({sales_lead_id:leadB}).eq('id',bookingA);
 assert.equal(badBookingLink.error?.code,'42501');
 const ownLink=await admin.from('sales_tasks').update({sales_lead_id:leadA}).eq('id',taskA);
 assert.equal(ownLink.error,null);
 assert.equal(sql(`SELECT next_task_title FROM sales_leads WHERE id='${leadA}'`).trim(),'A task');
 // Simulate a historical mixed-owner link; the summary trigger must ignore it.
 sql(`BEGIN; ALTER TABLE sales_tasks DISABLE TRIGGER personal_crm_references;
 UPDATE sales_tasks SET sales_lead_id='${leadA}',due_at=now()-interval '1 day' WHERE id='${taskB}';
 ALTER TABLE sales_tasks ENABLE TRIGGER personal_crm_references; COMMIT;`);
 const changed=await admin.from('sales_tasks').update({title:'A updated task'}).eq('id',taskA);
 assert.equal(changed.error,null);
 assert.equal(sql(`SELECT next_task_title FROM sales_leads WHERE id='${leadA}'`).trim(),'A updated task');
 sql(`UPDATE sales_leads SET next_task_title='B private task' WHERE id='${leadA}'; UPDATE sales_leads SET next_task_title='Manual follow-up' WHERE id='${leadB}';`);
 sql(readFileSync(new URL('../../../supabase/migrations/20260909160000_reconcile_personal_crm_links.sql',import.meta.url),'utf8'));
 assert.equal(sql(`SELECT sales_lead_id IS NULL FROM sales_tasks WHERE id='${taskB}'`).trim(),'t');
 assert.equal(sql(`SELECT title FROM sales_tasks WHERE id='${taskB}'`).trim(),'B private task');
 assert.equal(sql(`SELECT next_task_title FROM sales_leads WHERE id='${leadA}'`).trim(),'A updated task');
 assert.equal(sql(`SELECT next_task_title FROM sales_leads WHERE id='${leadB}'`).trim(),'Manual follow-up');
 assert.equal(sql(`SELECT previous_reference_id FROM personal_crm_link_quarantine WHERE source_id='${taskB}' AND reference_column='sales_lead_id'`).trim(),leadA);
 assert.equal(sql(`SELECT has_table_privilege('authenticated','personal_crm_link_quarantine','SELECT')`).trim(),'f');
 const capturedAt=new Date('2026-09-09T10:00:00Z');
 for(const [salesperson,user,amount] of [[salespersonA,a,2500],[salespersonB,b,7000]] as const) {
   assert.deepEqual(await loadSalespersonStripeRevenue(admin,salesperson,user),{paidTeams:0,mrrByCurrency:{}});
   await saveRevenueSnapshot(admin,{salespersonId:salesperson,userId:user,revenue:{paidTeams:1,mrrByCurrency:{CAD:amount}},capturedAt});
   assert.equal((await loadRevenueSnapshotNear(admin,salesperson,capturedAt,user)).mrrByCurrency.CAD,amount);
 }
 assert.equal(await loadRevenueSnapshotNear(admin,salespersonB,capturedAt,a),null);
 assert.equal(await loadRevenueSnapshotNear(admin,salespersonA,capturedAt,fresh),null);
 await assert.rejects(loadSalespersonStripeRevenue(admin,salespersonB,a),/owner not found/);
 await assert.rejects(saveRevenueSnapshot(admin,{salespersonId:salespersonB,userId:a,revenue:{paidTeams:99,mrrByCurrency:{CAD:99999}},capturedAt}),/owner not found/);
 assert.equal((await loadRevenueSnapshotNear(admin,salespersonB,capturedAt,b)).mrrByCurrency.CAD,7000);
 userId=a;
 const denied=await load('tasks').PATCH(new NextRequest('http://localhost/api/tasks',{method:'PATCH',body:JSON.stringify({id:taskB,title:'Attempted overwrite'})}));
 assert.equal(denied.status,404);
 assert.equal(sql(`SELECT title FROM sales_tasks WHERE id='${taskB}'`).trim(),'B private task');
 const bookingDenied=await load('bookings').PATCH(new NextRequest('http://localhost/api/bookings',{method:'PATCH',body:JSON.stringify({id:bookingB,outcome:'cancelled'})}));
 assert.equal(bookingDenied.status,404);
 assert.equal(sql(`SELECT status FROM sales_bookings WHERE id='${bookingB}'`).trim(),'confirmed');
 const threadDenied=await load('inbox/threads').PATCH(new NextRequest('http://localhost/api/inbox/threads',{method:'PATCH',body:JSON.stringify({id:threadB,status:'archived'})}));
 assert.equal(threadDenied.status,400);
 assert.equal(sql(`SELECT status FROM communication_threads WHERE id='${threadB}'`).trim(),'open');
 const meetingResponse=await load('meetings').POST(new NextRequest('http://localhost/api/meetings',{method:'POST',body:JSON.stringify({title:'Test meeting',contactId:cb,workspaceId:w,startAt:new Date(Date.now()+86400000).toISOString(),endAt:new Date(Date.now()+90000000).toISOString()})}));
 assert.equal(meetingResponse.status,404);
 const eventA=randomUUID(),eventB=randomUUID(),publicToken=randomUUID();
 sql(`INSERT INTO calendar_events(id,workspace_id,user_id,title,start_at,end_at) VALUES
 ('${eventA}','${w}','${a}','A event',now(),now()+interval '1 hour'),('${eventB}','${w}','${b}','B private event',now(),now()+interval '1 hour');
 UPDATE sales_bookings SET calendar_event_id='${eventB}',cancellation_token_hash='${createHash('sha256').update(publicToken).digest('hex')}' WHERE id='${bookingA}';`);
 const publicBooking=load('public/bookings/[token]'),params={params:Promise.resolve({token:publicToken})};
 assert.equal((await publicBooking.DELETE(new NextRequest('http://localhost/api/public/bookings/test',{method:'DELETE'}),params)).status,409);
 assert.equal((await publicBooking.PATCH(new NextRequest('http://localhost/api/public/bookings/test',{method:'PATCH',body:JSON.stringify({startAt:new Date(Date.now()+86400000).toISOString()})}),params)).status,409);
 assert.equal(sql(`SELECT status FROM sales_bookings WHERE id='${bookingA}'`).trim(),'confirmed');
 assert.equal(sql(`SELECT deleted_at IS NULL FROM calendar_events WHERE id='${eventB}'`).trim(),'t');
 sql(`UPDATE sales_bookings SET calendar_event_id='${eventA}' WHERE id='${bookingA}';`);
 assert.equal((await publicBooking.DELETE(new NextRequest('http://localhost/api/public/bookings/test',{method:'DELETE'}),params)).status,200);
 assert.equal(sql(`SELECT deleted_at IS NOT NULL FROM calendar_events WHERE id='${eventA}'`).trim(),'t');
 assert.equal(sql(`SELECT deleted_at IS NULL FROM calendar_events WHERE id='${eventB}'`).trim(),'t');
 console.log('PASS: actual contact/task/booking/inbox API handlers isolate both coworkers and a new user; foreign updates denied even with owner context; outreach metrics, revenue snapshots and messenger identity isolated.');
} finally { sql(`DELETE FROM smart_lists WHERE workspace_id='${w}'; DELETE FROM sales_contact_campaigns WHERE workspace_id='${w}'; DELETE FROM campaigns WHERE id IN ('${campaignA}','${campaignB}'); DELETE FROM personal_crm_link_quarantine WHERE workspace_id='${w}'; DELETE FROM sales_tasks WHERE workspace_id='${w}'; DELETE FROM sales_bookings WHERE workspace_id='${w}'; DELETE FROM sales_leads WHERE workspace_id='${w}'; DELETE FROM calendar_events WHERE workspace_id='${w}'; DELETE FROM salespeople WHERE id IN ('${salespersonA}','${salespersonB}'); DELETE FROM workspaces WHERE id='${w}'; DELETE FROM auth.users WHERE id IN ('${a}','${b}','${fresh}');`); }
