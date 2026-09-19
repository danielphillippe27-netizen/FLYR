import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createSalesFixture} from './field_sales_fixture.mjs';

const {db,id}=await createSalesFixture();
for(const file of [
  '20260916120000_pro_sales_foundation.sql',
  '20260916121000_pro_sales_records.sql',
  '20260916127000_pro_sales_entry.sql',
  '20260917120000_appointment_sales_v1.sql',
]) await db.exec(await readFile(new URL(`../migrations/${file}`,import.meta.url),'utf8'));

await db.exec(`
 INSERT INTO field_sales_settings(workspace_id,enabled,currency,timezone)
 VALUES('${id(10)}',true,'CAD','America/Toronto');
 INSERT INTO contact_activities(id,contact_id,type,timestamp,status) VALUES
 ('${id(40)}','${id(30)}','meeting',now()-interval '2 hours','completed'),
 ('${id(41)}','${id(30)}','meeting',now()-interval '1 hour','completed'),
 ('${id(42)}','${id(31)}','meeting',now()-interval '1 hour','completed'),
 ('${id(43)}','${id(30)}','meeting',now()+interval '1 hour','scheduled'),
 ('${id(44)}','${id(30)}','meeting',now()-interval '1 hour','cancelled'),
 ('${id(45)}','${id(33)}','meeting',now()-interval '1 hour','completed');
`);

const actor=async n=>db.exec(`RESET ROLE;SET ROLE authenticated;SET request.jwt.claim.sub='${id(n)}'`);
const entry=async(c={})=>(await db.query('select field_sales_entry($1,$2) d',[id(10),c])).rows[0].d;
const command=async(d)=>(await db.query("select field_sales_command($1,'submit',$2) d",[id(10),d])).rows[0].d;

await actor(2);
let data=await entry();
assert.deepEqual(data.appointment_options.map(x=>x.id).sort(),[id(40),id(41)].sort());
assert.equal(data.contacts.length,0);
await assert.rejects(()=>entry({contact_id:id(30)}),/Select an appointment/);
await assert.rejects(()=>entry({appointment_id:id(43),contact_id:id(30)}),/eligible past/);
await assert.rejects(()=>entry({appointment_id:id(44),contact_id:id(30)}),/eligible past/);
await assert.rejects(()=>command({request_id:id(100),contact_id:id(30),value_minor:'10000'}),/appointment/);

data=await entry({appointment_id:id(40),contact_id:id(30)});
assert.equal(data.selected.appointment_id,id(40));
assert.equal(data.selected.rep_id,id(2));
const first=await command({request_id:id(101),contact_id:id(30),appointment_id:id(40),value_minor:'10000'});
await assert.rejects(()=>entry({appointment_id:id(40),contact_id:id(30)}),/eligible past/);
await actor(1);
await assert.rejects(()=>command({request_id:id(102),contact_id:id(30),appointment_id:id(40),value_minor:'20000',job_identifier:'other',duplicate_override_reason:'other'}),/already been converted/);

data=await entry();
assert.ok(data.appointment_options.some(x=>x.id===id(41)),'owner can convert a member appointment');
assert.ok(data.appointment_options.some(x=>x.id===id(42)),'owner can convert an owner appointment');
await assert.rejects(()=>command({request_id:id(103),contact_id:id(30),appointment_id:id(41),rep_id:id(1),value_minor:'30000',job_identifier:'wrong-rep',duplicate_override_reason:'Testing attribution guard'}),/credited to the representative/);
const converted=await command({request_id:id(104),contact_id:id(30),appointment_id:id(41),value_minor:'30000',job_identifier:'second-appointment',duplicate_override_reason:'Separate appointment and contract'});
await db.exec('RESET ROLE');
const row=(await db.query('select appointment_id,rep_id,created_by from field_sales where id=$1',[converted.id])).rows[0];
assert.equal(row.appointment_id,id(41));
assert.equal(row.rep_id,id(2),'appointment owner keeps sale credit');
assert.equal(row.created_by,id(1),'owner is recorded as converter');
assert.ok(first.id);

console.log('PASS appointment-led Sales V1: eligible appointment picker, required source, one active conversion, owner/member access and rep attribution');
await db.close();
