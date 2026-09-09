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
await pg.exec(`ALTER TABLE sales_activities ADD COLUMN metadata jsonb DEFAULT '{}'::jsonb; CREATE TABLE contact_activities(id uuid PRIMARY KEY, type text, contact_id uuid); CREATE TABLE social_threads(id uuid PRIMARY KEY, connection_id uuid); CREATE TABLE social_interactions(id uuid PRIMARY KEY, connection_id uuid);`);
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
INSERT INTO contact_activities(id,type) VALUES ('${a}','text');`);

// Add the remaining modules to the same isolated database before applying the
// entire release sequence. Fixtures retain broad legacy policies intentionally.
await pg.exec(`CREATE ROLE anon; CREATE ROLE service_role; CREATE SCHEMA storage;
CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql AS $$ SELECT current_user::text $$;
CREATE FUNCTION storage.foldername(text) RETURNS text[] LANGUAGE sql AS $$ SELECT string_to_array($1,'/') $$;
CREATE TABLE workspace_members(workspace_id uuid,user_id uuid);
INSERT INTO workspace_members VALUES ('${w}','${a}'),('${w}','${b}');
ALTER TABLE sales_contacts ADD COLUMN user_id uuid, ADD COLUMN owner_user_id uuid, ADD COLUMN workspace_id uuid, ADD COLUMN source text, ADD COLUMN external_id text, ADD COLUMN merged_into_id uuid;
ALTER TABLE sales_leads ADD COLUMN assigned_user_id uuid, ADD COLUMN workspace_id uuid, ADD COLUMN sales_contact_id uuid;
CREATE TABLE sales_companies(id uuid PRIMARY KEY,owner_user_id uuid,workspace_id uuid,website_domain text,merged_into_id uuid);
CREATE TABLE salespeople(id uuid PRIMARY KEY,user_id uuid);
CREATE TABLE user_push_tokens(user_id uuid,token text,platform text,environment text,enabled boolean);
INSERT INTO user_push_tokens VALUES ('${a}','shared-device','ios','production',true),('${b}','shared-device','ios','production',true);
ALTER TABLE workspace_members ADD COLUMN role text DEFAULT 'member';
CREATE TABLE sales_merge_audit(id uuid,actor_user_id uuid,workspace_id uuid);
CREATE TABLE sales_company_research(id uuid,requested_by_user_id uuid,workspace_id uuid);
CREATE TABLE sales_company_research_batches(id uuid,requested_by_user_id uuid,workspace_id uuid);
CREATE TABLE sales_booking_reminders(id uuid,booking_id uuid,workspace_id uuid);
CREATE TABLE sales_communication_preferences(id uuid,sales_contact_id uuid,workspace_id uuid);
CREATE TABLE sales_contact_campaigns(id uuid,sales_contact_id uuid,workspace_id uuid);
CREATE TABLE sales_booking_links(id uuid,workspace_id uuid,owner_user_id uuid,mode text);
CREATE TABLE sales_booking_link_members(booking_link_id uuid,user_id uuid,is_active boolean DEFAULT true);
CREATE TABLE sales_availability_rules(id uuid,user_id uuid);
CREATE TABLE sales_availability_overrides(id uuid,user_id uuid);
CREATE TABLE sales_automation_definitions(id uuid,workspace_id uuid,created_by_user_id uuid);
CREATE TABLE sales_automation_versions(id uuid,automation_id uuid);
CREATE TABLE sales_sequence_enrollments(id uuid,workspace_id uuid,owner_user_id uuid,automation_id uuid);
CREATE TABLE sales_automation_executions(id uuid,workspace_id uuid,enrollment_id uuid);
CREATE FUNCTION claim_due_sales_automation_executions(integer) RETURNS void LANGUAGE sql AS $$ SELECT $$;
CREATE TABLE storage.buckets(id text,public boolean);
INSERT INTO storage.buckets VALUES ('dialer-voicemail-drops',true);
CREATE TABLE storage.objects(id uuid,bucket_id text,name text);
CREATE TABLE dialer_voicemail_drops(id uuid,user_id uuid,workspace_id uuid,storage_bucket text,storage_path text);
CREATE TABLE contacts(id uuid PRIMARY KEY,user_id uuid,workspace_id uuid);
CREATE TABLE field_leads(id uuid,user_id uuid,workspace_id uuid);
CREATE TABLE dialer_sessions(id uuid PRIMARY KEY,user_id uuid,workspace_id uuid);
CREATE TABLE dialer_session_leads(id uuid,workspace_id uuid,session_id uuid,contact_id uuid,position integer,status text,claimed_by_user_id uuid,claimed_at timestamptz,updated_at timestamptz);
CREATE TABLE calendar_events(id uuid,user_id uuid);
CREATE TABLE smart_lists(id uuid,created_by_user_id uuid);
CREATE TABLE sales_tasks(id uuid,workspace_id uuid,assigned_user_id uuid);
CREATE TABLE sales_bookings(id uuid,workspace_id uuid,assigned_user_id uuid);
GRANT USAGE ON SCHEMA storage TO authenticated; GRANT SELECT ON workspace_members TO authenticated;`);
const metricTables=['salesperson_referrals','salesperson_commissions','salesperson_click_events','salesperson_demo_video_events','salesperson_demo_links','salesperson_dialer_settings','salesperson_meeting_conferences','salesperson_revenue_snapshots'];
for(const table of metricTables) await pg.exec(`CREATE TABLE ${table}(id uuid,salesperson_id uuid); INSERT INTO ${table} VALUES ('${a}','${a}'),('${b}','${b}');`);
for(const user of [a,b]) await pg.exec(`
INSERT INTO salespeople VALUES ('${user}','${user}');
INSERT INTO calendar_events VALUES ('${user}','${user}');
INSERT INTO smart_lists VALUES ('${user}','${user}');
INSERT INTO sales_merge_audit VALUES ('${user}','${user}','${w}');
INSERT INTO sales_company_research VALUES ('${user}','${user}','${w}');
INSERT INTO sales_company_research_batches VALUES ('${user}','${user}','${w}');
INSERT INTO sales_booking_reminders VALUES ('${user}','${user}','${w}');
INSERT INTO sales_communication_preferences VALUES ('${user}','${user}','${w}');
INSERT INTO sales_contact_campaigns VALUES ('${user}','${user}','${w}');
INSERT INTO sales_booking_links VALUES ('${user}','${w}','${user}','personal');
INSERT INTO sales_availability_rules VALUES ('${user}','${user}');
INSERT INTO sales_availability_overrides VALUES ('${user}','${user}');
INSERT INTO sales_automation_definitions VALUES ('${user}','${w}','${user}');
INSERT INTO sales_automation_versions VALUES ('${user}','${user}');
INSERT INTO sales_sequence_enrollments VALUES ('${user}','${w}','${user}','${user}');
INSERT INTO sales_automation_executions VALUES ('${user}','${w}','${user}');
INSERT INTO sales_contacts(id,user_id,workspace_id) VALUES ('${user}','${user}','${w}');
INSERT INTO sales_leads(id,assigned_user_id,workspace_id) VALUES ('${user}','${user}','${w}');
INSERT INTO sales_companies VALUES ('${user}','${user}','${w}','same.example',NULL);
INSERT INTO sales_tasks VALUES ('${user}','${w}','${user}');
INSERT INTO sales_bookings VALUES ('${user}','${w}','${user}');
INSERT INTO contacts VALUES ('${user}','${user}','${w}');
INSERT INTO field_leads VALUES ('${user}','${user}','${w}');
INSERT INTO dialer_sessions VALUES ('${user}','${user}','${w}');
INSERT INTO dialer_session_leads VALUES ('${user}','${w}','${user}','${user}',1,'pending',NULL,NULL,NULL);
INSERT INTO dialer_voicemail_drops VALUES ('${user}','${user}','${w}','dialer-voicemail-drops','${w}/${user}/recording.mp3');
INSERT INTO storage.objects VALUES ('${user}','dialer-voicemail-drops','${w}/${user}/recording.mp3');`);
const personalTables=['smart_lists','calendar_events','sales_merge_audit','sales_company_research','sales_company_research_batches','sales_booking_reminders','sales_communication_preferences','sales_contact_campaigns','sales_booking_links','sales_availability_rules','sales_availability_overrides','sales_automation_definitions','sales_automation_versions','sales_sequence_enrollments','sales_automation_executions','salespeople','sales_contacts','sales_leads','sales_companies','sales_tasks','sales_bookings','contacts','field_leads','dialer_sessions','dialer_session_leads','dialer_voicemail_drops','storage.objects',...metricTables];
for(const table of personalTables) await pg.exec(`ALTER TABLE ${table} ENABLE ROW LEVEL SECURITY; CREATE POLICY legacy_workspace_access ON ${table} FOR ALL TO authenticated USING (true) WITH CHECK (true); GRANT ALL ON ${table} TO authenticated;`);

await pg.exec(`ALTER TABLE sales_contacts ADD COLUMN next_action_at timestamptz; ALTER TABLE sales_leads ADD COLUMN next_follow_up_at timestamptz, ADD COLUMN next_task_title text, ADD COLUMN next_task_type text; ALTER TABLE sales_tasks ADD COLUMN sales_lead_id uuid, ADD COLUMN sales_contact_id uuid, ADD COLUMN due_at timestamptz, ADD COLUMN title text, ADD COLUMN task_type text, ADD COLUMN status text, ADD COLUMN created_at timestamptz;`);
await pg.exec(readFileSync(new URL('../migrations/20260909010000_personal_communications_rls.sql', import.meta.url),'utf8'));
for(const name of ['20260909020000_personal_sales_metrics_rls.sql','20260909030000_personal_crm_records_rls.sql','20260909040000_personal_voicemail_drops.sql','20260909050000_personal_legacy_records_rls.sql','20260909060000_personal_dialer_claim.sql','20260909070000_personal_communication_references.sql','20260909080000_personal_push_device.sql','20260909090000_personal_automation_rls.sql','20260909100000_personal_booking_access.sql','20260909110000_personal_related_records.sql','20260909120000_sales_lead_contact_relationship.sql','20260909130000_contact_activity_relationship.sql','20260909140000_personal_rpc_permissions.sql','20260909150000_personal_crm_references.sql','20260909160000_reconcile_personal_crm_links.sql','20260909170000_personal_calendar_rls.sql','20260909180000_personal_smart_lists.sql']) {
 await pg.exec(readFileSync(new URL('../migrations/'+name,import.meta.url),'utf8'));
}

for(const [user,expected] of [[a,'A private email'],[b,'B private email']]) {
 await pg.exec(`SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','${user}',false);`);
 for(const table of personalTables) assert.deepEqual((await pg.query(`SELECT id FROM ${table}`)).rows.map(r=>r.id),[user],table);
 assert.equal((await pg.query(`SELECT * FROM claim_next_dialer_session_lead('${user}','${w}','${user}')`)).rows[0].claimed_by_user_id,user);
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
assert.equal((await pg.query('SELECT * FROM user_push_tokens WHERE enabled')).rows.length,0);
assert.equal((await pg.query("SELECT has_function_privilege('authenticated','claim_due_sales_automation_executions(integer)','EXECUTE') AS allowed")).rows[0].allowed,false);
console.log('PASS: all eighteen personal-isolation migrations execute together; both users retain only personal communications, CRM, metrics, storage and sessions; own claims work under the combined policies.');
await pg.close();
