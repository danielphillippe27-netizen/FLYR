const { PGlite } = await import(process.env.PGLITE_MODULE_PATH || '@electric-sql/pglite');
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const db = new PGlite();
const a='00000000-0000-0000-0000-000000000001', b='00000000-0000-0000-0000-000000000002', w='00000000-0000-0000-0000-000000000003';
await db.exec(`CREATE ROLE authenticated; CREATE ROLE anon; CREATE SCHEMA auth; CREATE SCHEMA storage;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
CREATE FUNCTION storage.foldername(text) RETURNS text[] LANGUAGE sql AS $$ SELECT string_to_array($1,'/') $$;
CREATE TABLE workspace_members(workspace_id uuid,user_id uuid);
INSERT INTO workspace_members VALUES ('${w}','${a}'),('${w}','${b}');
CREATE TABLE dialer_voicemail_drops(id uuid,user_id uuid,workspace_id uuid,storage_bucket text,storage_path text);
CREATE TABLE storage.buckets(id text,public boolean);
INSERT INTO storage.buckets VALUES ('dialer-voicemail-drops',true);
CREATE TABLE storage.objects(id uuid,bucket_id text,name text);
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
CREATE POLICY legacy_broad ON storage.objects FOR ALL TO public USING (true) WITH CHECK (true);
CREATE POLICY legacy_broad ON dialer_voicemail_drops FOR ALL TO authenticated USING (true) WITH CHECK (true);
GRANT USAGE ON SCHEMA public,auth,storage TO authenticated,anon;
GRANT SELECT ON workspace_members TO authenticated,anon;
GRANT ALL ON storage.objects,dialer_voicemail_drops TO authenticated,anon;`);
for(const user of [a,b]) await db.exec(`INSERT INTO dialer_voicemail_drops VALUES ('${user}','${user}','${w}','dialer-voicemail-drops','${w}/${user}/recording.mp3');
INSERT INTO storage.objects VALUES ('${user}','dialer-voicemail-drops','${w}/${user}/recording.mp3');`);
await db.exec(readFileSync(new URL('../migrations/20260909040000_personal_voicemail_drops.sql',import.meta.url),'utf8'));
assert.equal((await db.query('SELECT public FROM storage.buckets')).rows[0].public,false);
for(const user of [a,b]) {
 await db.exec(`SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','${user}',false);`);
 for(const table of ['dialer_voicemail_drops','storage.objects']) {
  assert.deepEqual((await db.query(`SELECT id FROM ${table}`)).rows.map(r=>r.id),[user]);
  assert.equal((await db.query(`DELETE FROM ${table} WHERE id <> '${user}' RETURNING id`)).rows.length,0);
 }
 await db.exec('RESET ROLE');
}
await db.exec(`SET ROLE anon; SELECT set_config('request.jwt.claim.sub','',false);`);
assert.equal((await db.query('SELECT * FROM storage.objects')).rows.length,0);
console.log('PASS: voicemail rows and private storage remain personal despite permissive workspace policies; anonymous reads denied.');
await db.close();
