const { PGlite } = await import(process.env.PGLITE_MODULE_PATH || '@electric-sql/pglite');
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const db = new PGlite();
const a='00000000-0000-0000-0000-000000000001',b='00000000-0000-0000-0000-000000000002';
await db.exec(`CREATE ROLE authenticated; CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
CREATE TABLE salespeople(id uuid PRIMARY KEY,user_id uuid,email text,full_name text);
INSERT INTO salespeople VALUES ('${a}','${a}','same@example.com','Daniel Phillippe'),('${b}','${b}','same@example.com','Daniel Hughes');
CREATE TABLE communication_events(workspace_id uuid,actor_user_id uuid,direction text,occurred_at timestamptz);
GRANT USAGE ON SCHEMA auth,public TO authenticated;
ALTER TABLE salespeople ENABLE ROW LEVEL SECURITY;
CREATE POLICY legacy_workspace_access ON salespeople FOR ALL TO authenticated USING (true) WITH CHECK (true);
GRANT ALL ON salespeople TO authenticated;`);
const tables=['salesperson_referrals','salesperson_commissions','salesperson_click_events','salesperson_demo_video_events','salesperson_demo_links','salesperson_dialer_settings','salesperson_meeting_conferences','salesperson_revenue_snapshots'];
for(const table of tables) {
  await db.exec(`CREATE TABLE ${table}(id uuid PRIMARY KEY,salesperson_id uuid,user_id uuid);
  INSERT INTO ${table} VALUES ('${a}','${a}','${a}'),('${b}','${b}','${b}');
  ALTER TABLE ${table} ENABLE ROW LEVEL SECURITY;
  CREATE POLICY legacy_workspace_access ON ${table} FOR ALL TO authenticated USING (true) WITH CHECK (true);
  GRANT ALL ON ${table} TO authenticated;`);
}
await db.exec(readFileSync(new URL('../migrations/20260909020000_personal_sales_metrics_rls.sql',import.meta.url),'utf8'));
for(const user of [a,b]) {
  await db.exec(`SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','${user}',false);`);
  for(const table of ['salespeople',...tables]) {
    assert.deepEqual((await db.query(`SELECT id FROM ${table}`)).rows.map(r=>r.id),[user],table);
    assert.equal((await db.query(`DELETE FROM ${table} WHERE id <> '${user}' RETURNING id`)).rows.length,0,table);
  }
  await db.exec('RESET ROLE');
}
console.log('PASS: revenue, referrals, commissions, demo events/links, phone settings and meetings are owner-specific despite workspace-wide policies and identical email aliases.');
await db.close();
