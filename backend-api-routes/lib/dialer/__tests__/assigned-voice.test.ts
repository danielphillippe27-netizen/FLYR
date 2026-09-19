import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import vm from 'node:vm';
import ts from 'typescript';
import { NextRequest, NextResponse } from 'next/server';
const require = createRequire(import.meta.url);
function load(path: string, overrides: Record<string, any>, globals: Record<string, any> = {}) {
  const source = readFileSync(new URL(path, import.meta.url), 'utf8');
  const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
  const module = { exports: {} as any };
  vm.runInNewContext(compiled, { exports: module.exports, module, require: (id: string) => overrides[id] ?? require(id), console, process: { env: { TELNYX_API_KEY: 'test', TELNYX_IOS_TELEPHONY_CREDENTIAL_ID: 'shared', TELNYX_FROM_NUMBER: '+16479303824' } }, ...globals });
  return module.exports;
}
function tokenHarness(assigned: boolean, denied = false) {
  const requests: string[] = [];
  const route = load('../../../app/api/dialer/token/route.ts', {
    '@/lib/dialer/server': { getDialerRequestContext: async () => denied ? NextResponse.json({}, { status: 401 }) : { workspaceId: 'sales', admin: {}, salesperson: { id: 'rep' }, settings: { defaultFromNumber: assigned ? '+14375290763' : '+16479303824', defaultSmsFromNumber: assigned ? '+14375290763' : '+16479303824', allowSmsFollowup: true } } },
    '@/lib/dialer/salesperson-settings': { getSalespersonDialerSettings: async () => assigned ? { workspace_id: 'sales', number_status: 'active', provisioning_metadata: { telnyx_telephony_credential_id: 'christian', telnyx_inbound_configured: true } } : null },
    '@/lib/dialer/telnyx-token': { cleanTelnyxToken: (s: string) => s, decodeTelnyxJwt: () => ({ sub: assigned ? 'christian' : 'shared', exp: 9999999999 }), telnyxIdentifierMisconfiguration: () => null, validateTelnyxAccessTokenPayload: () => null },
  }, { fetch: async (url: string) => { requests.push(url); return new Response('test-token'); } });
  return { requests, call: () => route.GET(new NextRequest('https://sales.wolfgrid.app/api/dialer/token?workspaceId=workspace&platform=ios')) };
}
test('voice tokens require a personal credential; unassigned users never receive the shared identity', async () => {
  for (const assigned of [true, false]) {
    const h = tokenHarness(assigned), r = await h.call(), d = await r.json();
    if (!assigned) { assert.equal(r.status, 409); assert.equal(h.requests.length, 0); continue; }
    assert.equal(r.status, 200);
    assert.equal(d.fromNumber, assigned ? '+14375290763' : '+16479303824');
    assert.equal(d.smsFromNumber, d.fromNumber);
    assert.equal(d.incomingAllowed, assigned);
    assert.equal(d.voipPushConfigured, false);
    assert.ok(h.requests[0].includes(assigned ? '/christian/token' : '/shared/token'));
  }
});
test('unauthorized users never obtain a voice token', async () => {
  const h = tokenHarness(true, true); assert.equal((await h.call()).status, 401); assert.equal(h.requests.length, 0);
});
function inboundHarness(options: { signature?: boolean; assigned?: boolean; active?: boolean; app?: string; direction?: string } = {}) {
  const actions: any[] = [], filters: any[] = [];
  const assignment = { salesperson_id: 'christian', workspace_id: 'sales', provisioning_metadata: { telnyx_telephony_credential_id: 'christian-voice', telnyx_inbound_configured: true, telnyx_call_control_application_id: 'christian-app' } };
  const route = load('../../../app/api/telnyx/voice/incoming/route.ts', {
    '@/lib/supabase/server': { createAdminClient: () => ({ from: (table: string) => { const q: any = { select: () => q, eq: (k: string,v: any) => {filters.push([table,k,v]);return q;}, maybeSingle: async () => ({ data: table === 'salespeople' ? options.active === false ? null : {user_id:'christian-user'} : options.assigned === false ? null : assignment, error: null }) }; return q; } }) },
    '@/lib/dialer/telnyx-messaging': { verifyTelnyxWebhookSignature: () => options.signature !== false },
    '@/lib/dialer/phone': { normalizePhoneNumber: (s: string) => ({e164:s}) },
    '@/lib/dialer/telnyx': { getTelnyxTelephonyCredential: async (id: string) => { assert.equal(id,'christian-voice');return {sipUsername:'gencredChristian'}; }, answerTelnyxCall: async (...args: any[]) => actions.push(['answer',...args]), transferTelnyxCall: async (...args: any[]) => actions.push(['transfer',...args]) },
  });
  const body = { data: {event_type:'call.initiated',payload:{direction:options.direction??'incoming',to:'+14375290763',call_control_id:'call-1',connection_id:options.app??'christian-app'}}};
  return { actions, filters, call: () => route.POST(new NextRequest('https://sales.wolfgrid.app/api/telnyx/voice/incoming',{method:'POST',body:JSON.stringify(body)})) };
}
test('inbound number is routed only to its active salesperson SIP identity with stable retry IDs', async () => {
  const h=inboundHarness();assert.equal((await h.call()).status,200);assert.equal((await h.call()).status,200);
  assert.equal(h.actions[1][2].to,'sip:gencredChristian@sip.telnyx.com');
  assert.equal(h.actions[1][2].commandId,h.actions[3][2].commandId);
  assert.ok(h.filters.some(f=>f[1]==='assigned_phone_number'&&f[2]==='+14375290763'));
  assert.ok(h.filters.some(f=>f[0]==='salespeople'&&f[1]==='workspace_id'&&f[2]==='sales'));
});
test('invalid signatures, unmapped numbers, inactive users and wrong applications cannot route calls', async () => {
  for(const options of [{signature:false},{assigned:false},{active:false},{app:'other-app'}]){const h=inboundHarness(options);assert.ok((await h.call()).status>=400);assert.equal(h.actions.length,0);}
  const h=inboundHarness({direction:'outgoing'});assert.equal((await h.call()).status,200);assert.equal(h.actions.length,0);
});

test('SMS sender follows the active salesperson assignment and falls back safely for other workspaces', async () => {
  const module=load('../salesperson-settings.ts', { '@/lib/dialer/phone': { normalizePhoneNumber: (s: string|null) => ({e164:s}) } });
  for(const [status,workspace,expected] of [['active','sales','+14375290763'],['unassigned','sales','+16479303824'],['active','other','+16479303824']]){
    const admin={from:(table:string)=>{const q:any={select:()=>q,eq:()=>q,order:()=>q,limit:()=>q,maybeSingle:async()=>({data:table==='salespeople'?{id:'christian',workspace_id:'sales'}:{workspace_id:workspace,number_status:status,assigned_phone_number:'+14375290763',default_sms_from_number:null},error:null})};return q;}};
    assert.equal(await module.getSalespersonSmsFromNumber(admin,{userId:'christian-user',workspaceId:'sales'},'+16479303824'),expected);
  }
});
test('Inbox SMS supplies the authenticated reps number to Telnyx and message history', async () => {
  const sends:any[]=[],stored:any[]=[];
  const query:any={upsert:(row:any)=>{stored.push(row);return query;},select:()=>query,single:async()=>({data:stored[0],error:null})};
  const route=load('../../../app/api/inbox/route.ts',{
    '@/lib/supabase/server':{createAdminClient:()=>({from:()=>query})},
    '../dialer/_utils':{resolveDialerWorkspace:async()=>({response:null,context:{workspace:{id:'sales'},user:{id:'christian-user'},role:'member'}})},
    '@/lib/dialer/telnyx-messaging':{normalizePhone:(s:any)=>s,publicMessage:(s:any)=>s,telnyxSmsFromNumber:()=>'+16479303824',sendTelnyxSms:async(p:any)=>{sends.push(p);return {id:'sms-id',to:[{status:'queued'}]};}},
    '@/lib/dialer/salesperson-settings':{getSalespersonSmsFromNumber:async(_a:any,p:any)=>{assert.equal(p.userId,'christian-user');assert.equal(p.workspaceId,'sales');return '+14375290763';}},
    '@/lib/sales-pro/communications':{appendCommunication:async()=>{}},
    '@/lib/email/icloud-sync':{},'@/lib/email/thread-identity':{},
  });
  const r=await route.POST(new NextRequest('https://sales.wolfgrid.app/api/inbox',{method:'POST',body:JSON.stringify({phone:'+14165550100',body:'Test'})}));
  assert.equal(r.status,200);assert.equal(sends[0].from,'+14375290763');assert.equal(stored[0].from_number_e164,'+14375290763');
});
