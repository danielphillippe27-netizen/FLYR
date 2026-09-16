ALTER TABLE sessions ADD COLUMN workspace_id uuid;
UPDATE sessions SET workspace_id='10000000-0000-0000-0000-000000000001';
CREATE TABLE user_profiles(user_id uuid PRIMARY KEY,daily_door_goal integer);
CREATE TABLE session_events(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),session_id uuid,user_id uuid,building_id text,address_id uuid,event_type text,metadata jsonb DEFAULT '{}',created_at timestamptz DEFAULT clock_timestamp());
CREATE TABLE contacts(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id uuid,workspace_id uuid,campaign_id uuid,lead_kind text,created_at timestamptz DEFAULT now());
CREATE TABLE contact_activities(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),contact_id uuid REFERENCES contacts(id) ON DELETE CASCADE,type text,status text,created_at timestamptz DEFAULT now());
CREATE TABLE field_sales(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),rep_id uuid,workspace_id uuid,campaign_id uuid,status text,verified_by uuid,verified_at timestamptz);
CREATE TABLE calendar_events(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id uuid,workspace_id uuid,campaign_id uuid,event_type text,deleted_at timestamptz,updated_at timestamptz DEFAULT now());
