// Run with @electric-sql/pglite available on NODE_PATH. No live DB or sends.
const { PGlite } = require('@electric-sql/pglite');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const assert = require('node:assert/strict');

async function main() {
  const db = new PGlite();
  const workspace = '11111111-1111-1111-1111-111111111111';
  const owner = '22222222-2222-2222-2222-222222222222';
  const other = '33333333-3333-3333-3333-333333333333';
  const contact = '44444444-4444-4444-4444-444444444444';
  const lead = '55555555-5555-5555-5555-555555555555';
  let passed = 0;
  try {
    await db.exec(`
      CREATE TABLE sales_contacts(id uuid PRIMARY KEY,workspace_id uuid,owner_user_id uuid,name text,email text,phone text,phone_e164 text);
      CREATE TABLE sales_leads(id uuid PRIMARY KEY,workspace_id uuid,assigned_user_id uuid,sales_contact_id uuid,name text,email text,phone text,phone_e164 text,lead_state text,pipeline_stage text,signed_up_user_id uuid,disposition text);
      CREATE TABLE sales_tasks(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),workspace_id uuid,assigned_user_id uuid,sales_lead_id uuid,sales_contact_id uuid,task_type text,title text,status text,due_at timestamptz,completed_at timestamptz,notes text,metadata jsonb DEFAULT '{}',created_at timestamptz DEFAULT now());
      CREATE TABLE communication_events(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),workspace_id uuid,actor_user_id uuid,sales_lead_id uuid,sales_contact_id uuid,channel text,direction text,event_kind text,status text,metadata jsonb DEFAULT '{}',to_addresses text[],from_address text,body text,subject text,thread_id uuid,occurred_at timestamptz DEFAULT now(),provider text,provider_event_id text);
      CREATE UNIQUE INDEX provider_event_unique ON communication_events(workspace_id,provider,provider_event_id) WHERE provider IS NOT NULL AND provider_event_id IS NOT NULL;
      CREATE TABLE sales_communication_preferences(workspace_id uuid,sales_contact_id uuid,channel text,status text);
    `);
    await db.exec(readFileSync(resolve(__dirname, '../../supabase/migrations/20261026160000_demo_follow_ups.sql'), 'utf8'));
    await db.query('INSERT INTO sales_contacts VALUES($1,$2,$3,$4,$5,$6,$6)', [contact, workspace, owner, 'Sarah Jones', 'sarah@example.com', '+14165550100']);
    await db.query('INSERT INTO sales_leads(id,workspace_id,assigned_user_id,sales_contact_id,name,email,phone,phone_e164,lead_state,pipeline_stage) VALUES($1,$2,$3,$4,$5,$6,$7,$7,$8,$9)', [lead, workspace, owner, contact, 'Sarah Jones', 'sarah@example.com', '+14165550100', 'queued', 'connected']);
    async function send(overrides = {}) {
      const r = { owner, channel: 'email', kind: 'demo_sent', direction: 'outbound', status: 'sent', to: 'sarah@example.com', from: null, body: 'Demo message', lead, contact, time: '2026-10-26T14:00:00Z', provider: null, providerId: null, ...overrides };
      return (await db.query(`INSERT INTO communication_events(workspace_id,actor_user_id,sales_lead_id,sales_contact_id,channel,direction,event_kind,status,to_addresses,from_address,body,occurred_at,provider,provider_event_id)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,ARRAY[$9],$10,$11,$12,$13,$14) RETURNING *`, [workspace,r.owner,r.lead,r.contact,r.channel,r.direction,r.kind,r.status,r.to,r.from,r.body,r.time,r.provider,r.providerId])).rows[0];
    }
    const tasks = async () => (await db.query("SELECT * FROM sales_tasks WHERE task_type='demo_follow_up' ORDER BY created_at,id")).rows;
    async function check(name, fn) { await fn(); passed++; console.log(`PASS ${name}`); }
    let first;
    await check('successful send creates seven-day reminder and links send history', async () => {
      first = await send({provider:'resend',providerId:'first-send'});
      const rows = await tasks(); assert.equal(rows.length,1); assert.equal(rows[0].due_at.toISOString(),'2026-11-02T14:00:00.000Z');
      assert.equal(first.metadata.demoFollowUpTaskId,rows[0].id); assert.equal(rows[0].metadata.sendCount,1);
    });
    await check('email and text share one reminder and preserve a user snooze', async () => {
      await db.query("UPDATE sales_tasks SET due_at='2026-11-10T14:00:00Z' WHERE id=$1",[first.metadata.demoFollowUpTaskId]);
      await send({channel:'sms',to:'+14165550100',time:'2026-10-27T14:00:00Z'});
      const rows=await tasks(); assert.equal(rows.length,1); assert.equal(rows[0].metadata.sendCount,2); assert.equal(rows[0].due_at.toISOString(),'2026-11-10T14:00:00.000Z');
    });
    await check('provider replay rolls back trigger changes without duplicating reminder', async () => {
      await assert.rejects(send({provider:'resend',providerId:'first-send'}), /duplicate key/);
      assert.equal((await tasks())[0].metadata.sendCount,2);
    });
    await check('failed sends, drafts, scheduled messages, and ordinary messages create no reminders', async () => {
      const before=(await tasks())[0].metadata.sendCount;
      for(const status of ['failed','rejected','undelivered','draft','scheduled','pending']) await send({status});
      await send({kind:'email_sent'}); assert.equal((await tasks())[0].metadata.sendCount,before);
    });
    await check('another salesperson gets a separate reminder without foreign CRM links', async () => {
      await send({owner:other}); const row=(await tasks()).find(t=>t.assigned_user_id===other);
      assert.ok(row); assert.equal(row.sales_lead_id,null); assert.equal(row.sales_contact_id,null);
      assert.equal((await tasks()).find(t=>t.assigned_user_id===owner).metadata.sendCount,2);
    });
    await check('reply flags the reminder without completing it', async () => {
      await send({direction:'inbound',kind:'email_received',from:'sarah@example.com',status:'received',time:'2026-10-28T14:00:00Z'});
      const row=(await tasks()).find(t=>t.assigned_user_id===owner); assert.ok(row.metadata.replyReceivedAt); assert.equal(row.status,'open');
      assert.equal((await tasks()).find(t=>t.assigned_user_id===other).metadata.replyReceivedAt,undefined);
    });
    await check('manual follow-ups survive signup, which closes only the owner’s demo reminder', async () => {
      await db.query("INSERT INTO sales_tasks(workspace_id,assigned_user_id,sales_lead_id,task_type,title,status) VALUES($1,$2,$3,'follow_up','Manual call','open')",[workspace,owner,lead]);
      await db.query("UPDATE sales_leads SET signed_up_user_id=$1,pipeline_stage='trial_active' WHERE id=$2",[other,lead]);
      const rows=await tasks(); assert.equal(rows.find(t=>t.assigned_user_id===owner).status,'completed'); assert.equal(rows.find(t=>t.assigned_user_id===other).status,'open');
      assert.equal((await db.query("SELECT status FROM sales_tasks WHERE task_type='follow_up'")).rows[0].status,'open');
    });
    await check('converted leads cannot start another demo reminder',async()=>{await send();assert.equal((await tasks()).length,2);});
    await db.query("UPDATE sales_leads SET signed_up_user_id=null,pipeline_stage='connected' WHERE id=$1",[lead]);
    let second;
    await check('new demo after completing previous reminder creates a new cycle',async()=>{second=await send({time:'2026-11-11T14:00:00Z'});assert.equal((await tasks()).length,3);assert.notEqual(second.metadata.demoFollowUpTaskId,first.metadata.demoFollowUpTaskId);});
    await check('opt-out stops active reminder and prevents new ones',async()=>{
      await db.query("INSERT INTO sales_communication_preferences VALUES($1,$2,'sms','unsubscribed')",[workspace,contact]);
      const row=(await tasks()).find(t=>t.id===second.metadata.demoFollowUpTaskId); assert.equal(row.status,'dismissed'); assert.equal(row.metadata.outcome,'opted_out');
      await send();assert.equal((await tasks()).length,3);
    });
    await db.exec('DELETE FROM sales_communication_preferences');
    await check('unlinked sends deduplicate by recipient, without requiring contact creation',async()=>{
      await send({lead:null,contact:null,to:'new@example.com'});await send({lead:null,contact:null,to:'NEW@example.com'});
      assert.equal((await tasks()).filter(t=>t.metadata.recipientEmail==='new@example.com').length,1);
    });
    await check('late delivery failure stops a reminder with no successful sends',async()=>{
      const event=await send({lead:null,contact:null,to:'failed@example.com',status:'queued'});
      await db.query("UPDATE communication_events SET status='undelivered' WHERE id=$1",[event.id]);
      assert.equal((await tasks()).find(t=>t.id===event.metadata.demoFollowUpTaskId).metadata.outcome,'delivery_failed');
    });
    await check('one failed message does not cancel another successful demo send',async()=>{
      const event=await send({lead:null,contact:null,to:'new@example.com',status:'queued'});
      await db.query("UPDATE communication_events SET status='failed' WHERE id=$1",[event.id]);
      assert.equal((await tasks()).find(t=>t.id===event.metadata.demoFollowUpTaskId).status,'open');
    });
    await check('do-not-contact stops demo reminders without changing manual tasks',async()=>{
      await send();await db.query("UPDATE sales_leads SET lead_state='dnc' WHERE id=$1",[lead]);
      assert.equal((await tasks()).filter(t=>t.sales_lead_id===lead&&t.status==='open').length,0);
      assert.equal((await db.query("SELECT status FROM sales_tasks WHERE task_type='follow_up'")).rows[0].status,'open');
    });
    await check('STOP replies close reminders for numbers without CRM contacts',async()=>{
      const event=await send({lead:null,contact:null,channel:'sms',to:'+14165550200'});
      await send({lead:null,contact:null,channel:'sms',direction:'inbound',kind:'sms_received',from:'+14165550200',body:' STOP ',status:'received',time:'2026-10-27T14:00:00Z'});
      const row=(await tasks()).find(t=>t.id===event.metadata.demoFollowUpTaskId);
      assert.equal(row.status,'dismissed');assert.equal(row.metadata.outcome,'opted_out');
    });
    console.log(`${passed} database scenarios passed.`);
  } finally { await db.close(); }
}
main().catch(error => { console.error(error); process.exitCode=1; });
