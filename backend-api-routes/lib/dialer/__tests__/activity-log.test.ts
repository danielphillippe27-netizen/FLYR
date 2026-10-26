import test from 'node:test';
import assert from 'node:assert/strict';
import { mergeActivityLogs } from '../activity-log';
const at = '2026-10-26T13:50:00Z';
test('recovers raw calls, derives duration, and merges texts and emails in time order', () => {
 const logs = mergeActivityLogs({
 calls:[{id:'call', direction:'outbound',status:'completed',created_at:at,answered_at:at,ended_at:'2026-10-26T13:51:18Z'}],
 messages:[{id:'sms',direction:'outbound',status:'delivered',created_at:'2026-10-26T14:00:00Z',body:'Demo link'}],
 communications:[{id:'email',channel:'email',direction:'outbound',occurred_at:'2026-10-26T15:04:00Z',subject:'Your WolfGrid demo',body:'Hello'}],
 });
 assert.deepEqual(logs.map(row=>row.channel),['email','sms','call']);
 assert.match(logs[2].subject,/completed · 1m 18s/);
 assert.equal(logs[1].body,'Demo link');
});
test('does not duplicate provider receipts or email activity receipts', () => {
 const logs=mergeActivityLogs({calls:[{id:'c',provider_call_id:'provider',created_at:at}],messages:[{id:'s',provider_message_id:'sms-provider',created_at:at}],communications:[{id:'c1',channel:'call',provider_event_id:'provider',occurred_at:at},{id:'s1',channel:'sms',provider_event_id:'sms-provider',occurred_at:at},{id:'e',channel:'email',occurred_at:at}],activities:[{id:'a',activity_type:'email',occurred_at:at}]});
 assert.equal(logs.length,3);
 assert.equal(logs.filter(row=>row.channel==='email').length,1);
});
test('preserves notes, follow-up creation/completion, and meeting activity', () => {
 const logs=mergeActivityLogs({activities:[{id:'n',activity_type:'note',note:'Call tomorrow',occurred_at:at}],tasks:[{id:'t',title:'Follow up',created_at:at,completed_at:'2026-10-27T13:00:00Z'}],calendar:[{id:'m',event_type:'meeting',title:'Demo',created_at:at,start_at:'2026-10-28T13:00:00Z'}]});
 assert.equal(logs.length,4);
 assert.equal(logs[0].timelineKind,'task_completed');
 assert.equal(logs.find(row=>row.channel==='note')?.body,'Call tomorrow');
 assert.match(logs.find(row=>row.channel==='meeting')!.body!,/2026-10-28/);
 assert.equal(new Set(logs.map(row=>row.id)).size,4);
});
test('ignores corrupt dates and keeps stable IDs across refreshes', () => {
 const source={activities:[{id:'bad',occurred_at:'bad'},{id:'ok',occurred_at:at,activity_type:'note'}]};
 assert.deepEqual(mergeActivityLogs(source).map(row=>row.id),['activity:ok']);
 assert.deepEqual(mergeActivityLogs(source),mergeActivityLogs(source));
});

test('every communication source stays scoped to the signed-in user and workspace', async () => {
 const { loadActivityLogs }=await import('../activity-log');
 const queries: {table:string;filters:[string,unknown][]}[]=[];
 const admin={from(table:string) {
  const record={table,filters:[] as [string,unknown][]};queries.push(record);
  const query:any={select(){return query},eq(key:string,value:unknown){record.filters.push([key,value]);return query},in(){return query},or(){return query},order(){return query},limit(){return query},then(resolve:any){return Promise.resolve({data:table==='sales_leads'?[{id:'lead',phone:'+19059491553'}]:[],error:null}).then(resolve)}};return query;
 }};
 await loadActivityLogs({admin,userId:'owner',workspaceId:'workspace'},{leadId:'lead'},25,0);
 for(const table of ['dialer_calls','dialer_messages','sales_activities','communication_events','sales_tasks','sales_bookings','calendar_events']) {
  const query=queries.find(row=>row.table===table)!;
  assert.ok(query.filters.some(([key,value])=>key==='workspace_id'&&value==='workspace'),table);
  assert.ok(query.filters.some(([key,value])=>key!=='workspace_id'&&value==='owner'),table);
 }
});
