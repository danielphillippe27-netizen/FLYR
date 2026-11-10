import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createSalesFixture } from './field_sales_fixture.mjs';

const { db, id } = await createSalesFixture();
const workspace = id(10);
const migrations = new URL('../migrations/', import.meta.url);
const migration = async name => db.exec(await readFile(new URL(name, migrations), 'utf8'));
await db.exec(`
  CREATE ROLE service_role;
  CREATE FUNCTION can_view_campaign(campaign uuid, actor uuid) RETURNS boolean LANGUAGE sql AS $$
    SELECT EXISTS (SELECT 1 FROM campaigns c JOIN workspace_members m ON m.workspace_id=c.workspace_id
      WHERE c.id=campaign AND m.user_id=actor)
  $$;
  ALTER TABLE contact_activities DROP COLUMN status;
  ALTER TABLE contacts ADD COLUMN appointment_at timestamptz, ADD COLUMN address_id uuid, ADD COLUMN address text, ADD COLUMN phone text;
  CREATE TABLE calendar_events (id uuid PRIMARY KEY, workspace_id uuid, user_id uuid, contact_id uuid, event_type text);
  CREATE TABLE campaign_addresses (id uuid PRIMARY KEY, campaign_id uuid, formatted text);
  INSERT INTO campaign_addresses VALUES ('${id(41)}','${id(20)}','7 Test Street, Unit 2');
  UPDATE contacts SET address_id='${id(41)}' WHERE id='${id(30)}';
  INSERT INTO field_sales_settings(workspace_id,enabled,currency,timezone)
  VALUES ('${workspace}',true,'CAD','America/Toronto');
`);
await migration('20260916120000_pro_sales_foundation.sql');
await migration('20261110120000_roofing_appointments.sql');
await migration('20261110121000_roofing_appointment_reminders.sql');

async function actor(n) {
  await db.exec(`RESET ROLE; SET ROLE authenticated; SET request.jwt.claim.sub='${id(n)}';`);
}
async function rpc(name, ...args) {
  const argsSql = args.map((_, index) => '$' + (index + 1)).join(',');
  return (await db.query(`SELECT ${name}(${argsSql}) AS result`, args)).rows[0].result;
}
function command(action, data) {
  return rpc('field_appointment_command', workspace, action, data);
}
const appointment = id(50);
const book = {
  id: appointment,
  request_id: id(70),
  contact_id: id(30),
  start_at: new Date(Date.now() + 7_200_000).toISOString(),
  timezone: 'America/Toronto',
};
await actor(2);
await assert.rejects(() => command('book', book), /unavailable/);
await db.exec(`RESET ROLE;
  UPDATE field_sales_settings SET roofing_appointments_enabled=true, roofing_appointment_writes_enabled=true, roofing_reminders_enabled=true;
`);
await actor(2);
await assert.rejects(() => command('book', { ...book, assignee_id: id(3) }), /Assignment permission/);
await assert.rejects(() => command('book', { ...book, contact_id: id(33) }), /Contact unavailable/);
await assert.rejects(() => command('book', { ...book, campaign_address_id: id(99) }), /Property unavailable/);
const first = await command('book', book);
assert.deepEqual(await command('book', book), first);
await assert.rejects(() => command('book', { ...book, notes: 'changed' }), /different inputs/);
assert.equal((await rpc('field_appointment_detail', workspace, appointment)).property_label, '7 Test Street, Unit 2');
await assert.rejects(() => command('held', { id: appointment, request_id: id(71), version: 1 }), /not started/);

await actor(1);
const assigned = await command('assign', { id: appointment, request_id: id(72), version: 1, assignee_id: id(3) });
assert.equal(assigned.version, 2);
await db.exec(`RESET ROLE; UPDATE contacts SET user_id='${id(1)}' WHERE id='${id(30)}';`);
await actor(2);
await assert.rejects(() => command('cancel', { id: appointment, request_id: id(73), version: 2, reason: 'Cancelled' }), /Appointment unavailable/);
await actor(3);
const { alerts } = await rpc('field_appointment_alerts', workspace);
assert.equal(alerts[0].kind, 'assignment');
await assert.rejects(() => rpc('field_appointment_claim_push'), /permission denied/);
await db.exec('RESET ROLE; SET ROLE service_role;');
const jobs = (await db.query('SELECT * FROM field_appointment_claim_push()')).rows;
assert.equal(jobs.length, 1);
assert.equal(jobs[0].recipient_id, id(3));
assert.equal(await rpc('field_appointment_push_current', jobs[0].id, jobs[0].attempt), true);
assert.equal((await db.query('SELECT * FROM field_appointment_claim_push()')).rows.length, 0);
await actor(3);
const stale = await command('confirm', { id: appointment, request_id: id(74), version: 1 });
assert.equal(stale.conflict, true);
assert.equal(stale.appointment.version, 2);
const rescheduled = await command('reschedule', {
  id: appointment, request_id: id(75), version: 2, start_at: new Date(Date.now() - 3_600_000).toISOString(),
});
assert.equal(rescheduled.version, 3);
await command('held', { id: appointment, request_id: id(76), version: 3 });
assert.deepEqual((await rpc('field_appointment_alerts', workspace)).alerts, []);
await db.exec('RESET ROLE; SET ROLE service_role;');
assert.equal(await rpc('field_appointment_push_current', jobs[0].id, jobs[0].attempt), false);
await actor(3);
const detail = await rpc('field_appointment_detail', workspace, appointment);
assert.equal(detail.setter_id, id(2));
assert.equal(detail.assignee_id, id(3));
assert.equal(detail.status, 'held');
assert.deepEqual(detail.history.map(event => event.action), ['book', 'assign', 'reschedule', 'held']);
await assert.rejects(() => db.query('SELECT * FROM field_appointments'), /permission denied/);
await actor(4);
await assert.rejects(() => rpc('field_appointment_list', workspace), /Workspace access/);

await db.exec('RESET ROLE');
const { rows: [counts] } = await db.query(`SELECT
  (SELECT count(*)::int FROM field_appointments) AS appointments,
  (SELECT count(*)::int FROM field_appointment_reminders WHERE cancelled_at IS NULL) AS reminders`);
assert.deepEqual(counts, { appointments: 1, reminders: 0 });
await assert.rejects(() => db.query('UPDATE contacts SET appointment_at=now() WHERE id=$1', [id(30)]), /Update WolfGrid/);
await assert.rejects(() => db.query(
  "INSERT INTO contact_activities (id,contact_id,type,timestamp) VALUES ($1,$2,'meeting',now())", [id(51),id(30)]
), /Update WolfGrid/);
await assert.rejects(() => db.query(
  "INSERT INTO calendar_events (id,workspace_id,contact_id,event_type) VALUES ($1,$2,$3,'appointment')", [id(52),workspace,id(30)]
), /Update WolfGrid/);
await db.query('UPDATE contacts SET full_name=$1 WHERE id=$2', ['Updated contact', id(30)]);
await actor(2);
const linked = { ...book, id: id(90), request_id: id(91), contact_id: id(92), new_contact_name: 'New resident',
  campaign_address_id: id(41), campaign_id: id(20) };
await assert.rejects(() => command('book', { ...linked, timezone: 'Invalid/Zone' }), /Valid appointment times/);
await db.exec('RESET ROLE');
assert.equal((await db.query('SELECT count(*)::int AS count FROM contacts WHERE id=$1', [id(92)])).rows[0].count, 0);
await actor(2);
assert.deepEqual(await command('book', linked), await command('book', linked));
await db.exec('RESET ROLE');
assert.equal((await db.query('SELECT count(*)::int AS count FROM contacts WHERE id=$1', [id(92)])).rows[0].count, 1);
await db.exec('UPDATE field_sales_settings SET roofing_appointment_writes_enabled=false;');
await actor(1);
assert.equal((await rpc('field_appointment_list', workspace, null, null, null, true)).appointments.length, 2);
await assert.rejects(() => command('book', { ...book, request_id: id(77) }), /unavailable/);
await db.close();
console.log('PASS roofing appointments: live-shaped meeting schema, permissions, retries, handoffs, conflicts, outcomes, legacy guards, reminders and read-only rollback');
