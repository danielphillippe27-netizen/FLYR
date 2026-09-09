import { requirePersonalReferences } from '../../sales-pro/personal-references';
import { containsDemoLink } from '../../salesperson/outreach-metrics';
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import vm from 'node:vm';
import ts from 'typescript';
import { NextRequest } from 'next/server';

const require = createRequire(import.meta.url);
function load(path: string, overrides: Record<string, unknown>) {
  const source = readFileSync(new URL(path, import.meta.url), 'utf8');
  const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
  const module = { exports: {} as any };
  vm.runInNewContext(compiled, { exports: module.exports, module, require: (id: string) => overrides[id] ?? require(id), console, process, Date, File });
  return module.exports;
}
function db(tables: Record<string, any[]>) {
  return { from(table: string) {
    const filters: Array<(r: any) => boolean> = [];
    let update: any, insert: any;
    const embeddedFilters: Array<[string,string,unknown]> = [];
    const execute = () => {
      if (insert) (tables[table] ??= []).push({ id: `new-${tables[table]?.length ?? 0}`, ...insert });
      const rows = (tables[table] ?? []).filter(r => filters.every(f => f(r)));
      if (update) rows.forEach(r => Object.assign(r, update));
      const selected = (insert ? tables[table].slice(-1) : rows).map(row => {
        const result = { ...row };
        for (const [relation, key, value] of embeddedFilters) {
          const child = result[relation];
          result[relation] = Array.isArray(child) ? child.filter(item => item[key] === value)
            : child && child[key] === value ? child : null;
        }
        return result;
      });
      return { data: selected, error: null };
    };
    const q: any = {
      select: () => q, order: () => q, limit: () => q,
      eq: (k: string, v: unknown) => { if (k.includes(".")) { const [relation,key] = k.split("."); embeddedFilters.push([relation,key,v]); } else filters.push(r => r[k] === v); return q; },
      neq: (k: string, v: unknown) => { filters.push(r => r[k] !== v); return q; },
      is: (k: string, v: unknown) => { filters.push(r => r[k] === v); return q; },
      in: (k: string, v: unknown[]) => { filters.push(r => v.includes(r[k])); return q; },
      or: () => q, contains: () => q,
      update: (v: any) => { update = v; return q; },
      insert: (v: any) => { insert = v; return q; },
      single: async () => { const r = execute(); return { ...r, data: r.data[0] ?? null }; },
      maybeSingle: async () => { const r = execute(); return { ...r, data: r.data[0] ?? null }; },
      throwOnError: async () => execute(),
      then: (resolve: any, reject: any) => Promise.resolve(execute()).then(resolve, reject),
    };
    return q;
  } };
}
function inbox(tables: Record<string, any[]>, userId = 'daniel-hughes') {
  return load('../../../app/api/inbox/route.ts', {
    '@/lib/supabase/server': { createAdminClient: () => db(tables) },
    '../dialer/_utils': { resolveDialerWorkspace: async () => ({ context: { workspace: { id: 'shared' }, user: { id: userId } } }) },
    '@/lib/dialer/telnyx-messaging': { normalizePhone: (s: any) => s },
    '@/lib/sales-pro/communications': {}, '@/lib/email/icloud-sync': { syncICloudInbox: async () => {} },
    '@/lib/email/thread-identity': { counterpartyEmail: () => null, replyEmailForEvents: () => null },
    '@/lib/dialer/salesperson-settings': {},
  });
}
const event = (id: string, user: string) => ({ id, actor_user_id: user, workspace_id: 'shared', channel: 'call', direction: 'inbound', event_kind: 'call', occurred_at: '2026-09-09T01:00:00Z', body: id });
test('first-time user sees none of another workspace member’s canonical or fallback communications', async () => {
  const tables = {
    communication_threads: [{ id: 'private-thread', workspace_id: 'shared', assigned_user_id: 'other', communication_events: [event('secret', 'other')] }],
    dialer_calls: [{ id: 'call', workspace_id: 'shared', user_id: 'other' }],
    dialer_messages: [{ id: 'sms', workspace_id: 'shared', sender_user_id: 'other' }],
    contact_activities: [{ id: 'legacy-private-note' }],
  };
  const res = await inbox(tables).GET(new NextRequest('https://example.test/api/inbox'));
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.deepEqual(body.threads, []);
  assert.deepEqual(body.items, []);
});
test('mixed legacy threads never return another user’s nested events', async () => {
  const tables = { communication_threads: [{ id: 'mixed', workspace_id: 'shared', assigned_user_id: 'daniel-hughes', communication_events: [event('mine', 'daniel-hughes'), event('secret', 'other')] }] };
  const res = await inbox(tables).GET(new NextRequest('https://example.test/api/inbox'));
  const body = await res.json();
  assert.equal(body.threads.length, 1);
  assert.deepEqual(body.threads[0].events.map((e: any) => e.id), ['mine']);
});
test('foreign event, thread and SMS IDs cannot be marked read or changed', async () => {
  const tables = {
    communication_events: [{ id: 'private-event', workspace_id: 'shared', actor_user_id: 'other', thread_id: 'private-thread' }],
    communication_threads: [{ id: 'private-thread', workspace_id: 'shared', assigned_user_id: 'other' }],
    dialer_messages: [{ id: 'private-sms', workspace_id: 'shared', sender_user_id: 'other' }],
  };
  const before = JSON.stringify(tables);
  for (const id of ['private-event', 'private-thread', 'sms:private-sms']) {
    await inbox(tables).PATCH(new NextRequest('https://example.test/api/inbox', { method: 'PATCH', body: JSON.stringify({ id, read: true, status: 'done' }) }));
  }
  assert.equal(JSON.stringify(tables), before);
});
test('same-contact conversations are separate per user, and unowned events cannot join a personal thread', async () => {
  const tables: Record<string, any[]> = { communication_threads: [], communication_events: [], sales_contacts: [{ id: 'same-contact', workspace_id: 'shared', owner_user_id: 'other' }] };
  const { appendCommunication } = load('../../sales-pro/communications.ts', {
    '@/lib/sales-pro/personal-references': { requirePersonalReferences }, '@/lib/salesperson/outreach-metrics': { containsDemoLink }, resend: {}, '@/lib/dialer/telnyx-messaging': {}, '@/lib/sales-pro/automation-trigger': {},
    '@/lib/sales-pro/notifications': {}, '@/lib/email/icloud-client': {}, '@/lib/email/signature': {},
    '@/lib/email/demo': {}, '@/lib/dialer/salesperson-settings': {},
  });
  for (const user of ['other', 'daniel-hughes', null]) {
    await appendCommunication(db(tables), { workspaceId: 'shared', contactId: 'same-contact', actorUserId: user, channel: 'call', direction: 'inbound', eventKind: 'call' });
  }
  assert.equal(tables.communication_threads.length, 3);
  assert.equal(new Set(tables.communication_events.map(e => e.thread_id)).size, 3);
  assert.equal(tables.communication_events.find(e => e.actor_user_id === 'other').sales_contact_id, 'same-contact');
  assert.equal(tables.communication_events.find(e => e.actor_user_id === 'daniel-hughes').sales_contact_id, null);
  assert.equal(tables.communication_events.find(e => e.actor_user_id === null).sales_contact_id, null);
});
test('number ownership resolves the recipient, never the caller or workspace owner', async () => {
  const { communicationNumberOwner } = load('../../sales-pro/communication-owner.ts', {});
  const tables = {
    salesperson_dialer_settings: [{ assigned_phone_number: '+14165550101', number_status: 'active', workspace_id: 'shared', salesperson_id: 'rep' }],
    salespeople: [{ id: 'rep', workspace_id: 'shared', status: 'active', user_id: 'daniel-hughes' }],
  };
  assert.equal((await communicationNumberOwner(db(tables), '+14165550101')).userId, 'daniel-hughes');
  assert.equal(await communicationNumberOwner(db(tables), '+14165550999'), null);
  tables.salespeople[0].status = 'inactive';
  assert.equal(await communicationNumberOwner(db(tables), '+14165550101'), null);
});
test('even a workspace owner cannot download another user’s recording by call ID', async () => {
  const tables = { dialer_calls: [{ id: 'secret-call', workspace_id: 'shared', user_id: 'other' }] };
  const route = load('../../../app/api/dialer/calls/[callId]/recording/route.ts', {
    '@/lib/dialer/server': { getDialerRequestContext: async () => ({ workspaceId: 'shared', requestUser: { id: 'daniel-hughes' }, role: 'owner', admin: db(tables) }) },
    '@/lib/dialer/env': {}, '@/lib/dialer/recordings': {}, '@/lib/dialer/telnyx': {},
  });
  const res = await route.GET(new NextRequest('https://example.test/api/dialer/calls/secret-call/recording'), { params: Promise.resolve({ callId: 'secret-call' }) });
  assert.equal(res.status, 404);
});
test('replayed provider IDs cannot return another user’s communication', async () => {
  const tables = { communication_events: [{ id: 'secret-event', workspace_id: 'shared', actor_user_id: 'other', provider: 'icloud', provider_event_id: 'same-message' }] };
  const { appendCommunication } = load('../../sales-pro/communications.ts', {
    '@/lib/sales-pro/personal-references': { requirePersonalReferences }, '@/lib/salesperson/outreach-metrics': { containsDemoLink }, resend: {}, '@/lib/dialer/telnyx-messaging': {}, '@/lib/sales-pro/automation-trigger': {},
    '@/lib/sales-pro/notifications': {}, '@/lib/email/icloud-client': {}, '@/lib/email/signature': {},
    '@/lib/email/demo': {}, '@/lib/dialer/salesperson-settings': {},
  });
  await assert.rejects(appendCommunication(db(tables), {
    workspaceId: 'shared', actorUserId: 'daniel-hughes', provider: 'icloud', providerEventId: 'same-message',
    channel: 'email', direction: 'inbound', eventKind: 'email_received',
  }), /different communication owner/);
});

test('personal task and booking APIs reject foreign links before writes or automation, including owners', async () => {
  const tables: Record<string, any[]> = {
    sales_contacts: [{id:'foreign',workspace_id:'shared',owner_user_id:'other'}],
    sales_leads: [], sales_tasks: [],
    sales_bookings: [{id:'mine',workspace_id:'shared',assigned_user_id:'daniel-hughes',sales_contact_id:'foreign'}],
  };
  let automations = 0;
  const overrides = {
    '@/lib/sales-pro/personal-references': { requirePersonalReferences },
    '@/lib/sales-pro/context': {
      requireSalesProContext: async()=>({admin:db(tables),workspaceId:'shared',userId:'daniel-hughes',role:'owner'}),
      cleanText: (value: unknown)=>typeof value==='string' ? value.trim() || null : null,
    },
    '@/lib/sales-pro/automation-trigger': { triggerSalesAutomations: async()=>{automations++;} },
  };
  const before=JSON.stringify(tables);
  const task=load('../../../app/api/tasks/route.ts',overrides);
  const booking=load('../../../app/api/bookings/route.ts',overrides);
  const created=await task.POST(new NextRequest('https://example.test/api/tasks',{method:'POST',body:JSON.stringify({title:'Follow up',contactId:'foreign'})}));
  assert.equal(created.status,404);
  const changed=await booking.PATCH(new NextRequest('https://example.test/api/bookings',{method:'PATCH',body:JSON.stringify({id:'mine',outcome:'held',nextTaskTitle:'Next meeting'})}));
  assert.equal(changed.status,404);
  assert.equal(JSON.stringify(tables),before);
  assert.equal(automations,0);
});

test('personal inbox does not expand a foreign legacy contact reference', async () => {
  const tables = { communication_threads: [{ id:'mine', workspace_id:'shared', assigned_user_id:'daniel-hughes',
    sales_contacts:{id:'foreign',owner_user_id:'other',workspace_id:'shared',name:'Private colleague contact',email:'private@example.test'},
    communication_events:[event('mine','daniel-hughes')] }] };
  const response = await inbox(tables).GET(new NextRequest('https://example.test/api/inbox'));
  const body = await response.json();
  assert.equal(body.threads.length,1);
  assert.equal(JSON.stringify(body).includes('private@example.test'),false);
  assert.equal(JSON.stringify(body).includes('Private colleague contact'),false);
});

test('generic contacts API remains user-specific when a workspace is selected', async () => {
  const tables={contacts:[{id:'mine',user_id:'daniel-hughes',workspace_id:'shared',full_name:'My contact'},
    {id:'foreign',user_id:'other',workspace_id:'shared',full_name:'Private contact'}]};
  const route=load('../../../app/api/contacts/route.ts',{
    '@/app/api/_utils/request-user':{resolveUserFromRequest:async()=>({id:'daniel-hughes'})},
    '@/app/api/_utils/workspace':{resolveWorkspaceIdForUser:async()=>({workspaceId:'shared'})},
    '@/lib/supabase/server':{createAdminClient:()=>db(tables)},
    '@/lib/integrations/auto-push':{},
  });
  const response=await route.GET(new NextRequest('https://example.test/api/contacts?workspaceId=shared'));
  assert.equal(response.status,200);
  assert.deepEqual((await response.json()).map((row:any)=>row.id),['mine']);
});

test('contact creation rejects foreign campaign and farm references before saving or CRM push', async () => {
  const tables={contacts:[],campaigns:[{id:'foreign',owner_id:'other',workspace_id:'shared'}],farms:[{id:'foreign',owner_id:'other',workspace_id:'shared'}]};
  let pushed=false;
  const route=load('../../../app/api/contacts/route.ts',{
    '@/app/api/_utils/request-user':{resolveUserFromRequest:async()=>({id:'daniel-hughes'})},
    '@/app/api/_utils/workspace':{resolveWorkspaceIdForUser:async()=>({workspaceId:'shared'})},
    '@/lib/supabase/server':{createAdminClient:()=>db(tables)},
    '@/lib/integrations/auto-push':{pushLeadToConnectedCrms:async()=>{pushed=true;return [];}},
  });
  for(const reference of [{campaign_id:'foreign'},{farm_id:'foreign'}]) {
    const response=await route.POST(new NextRequest('https://example.test/api/contacts',{method:'POST',body:JSON.stringify({fullName:'Prospect',workspaceId:'shared',...reference})}));
    assert.equal(response.status,404);
  }
  assert.equal(tables.contacts.length,0);
  assert.equal(pushed,false);
});

test('CRM contacts reject foreign companies on create and update', async () => {
  const tables={sales_contacts:[{id:'mine',owner_user_id:'daniel-hughes',workspace_id:'shared'}],sales_companies:[{id:'foreign',owner_user_id:'other',workspace_id:'shared'}]};
  const route=load('../../../app/api/crm/contacts/route.ts',{
    '@/lib/sales-pro/personal-references':{requirePersonalReferences},
    '@/lib/sales-pro/context':{requireSalesProContext:async()=>({admin:db(tables),userId:'daniel-hughes',workspaceId:'shared'}),cleanText:(v:any)=>typeof v==='string'?v:null},
  });
  const before=JSON.stringify(tables);
  for(const method of ['POST','PATCH']) {
    const response=await route[method](new NextRequest('https://example.test/api/crm/contacts',{method,body:JSON.stringify({id:'mine',name:'Prospect',companyId:'foreign'})}));
    assert.equal(response.status,404);
  }
  assert.equal(JSON.stringify(tables),before);
});

test('recording lookup rejects a foreign lead even for workspace owners with a matching legacy salesperson ID', async () => {
  const tables={sales_leads:[{id:'foreign',workspace_id:'shared',assigned_user_id:'other',assigned_salesperson_id:'legacy-rep'}]};
  const route=load('../../../app/api/dialer/leads/[leadId]/recording/route.ts',{
    '@/lib/dialer/server':{getDialerRequestContext:async()=>({admin:db(tables),workspaceId:'shared',requestUser:{id:'daniel-hughes'},role:'owner',salesperson:{id:'legacy-rep'}})},
    '@/lib/dialer/env':{},'@/lib/dialer/recordings':{},'@/lib/dialer/telnyx':{},
  });
  const response=await route.GET(new NextRequest('https://example.test/api/dialer/leads/foreign/recording'),{params:Promise.resolve({leadId:'foreign'})});
  assert.equal(response.status,404);
});

test('Resend inbound copies are mailbox-specific when both users receive one email', async () => {
  const priorKey=process.env.RESEND_API_KEY,priorSecret=process.env.RESEND_WEBHOOK_SECRET;
  process.env.RESEND_API_KEY='test';process.env.RESEND_WEBHOOK_SECRET='test';
  try {
    const tables={sales_mailboxes:[{id:'a',address:'a@example.test',workspace_id:'shared',user_id:'a',is_active:true},{id:'b',address:'b@example.test',workspace_id:'shared',user_id:'b',is_active:true}],sales_contacts:[]};
    const appended:any[]=[];
    class MockResend {
      webhooks={verify:()=>({type:'email.received',data:{email_id:'same-email',received_for:['a@example.test','b@example.test']}})};
      emails={receiving:{get:async()=>({data:{from:'prospect@example.test',to:['a@example.test','b@example.test'],headers:{},message_id:'same-message',text:'Hello'}})}};
    }
    const route=load('../../../app/api/webhooks/resend/route.ts',{
      resend:{Resend:MockResend},'@/lib/supabase/server':{createAdminClient:()=>db(tables)},
      '@/lib/sales-pro/communications':{appendCommunication:async(_:any,event:any)=>{appended.push(event);}},
    });
    const response=await route.POST(new NextRequest('https://example.test/api/webhooks/resend',{method:'POST',body:'{}'}));
    assert.equal(response.status,200);assert.equal(appended.length,2);
    assert.deepEqual(appended.map(e=>e.actorUserId),['a','b']);
    assert.equal(new Set(appended.map(e=>e.providerEventId)).size,2);
  } finally {
    if(priorKey===undefined) delete process.env.RESEND_API_KEY;else process.env.RESEND_API_KEY=priorKey;
    if(priorSecret===undefined) delete process.env.RESEND_WEBHOOK_SECRET;else process.env.RESEND_WEBHOOK_SECRET=priorSecret;
  }
});

test('CSV import permits the same prospect for two users and still deduplicates personal repeats', async () => {
  const rows:any[]=[{id:'foreign',workspace_id:'shared',assigned_user_id:'other',name:'Prospect',phone:'14165550100'}];
  const admin={from(){
    const filters:Array<(row:any)=>boolean>=[];let inserts:any[]|null=null;
    const q:any={select:()=>q,eq:(key:string,value:any)=>{filters.push(row=>row[key]===value);return q;},
      insert:(value:any[])=>{inserts=value;return q;},then:(resolve:any,reject:any)=>{
        const data=inserts?inserts.map(row=>({id:`new-${rows.length}`, ...row})):rows.filter(row=>filters.every(f=>f(row)));
        if(inserts)rows.push(...data);
        return Promise.resolve({data,error:null}).then(resolve,reject);
      }};return q;
  }};
  const route=load('../../../app/api/leads/import/route.ts',{
    '@/lib/supabase/server':{createAdminClient:()=>admin},
    '@/app/api/_utils/request-user':{resolveUserFromRequest:async()=>({id:'daniel-hughes'})},
    '@/app/api/_utils/workspace':{resolveWorkspaceIdForUser:async()=>({workspaceId:'shared'})},
    '@/lib/dialer/phone':{normalizePhoneMarket:()=> 'CA',normalizePhoneNumber:()=>({e164:'14165550100'})},
  });
  for(const expected of [1,0]) {
    const form=new FormData();form.set('workspaceId','shared');form.set('file',new File(['name,phone\nProspect,14165550100'],'leads.csv',{type:'text/csv'}));
    const response=await route.POST(new NextRequest('https://example.test/api/leads/import',{method:'POST',body:form}));
    assert.equal(response.status,200);assert.equal((await response.json()).imported,expected);
  }
  assert.equal(rows.length,2);assert.equal(rows[1].assigned_user_id,'daniel-hughes');
});

test('push registration switches a shared device to the signed-in user', async () => {
  const rows:any[]=[{user_id:'other',token:'device',platform:'ios',environment:'production',enabled:true}];
  const admin={from(){const filters:Array<(r:any)=>boolean>=[];let updates:any,insert:any;
    const q:any={update:(v:any)=>{updates=v;return q;},eq:(k:string,v:any)=>{filters.push(r=>r[k]===v);return q;},neq:(k:string,v:any)=>{filters.push(r=>r[k]!==v);return q;},
      upsert:(v:any)=>{insert=v;return q;},then:(resolve:any,reject:any)=>{
        if(updates)rows.filter(r=>filters.every(f=>f(r))).forEach(r=>Object.assign(r,updates));
        if(insert)rows.push(insert);
        return Promise.resolve({error:null}).then(resolve,reject);
      }};return q;}};
  const route=load('../../../app/api/devices/push-token/route.ts',{
    '@/app/api/_utils/request-user':{resolveUserFromRequest:async()=>({id:'daniel-hughes'})},
    '@/lib/supabase/server':{createAdminClient:()=>admin},
  });
  const response=await route.POST(new NextRequest('https://example.test/api/devices/push-token',{method:'POST',body:JSON.stringify({token:'device'})}));
  assert.equal(response.status,200);assert.deepEqual(rows.filter(r=>r.enabled).map(r=>r.user_id),['daniel-hughes']);
  await route.DELETE(new NextRequest('https://example.test/api/devices/push-token',{method:'DELETE',body:JSON.stringify({token:'device'})}));
  assert.equal(rows.filter(r=>r.enabled).length,0);
});

test('automatic enrollment uses only the record owner’s definitions and rejects foreign records', async () => {
  const tables:Record<string,any[]>={sales_leads:[{id:'mine',workspace_id:'shared',assigned_user_id:'daniel-hughes'}],
    sales_automation_definitions:[{id:'mine',workspace_id:'shared',created_by_user_id:'daniel-hughes',trigger_type:'missed_call',is_enabled:true,active_version:1},
      {id:'other',workspace_id:'shared',created_by_user_id:'other',trigger_type:'missed_call',is_enabled:true,active_version:1}],
    sales_sequence_enrollments:[],sales_automation_executions:[]};
  const {triggerSalesAutomations}=load('../../sales-pro/automation-trigger.ts',{'@/lib/sales-pro/personal-references':{requirePersonalReferences}});
  await triggerSalesAutomations(db(tables),{workspaceId:'shared',leadId:'mine',ownerUserId:'daniel-hughes',triggerType:'missed_call'});
  assert.equal(tables.sales_sequence_enrollments.length,1);
  assert.equal(tables.sales_sequence_enrollments[0].automation_id,'mine');
  await assert.rejects(triggerSalesAutomations(db(tables),{workspaceId:'shared',leadId:'mine',ownerUserId:'other',triggerType:'missed_call'}),/not found/);
  assert.equal(tables.sales_sequence_enrollments.length,1);
});

test('booking links hide foreign personal links and reject foreign member creation or editing', async () => {
  const tables={sales_booking_links:[{id:'foreign',workspace_id:'shared',owner_user_id:'other',mode:'personal'},{id:'mine',workspace_id:'shared',owner_user_id:'daniel-hughes',mode:'personal'}],workspace_members:[{user_id:'daniel-hughes',workspace_id:'shared'}]};
  const route=load('../../../app/api/booking-links/route.ts',{'@/lib/sales-pro/context':{
    requireSalesProContext:async()=>({admin:db(tables),workspaceId:'shared',userId:'daniel-hughes',role:'owner'}),
    cleanText:(value:any)=>typeof value==='string'?value:null,
  }});
  const listed=await route.GET(new NextRequest('https://example.test/api/booking-links'));
  assert.deepEqual((await listed.json()).links.map((link:any)=>link.id),['mine']);
  const before=JSON.stringify(tables);
  const patched=await route.PATCH(new NextRequest('https://example.test/api/booking-links',{method:'PATCH',body:JSON.stringify({id:'foreign',title:'Changed'})}));
  assert.equal(patched.status,404);
  const created=await route.POST(new NextRequest('https://example.test/api/booking-links',{method:'POST',body:JSON.stringify({title:'Team',mode:'round_robin',memberUserIds:['outside-workspace']})}));
  assert.equal(created.status,403);assert.equal(JSON.stringify(tables),before);
});
