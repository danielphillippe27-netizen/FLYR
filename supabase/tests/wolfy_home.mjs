// Isolated PostgreSQL regression test. Requires @electric-sql/pglite.
// PGLITE_MODULE=/absolute/path/to/pglite/dist/index.js node supabase/tests/wolfy_home.mjs
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const { PGlite } = await import(process.env.PGLITE_MODULE ?? '@electric-sql/pglite');
const db = new PGlite();
const user = '00000000-0000-0000-0000-000000000001';
const other = '00000000-0000-0000-0000-000000000002';
const workspace = '00000000-0000-0000-0000-000000000003';
await db.exec(`
CREATE ROLE anon; CREATE ROLE authenticated;
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$ SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql AS $$ SELECT current_user::text $$;
GRANT USAGE ON SCHEMA auth TO authenticated, anon;
CREATE TABLE user_profiles(user_id uuid PRIMARY KEY, weekly_door_goal integer);
CREATE TABLE workspace_members(workspace_id uuid, user_id uuid);
CREATE TABLE sessions(id uuid PRIMARY KEY, user_id uuid, workspace_id uuid);
CREATE TABLE session_events(id uuid PRIMARY KEY, session_id uuid, building_id text, address_id uuid,
 event_type text, created_at timestamptz, metadata jsonb, outcome text);
CREATE TABLE contacts(id uuid PRIMARY KEY, user_id uuid, workspace_id uuid, lead_kind text, created_at timestamptz);
CREATE TABLE contact_activities(id uuid PRIMARY KEY, contact_id uuid, type text, created_at timestamptz);
INSERT INTO user_profiles VALUES ('${user}',100),('${other}',200);
INSERT INTO workspace_members VALUES ('${workspace}','${user}');
INSERT INTO sessions VALUES ('00000000-0000-0000-0000-000000000004','${user}','${workspace}');
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO authenticated;
`);
await db.exec(await readFile(new URL('../migrations/20260915150000_wolfy_home.sql', import.meta.url), 'utf8'));
await db.exec(`SET ROLE authenticated; SET request.jwt.claim.sub = '${user}';`);
async function mustFail(sql) {
  await assert.rejects(db.query(sql));
}
await db.query(`SELECT wolfy_save_personal_goals('${user}',70,500)`);
assert.deepEqual((await db.query(`SELECT daily_door_goal, weekly_door_goal FROM user_profiles WHERE user_id='${user}'`)).rows[0], {daily_door_goal:70,weekly_door_goal:500});
await mustFail(`SELECT wolfy_save_personal_goals('${other}',1,1)`);
await mustFail(`SELECT wolfy_save_personal_goals('${user}',0,100)`);
await mustFail(`UPDATE user_profiles SET daily_door_goal=9 WHERE user_id='${other}'`);
await db.query(`SELECT wolfy_save_personal_goals('${user}',NULL,NULL)`);
assert.equal((await db.query(`SELECT daily_door_goal FROM user_profiles WHERE user_id='${user}'`)).rows[0].daily_door_goal,null);
await db.exec(`RESET ROLE;
INSERT INTO contacts VALUES
('00000000-0000-0000-0000-000000000020','${user}','${workspace}','field','2026-09-15T05:00:00Z'),
('00000000-0000-0000-0000-000000000021','${other}','${workspace}','field','2026-09-15T05:00:00Z'),
('00000000-0000-0000-0000-000000000022','${user}','${workspace}','scraped','2026-09-15T05:00:00Z');
INSERT INTO contact_activities VALUES
('00000000-0000-0000-0000-000000000030','00000000-0000-0000-0000-000000000020','meeting','2026-09-15T05:00:00Z'),
('00000000-0000-0000-0000-000000000031','00000000-0000-0000-0000-000000000021','meeting','2026-09-15T05:00:00Z');
INSERT INTO session_events VALUES
('00000000-0000-0000-0000-000000000011','00000000-0000-0000-0000-000000000004','a',NULL,'conversation','2026-09-15T03:59:00Z','{"address_status":"talked"}',NULL),
('00000000-0000-0000-0000-000000000012','00000000-0000-0000-0000-000000000004','b',NULL,'conversation','2026-09-15T04:01:00Z','{"address_status":"no_answer"}',NULL),
('00000000-0000-0000-0000-000000000013','00000000-0000-0000-0000-000000000004','c',NULL,'conversation','2026-09-15T05:00:00Z','{"address_status":"talked"}',NULL),
('00000000-0000-0000-0000-000000000014','00000000-0000-0000-0000-000000000004','c',NULL,'conversation','2026-09-15T05:01:00Z','{"address_status":"talked"}',NULL),
('00000000-0000-0000-0000-000000000015','00000000-0000-0000-0000-000000000004','d',NULL,'completed_manual','2026-09-15T06:00:00Z',NULL,NULL),
('00000000-0000-0000-0000-000000000016','00000000-0000-0000-0000-000000000004','d',NULL,'completion_undone','2026-09-15T06:01:00Z',NULL,NULL);
SET ROLE authenticated;`);
const metricsSQL = `SELECT wolfy_home_metrics('${workspace}','2026-09-15T04:00:00Z','2026-09-14T04:00:00Z','2026-09-15T12:00:00Z') AS metrics`;
assert.deepEqual((await db.query(metricsSQL)).rows[0].metrics, {doors:2,weekly_doors:3,conversations:1,leads:1,appointments:1});
await db.exec(`SET request.jwt.claim.sub = '${other}';`);
await mustFail(metricsSQL);
await db.exec(`SET ROLE anon;`);
await mustFail(`SELECT wolfy_save_personal_goals('${user}',10,100)`);
console.log('PASS: migration, goal persistence/clearing/validation, foreign-owner rejection, anonymous rejection, workspace access, midnight event counts, deduplication and undo');
await db.close();
