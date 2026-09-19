BEGIN;

ALTER TABLE public.dialer_inbound_messages ADD COLUMN IF NOT EXISTS owner_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;

-- Restrictive policies AND with every existing permissive policy. Workspace
-- membership (including owner/admin) alone must never grant personal access.
DO $$
DECLARE item record;
BEGIN
  FOR item IN SELECT * FROM (VALUES
    ('communication_threads', 'assigned_user_id'),
    ('communication_events', 'actor_user_id'),
    ('dialer_calls', 'user_id'),
    ('dialer_inbound_messages', 'owner_user_id'),
    ('dialer_messages', 'sender_user_id'),
    ('dialer_sms_followups', 'user_id'),
    ('sales_mailboxes', 'user_id'),
    ('sales_activities', 'actor_user_id'),
    ('sales_notifications', 'user_id')
  ) AS ownership(table_name, owner_column)
  LOOP
    IF item.table_name = 'dialer_sms_followups' AND to_regclass('public.dialer_sms_followups') IS NULL THEN CONTINUE; END IF;
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', item.table_name);
    EXECUTE format('CREATE POLICY personal_communication_owner ON public.%I AS RESTRICTIVE FOR ALL TO authenticated USING (%I = auth.uid() AND public.sales_workspace_member(workspace_id)) WITH CHECK (%I = auth.uid() AND public.sales_workspace_member(workspace_id))', item.table_name, item.owner_column, item.owner_column);
    EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON public.%I (workspace_id, %I)', item.table_name || '_personal_owner_idx', item.table_name, item.owner_column);
  END LOOP;
END $$;

-- Serialize the one-time split against concurrent webhook/thread writes.
LOCK TABLE public.communication_threads, public.communication_events IN SHARE ROW EXCLUSIVE MODE;

-- Older Telnyx webhook events used the caller's lead assignee, which does not
-- prove who received the communication. Retain the evidence for reconciliation
-- but quarantine these records; current assignments cannot prove past ownership.
UPDATE public.communication_events
SET metadata = metadata || jsonb_build_object('unverified_legacy_actor_user_id', actor_user_id),
    actor_user_id = NULL
WHERE provider = 'telnyx'
  AND (event_kind LIKE 'call.%' OR event_kind LIKE 'message.%' OR event_kind = 'voicemail_received')
  AND metadata->>'ownershipVerified' IS DISTINCT FROM 'true';

-- Hide CRM copies of the same unverified provider events as well.
UPDATE public.sales_activities a
SET metadata = a.metadata || jsonb_build_object('unverified_legacy_actor_user_id', a.actor_user_id),
    actor_user_id = NULL
WHERE EXISTS (
  SELECT 1 FROM public.communication_events e
  WHERE e.id::text = a.metadata->>'communicationEventId'
    AND e.actor_user_id IS NULL AND e.metadata ? 'unverified_legacy_actor_user_id'
);

-- Rebuild personal threads from each event's known owner. Do not copy thread
-- subjects, previews, read state or metadata that may belong to another user.
DO $$
DECLARE grp record; personal_thread_id uuid;
BEGIN
  FOR grp IN
    SELECT e.thread_id, e.workspace_id, e.actor_user_id
    FROM public.communication_events e WHERE e.actor_user_id IS NOT NULL
    GROUP BY e.thread_id, e.workspace_id, e.actor_user_id
  LOOP
    INSERT INTO public.communication_threads (
      workspace_id, assigned_user_id, sales_contact_id, sales_lead_id,
      subject, latest_channel, latest_event_at, needs_response, metadata
    )
    SELECT e.workspace_id, e.actor_user_id, e.sales_contact_id, e.sales_lead_id,
      e.subject, e.channel, e.occurred_at, e.direction = 'inbound',
      jsonb_build_object('personal_ownership_migration', true)
    FROM public.communication_events e
    WHERE e.thread_id = grp.thread_id AND e.workspace_id = grp.workspace_id AND e.actor_user_id = grp.actor_user_id
    ORDER BY e.occurred_at DESC, e.id DESC LIMIT 1
    RETURNING id INTO personal_thread_id;
    UPDATE public.communication_events SET thread_id = personal_thread_id
    WHERE thread_id = grp.thread_id AND workspace_id = grp.workspace_id AND actor_user_id = grp.actor_user_id;
  END LOOP;
END $$;
UPDATE public.communication_threads SET assigned_user_id = NULL
WHERE metadata->>'personal_ownership_migration' IS DISTINCT FROM 'true';

CREATE POLICY personal_event_thread_owner ON public.communication_events
AS RESTRICTIVE FOR ALL TO authenticated
USING (EXISTS (SELECT 1 FROM public.communication_threads t
  WHERE t.id = thread_id AND t.workspace_id = communication_events.workspace_id AND t.assigned_user_id = auth.uid()))
WITH CHECK (EXISTS (SELECT 1 FROM public.communication_threads t
  WHERE t.id = thread_id AND t.workspace_id = communication_events.workspace_id AND t.assigned_user_id = auth.uid()));

-- Legacy contact logs have no trustworthy owner. Keep old communication bodies
-- private and stamp future authenticated writes with the authenticated user.
ALTER TABLE public.contact_activities ADD COLUMN IF NOT EXISTS communication_owner_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.contact_activities ALTER COLUMN communication_owner_user_id SET DEFAULT auth.uid();
CREATE POLICY personal_contact_communication ON public.contact_activities
AS RESTRICTIVE FOR ALL TO authenticated
USING (type NOT IN ('text', 'email', 'call') OR communication_owner_user_id = auth.uid())
WITH CHECK (type NOT IN ('text', 'email', 'call') OR communication_owner_user_id = auth.uid());

CREATE POLICY personal_social_connection ON public.social_connections
AS RESTRICTIVE FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY personal_social_thread ON public.social_threads
AS RESTRICTIVE FOR ALL TO authenticated
USING (EXISTS (SELECT 1 FROM public.social_connections c WHERE c.id = connection_id AND c.user_id = auth.uid()))
WITH CHECK (EXISTS (SELECT 1 FROM public.social_connections c WHERE c.id = connection_id AND c.user_id = auth.uid()));
CREATE POLICY personal_social_interaction ON public.social_interactions
AS RESTRICTIVE FOR ALL TO authenticated
USING (EXISTS (SELECT 1 FROM public.social_connections c WHERE c.id = connection_id AND c.user_id = auth.uid()))
WITH CHECK (EXISTS (SELECT 1 FROM public.social_connections c WHERE c.id = connection_id AND c.user_id = auth.uid()));

COMMIT;
