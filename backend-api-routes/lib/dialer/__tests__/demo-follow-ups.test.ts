import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import vm from 'node:vm';
import ts from 'typescript';
import { NextRequest, NextResponse } from 'next/server';
import { demoMatchesFilter, type DemoFollowUp } from '../../sales-pro/demo-follow-ups';
import { containsDemoLink } from '../../salesperson/outreach-metrics';

const require = createRequire(import.meta.url);
function load(path: string, overrides: Record<string, unknown>) {
  const code = ts.transpileModule(readFileSync(new URL(path, import.meta.url), 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
  const module = { exports: {} as any };
  vm.runInNewContext(code, { exports: module.exports, module, require: (id: string) => overrides[id] ?? require(id), console, process, Date });
  return module.exports;
}
function db(tables: Record<string, any[]>) {
  return { from(table: string) {
    const filters: Array<(row: any) => boolean> = []; let updates: any; let start = 0, end = Infinity;
    const value = (row: any, key: string) => key.includes('->>') ? row[key.split('->>')[0]]?.[key.split('->>')[1]] : row[key];
    const execute = () => {
      const rows = (tables[table] ?? []).filter(row => filters.every(filter => filter(row))).slice(start, end + 1);
      if (updates) rows.forEach(row => Object.assign(row, updates));
      return { data: rows, error: null };
    };
    const q: any = { select: () => q, order: () => q, limit: () => q,
      eq: (key: string, expected: any) => { filters.push(row => value(row,key) === expected); return q; },
      neq: (key: string, expected: any) => { filters.push(row => value(row,key) !== expected); return q; },
      range: (a: number,b: number) => { start=a;end=b;return q; },
      update: (patch: any) => { updates=patch; return q; },
      single: async()=>({ ...execute(), data: execute().data[0] ?? null }),
      maybeSingle: async()=>({ ...execute(), data: execute().data[0] ?? null }),
      then: (resolve: any, reject: any) => Promise.resolve(execute()).then(resolve,reject),
    }; return q;
  } };
}
const mine = { id:'mine',workspace_id:'shared',assigned_user_id:'rep',task_type:'demo_follow_up',status:'open',metadata:{} };
function harness(tables: Record<string, any[]>, denied = false) {
  const admin=db(tables);
  const overrides = {
    '@/lib/sales-pro/context': { requireSalesProContext: async()=>denied ? NextResponse.json({error:'Unauthorized'},{status:401}) : {admin,workspaceId:'shared',userId:'rep'},
      cleanText:(v:unknown)=>typeof v==='string' ? v.trim() || null : null, clampLimit:(v:string|null,f:number,m:number)=>Math.min(Number(v??f),m) },
    '@/lib/sales-pro/personal-references': {requirePersonalReferences:async()=>{}},
    '@/lib/sales-pro/automation-trigger':{triggerSalesAutomations:async()=>{}},
  };
  return { demos:load('../../../app/api/demo-follow-ups/route.ts',overrides), tasks:load('../../../app/api/tasks/route.ts',overrides) };
}

test('demo list excludes manual tasks, other owners, and other workspaces', async()=>{
  const {demos}=harness({sales_tasks:[mine,{...mine,id:'manual',task_type:'follow_up'},{...mine,id:'foreign',assigned_user_id:'other'},{...mine,id:'other-space',workspace_id:'other'}]});
  const response=await demos.GET(new NextRequest('https://example.test/api/demo-follow-ups'));
  assert.deepEqual((await response.json()).tasks.map((task:any)=>task.id),['mine']);
});
test('send history is restricted to the task owner and workspace',async()=>{
  const {demos}=harness({sales_tasks:[mine],communication_events:[
    {id:'mine-send',workspace_id:'shared',actor_user_id:'rep',metadata:{demoFollowUpTaskId:'mine'}},
    {id:'foreign-send',workspace_id:'shared',actor_user_id:'other',metadata:{demoFollowUpTaskId:'mine'}},
    {id:'unrelated-send',workspace_id:'shared',actor_user_id:'rep',metadata:{demoFollowUpTaskId:'unrelated'}},
  ]});
  const response=await demos.GET(new NextRequest('https://example.test/api/demo-follow-ups?taskId=mine'));
  assert.deepEqual((await response.json()).events.map((e:any)=>e.id),['mine-send']);
  assert.equal((await demos.GET(new NextRequest('https://example.test/api/demo-follow-ups?taskId=foreign'))).status,404);
});
test('demo endpoint requires authentication and validates pagination',async()=>{
  assert.equal((await harness({},true).demos.GET(new NextRequest('https://example.test/api/demo-follow-ups'))).status,401);
  for(const offset of ['-1','NaN','1.5']) assert.equal((await harness({}).demos.GET(new NextRequest(`https://example.test/api/demo-follow-ups?offset=${offset}`))).status,400);
});
test('completion and snooze persist through the shared task API; foreign IDs and bad dates are rejected',async()=>{
  const task={...mine};const {tasks}=harness({sales_tasks:[task]});
  const patch=(payload:any)=>tasks.PATCH(new NextRequest('https://example.test/api/tasks',{method:'PATCH',body:JSON.stringify(payload)}));
  assert.equal((await patch({id:'mine',dueAt:'bad'})).status,400);assert.equal(task.status,'open');
  assert.equal((await patch({id:'foreign',status:'completed'})).status,404);
  assert.equal((await patch({id:'mine',dueAt:'2026-11-10T14:00:00Z'})).status,200);assert.equal((task as any).due_at,'2026-11-10T14:00:00Z');
  assert.equal((await patch({id:'mine',status:'completed'})).status,200);assert.equal(task.status,'completed');
});
test('due filters include overdue, today, and upcoming while keeping closed reminders in All',()=>{
  const now=new Date(2026,9,26,12);const row=(day:number,status='open')=>({...mine,due_at:new Date(2026,9,day,9).toISOString(),status} as unknown as DemoFollowUp);
  assert.equal(demoMatchesFilter(row(25),'overdue',now),true);
  assert.equal(demoMatchesFilter(row(25),'today',now),false);
  assert.equal(demoMatchesFilter(row(26),'today',now),true);
  assert.equal(demoMatchesFilter(row(27),'upcoming',now),true);
  for(const filter of ['today','overdue','upcoming'] as const) assert.equal(demoMatchesFilter(row(26,'completed'),filter,now),false);
  assert.equal(demoMatchesFilter(row(26,'dismissed'),'all',now),true);
});
test('Telnyx status callbacks update a single existing send without creating another communication',async()=>{
  const existing={id:'send',workspace_id:'shared',actor_user_id:'rep',provider:'telnyx',provider_event_id:'provider-message',thread_id:'thread',status:'queued'};
  const {appendCommunication}=load('../../sales-pro/communications.ts',{
    '@/lib/sales-pro/personal-references':{},'@/lib/salesperson/outreach-metrics':{ containsDemoLink },resend:{},'@/lib/dialer/telnyx-messaging':{},
    '@/lib/sales-pro/automation-trigger':{},'@/lib/sales-pro/notifications':{},'@/lib/email/icloud-client':{},'@/lib/email/signature':{},'@/lib/email/demo':{},'@/lib/dialer/salesperson-settings':{},
  });
  const tables={communication_events:[existing]}; const admin=db(tables);
  const input={workspaceId:'shared',actorUserId:'rep',channel:'sms',direction:'outbound',eventKind:'message.finalized',provider:'telnyx',providerEventId:'provider-message',status:'delivered'};
  await appendCommunication(admin,{...input,status:'queued',body:'Here is the demo https://wolfgrid.app/demo1'});
  assert.equal((existing as any).event_kind,'demo_sent');
  await appendCommunication(admin,input);assert.equal(existing.status,'delivered');assert.equal(tables.communication_events.length,1);
  await appendCommunication(admin,{...input,status:'sent'});assert.equal(existing.status,'delivered');
});

test('older send surfaces bridge only demo messages and resolve CRM references within the owner’s workspace',async()=>{
  const appended:any[]=[];
  const {recordLegacyDemoSend}=load('../../sales-pro/demo-send.ts',{
    '@/lib/salesperson/outreach-metrics':{containsDemoLink},
    '@/lib/sales-pro/communications':{appendCommunication:async(_:any,input:any)=>{appended.push(input);return {event:{metadata:{demoFollowUpTaskId:'task'}}};}},
  });
  const admin=db({sales_leads:[{id:'foreign',legacy_contact_id:'legacy',assigned_user_id:'other',workspace_id:'shared'},{id:'mine',legacy_contact_id:'legacy',assigned_user_id:'rep',workspace_id:'shared',sales_contact_id:'my-contact'}]});
  const input={workspaceId:'shared',actorUserId:'rep',legacyContactId:'legacy',channel:'sms',direction:'outbound',eventKind:'sms_sent',body:'Thanks for your time',toAddresses:['+14165550100'],status:'sent'};
  assert.equal(await recordLegacyDemoSend(admin,input),null);assert.equal(appended.length,0);
  assert.match(await recordLegacyDemoSend(admin,{...input,body:'Demo: https://wolfgrid.app/demo1'}),/Follow Up → Demo/);
  assert.equal(appended[0].leadId,'mine');assert.equal(appended[0].contactId,'my-contact');
});
test('older sends report reminder recording failures without pretending the accepted message failed',async()=>{
  const {recordLegacyDemoSend}=load('../../sales-pro/demo-send.ts',{
    '@/lib/salesperson/outreach-metrics':{containsDemoLink},
    '@/lib/sales-pro/communications':{appendCommunication:async()=>{throw new Error('storage failure');}},
  });
  assert.match(await recordLegacyDemoSend(db({}),{workspaceId:'shared',actorUserId:'rep',channel:'email',direction:'outbound',eventKind:'email_sent',body:'https://wolfgrid.app/demo1',status:'sent'}),/Demo sent, but its follow-up could not be recorded/);
});
test('older dialler text sends record successful demo sends before returning, including contactless numbers',async()=>{
  const recorded:any[]=[];let sent=0;
  const {POST}=load('../../../app/api/dialer/leads/[leadId]/sms/route.ts',{
    '@/lib/sales-pro/demo-send':{recordLegacyDemoSend:async(_:any,input:any)=>{recorded.push(input);return 'Demo reminder saved';}},
    '@/lib/supabase/server':{createAdminClient:()=>({})},
    '../../../_utils':{resolveDialerWorkspace:async()=>({context:{workspace:{id:'shared'},user:{id:'rep'}}})},
    '@/lib/dialer/salesperson-settings':{getSalespersonSmsFromNumber:async()=>'+14165550999'},
    '@/lib/dialer/telnyx-messaging':{getContactForWorkspace:async()=>null,normalizePhone:(v:any)=>v,publicMessage:(v:any)=>v,sendTelnyxSms:async()=>{sent++;return{id:'provider-id',to:[{status:'queued'}]};}},
  });
  const call=(body:any)=>POST(new NextRequest('https://example.test/api/dialer/leads/lead/sms',{method:'POST',body:JSON.stringify(body)}),{params:Promise.resolve({leadId:'lead'})});
  assert.equal((await call({body:''})).status,400);assert.equal(sent,0);
  const response=await call({body:'Demo: https://wolfgrid.app/demo1',phone:'+14165550100'});
  assert.equal(response.status,200);assert.equal((await response.json()).warning,'Demo reminder saved');
  assert.equal(recorded[0].actorUserId,'rep');assert.equal(recorded[0].leadId,'lead');assert.equal(recorded[0].providerEventId,'provider-id');
});

test('opening a tracked demo records the click without creating or rescheduling follow-ups',async()=>{
  const writes:Array<{table:string,patch:any}>=[];const pipeline:any[]=[];
  const admin={from(table:string){const q:any={eq:()=>q,update:(patch:any)=>{writes.push({table,patch});return q;},insert:(patch:any)=>{writes.push({table,patch});return q;},then:(resolve:any)=>Promise.resolve({error:null}).then(resolve)};return q;}};
  const {recordDemoLinkOpen}=load('../../dialer/demo-link-tracking.ts',{
    '@/app/lib/ambassador/tracking':{getTrackingMetadata:()=>({})},'@/app/lib/ambassador/portal':{},'@/lib/supabase/server':{},
    '@/lib/sales-pipeline/server':{recordDemoOpenInPipeline:async(input:any)=>pipeline.push(input)},
  });
  await recordDemoLinkOpen({admin,request:new NextRequest('https://example.test/d/token'),link:{id:'link',salesperson_id:'rep',dialler_lead_id:'lead',workspace_id:'shared',open_count:0}});
  assert.deepEqual(writes.map(write=>write.table),['salesperson_demo_links','salesperson_click_events']);
  assert.equal(writes[0].patch.open_count,1);assert.equal(writes[0].patch.follow_up_due_at,undefined);
  assert.equal(pipeline[0].followUpDueAt,undefined);
});
