BEGIN;

-- WolfGrid Sales Pro: canonical CRM, communications, automation, and booking.
-- The migration is additive so the current iOS and web clients remain compatible.

-- The standalone WolfGrid Sales project was initially provisioned without the
-- field-app migration ledger. Restore the two canonical CRM relations that may
-- therefore be absent before extending them below.
CREATE TABLE IF NOT EXISTS public.sales_contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  name text NOT NULL,
  company text,
  phone text,
  phone_e164 text,
  email text,
  email_normalized text,
  website text,
  website_domain text,
  address text,
  city text,
  region text,
  country_code text,
  source text,
  external_id text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.sales_tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  sales_lead_id uuid REFERENCES public.sales_leads(id) ON DELETE CASCADE,
  sales_contact_id uuid REFERENCES public.sales_contacts(id) ON DELETE SET NULL,
  assigned_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  task_type text NOT NULL DEFAULT 'follow_up',
  title text NOT NULL,
  status text NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'completed', 'dismissed')),
  due_at timestamptz,
  completed_at timestamptz,
  notes text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.sales_companies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  owner_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  name text NOT NULL,
  website text,
  website_domain text,
  phone text,
  email text,
  address text,
  city text,
  region text,
  country_code text,
  notes text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  merged_into_id uuid REFERENCES public.sales_companies(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS sales_companies_workspace_domain_unique
  ON public.sales_companies(workspace_id, lower(website_domain))
  WHERE website_domain IS NOT NULL AND merged_into_id IS NULL;

ALTER TABLE public.sales_contacts ADD COLUMN IF NOT EXISTS company_id uuid REFERENCES public.sales_companies(id) ON DELETE SET NULL;
ALTER TABLE public.sales_contacts ADD COLUMN IF NOT EXISTS owner_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.sales_contacts ADD COLUMN IF NOT EXISTS last_touch_at timestamptz;
ALTER TABLE public.sales_contacts ADD COLUMN IF NOT EXISTS next_action_at timestamptz;
ALTER TABLE public.sales_contacts ADD COLUMN IF NOT EXISTS merged_into_id uuid REFERENCES public.sales_contacts(id) ON DELETE SET NULL;
ALTER TABLE public.sales_leads ADD COLUMN IF NOT EXISTS company_id uuid REFERENCES public.sales_companies(id) ON DELETE SET NULL;
ALTER TABLE public.sales_leads ADD COLUMN IF NOT EXISTS source_campaign_id uuid REFERENCES public.campaigns(id) ON DELETE SET NULL;
ALTER TABLE public.sales_leads ADD COLUMN IF NOT EXISTS territory text;

CREATE INDEX IF NOT EXISTS sales_contacts_workspace_email_pro_idx
  ON public.sales_contacts(workspace_id, email_normalized)
  WHERE email_normalized IS NOT NULL AND merged_into_id IS NULL;
CREATE INDEX IF NOT EXISTS sales_contacts_workspace_phone_pro_idx
  ON public.sales_contacts(workspace_id, phone_e164)
  WHERE phone_e164 IS NOT NULL AND merged_into_id IS NULL;

CREATE TABLE IF NOT EXISTS public.sales_pipeline_stages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  stage_key text NOT NULL,
  name text NOT NULL,
  color text NOT NULL DEFAULT '#64748B',
  position integer NOT NULL,
  terminal_kind text CHECK (terminal_kind IN ('won', 'lost')),
  is_archived boolean NOT NULL DEFAULT false,
  created_by_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, stage_key),
  UNIQUE (workspace_id, position)
);

ALTER TABLE public.sales_leads ADD COLUMN IF NOT EXISTS pipeline_stage_id uuid REFERENCES public.sales_pipeline_stages(id) ON DELETE RESTRICT;

INSERT INTO public.sales_pipeline_stages (workspace_id, stage_key, name, color, position, terminal_kind)
SELECT w.id, seed.stage_key, seed.name, seed.color, seed.position, seed.terminal_kind
FROM public.workspaces w
CROSS JOIN (VALUES
  ('new', 'New Lead', '#64748B', 10, NULL::text),
  ('contacted', 'Contacted', '#2563EB', 20, NULL::text),
  ('conversation', 'Conversation', '#7C3AED', 30, NULL::text),
  ('meeting_booked', 'Meeting Booked', '#0891B2', 40, NULL::text),
  ('proposal', 'Proposal', '#D97706', 50, NULL::text),
  ('won', 'Won', '#16A34A', 60, 'won'),
  ('lost', 'Lost', '#DC2626', 70, 'lost')
) AS seed(stage_key, name, color, position, terminal_kind)
ON CONFLICT (workspace_id, stage_key) DO NOTHING;

UPDATE public.sales_leads lead
SET pipeline_stage_id = stage.id
FROM public.sales_pipeline_stages stage
WHERE stage.workspace_id = lead.workspace_id
  AND stage.stage_key = CASE
    WHEN lead.pipeline_stage = 'new_lead' THEN 'new'
    WHEN lead.pipeline_stage IN ('attempting_contact', 'nurture') THEN 'contacted'
    WHEN lead.pipeline_stage = 'connected' THEN 'conversation'
    WHEN lead.pipeline_stage IN ('demo_sent', 'trial_sent', 'trial_active', 'closing') THEN 'proposal'
    WHEN lead.pipeline_stage = 'won' THEN 'won'
    WHEN lead.pipeline_stage = 'lost' THEN 'lost'
    ELSE 'new'
  END
  AND lead.pipeline_stage_id IS NULL;

INSERT INTO public.sales_activities (workspace_id, sales_lead_id, activity_type, note, occurred_at, metadata)
SELECT lead.workspace_id, lead.id, 'stage_change', 'Pipeline migrated to customizable Pro stages.', now(),
       jsonb_build_object('migration', 'sales_pro_crm', 'legacyStage', lead.pipeline_stage, 'stageId', lead.pipeline_stage_id)
FROM public.sales_leads lead
WHERE lead.pipeline_stage_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.sales_activities activity
    WHERE activity.sales_lead_id = lead.id
      AND activity.metadata->>'migration' = 'sales_pro_crm'
  );

CREATE TABLE IF NOT EXISTS public.sales_contact_campaigns (
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  sales_contact_id uuid NOT NULL REFERENCES public.sales_contacts(id) ON DELETE CASCADE,
  campaign_id uuid NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (sales_contact_id, campaign_id)
);

CREATE TABLE IF NOT EXISTS public.communication_threads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  sales_contact_id uuid REFERENCES public.sales_contacts(id) ON DELETE SET NULL,
  sales_lead_id uuid REFERENCES public.sales_leads(id) ON DELETE SET NULL,
  assigned_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  subject text,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'done', 'archived')),
  needs_response boolean NOT NULL DEFAULT false,
  latest_channel text,
  latest_event_at timestamptz NOT NULL DEFAULT now(),
  last_read_at timestamptz,
  provider_thread_keys jsonb NOT NULL DEFAULT '{}'::jsonb,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.communication_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  thread_id uuid NOT NULL REFERENCES public.communication_threads(id) ON DELETE CASCADE,
  sales_contact_id uuid REFERENCES public.sales_contacts(id) ON DELETE SET NULL,
  sales_lead_id uuid REFERENCES public.sales_leads(id) ON DELETE SET NULL,
  actor_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  channel text NOT NULL CHECK (channel IN ('sms', 'email', 'call', 'voicemail', 'social', 'notification')),
  direction text CHECK (direction IN ('inbound', 'outbound', 'internal')),
  event_kind text NOT NULL,
  provider text,
  provider_event_id text,
  provider_thread_id text,
  subject text,
  body text,
  from_address text,
  to_addresses text[] NOT NULL DEFAULT '{}',
  status text NOT NULL DEFAULT 'received',
  attachments jsonb NOT NULL DEFAULT '[]'::jsonb,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  read_at timestamptz,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS communication_events_provider_unique
  ON public.communication_events(workspace_id, provider, provider_event_id)
  WHERE provider IS NOT NULL AND provider_event_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS communication_threads_inbox_idx
  ON public.communication_threads(workspace_id, status, latest_event_at DESC);
CREATE INDEX IF NOT EXISTS communication_events_thread_idx
  ON public.communication_events(thread_id, occurred_at, id);

INSERT INTO public.communication_threads(workspace_id, sales_contact_id, sales_lead_id, assigned_user_id, subject, latest_channel, latest_event_at, metadata)
SELECT lead.workspace_id, lead.sales_contact_id, lead.id, lead.assigned_user_id, lead.name,
       CASE WHEN activity.activity_type = 'text' THEN 'sms' ELSE activity.activity_type END,
       activity.occurred_at, jsonb_build_object('backfill', 'sales_pro_activity', 'leadId', lead.id)
FROM public.sales_leads lead
JOIN LATERAL (
  SELECT * FROM public.sales_activities candidate
  WHERE candidate.sales_lead_id = lead.id AND candidate.activity_type IN ('call', 'text', 'email')
  ORDER BY candidate.occurred_at DESC LIMIT 1
) activity ON true
WHERE NOT EXISTS (
  SELECT 1 FROM public.communication_threads thread
  WHERE thread.workspace_id = lead.workspace_id AND thread.metadata->>'backfill' = 'sales_pro_activity' AND thread.metadata->>'leadId' = lead.id::text
);

INSERT INTO public.communication_events(workspace_id, thread_id, sales_contact_id, sales_lead_id, actor_user_id, channel, direction, event_kind, provider, provider_event_id, body, status, occurred_at, read_at, metadata)
SELECT activity.workspace_id, thread.id, activity.sales_contact_id, activity.sales_lead_id, activity.actor_user_id,
       CASE WHEN activity.activity_type = 'text' THEN 'sms' ELSE activity.activity_type END,
       COALESCE(activity.metadata->>'direction', 'internal'), activity.activity_type || '_activity',
       'legacy_activity', activity.id::text, activity.note, 'imported', activity.occurred_at, activity.occurred_at,
       jsonb_build_object('backfill', 'sales_pro_activity', 'legacyActivityId', activity.id)
FROM public.sales_activities activity
JOIN public.communication_threads thread ON thread.sales_lead_id = activity.sales_lead_id AND thread.metadata->>'backfill' = 'sales_pro_activity'
WHERE activity.activity_type IN ('call', 'text', 'email')
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS public.sales_mailboxes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  local_part text NOT NULL,
  address text GENERATED ALWAYS AS (local_part || '@wolfgrid.app') STORED,
  forward_to text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, user_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS sales_mailboxes_local_part_unique
  ON public.sales_mailboxes(lower(local_part));

CREATE TABLE IF NOT EXISTS public.sales_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type text NOT NULL,
  title text NOT NULL,
  body text,
  data jsonb NOT NULL DEFAULT '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS sales_notifications_user_unread_idx ON public.sales_notifications(user_id, created_at DESC) WHERE read_at IS NULL;

CREATE TABLE IF NOT EXISTS public.sales_automation_definitions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  name text NOT NULL,
  trigger_type text NOT NULL,
  trigger_config jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_enabled boolean NOT NULL DEFAULT false,
  active_version integer NOT NULL DEFAULT 1,
  created_by_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.sales_automation_settings (
  workspace_id uuid PRIMARY KEY REFERENCES public.workspaces(id) ON DELETE CASCADE,
  timezone text NOT NULL DEFAULT 'America/Toronto',
  business_start_minute integer NOT NULL DEFAULT 540 CHECK (business_start_minute BETWEEN 0 AND 1439),
  business_end_minute integer NOT NULL DEFAULT 1020 CHECK (business_end_minute BETWEEN 1 AND 1440),
  business_weekdays integer[] NOT NULL DEFAULT ARRAY[1,2,3,4,5],
  sms_hourly_limit integer NOT NULL DEFAULT 100,
  email_hourly_limit integer NOT NULL DEFAULT 200,
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.sales_automation_settings(workspace_id) SELECT id FROM public.workspaces ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS public.sales_communication_preferences (
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  sales_contact_id uuid NOT NULL REFERENCES public.sales_contacts(id) ON DELETE CASCADE,
  channel text NOT NULL CHECK (channel IN ('sms', 'email', 'call')),
  status text NOT NULL DEFAULT 'unknown' CHECK (status IN ('unknown', 'consented', 'unsubscribed', 'dnc', 'bounced', 'complained')),
  source text,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (sales_contact_id, channel)
);

CREATE TABLE IF NOT EXISTS public.sales_automation_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  automation_id uuid NOT NULL REFERENCES public.sales_automation_definitions(id) ON DELETE CASCADE,
  version integer NOT NULL,
  steps jsonb NOT NULL DEFAULT '[]'::jsonb,
  published_at timestamptz NOT NULL DEFAULT now(),
  published_by_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  UNIQUE (automation_id, version)
);

CREATE TABLE IF NOT EXISTS public.sales_sequence_enrollments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  automation_id uuid NOT NULL REFERENCES public.sales_automation_definitions(id) ON DELETE CASCADE,
  automation_version integer NOT NULL,
  sales_lead_id uuid NOT NULL REFERENCES public.sales_leads(id) ON DELETE CASCADE,
  sales_contact_id uuid REFERENCES public.sales_contacts(id) ON DELETE SET NULL,
  owner_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paused', 'completed', 'stopped', 'failed')),
  current_step integer NOT NULL DEFAULT 0,
  next_run_at timestamptz,
  stop_reason text,
  state jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS sales_sequence_one_active_per_automation
  ON public.sales_sequence_enrollments(automation_id, sales_lead_id)
  WHERE status IN ('active', 'paused');

CREATE TABLE IF NOT EXISTS public.sales_automation_executions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  enrollment_id uuid NOT NULL REFERENCES public.sales_sequence_enrollments(id) ON DELETE CASCADE,
  step_index integer NOT NULL,
  idempotency_key text NOT NULL UNIQUE,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'running', 'succeeded', 'retry', 'dead_letter')),
  attempt_count integer NOT NULL DEFAULT 0,
  scheduled_for timestamptz NOT NULL,
  started_at timestamptz,
  completed_at timestamptz,
  next_retry_at timestamptz,
  error text,
  output jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS sales_automation_due_idx
  ON public.sales_automation_executions(status, COALESCE(next_retry_at, scheduled_for))
  WHERE status IN ('pending', 'retry');

CREATE OR REPLACE FUNCTION public.claim_due_sales_automation_executions(batch_size integer DEFAULT 25)
RETURNS SETOF public.sales_automation_executions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN QUERY
  WITH due AS (
    SELECT execution.id
    FROM public.sales_automation_executions execution
    WHERE execution.status IN ('pending', 'retry')
      AND COALESCE(execution.next_retry_at, execution.scheduled_for) <= now()
    ORDER BY COALESCE(execution.next_retry_at, execution.scheduled_for), execution.id
    FOR UPDATE SKIP LOCKED
    LIMIT LEAST(GREATEST(batch_size, 1), 100)
  )
  UPDATE public.sales_automation_executions execution
  SET status = 'running', started_at = now(), attempt_count = attempt_count + 1, updated_at = now()
  FROM due WHERE execution.id = due.id
  RETURNING execution.*;
END;
$$;

CREATE TABLE IF NOT EXISTS public.sales_availability_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  weekday smallint NOT NULL CHECK (weekday BETWEEN 0 AND 6),
  start_minute smallint NOT NULL CHECK (start_minute BETWEEN 0 AND 1439),
  end_minute smallint NOT NULL CHECK (end_minute BETWEEN 1 AND 1440 AND end_minute > start_minute),
  timezone text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  UNIQUE (user_id, weekday, start_minute, end_minute)
);

CREATE TABLE IF NOT EXISTS public.sales_availability_overrides (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL CHECK (ends_at > starts_at),
  is_available boolean NOT NULL DEFAULT false,
  note text
);

CREATE TABLE IF NOT EXISTS public.sales_booking_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  owner_user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  slug text NOT NULL UNIQUE,
  title text NOT NULL,
  description text,
  duration_minutes integer NOT NULL DEFAULT 30 CHECK (duration_minutes BETWEEN 10 AND 240),
  mode text NOT NULL DEFAULT 'personal' CHECK (mode IN ('personal', 'round_robin')),
  timezone text NOT NULL DEFAULT 'UTC',
  buffer_before_minutes integer NOT NULL DEFAULT 0,
  buffer_after_minutes integer NOT NULL DEFAULT 0,
  minimum_notice_minutes integer NOT NULL DEFAULT 60,
  reminder_minutes integer[] NOT NULL DEFAULT ARRAY[1440, 60],
  is_active boolean NOT NULL DEFAULT true,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.sales_booking_link_members (
  booking_link_id uuid NOT NULL REFERENCES public.sales_booking_links(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  position integer NOT NULL DEFAULT 0,
  last_assigned_at timestamptz,
  is_active boolean NOT NULL DEFAULT true,
  PRIMARY KEY (booking_link_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.sales_booking_holds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_link_id uuid NOT NULL REFERENCES public.sales_booking_links(id) ON DELETE CASCADE,
  assigned_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  token_hash text NOT NULL UNIQUE,
  verification_code_hash text,
  guest_name text,
  guest_email text,
  guest_phone text,
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '10 minutes'),
  confirmed_at timestamptz
);

CREATE UNIQUE INDEX IF NOT EXISTS sales_booking_active_hold_unique
  ON public.sales_booking_holds(assigned_user_id, starts_at, ends_at)
  WHERE confirmed_at IS NULL;

CREATE OR REPLACE FUNCTION public.create_sales_booking_hold(
  target_link_id uuid, target_starts_at timestamptz, target_ends_at timestamptz,
  target_token_hash text, target_verification_hash text, target_guest_name text,
  target_guest_email text, target_guest_phone text
) RETURNS SETOF public.sales_booking_holds
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE selected_user_id uuid;
BEGIN
  SELECT member.user_id INTO selected_user_id
  FROM public.sales_booking_link_members member
  JOIN public.sales_booking_links link ON link.id = member.booking_link_id
  WHERE member.booking_link_id = target_link_id AND member.is_active AND link.is_active
    AND NOT EXISTS (SELECT 1 FROM public.sales_bookings booking WHERE booking.assigned_user_id = member.user_id AND booking.status = 'confirmed' AND booking.starts_at < target_ends_at AND booking.ends_at > target_starts_at)
    AND NOT EXISTS (SELECT 1 FROM public.sales_booking_holds hold WHERE hold.assigned_user_id = member.user_id AND hold.confirmed_at IS NULL AND hold.expires_at > now() AND hold.starts_at < target_ends_at AND hold.ends_at > target_starts_at)
  ORDER BY member.last_assigned_at NULLS FIRST, member.position, member.user_id
  FOR UPDATE OF member SKIP LOCKED LIMIT 1;
  IF selected_user_id IS NULL THEN RAISE EXCEPTION 'No host is available.'; END IF;
  UPDATE public.sales_booking_link_members SET last_assigned_at = now() WHERE booking_link_id = target_link_id AND user_id = selected_user_id;
  RETURN QUERY INSERT INTO public.sales_booking_holds(booking_link_id, assigned_user_id, starts_at, ends_at, token_hash, verification_code_hash, guest_name, guest_email, guest_phone)
    VALUES(target_link_id, selected_user_id, target_starts_at, target_ends_at, target_token_hash, target_verification_hash, target_guest_name, target_guest_email, target_guest_phone)
    RETURNING *;
END;
$$;

CREATE TABLE IF NOT EXISTS public.sales_public_booking_requests (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ip_hash text NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS sales_public_booking_requests_recent_idx ON public.sales_public_booking_requests(ip_hash, occurred_at DESC);
ALTER TABLE public.sales_public_booking_requests ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.sales_bookings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  booking_link_id uuid REFERENCES public.sales_booking_links(id) ON DELETE SET NULL,
  assigned_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  sales_contact_id uuid REFERENCES public.sales_contacts(id) ON DELETE SET NULL,
  sales_lead_id uuid REFERENCES public.sales_leads(id) ON DELETE SET NULL,
  calendar_event_id uuid REFERENCES public.calendar_events(id) ON DELETE SET NULL,
  guest_name text NOT NULL,
  guest_email text NOT NULL,
  guest_phone text,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL CHECK (ends_at > starts_at),
  status text NOT NULL DEFAULT 'confirmed' CHECK (status IN ('confirmed', 'cancelled', 'completed', 'no_show', 'rescheduled')),
  outcome text CHECK (outcome IN ('held', 'no_show', 'rescheduled', 'cancelled')),
  zoom_join_url text,
  zoom_start_url text,
  cancellation_token_hash text NOT NULL UNIQUE,
  notes text,
  next_task_id uuid REFERENCES public.sales_tasks(id) ON DELETE SET NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS sales_bookings_owner_slot_unique
  ON public.sales_bookings(assigned_user_id, starts_at, ends_at)
  WHERE status = 'confirmed';

CREATE TABLE IF NOT EXISTS public.sales_booking_reminders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  booking_id uuid NOT NULL REFERENCES public.sales_bookings(id) ON DELETE CASCADE,
  channel text NOT NULL CHECK (channel IN ('email', 'push')),
  scheduled_for timestamptz NOT NULL,
  sent_at timestamptz,
  attempt_count integer NOT NULL DEFAULT 0,
  error text,
  UNIQUE (booking_id, channel, scheduled_for)
);

CREATE TABLE IF NOT EXISTS public.sales_merge_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  actor_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  entity_type text NOT NULL CHECK (entity_type IN ('contact', 'company')),
  survivor_id uuid NOT NULL,
  merged_id uuid NOT NULL,
  snapshot jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.sales_pro_rollouts (
  workspace_id uuid PRIMARY KEY REFERENCES public.workspaces(id) ON DELETE CASCADE,
  mode text NOT NULL DEFAULT 'shadow' CHECK (mode IN ('off', 'shadow', 'canary', 'enabled')),
  dual_write_enabled boolean NOT NULL DEFAULT true,
  reads_enabled boolean NOT NULL DEFAULT false,
  writes_enabled boolean NOT NULL DEFAULT false,
  enabled_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.sales_pro_rollouts(workspace_id)
SELECT id FROM public.workspaces ON CONFLICT (workspace_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.merge_sales_contacts(target_workspace_id uuid, survivor_contact_id uuid, merged_contact_id uuid, actor_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE merged_snapshot jsonb;
BEGIN
  IF survivor_contact_id = merged_contact_id THEN RAISE EXCEPTION 'Contacts must be different.'; END IF;
  SELECT to_jsonb(contact) INTO merged_snapshot FROM public.sales_contacts contact WHERE contact.workspace_id = target_workspace_id AND contact.id = merged_contact_id AND contact.merged_into_id IS NULL FOR UPDATE;
  IF merged_snapshot IS NULL OR NOT EXISTS (SELECT 1 FROM public.sales_contacts WHERE workspace_id = target_workspace_id AND id = survivor_contact_id AND merged_into_id IS NULL) THEN RAISE EXCEPTION 'Contact not found.'; END IF;
  UPDATE public.sales_leads SET sales_contact_id = survivor_contact_id WHERE workspace_id = target_workspace_id AND sales_contact_id = merged_contact_id;
  UPDATE public.sales_tasks SET sales_contact_id = survivor_contact_id WHERE workspace_id = target_workspace_id AND sales_contact_id = merged_contact_id;
  UPDATE public.sales_activities SET sales_contact_id = survivor_contact_id WHERE workspace_id = target_workspace_id AND sales_contact_id = merged_contact_id;
  UPDATE public.communication_threads SET sales_contact_id = survivor_contact_id WHERE workspace_id = target_workspace_id AND sales_contact_id = merged_contact_id;
  UPDATE public.communication_events SET sales_contact_id = survivor_contact_id WHERE workspace_id = target_workspace_id AND sales_contact_id = merged_contact_id;
  UPDATE public.sales_bookings SET sales_contact_id = survivor_contact_id WHERE workspace_id = target_workspace_id AND sales_contact_id = merged_contact_id;
  INSERT INTO public.sales_contact_campaigns(workspace_id, sales_contact_id, campaign_id) SELECT workspace_id, survivor_contact_id, campaign_id FROM public.sales_contact_campaigns WHERE sales_contact_id = merged_contact_id ON CONFLICT DO NOTHING;
  DELETE FROM public.sales_contact_campaigns WHERE sales_contact_id = merged_contact_id;
  UPDATE public.sales_contacts SET merged_into_id = survivor_contact_id WHERE id = merged_contact_id;
  INSERT INTO public.sales_merge_audit(workspace_id, actor_user_id, entity_type, survivor_id, merged_id, snapshot) VALUES(target_workspace_id, actor_id, 'contact', survivor_contact_id, merged_contact_id, merged_snapshot);
  RETURN survivor_contact_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.merge_sales_companies(target_workspace_id uuid, survivor_company_id uuid, merged_company_id uuid, actor_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE merged_snapshot jsonb;
BEGIN
  IF survivor_company_id = merged_company_id THEN RAISE EXCEPTION 'Companies must be different.'; END IF;
  SELECT to_jsonb(company) INTO merged_snapshot FROM public.sales_companies company WHERE company.workspace_id = target_workspace_id AND company.id = merged_company_id AND company.merged_into_id IS NULL FOR UPDATE;
  IF merged_snapshot IS NULL OR NOT EXISTS (SELECT 1 FROM public.sales_companies WHERE workspace_id = target_workspace_id AND id = survivor_company_id AND merged_into_id IS NULL) THEN RAISE EXCEPTION 'Company not found.'; END IF;
  UPDATE public.sales_contacts SET company_id = survivor_company_id WHERE workspace_id = target_workspace_id AND company_id = merged_company_id;
  UPDATE public.sales_leads SET company_id = survivor_company_id WHERE workspace_id = target_workspace_id AND company_id = merged_company_id;
  UPDATE public.sales_companies SET merged_into_id = survivor_company_id WHERE id = merged_company_id;
  INSERT INTO public.sales_merge_audit(workspace_id, actor_user_id, entity_type, survivor_id, merged_id, snapshot) VALUES(target_workspace_id, actor_id, 'company', survivor_company_id, merged_company_id, merged_snapshot);
  RETURN survivor_company_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.sales_pro_set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.sales_pro_refresh_next_action()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE lead_id uuid; contact_id uuid;
BEGIN
  lead_id := COALESCE(NEW.sales_lead_id, OLD.sales_lead_id);
  contact_id := COALESCE(NEW.sales_contact_id, OLD.sales_contact_id);
  IF lead_id IS NOT NULL THEN
    UPDATE public.sales_leads lead SET
      next_follow_up_at = task.due_at, next_task_title = task.title, next_task_type = task.task_type
    FROM (SELECT lead_id AS id) target
    LEFT JOIN LATERAL (
      SELECT due_at, title, task_type FROM public.sales_tasks
      WHERE sales_lead_id = target.id AND status = 'open'
      ORDER BY due_at NULLS LAST, created_at LIMIT 1
    ) task ON true
    WHERE lead.id = target.id;
  END IF;
  IF contact_id IS NOT NULL THEN
    UPDATE public.sales_contacts contact SET next_action_at = (
      SELECT due_at FROM public.sales_tasks WHERE sales_contact_id = contact_id AND status = 'open'
      ORDER BY due_at NULLS LAST, created_at LIMIT 1
    ) WHERE contact.id = contact_id;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS sales_tasks_refresh_next_action ON public.sales_tasks;
CREATE TRIGGER sales_tasks_refresh_next_action AFTER INSERT OR UPDATE OR DELETE ON public.sales_tasks
FOR EACH ROW EXECUTE FUNCTION public.sales_pro_refresh_next_action();

DO $$
DECLARE table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'sales_companies', 'sales_pipeline_stages', 'communication_threads', 'sales_mailboxes',
    'sales_automation_definitions', 'sales_sequence_enrollments', 'sales_automation_executions',
    'sales_booking_links', 'sales_bookings', 'sales_pro_rollouts', 'sales_automation_settings'
  ] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I_set_updated_at ON public.%I', table_name, table_name);
    EXECUTE format('CREATE TRIGGER %I_set_updated_at BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.sales_pro_set_updated_at()', table_name, table_name);
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.sales_workspace_member(target_workspace_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.workspace_members wm
    WHERE wm.workspace_id = target_workspace_id AND wm.user_id = auth.uid()
    UNION ALL
    SELECT 1 FROM public.workspaces workspace
    WHERE workspace.id = target_workspace_id AND workspace.owner_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.sales_workspace_admin(target_workspace_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.workspace_members wm
    WHERE wm.workspace_id = target_workspace_id AND wm.user_id = auth.uid() AND wm.role IN ('owner', 'admin')
    UNION ALL
    SELECT 1 FROM public.workspaces workspace
    WHERE workspace.id = target_workspace_id AND workspace.owner_id = auth.uid()
  );
$$;

DO $$
DECLARE table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'sales_companies', 'sales_pipeline_stages', 'sales_contact_campaigns', 'communication_threads',
    'communication_events', 'sales_mailboxes', 'sales_notifications', 'sales_automation_definitions', 'sales_automation_settings', 'sales_communication_preferences', 'sales_sequence_enrollments',
    'sales_automation_executions', 'sales_availability_rules', 'sales_availability_overrides',
    'sales_booking_links', 'sales_bookings', 'sales_booking_reminders', 'sales_merge_audit'
  ] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name);
    EXECUTE format('DROP POLICY IF EXISTS %I_member_access ON public.%I', table_name, table_name);
    EXECUTE format(
      'CREATE POLICY %I_member_access ON public.%I FOR ALL USING (public.sales_workspace_member(workspace_id)) WITH CHECK (public.sales_workspace_member(workspace_id))',
      table_name, table_name
    );
  END LOOP;
END $$;

ALTER TABLE public.sales_pro_rollouts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sales_pro_rollouts_member_read ON public.sales_pro_rollouts;
CREATE POLICY sales_pro_rollouts_member_read ON public.sales_pro_rollouts FOR SELECT
USING (public.sales_workspace_member(workspace_id));
DROP POLICY IF EXISTS sales_pro_rollouts_admin_write ON public.sales_pro_rollouts;
CREATE POLICY sales_pro_rollouts_admin_write ON public.sales_pro_rollouts FOR ALL
USING (public.sales_workspace_admin(workspace_id)) WITH CHECK (public.sales_workspace_admin(workspace_id));

DO $$
DECLARE table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY['sales_pipeline_stages', 'sales_mailboxes', 'sales_automation_definitions', 'sales_automation_executions'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I_member_access ON public.%I', table_name, table_name);
    EXECUTE format('DROP POLICY IF EXISTS %I_member_read ON public.%I', table_name, table_name);
    EXECUTE format('DROP POLICY IF EXISTS %I_admin_write ON public.%I', table_name, table_name);
    EXECUTE format('CREATE POLICY %I_member_read ON public.%I FOR SELECT USING (public.sales_workspace_member(workspace_id))', table_name, table_name);
    EXECUTE format('CREATE POLICY %I_admin_write ON public.%I FOR ALL USING (public.sales_workspace_admin(workspace_id)) WITH CHECK (public.sales_workspace_admin(workspace_id))', table_name, table_name);
  END LOOP;
END $$;

ALTER TABLE public.sales_automation_versions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sales_automation_versions_member_access ON public.sales_automation_versions;
CREATE POLICY sales_automation_versions_member_access ON public.sales_automation_versions FOR SELECT
USING (EXISTS (
  SELECT 1 FROM public.sales_automation_definitions definition
  WHERE definition.id = automation_id AND public.sales_workspace_member(definition.workspace_id)
));

ALTER TABLE public.sales_booking_link_members ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sales_booking_link_members_member_access ON public.sales_booking_link_members;
CREATE POLICY sales_booking_link_members_member_access ON public.sales_booking_link_members FOR ALL
USING (EXISTS (
  SELECT 1 FROM public.sales_booking_links link
  WHERE link.id = booking_link_id AND public.sales_workspace_member(link.workspace_id)
)) WITH CHECK (EXISTS (
  SELECT 1 FROM public.sales_booking_links link
  WHERE link.id = booking_link_id AND public.sales_workspace_member(link.workspace_id)
));

ALTER TABLE public.sales_booking_holds ENABLE ROW LEVEL SECURITY;
-- Holds are intentionally service-role only; public booking routes never receive direct table access.

COMMIT;
