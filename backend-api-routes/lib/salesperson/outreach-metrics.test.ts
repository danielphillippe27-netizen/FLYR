import assert from 'node:assert/strict';
import test from 'node:test';
import { containsDemoLink, countPersonalOutreach, loadPersonalOutreach } from './outreach-metrics';

test('demo links match actual WolfGrid destinations, not lookalike domains or draft labels', () => {
  assert.equal(containsDemoLink('Watch https://wolfgrid.app/demo100'), true);
  assert.equal(containsDemoLink('Demo: https://wolfgrid.app/demo-2?ref=HUGHES.'), true);
  assert.equal(containsDemoLink('https://wolfgrid.app.evil.example/demo100'), false);
  assert.equal(containsDemoLink('Demo prepared'), false);
});

test('counts each accepted send once across webhook, canonical and legacy copies; excludes failures and inbound', () => {
  const counts = countPersonalOutreach([
    { id: 'c1', direction: 'outbound', channel: 'sms', provider: 'telnyx', provider_event_id: 'sms-1', body: 'https://wolfgrid.app/demo100' },
    { id: 'c2', direction: 'outbound', channel: 'sms', provider: 'telnyx', provider_event_id: 'webhook-1', metadata: { providerMessageId: 'sms-1' } },
    { id: 'c3', direction: 'outbound', channel: 'email', provider: 'icloud', provider_event_id: 'mail-1', event_kind: 'demo_sent', status: 'sent' },
    { id: 'failed', direction: 'outbound', channel: 'email', status: 'failed', body: 'https://wolfgrid.app/demo100' },
    { id: 'inbound', direction: 'inbound', channel: 'email', body: 'https://wolfgrid.app/demo100' },
  ], [{ id: 'legacy', direction: 'outbound', provider: 'telnyx', provider_message_id: 'sms-1' }],
  [{ id: 'followup', telecom_provider: 'telnyx', provider_message_id: 'sms-1' }], []);
  assert.deepEqual(counts, { inboundMessages: 0, outboundMessages: 1, emails: 1, demosSent: 2 });
});

function database(tables: Record<string, any[]>) {
  return { from(table: string) {
    const filters: Array<(row: any) => boolean> = [];
    let from = 0, to = 999;
    const value = (row: any, key: string) => key.split('.').reduce((v, part) => v?.[part], row);
    const q: any = {
      select: () => q, order: () => q,
      eq: (key: string, v: any) => { filters.push(row => value(row,key) === v); return q; },
      gte: (key: string,v: any) => { filters.push(row => value(row,key) >= v); return q; },
      lt: (key: string,v: any) => { filters.push(row => value(row,key) < v); return q; },
      range: (start: number,end: number) => { from=start; to=end; return q; },
      then: (resolve: any,reject: any) => Promise.resolve({ data: (tables[table] ?? []).filter(row=>filters.every(f=>f(row))).slice(from,to+1), error:null }).then(resolve,reject),
    };
    return q;
  } } as any;
}

test('metric queries exclude coworkers and other workspaces, and attribute email to its sender after contact reassignment', async () => {
  const rows = ['hughes','phillippe'].flatMap(user => ['workspace-a','workspace-b'].map(workspace => ({
    id: `${user}:${workspace}`, workspace_id: workspace, actor_user_id: user,
    channel: 'email', direction: 'outbound', occurred_at: '2026-09-09T10:00:00Z', event_kind: 'demo_sent', status: 'sent',
  })));
  const admin = database({ communication_events: rows, contact_activities: [
    { id: 'old-email', communication_owner_user_id:'hughes', contacts:{workspace_id:'workspace-a',user_id:'phillippe'}, type:'email', timestamp:'2026-09-09T10:00:00Z' },
    { id: 'foreign-email', communication_owner_user_id:'phillippe', contacts:{workspace_id:'workspace-a',user_id:'hughes'}, type:'email', timestamp:'2026-09-09T10:00:00Z' },
  ] });
  const result = await loadPersonalOutreach(admin,{userId:'hughes',workspaceId:'workspace-a',start:'2026-09-09T00:00:00Z',end:'2026-09-10T00:00:00Z'});
  assert.deepEqual(result,{inboundMessages:0,outboundMessages:0,emails:2,demosSent:1});
});

test('counts beyond the database page limit and uses an exclusive period end', async () => {
  const rows = Array.from({length:1001},(_,i)=>({id:String(i), workspace_id:'w',actor_user_id:'u',channel:'email',direction:'outbound',occurred_at:'2026-09-09T10:00:00Z'}));
  rows.push({...rows[0],id:'boundary',occurred_at:'2026-09-10T00:00:00Z'});
  assert.equal((await loadPersonalOutreach(database({communication_events:rows}),{userId:'u',workspaceId:'w',start:'2026-09-09T00:00:00Z',end:'2026-09-10T00:00:00Z'})).emails,1001);
});

test('received SMS totals use recipient ownership and deduplicate canonical/legacy copies', async () => {
  const receivedAt='2026-09-09T10:00:00Z';
  const canonical=['hughes','phillippe'].flatMap(user=>['w','other'].map(workspace=>({
    id:`${user}:${workspace}`,actor_user_id:user,workspace_id:workspace,occurred_at:receivedAt,
    direction:'inbound',channel:'sms',provider:'telnyx',provider_event_id:`${user}:${workspace}`,status:'received',
  })));
  const admin=database({communication_events:canonical,dialer_inbound_messages:[
    {id:'copy',owner_user_id:'hughes',workspace_id:'w',received_at:receivedAt,telecom_provider:'telnyx',provider_message_id:'hughes:w'},
    {id:'foreign',owner_user_id:'phillippe',workspace_id:'w',received_at:receivedAt,telecom_provider:'telnyx',provider_message_id:'foreign'},
    {id:'unowned',owner_user_id:null,workspace_id:'w',received_at:receivedAt},
    {id:'boundary',owner_user_id:'hughes',workspace_id:'w',received_at:'2026-09-10T00:00:00Z'},
  ]});
  const params={workspaceId:'w',start:'2026-09-09T00:00:00Z',end:'2026-09-10T00:00:00Z'};
  assert.deepEqual(await loadPersonalOutreach(admin,{...params,userId:'hughes'}),{inboundMessages:1,outboundMessages:0,emails:0,demosSent:0});
  assert.equal((await loadPersonalOutreach(admin,{...params,userId:'new'})).inboundMessages,0);
});
