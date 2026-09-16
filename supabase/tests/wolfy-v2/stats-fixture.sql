CREATE TABLE field_sales_settings(workspace_id uuid PRIMARY KEY,currency text,timezone text,team_revenue_visible boolean DEFAULT false);
ALTER TABLE field_sales ADD COLUMN value_minor bigint DEFAULT 10000;
CREATE TABLE session_participants(session_id uuid,campaign_id uuid,user_id uuid,joined_at timestamptz DEFAULT now(),left_at timestamptz);
INSERT INTO field_sales_settings(workspace_id,currency,timezone) SELECT id,'CAD','America/Toronto' FROM workspaces;
