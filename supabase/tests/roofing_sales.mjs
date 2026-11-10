import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { createSalesFixture } from './field_sales_fixture.mjs';

const postgres = process.env.ROOFING_PG_MODULE ? await import(process.env.ROOFING_PG_MODULE) : null;
async function connect() {
  const client = new postgres.default.Client();
  await client.connect();
  return client;
}
const client = postgres ? await connect() : null;
const { db, id } = await createSalesFixture(client ? {
  exec: sql => client.query(sql),
  query: (sql, args) => client.query(sql, args),
  close: () => client.end(),
} : undefined);
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
  UPDATE contacts SET address_id='${id(41)}',address='7 Test Street, Unit 2' WHERE id='${id(30)}';
  INSERT INTO field_sales_settings(workspace_id,enabled,currency,timezone)
  VALUES ('${workspace}',true,'CAD','America/Toronto'),('${id(11)}',true,'CAD','America/Toronto');
`);
for (const file of (await readdir(migrations)).filter(file =>
  /^202609161\d+_pro_sales_.*\.sql$/.test(file) || /^2026091712\d+_appointment_.*\.sql$/.test(file) ||
  /^2026111012[01234]000_roofing_.*\.sql$/.test(file)).sort()) await migration(file);

async function actor(n) {
  await db.exec(`RESET ROLE; SET ROLE authenticated; SET request.jwt.claim.sub='${id(n)}';`);
}
async function rpc(name, ...args) {
  const argsSql = args.map((_, index) => '$' + (index + 1)).join(',');
  return (await db.query(`SELECT ${name}(${argsSql}) AS result`, args)).rows[0].result;
}
const appointment = (action, data) => rpc('field_appointment_command', workspace, action, data);
const deal = data => rpc('field_sales_pipeline_command', workspace, 'deal', data);
const sale = (action, data) => rpc('field_sales_command', workspace, action, { ...data, client_contract_version: 2 });
const earnings = (action, data) => rpc('field_earnings_command', workspace, action, data);
const earningsList = (filter = {}) => rpc('field_earnings_list', workspace, filter);
const { rows: [{ today }] } = await db.query("SELECT (now() AT TIME ZONE 'America/Toronto')::date::text AS today");

await actor(4);
await rpc('field_sales_pipeline_command', id(11), 'opportunity', { contact_id: id(33), stage_key: 'new' });
await db.exec(`RESET ROLE; INSERT INTO contact_activities(id,contact_id,type,timestamp)
 VALUES ('${id(46)}','${id(33)}','meeting',now()-interval '1 minute');`);
await actor(4);
const legacySale = await rpc('field_sales_command', id(11), 'submit',
  { request_id: id(199), contact_id: id(33), appointment_id: id(46), value_minor: '12300' });
assert.equal(legacySale.status, 'pending');
await db.exec(`RESET ROLE;
  UPDATE field_sales_settings SET roofing_appointments_enabled=true, roofing_appointment_writes_enabled=true,
     roofing_sales_enabled=true, roofing_sale_writes_enabled=true,
     roofing_earnings_enabled=true, roofing_earnings_writes_enabled=true
   WHERE workspace_id='${workspace}';`);
await actor(1);
const setterPlan = await earnings('publish_plan', { request_id: id(80), role: 'setter', title: 'Held inspection',
  effective_on: today, rules: [{kind: 'held_fee', amount_minor: '10000'}] });
const closerPlan = await earnings('publish_plan', { request_id: id(81), role: 'closer', title: 'Closing commission',
  effective_on: today, rules: [{kind: 'cash_percent', rate_bps: 500}] });
await actor(2);
const book = { id: id(50), request_id: id(51), contact_id: id(30),
  start_at: new Date(Date.now() - 1_000).toISOString(), timezone: 'America/Toronto' };
if (postgres) {
  const clients = await Promise.all([connect(), connect()]);
  try {
    await Promise.all(clients.map(c => c.query(`SET ROLE authenticated; SET request.jwt.claim.sub='${id(2)}'`)));
    const run = c => c.query('SELECT field_appointment_command($1,$2,$3) AS result',
      [workspace, 'book', book]).then(response => response.rows[0].result);
    const [a, b] = await Promise.all(clients.map(run));
    assert.deepEqual(a, b);
    assert.equal(a.id, book.id);
    console.log('PASS PostgreSQL concurrent booking retry produced one appointment and one receipt');
  } finally { await Promise.all(clients.map(c => c.end())); }
} else {
  await appointment('book', book);
}
const roof = { id: id(60), request_id: id(61), contact_id: id(30), job_label: 'Roof replacement', stage_key: 'new' };
const gutter = { id: id(62), request_id: id(63), contact_id: id(30), job_label: 'Gutters', stage_key: 'new' };
await deal(roof);
await deal(gutter);
assert.deepEqual(await deal(gutter), { id: gutter.id, version: 1, stage_key: 'new' });
await actor(1);
await deal({ id: roof.id, request_id: id(64), version: 1, owner_id: id(3), stage_key: 'proposal', field_appointment_id: book.id });
await appointment('assign', { id: book.id, request_id: id(52), version: 1, assignee_id: id(3) });
await db.exec(`RESET ROLE; UPDATE contacts SET user_id='${id(1)}' WHERE id='${id(30)}';`);
await actor(3);
const submission = { request_id: id(70), contact_id: id(30), field_appointment_id: book.id,
  opportunity_id: roof.id, sale_source: 'appointment', value_minor: '2000000', sold_on: today };
await assert.rejects(() => sale('submit', submission), /held appointment/);
await assert.rejects(() => rpc('field_sales_command', workspace, 'submit', submission), /Update WolfGrid/);
await appointment('held', { id: book.id, request_id: id(53), version: 2 });
await actor(2);
await assert.rejects(() => sale('submit', submission), /held appointment/);
await actor(3);
const contract = await sale('submit', submission);
assert.deepEqual(await sale('submit', submission), contract);
const detail = await rpc('field_sales_record', workspace, contract.id);
assert.equal(detail.setter_id, id(2));
assert.equal(detail.assigned_closer_id, id(3));
assert.equal(detail.closer_id, id(3));
assert.equal(detail.field_appointment_id, book.id);
assert.equal(detail.status, 'pending');
assert.equal(detail.credits.find(credit => credit.user_id === id(2)).basis_points, 0);
assert.equal(detail.credits.find(credit => credit.user_id === id(3)).basis_points, 10000);
await assert.rejects(() => sale('submit', { ...submission, request_id: id(71) }), /one_canonical_conversion|one_roofing_opportunity_conversion|active sale/);
await actor(1);
const options = await rpc('field_sales_roofing_entry', workspace, { opportunity_id: roof.id });
assert.equal(options.enabled, true);
assert.ok(options.contacts.some(row => row.id === id(30)));
const verified = await sale('verify', { id: contract.id, version: contract.version, request_id: id(180) });
const workbench = await rpc('field_sales_workbench', workspace);
assert.equal(workbench.opportunities.find(op => op.id === roof.id).stage_key, 'won');
assert.equal(workbench.opportunities.find(op => op.id === gutter.id).stage_key, 'new');
const direct = await sale('submit', {
  request_id: id(72), contact_id: id(30), opportunity_id: gutter.id, sale_source: 'door',
  value_minor: '250000', sold_on: today,
});
const directDetail = await rpc('field_sales_record', workspace, direct.id);
assert.equal(directDetail.setter_id ?? null, null);
assert.equal(directDetail.field_appointment_id ?? null, null);
assert.equal(directDetail.duplicate_review, true);
await assert.rejects(() => sale('verify', { id: direct.id, version: direct.version, request_id: id(181) }), /separate job/);
await sale('verify', { id: direct.id, version: direct.version, request_id: id(181), reason: 'Separate gutter contract' });
await sale('attribution', { id: verified.id, version: verified.version, request_id: id(73), reason: 'Agreed revenue split',
  credits: [{ user_id: id(2), role: 'setter', basis_points: 2500 }, { user_id: id(3), role: 'closer', basis_points: 7500 }] });
const report = await rpc('field_sales_report', workspace, { scope: 'team', period: 'year' });
assert.equal(report.summary.sold_value_minor, '2250000');
const receiptTime = new Date().toISOString();
await sale('collect', { id: contract.id, request_id: id(82), amount_minor: '800000', occurred_at: receiptTime });
const receipt = (await rpc('field_sales_record', workspace, contract.id)).payments[0];
let ledger = (await earningsList({ team: true })).entries;
const fee = ledger.find(entry => entry.kind === 'held_fee');
const closer = ledger.find(entry => entry.kind === 'cash_percent');
assert.equal(fee.amount_minor, '10000');
assert.equal(fee.plan_version_id, setterPlan.id);
assert.equal(fee.representative_id, id(2));
assert.equal(closer.amount_minor, '40000');
assert.equal(closer.plan_version_id, closerPlan.id);
assert.equal(closer.representative_id, id(3));
await actor(3);
await assert.rejects(() => earnings('approve', { id: closer.id, version: closer.version, request_id: id(83) }), /Another authorized reviewer/);
assert.equal((await earningsList()).entries.length, 1);
await actor(2);
await assert.rejects(() => earningsList({ team: true }), /Team earnings access/);
assert.equal((await earningsList()).entries.length, 1);
await actor(1);
for (const [index, entry] of [fee, closer].entries()) {
  const approved = await earnings('approve', { id: entry.id, version: entry.version, request_id: id(84 + index) });
  const settle = { id: entry.id, version: approved.version, request_id: id(86 + index),
    paid_at: new Date().toISOString(), payment_reference: 'External pay run 42' };
  const paid = await earnings('settle', settle);
  assert.deepEqual(await earnings('settle', settle), paid);
  await assert.rejects(() => earnings('settle', { ...settle, request_id: id(93 + index), version: paid.version }), /approved earning/);
}
await assert.rejects(() => sale('refund_payment', {
  id: contract.id, request_id: id(95), amount_minor: '200000', occurred_at: new Date().toISOString()
}), /original collection/);
await sale('refund_payment', { id: contract.id, request_id: id(88), reverses_payment_id: receipt.id,
  amount_minor: '200000', occurred_at: new Date().toISOString() });
ledger = (await earningsList({ team: true })).entries;
assert.equal(ledger.find(entry => entry.kind === 'reversal').amount_minor, '-10000');
assert.equal(ledger.find(entry => entry.id === closer.id).status, 'paid');
const paymentReport = await rpc('field_sales_report', workspace, { scope: 'team', period: 'year' });
assert.equal(paymentReport.summary.collected_revenue_minor, '600000');
await sale('chargeback_payment', { id: contract.id, request_id: id(89), reverses_payment_id: receipt.id,
  amount_minor: '600000', occurred_at: new Date().toISOString() });
ledger = (await earningsList({ team: true })).entries;
assert.equal(ledger.filter(entry => entry.kind === 'reversal').reduce((total, entry) => total + BigInt(entry.amount_minor), 0n), -40000n);
await sale('cancel', { id: contract.id, request_id: id(182), reason: 'Customer cancelled roof' });
const updated = await rpc('field_sales_workbench', workspace);
assert.equal(updated.opportunities.find(op => op.id === roof.id).stage_key, 'cancelled');
assert.equal(updated.opportunities.find(op => op.id === gutter.id).stage_key, 'won');
assert.equal((await earningsList({ team: true })).entries.find(entry => entry.id === fee.id).status, 'paid');
await actor(4);
await assert.rejects(() => earningsList(), /Workspace access/);
await assert.rejects(() => rpc('field_sales_record', workspace, contract.id), /Workspace access/);
await db.close();
console.log('PASS roofing sales: legacy opportunity, distinct jobs, held-only conversion, reassignment, split credit, duplicate review, sibling-safe cancellation, commission accrual, settlement and reversal');
