-- Disposable PostgreSQL fixture only. Never run against a WolfGrid database.
CREATE ROLE anon; CREATE ROLE authenticated;
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
GRANT USAGE ON SCHEMA auth TO authenticated,anon; GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated,anon;
CREATE TABLE auth.users(id uuid PRIMARY KEY);
CREATE TABLE public.workspaces(id uuid PRIMARY KEY,owner_id uuid);
CREATE TABLE public.workspace_members(workspace_id uuid,user_id uuid,role text);
CREATE TABLE public.campaigns(id uuid PRIMARY KEY,workspace_id uuid,owner_id uuid);
CREATE TABLE public.sessions(id uuid PRIMARY KEY,user_id uuid,campaign_id uuid,end_time timestamptz,is_paused boolean);
CREATE TABLE public.wolfy_profiles(workspace_id uuid,user_id uuid,xp bigint);
CREATE TABLE public.campaign_presence(campaign_id uuid,user_id uuid,session_id uuid,lat double precision,lng double precision,updated_at timestamptz,status text,PRIMARY KEY(campaign_id,user_id));
ALTER TABLE campaign_presence ENABLE ROW LEVEL SECURITY;
CREATE FUNCTION public.is_campaign_member(p_campaign_id uuid,p_user_id uuid DEFAULT auth.uid()) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER AS $$
 SELECT EXISTS(SELECT 1 FROM campaigns c JOIN workspace_members m ON m.workspace_id=c.workspace_id WHERE c.id=p_campaign_id AND m.user_id=p_user_id)
$$;
GRANT SELECT,INSERT,UPDATE,DELETE ON campaign_presence TO authenticated;
CREATE POLICY campaign_presence_select_member ON campaign_presence FOR SELECT TO authenticated USING(is_campaign_member(campaign_id));
CREATE POLICY self_write ON campaign_presence FOR ALL TO authenticated USING(user_id=auth.uid()) WITH CHECK(user_id=auth.uid());
-- Real schema uses distinct self write policies, never a permissive ALL policy.
DROP POLICY self_write ON campaign_presence;
CREATE POLICY self_insert ON campaign_presence FOR INSERT TO authenticated WITH CHECK(user_id=auth.uid());
CREATE POLICY self_update ON campaign_presence FOR UPDATE TO authenticated USING(user_id=auth.uid()) WITH CHECK(user_id=auth.uid());
INSERT INTO auth.users VALUES('00000000-0000-0000-0000-000000000001'),('00000000-0000-0000-0000-000000000002'),('00000000-0000-0000-0000-000000000003');
INSERT INTO workspaces VALUES('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001'),('10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003');
INSERT INTO workspace_members VALUES('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','owner'),('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','member'),('10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003','owner');
INSERT INTO campaigns VALUES('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001');
INSERT INTO sessions VALUES('30000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',NULL,false),('30000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001',NULL,false);
INSERT INTO wolfy_profiles VALUES('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001',2500),('10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001',1000);
