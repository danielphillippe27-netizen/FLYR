const { PGlite } = await import(process.env.PGLITE_MODULE_PATH || '@electric-sql/pglite');
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const db = new PGlite();
const a='00000000-0000-0000-0000-000000000001',b='00000000-0000-0000-0000-000000000002',w='00000000-0000-0000-0000-000000000003';
await db.exec(`CREATE ROLE authenticated; CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
GRANT USAGE ON SCHEMA auth,public TO authenticated;`);
for(const table of ['contacts','field_leads','dialer_sessions','dialer_session_leads']) {
 await db.exec(`CREATE TABLE ${table}(id uuid,user_id uuid,workspace_id uuid,session_id uuid,contact_id uuid);
 INSERT INTO ${table} VALUES ('${a}','${a}','${w}','${a}','${a}'),('${b}','${b}','${w}','${b}','${b}');
 ALTER TABLE ${table} ENABLE ROW LEVEL SECURITY;
 CREATE POLICY legacy_workspace_access ON ${table} FOR ALL TO authenticated USING (true) WITH CHECK (true);
 GRANT ALL ON ${table} TO authenticated;`);
}
await db.exec(readFileSync(new URL('../migrations/20260909050000_personal_legacy_records_rls.sql',import.meta.url),'utf8'));
for(const user of [a,b]) {
 await db.exec(`SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','${user}',false);`);
 for(const table of ['contacts','field_leads','dialer_sessions','dialer_session_leads']) {
  assert.deepEqual((await db.query(`SELECT id FROM ${table}`)).rows.map(r=>r.id),[user]);
  assert.equal((await db.query(`DELETE FROM ${table} WHERE id <> '${user}' RETURNING id`)).rows.length,0);
 }
 const foreign=user===a?b:a;
 await assert.rejects(db.exec(`UPDATE dialer_session_leads SET contact_id='${foreign}' WHERE id='${user}'`),/row-level security/);
 await db.exec('RESET ROLE');
}
console.log('PASS: contacts, field leads, sessions and child rows remain personal despite legacy workspace policies; foreign contact linking denied.');
await db.close();
