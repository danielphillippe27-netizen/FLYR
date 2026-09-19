import assert from 'node:assert/strict';
import { createSalesFixture } from './field_sales_fixture.mjs';
const {db,id} = await createSalesFixture();
const actor=async n=>db.exec(`SET ROLE authenticated; SET request.jwt.claim.sub='${id(n)}';`);
const cmd=async(action,data={})=>(await db.query('SELECT field_sales_command($1,$2,$3::jsonb) result',[id(10),action,JSON.stringify(data)])).rows[0].result;
const dash=async(team=false,status=null)=>(await db.query('SELECT field_sales_dashboard($1, $2, $3, NULL,NULL,$4) result',[id(10),'month',team,status])).rows[0].result;
await actor(2);
assert.equal((await dash()).enabled,false);
await assert.rejects(cmd('submit',{}));
await db.exec(`RESET ROLE; INSERT INTO field_sales_settings(workspace_id,enabled) VALUES('${id(10)}',true);`);
await actor(2); await assert.rejects(cmd('settings',{currency:'CAD',timezone:'America/Toronto'}));
await actor(1); await cmd('settings',{currency:'CAD',timezone:'America/Toronto'});
const today=(await dash()).today;
const payload={request_id:id(100),contact_id:id(30),value_minor:'6200000',sold_on:today,notes:'Private note'};
await actor(2);
const sale=await cmd('submit',payload);
assert.deepEqual(await cmd('submit',payload),sale);
assert.equal((await dash()).totals.sales,0);
await assert.rejects(cmd('submit',{...payload,request_id:id(101)}));
await assert.rejects(cmd('submit',{...payload,request_id:id(102),contact_id:id(33)}));
await assert.rejects(cmd('verify',{id:sale.id,version:1}));
await cmd('goal',{rep_id:id(2),month:(await dash()).month,target:6});
await assert.rejects(cmd('goal',{rep_id:id(1),month:(await dash()).month,target:1}));
await actor(1);
await assert.rejects(cmd('goal',{rep_id:id(2),month:(await dash()).month,target:1}));
await cmd('verify',{id:sale.id,version:1});
await cmd('verify',{id:sale.id,version:1});
await actor(2);
let d=await dash(); assert.equal(d.totals.sales,1); assert.equal(d.totals.revenue_minor,'6200000'); assert.equal(d.goal.remaining,5);
assert.equal(d.metrics.appointment_converted,null);
assert.equal(d.metrics.sales_per_100_doors,null);
assert.equal(d.feed[0].value_minor,undefined);
assert.equal(d.ranking.find(x=>x.rep_id===id(2)).revenue_minor,undefined);
assert.equal((await dash(true)).totals.revenue_minor,undefined);
await assert.rejects(cmd('edit',{...payload,id:sale.id,version:2}));
await assert.rejects(db.query('SELECT * FROM field_sales'));
await assert.rejects(db.query('SELECT * FROM field_sales_events'));
await actor(3);
assert.equal((await dash(true)).sales[0].contact_id,undefined);
const admin=await cmd('submit',{...payload,request_id:id(103),contact_id:id(32)});
await assert.rejects(cmd('verify',{id:admin.id,version:1}));
await actor(1);
const own=await cmd('submit',{...payload,request_id:id(104),contact_id:id(31)});
await cmd('verify',{id:own.id,version:1});
await assert.rejects(cmd('settings',{currency:'USD',timezone:'America/Toronto'}));
await cmd('cancel',{id:sale.id,reason:'Contract cancelled'});
await cmd('cancel',{id:sale.id,reason:'Contract cancelled'});
await actor(2); d=await dash(); assert.equal(d.totals.sales,0); assert.equal(d.goal.remaining,6);
await actor(4); await assert.rejects(dash());
await db.exec('RESET ROLE');
const events=(await db.query('SELECT action FROM field_sales_events WHERE sale_id=$1 ORDER BY created_at',[sale.id])).rows;
assert.deepEqual(events.map(e=>e.action),['submit','verify','cancel']);

// Monetary validation, linked cohorts, old submissions, and event deduplication.
await actor(2);
for (const bad of ['0','-1','12.34','9000000000000001']) await assert.rejects(cmd('submit',{...payload,request_id:id(110),value_minor:bad}));
await assert.rejects(cmd('submit',{...payload,request_id:id(111),sold_on:'2099-01-01'}));
const replacement=await cmd('submit',{...payload,request_id:id(112),replaces_id:sale.id});
await cmd('edit',{...payload,id:replacement.id,version:1,value_minor:'6200001'});
await actor(1); await assert.rejects(cmd('verify',{id:replacement.id,version:1}));
await cmd('verify',{id:replacement.id,version:2});
await cmd('settings',{currency:'CAD',timezone:'America/Toronto',team_revenue_visible:true});
await actor(2); assert.equal((await dash(true)).ranking.find(x=>x.rep_id===id(2)).revenue_minor,'6200001');
await db.exec(`RESET ROLE;
INSERT INTO contacts(id,workspace_id,user_id,full_name,created_at) VALUES('${id(40)}','${id(10)}','${id(2)}','Cohort lead',date_trunc('month',now()));
INSERT INTO contact_activities(id,contact_id,type,timestamp,status) VALUES
('${id(41)}','${id(40)}','meeting',date_trunc('month',now()),'scheduled'),
('${id(42)}','${id(40)}','meeting',now()+interval '1 day','scheduled'),
('${id(43)}','${id(40)}','meeting',date_trunc('month',now()),'cancelled');
INSERT INTO sessions VALUES('${id(50)}','${id(10)}','${id(2)}',null);
INSERT INTO session_events(id,session_id,building_id,created_at,event_type,metadata) VALUES
('${id(51)}','${id(50)}','doorA',now()-interval '2 minutes','conversation','{"address_status":"talked"}'),
('${id(52)}','${id(50)}','doorA',now()-interval '1 minute','conversation','{"address_status":"talked"}'),
('${id(53)}','${id(50)}','doorB',now()-interval '2 minutes','completed_manual',null),
('${id(54)}','${id(50)}','doorB',now()-interval '1 minute','completion_undone',null);
`);
await actor(2);
await assert.rejects(cmd('submit',{...payload,request_id:id(113),contact_id:id(40),appointment_id:id(42)}));
await assert.rejects(cmd('submit',{...payload,request_id:id(113),contact_id:id(40),appointment_id:id(43)}));
const linked=await cmd('submit',{...payload,request_id:id(113),contact_id:id(40),appointment_id:id(41)});
await actor(1); await cmd('verify',{id:linked.id,version:1});await cmd('cancel',{id:replacement.id,reason:'Replacing unlinked fixture'});
await actor(2); d=await dash();
assert.equal(d.metrics.leads,1);assert.equal(d.metrics.lead_converted,1);
assert.equal(d.metrics.appointments,1);assert.equal(d.metrics.appointment_converted,1);
assert.equal(d.metrics.doors,1);assert.equal(d.metrics.conversations,1);assert.equal(d.metrics.sales_per_100_doors,100);
assert.equal(d.coaching.includes('cohort'),false); // Too few opportunities for conversion advice.
await actor(1); await cmd('cancel',{id:linked.id,reason:'Reverse cohort fixture'});
await actor(2); d=await dash();assert.equal(d.metrics.lead_converted,0);assert.equal(d.metrics.appointment_converted,0);
const history = async (saleID) => (await db.query('select field_sales_history($1,$2) d',[id(10),saleID])).rows[0].d;
assert.ok((await history(linked.id)).some(e=>e.action==='cancel'));
assert.equal((await history(linked.id))[0].contact_id,undefined);
await actor(3); await assert.rejects(history(linked.id).then(async () => { await actor(2); await history(admin.id); }));
await actor(2);
const historical = (await db.query("select field_sales_dashboard($1,'previous_month',false) d",[id(10)])).rows[0].d;
assert.equal(historical.metrics.doors,0);
assert.equal(historical.metrics.appointments,0);
assert.equal(historical.metrics.sales_per_100_doors,null);
assert.ok(historical.period_end < historical.today);
for (const period of ['previous_week','quarter','year']) {
 const report=(await db.query('select field_sales_dashboard($1,$2,false) d',[id(10),period])).rows[0].d;
 assert.ok(report.period_start<=report.period_end);
}
await db.exec('SET ROLE anon');await assert.rejects(dash());
console.log('PASS: disabled gate, setup permissions, idempotency, unique lead, cross-workspace rejection, verification roles, owner self-verification, money privacy, goal ownership, cancellation reversal and audit history');
await db.close();
