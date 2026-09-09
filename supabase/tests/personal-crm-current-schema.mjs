const { PGlite } = await import(process.env.PGLITE_MODULE_PATH || '@electric-sql/pglite');
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const db=new PGlite();
const a='00000000-0000-0000-0000-000000000001',b='00000000-0000-0000-0000-000000000002',w='00000000-0000-0000-0000-000000000003';
await db.exec(`CREATE ROLE authenticated; CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql AS $$ SELECT current_user::text $$;
GRANT USAGE ON SCHEMA public,auth TO authenticated;
CREATE TABLE sales_contacts(id uuid PRIMARY KEY,owner_user_id uuid,workspace_id uuid,source text,external_id text,merged_into_id uuid);
CREATE TABLE sales_companies(id uuid PRIMARY KEY,owner_user_id uuid,workspace_id uuid,website_domain text,merged_into_id uuid);
INSERT INTO sales_contacts VALUES ('${a}','${a}','${w}','source','same-external',NULL),('${b}','${b}','${w}','source','same-external',NULL);
INSERT INTO sales_companies VALUES ('${a}','${a}','${w}','same.example',NULL),('${b}','${b}','${w}','same.example',NULL);`);
for(const table of ['sales_leads','sales_tasks','sales_bookings']) {
 await db.exec(`CREATE TABLE ${table}(id uuid PRIMARY KEY,assigned_user_id uuid,workspace_id uuid);
 INSERT INTO ${table} VALUES ('${a}','${a}','${w}'),('${b}','${b}','${w}');`);
}
const tables=['sales_contacts','sales_companies','sales_leads','sales_tasks','sales_bookings'];
for(const table of tables) await db.exec(`ALTER TABLE ${table} ENABLE ROW LEVEL SECURITY; CREATE POLICY workspace_access ON ${table} FOR ALL TO authenticated USING (true) WITH CHECK (true); GRANT ALL ON ${table} TO authenticated;`);
await db.exec(readFileSync(new URL('../migrations/20260909030000_personal_crm_records_rls.sql',import.meta.url),'utf8'));
for(const user of [a,b]) {
 await db.exec(`SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','${user}',false);`);
 for(const table of tables) assert.deepEqual((await db.query(`SELECT id FROM ${table}`)).rows.map(r=>r.id),[user],table);
 await assert.rejects(db.exec(`SELECT merge_sales_contacts('${w}','${a}','${b}','${user}')`),/Personal records not found/);
 await assert.rejects(db.exec(`SELECT merge_sales_companies('${w}','${a}','${b}','${user}')`),/Personal records not found/);
 await assert.rejects(db.exec(`SELECT merge_sales_contacts('${w}','${a}','${b}','${user===a?b:a}')`),/Authenticated actor required/);
 await db.exec('RESET ROLE');
}
console.log('PASS: current sales schema without legacy sales_contacts.user_id; personal CRM ownership, same-prospect independence and cross-user merge/actor-spoof prevention.');
await db.close();
