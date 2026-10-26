BEGIN;

-- Demo reminders share the task lifecycle but never replace manual reminders.
CREATE INDEX IF NOT EXISTS sales_tasks_demo_queue_idx
  ON public.sales_tasks(workspace_id, assigned_user_id, status, due_at)
  WHERE task_type = 'demo_follow_up';
CREATE INDEX IF NOT EXISTS communication_events_demo_task_idx
  ON public.communication_events((metadata->>'demoFollowUpTaskId'), occurred_at);

CREATE OR REPLACE FUNCTION public.track_sent_demo_follow_up() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  lead public.sales_leads;
  contact public.sales_contacts;
  task public.sales_tasks;
  lead_id uuid;
  contact_id uuid;
  recipient text;
  recipient_name text;
  email text;
  phone text;
  task_id uuid;
BEGIN
  IF NEW.actor_user_id IS NULL OR NEW.channel NOT IN ('email','sms') THEN RETURN NEW; END IF;
  IF NEW.direction <> 'outbound' OR NEW.event_kind <> 'demo_sent'
    OR lower(NEW.status) NOT IN ('sent','queued','accepted','sending','delivered','sent_to_carrier','opened','clicked')
    OR NEW.metadata ? 'demoFollowUpTaskId' THEN RETURN NEW; END IF;

  -- Serializes simultaneous email/text sends for this owner, including sends
  -- without a CRM link. The communication and reminder commit together.
  PERFORM pg_advisory_xact_lock(hashtextextended(NEW.workspace_id::text || NEW.actor_user_id::text, 0));
  SELECT * INTO lead FROM public.sales_leads WHERE id=NEW.sales_lead_id
    AND workspace_id=NEW.workspace_id AND assigned_user_id=NEW.actor_user_id;
  lead_id := lead.id;
  SELECT * INTO contact FROM public.sales_contacts
    WHERE id=COALESCE(NEW.sales_contact_id,lead.sales_contact_id)
      AND workspace_id=NEW.workspace_id AND owner_user_id=NEW.actor_user_id;
  contact_id := contact.id;
  recipient := lower(nullif(trim(NEW.to_addresses[1]),''));
  email := lower(CASE WHEN NEW.channel='email' THEN recipient ELSE COALESCE(nullif(contact.email,''),nullif(lead.email,'')) END);
  phone := regexp_replace(CASE WHEN NEW.channel='sms' THEN recipient
    ELSE COALESCE(nullif(contact.phone_e164,''),nullif(lead.phone_e164,''),nullif(contact.phone,''),nullif(lead.phone,'')) END,'[^0-9]','','g');
  recipient_name := COALESCE(nullif(contact.name,''),nullif(lead.name,''),nullif(NEW.metadata->>'recipientName',''),recipient,'Demo recipient');
  IF recipient IS NULL THEN RETURN NEW; END IF;
  IF lead.lead_state IN ('dnc','converted','archived') OR lead.pipeline_stage IN ('won','lost','trial_active')
    OR lead.signed_up_user_id IS NOT NULL THEN RETURN NEW; END IF;
  IF EXISTS(SELECT 1 FROM public.sales_communication_preferences WHERE sales_contact_id=contact_id
    AND workspace_id=NEW.workspace_id AND status IN ('unsubscribed','dnc','complained')) THEN RETURN NEW; END IF;

  SELECT * INTO task FROM public.sales_tasks t
    WHERE t.workspace_id=NEW.workspace_id AND t.assigned_user_id=NEW.actor_user_id
      AND t.task_type='demo_follow_up' AND t.status='open'
      AND ((lead_id IS NOT NULL AND t.sales_lead_id=lead_id)
        OR (contact_id IS NOT NULL AND t.sales_contact_id=contact_id)
        OR ((contact_id IS NULL OR t.sales_contact_id IS NULL OR t.sales_contact_id=contact_id)
          AND ((email IS NOT NULL AND t.metadata->>'recipientEmail'=email)
            OR (nullif(phone,'') IS NOT NULL AND t.metadata->>'recipientPhone'=phone))))
    ORDER BY t.created_at,t.id LIMIT 1 FOR UPDATE;
  task_id := task.id;
  IF task_id IS NULL THEN
    INSERT INTO public.sales_tasks(workspace_id,assigned_user_id,sales_lead_id,sales_contact_id,
      task_type,title,status,due_at,notes,metadata)
    VALUES(NEW.workspace_id,NEW.actor_user_id,lead_id,contact_id,'demo_follow_up',
      'Follow up with ' || recipient_name,'open',NEW.occurred_at + interval '7 days',
      'Automatically scheduled seven days after sending a demo.',
      jsonb_build_object('source','demo_send','recipientName',recipient_name,
        'recipientEmail',email,'recipientPhone',phone,'firstSentAt',NEW.occurred_at,
        'lastSentAt',NEW.occurred_at,'lastChannel',NEW.channel,'sendCount',1,
        'lastBody',NEW.body,'lastSubject',NEW.subject,'threadId',NEW.thread_id))
    RETURNING id INTO task_id;
  ELSE
    -- Resends retain the original due date, including a user-selected snooze.
    UPDATE public.sales_tasks SET
      sales_lead_id=COALESCE(sales_lead_id,lead_id),
      sales_contact_id=COALESCE(sales_contact_id,contact_id),
      metadata=metadata || jsonb_build_object('lastSentAt',NEW.occurred_at,
        'lastChannel',NEW.channel,'sendCount',COALESCE((metadata->>'sendCount')::integer,0)+1,
        'recipientName',CASE WHEN contact_id IS NOT NULL OR lead_id IS NOT NULL THEN recipient_name ELSE metadata->>'recipientName' END,
        'recipientEmail',COALESCE(email,metadata->>'recipientEmail'),
        'recipientPhone',COALESCE(nullif(phone,''),metadata->>'recipientPhone'),
        'lastBody',NEW.body,'lastSubject',NEW.subject,'threadId',NEW.thread_id)
    WHERE id=task_id;
  END IF;
  NEW.metadata := NEW.metadata || jsonb_build_object('demoFollowUpTaskId',task_id);
  RETURN NEW;
END $$;

CREATE TRIGGER communication_events_demo_follow_up
  BEFORE INSERT OR UPDATE OF status ON public.communication_events
  FOR EACH ROW EXECUTE FUNCTION public.track_sent_demo_follow_up();

-- A reply is a signal to act, not evidence that the follow-up is complete.
CREATE OR REPLACE FUNCTION public.flag_demo_follow_up_reply() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE stop_requested boolean;
BEGIN
  IF NEW.direction='inbound' AND NEW.actor_user_id IS NOT NULL AND NEW.channel IN ('email','sms') THEN
    stop_requested := NEW.channel='sms' AND lower(trim(COALESCE(NEW.body,''))) IN ('stop','stopall','unsubscribe','cancel','end','quit');
    UPDATE public.sales_tasks SET
      status=CASE WHEN stop_requested THEN 'dismissed' ELSE status END,
      metadata=metadata || jsonb_build_object('replyReceivedAt',NEW.occurred_at)
        || CASE WHEN stop_requested THEN jsonb_build_object('outcome','opted_out') ELSE '{}'::jsonb END
    WHERE workspace_id=NEW.workspace_id AND assigned_user_id=NEW.actor_user_id
      AND task_type='demo_follow_up' AND status='open'
      AND (sales_lead_id=NEW.sales_lead_id OR sales_contact_id=NEW.sales_contact_id
        OR (NEW.channel='email' AND metadata->>'recipientEmail'=lower(NEW.from_address))
        OR (NEW.channel='sms' AND metadata->>'recipientPhone'=regexp_replace(NEW.from_address,'[^0-9]','','g')))
      AND (metadata->>'firstSentAt')::timestamptz <= NEW.occurred_at;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER communication_events_demo_reply AFTER INSERT ON public.communication_events
  FOR EACH ROW EXECUTE FUNCTION public.flag_demo_follow_up_reply();

CREATE OR REPLACE FUNCTION public.close_demo_follow_ups_for_lead() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE outcome text;
BEGIN
  IF NEW.signed_up_user_id IS NOT NULL OR NEW.lead_state='converted' OR NEW.pipeline_stage IN ('trial_active','won') THEN
    outcome := 'signed_up';
  ELSIF NEW.lead_state IN ('dnc','archived') OR NEW.pipeline_stage='lost' OR NEW.disposition='not_interested' THEN
    outcome := 'stopped';
  ELSE RETURN NEW; END IF;
  UPDATE public.sales_tasks SET status=CASE WHEN outcome='signed_up' THEN 'completed' ELSE 'dismissed' END,
    completed_at=CASE WHEN outcome='signed_up' THEN now() END,
    metadata=metadata || jsonb_build_object('outcome',outcome)
  WHERE workspace_id=NEW.workspace_id AND assigned_user_id=NEW.assigned_user_id
    AND task_type='demo_follow_up' AND status='open'
    AND (sales_lead_id=NEW.id OR sales_contact_id=NEW.sales_contact_id
      OR (sales_lead_id IS NULL AND sales_contact_id IS NULL AND metadata->>'recipientEmail'=lower(NEW.email)));
  RETURN NEW;
END $$;
CREATE TRIGGER sales_leads_close_demo_follow_ups
  AFTER UPDATE OF signed_up_user_id,lead_state,pipeline_stage,disposition ON public.sales_leads
  FOR EACH ROW WHEN (OLD.signed_up_user_id IS DISTINCT FROM NEW.signed_up_user_id
    OR OLD.lead_state IS DISTINCT FROM NEW.lead_state OR OLD.pipeline_stage IS DISTINCT FROM NEW.pipeline_stage
    OR OLD.disposition IS DISTINCT FROM NEW.disposition)
  EXECUTE FUNCTION public.close_demo_follow_ups_for_lead();

CREATE OR REPLACE FUNCTION public.stop_opted_out_demo_follow_ups() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.status IN ('unsubscribed','dnc','complained') THEN
    UPDATE public.sales_tasks task SET status='dismissed',
      metadata=task.metadata || jsonb_build_object('outcome','opted_out')
    FROM public.sales_contacts contact
    WHERE contact.id=NEW.sales_contact_id AND contact.workspace_id=NEW.workspace_id
      AND task.sales_contact_id=contact.id AND task.workspace_id=contact.workspace_id
      AND task.assigned_user_id=contact.owner_user_id
      AND task.task_type='demo_follow_up' AND task.status='open';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER sales_preferences_stop_demo_follow_ups
  AFTER INSERT OR UPDATE OF status ON public.sales_communication_preferences
  FOR EACH ROW EXECUTE FUNCTION public.stop_opted_out_demo_follow_ups();

-- A provider can accept a message and later report a delivery failure. Keep
-- its history, but stop the reminder if none of this task's sends succeeded.
CREATE OR REPLACE FUNCTION public.stop_failed_demo_follow_up() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.metadata ? 'demoFollowUpTaskId' AND lower(NEW.status) IN ('failed','rejected','canceled','cancelled','undelivered','bounced','suppressed','complained') THEN
    UPDATE public.sales_tasks task SET status='dismissed',
      metadata=task.metadata || jsonb_build_object('outcome','delivery_failed')
    WHERE task.id::text=NEW.metadata->>'demoFollowUpTaskId'
      AND task.workspace_id=NEW.workspace_id AND task.assigned_user_id=NEW.actor_user_id
      AND task.task_type='demo_follow_up' AND task.status='open'
      AND NOT EXISTS(SELECT 1 FROM public.communication_events event
        WHERE event.workspace_id=NEW.workspace_id AND event.actor_user_id=NEW.actor_user_id
          AND event.metadata->>'demoFollowUpTaskId'=task.id::text
          AND lower(event.status) IN ('sent','queued','accepted','sending','delivered','sent_to_carrier','opened','clicked'));
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER communication_events_stop_failed_demo
  AFTER UPDATE OF status ON public.communication_events FOR EACH ROW
  EXECUTE FUNCTION public.stop_failed_demo_follow_up();

REVOKE ALL ON FUNCTION public.track_sent_demo_follow_up() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.flag_demo_follow_up_reply() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.close_demo_follow_ups_for_lead() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.stop_opted_out_demo_follow_ups() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.stop_failed_demo_follow_up() FROM PUBLIC;

-- No historical backfill: generated links and old drafts are not proof of send.
COMMIT;
