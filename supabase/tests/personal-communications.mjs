// Run in an isolated test database; never against the live Supabase database.
const { PGlite } = await import(process.env.PGLITE_MODULE_PATH || '@electric-sql/pglite');
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const pg = new PGlite();
const a='00000000-0000-0000-0000-000000000001', b='00000000-0000-0000-0000-000000000002', w='00000000-0000-0000-0000-000000000003', t='00000000-0000-0000-0000-000000000004';
await pg.exec(`CREATE ROLE authenticated; CREATE SCHEMA auth; CREATE TABLE auth.users(id uuid PRIMARY KEY);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
CREATE TABLE workspaces(id uuid PRIMARY KEY);
CREATE FUNCTION sales_workspace_member(uuid) RETURNS boolean LANGUAGE sql AS $$ SELECT true $$;
INSERT INTO auth.users VALUES ('${a}'),('${b}'); INSERT INTO workspaces VALUES ('${w}');
CREATE TABLE sales_contacts(id uuid PRIMARY KEY); CREATE TABLE sales_leads(id uuid PRIMARY KEY);`);
const crm=readFileSync(new URL('../migrations/20260806120000_sales_pro_crm.sql', import.meta.url),'utf8');
await pg.exec(crm.slice(crm.indexOf('CREATE TABLE IF NOT EXISTS public.communication_threads'),crm.indexOf('CREATE UNIQUE INDEX IF NOT EXISTS communication_events_provider_unique')));
for (const [table,col] of [['sales_activities','actor_user_id'],['social_connections','user_id'],['dialer_calls','user_id'],['dialer_messages','sender_user_id'],['dialer_inbound_messages','salesperson_id'],['sales_mailboxes','user_id'],['sales_notifications','user_id']]) {
 await pg.exec(`CREATE TABLE ${table}(id uuid DEFAULT gen_random_uuid() PRIMARY KEY, workspace_id uuid, ${col} uuid);`);
}
await pg.exec(`ALTER TABLE sales_activities ADD COLUMN metadata jsonb DEFAULT '{}'::jsonb; CREATE TABLE contact_activities(id uuid PRIMARY KEY, type text); CREATE TABLE social_threads(id uuid PRIMARY KEY, connection_id uuid); CREATE TABLE social_interactions(id uuid PRIMARY KEY, connection_id uuid);`);
for(const table of ['sales_activities','contact_activities','social_threads','social_interactions','social_connections','communication_threads','communication_events','dialer_calls','dialer_messages','dialer_inbound_messages','sales_mailboxes','sales_notifications']) {
 await pg.exec(`ALTER TABLE ${table} ENABLE ROW LEVEL SECURITY; CREATE POLICY legacy_workspace_access ON ${table} FOR ALL TO authenticated USING (true) WITH CHECK (true); GRANT ALL ON ${table} TO authenticated;`);
}
await pg.exec(`GRANT USAGE ON SCHEMA public,auth TO authenticated;
INSERT INTO communication_threads(id,workspace_id,assigned_user_id,subject) VALUES ('${t}','${w}','${a}','mixed private subject');
INSERT INTO communication_events(workspace_id,thread_id,actor_user_id,channel,direction,event_kind,body) VALUES
('${w}','${t}','${a}','email','outbound','email_sent','A private email'),
('${w}','${t}','${b}','email','inbound','email_received','B private email');
INSERT INTO communication_events(workspace_id,thread_id,actor_user_id,channel,direction,event_kind,provider,body)
VALUES ('${w}','${t}','${b}','call','inbound','call.initiated','telnyx','unverified call');
INSERT INTO dialer_calls(workspace_id,user_id) VALUES ('${w}','${a}'),('${w}','${b}'),('${w}',NULL);
INSERT INTO dialer_messages(workspace_id,sender_user_id) VALUES ('${w}','${a}'),('${w}','${b}'),('${w}',NULL);`);
await pg.exec(`INSERT INTO social_connections(id, workspace_id, user_id) VALUES ('${a}','${w}','${a}'),('${b}','${w}','${b}');
INSERT INTO social_threads VALUES ('${a}','${a}'),('${b}','${b}');
INSERT INTO social_interactions VALUES ('${a}','${a}'),('${b}','${b}');
INSERT INTO sales_activities(workspace_id,actor_user_id) VALUES ('${w}','${a}'),('${w}','${b}');
INSERT INTO contact_activities VALUES ('${a}','text');`);
await pg.exec(readFileSync(new URL('../migrations/20260909010000_personal_communications_rls.sql', import.meta.url),'utf8'));
for(const [user,expected] of [[a,'A private email'],[b,'B private email']]) {
 await pg.exec(`SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','${user}',false);`);
 assert.deepEqual((await pg.query('SELECT body FROM communication_events')).rows.map(r=>r.body),[expected]);
 assert.equal((await pg.query('SELECT * FROM communication_threads')).rows.length,1);
 assert.equal((await pg.query('SELECT * FROM dialer_calls')).rows.length,1);
 assert.equal((await pg.query('SELECT * FROM dialer_messages')).rows.length,1);
 assert.equal((await pg.query('SELECT * FROM sales_activities')).rows.length,1);
 assert.equal((await pg.query('SELECT * FROM contact_activities')).rows.length,0);
 assert.deepEqual((await pg.query('SELECT id FROM social_threads')).rows.map(r=>r.id),[user]);
 assert.deepEqual((await pg.query('SELECT id FROM social_interactions')).rows.map(r=>r.id),[user]);
 assert.equal((await pg.query(`UPDATE communication_events SET body='stolen' WHERE actor_user_id <> '${user}' RETURNING id`)).rows.length,0);
 await assert.rejects(pg.exec(`UPDATE communication_threads SET assigned_user_id='${user===a?b:a}'`));
 await pg.exec('RESET ROLE');
}
console.log('PASS: migration executes; mixed history splits; unverified calls quarantine; both users isolated despite permissive workspace policy; foreign writes and ownership transfers denied.');
await pg.close();
