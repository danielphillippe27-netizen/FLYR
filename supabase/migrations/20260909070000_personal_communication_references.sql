BEGIN;
-- Detach uncertain historical CRM links without deleting personal communication.
UPDATE public.communication_events e SET sales_contact_id = NULL
WHERE e.sales_contact_id IS NOT NULL AND NOT EXISTS (
 SELECT 1 FROM public.sales_contacts c WHERE c.id=e.sales_contact_id
 AND c.workspace_id=e.workspace_id AND c.owner_user_id=e.actor_user_id);
UPDATE public.communication_events e SET sales_lead_id = NULL
WHERE e.sales_lead_id IS NOT NULL AND NOT EXISTS (
 SELECT 1 FROM public.sales_leads l WHERE l.id=e.sales_lead_id
 AND l.workspace_id=e.workspace_id AND l.assigned_user_id=e.actor_user_id);
UPDATE public.communication_threads t SET sales_contact_id = NULL
WHERE t.sales_contact_id IS NOT NULL AND NOT EXISTS (
 SELECT 1 FROM public.sales_contacts c WHERE c.id=t.sales_contact_id
 AND c.workspace_id=t.workspace_id AND c.owner_user_id=t.assigned_user_id);
UPDATE public.communication_threads t SET sales_lead_id = NULL
WHERE t.sales_lead_id IS NOT NULL AND NOT EXISTS (
 SELECT 1 FROM public.sales_leads l WHERE l.id=t.sales_lead_id
 AND l.workspace_id=t.workspace_id AND l.assigned_user_id=t.assigned_user_id);

CREATE FUNCTION public.enforce_personal_communication_references() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
DECLARE owner_user uuid;
BEGIN
 IF TG_TABLE_NAME = 'communication_events' THEN owner_user := NEW.actor_user_id;
 ELSE owner_user := NEW.assigned_user_id; END IF;
 IF NEW.sales_contact_id IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM public.sales_contacts c WHERE c.id=NEW.sales_contact_id
  AND c.workspace_id=NEW.workspace_id AND c.owner_user_id=owner_user) THEN
  RAISE EXCEPTION 'Communication contact owner does not match.' USING ERRCODE='42501';
 END IF;
 IF NEW.sales_lead_id IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM public.sales_leads l WHERE l.id=NEW.sales_lead_id
  AND l.workspace_id=NEW.workspace_id AND l.assigned_user_id=owner_user) THEN
  RAISE EXCEPTION 'Communication lead owner does not match.' USING ERRCODE='42501';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER personal_communication_event_references
BEFORE INSERT OR UPDATE OF sales_contact_id,sales_lead_id,actor_user_id,workspace_id
ON public.communication_events FOR EACH ROW EXECUTE FUNCTION public.enforce_personal_communication_references();
CREATE TRIGGER personal_communication_thread_references
BEFORE INSERT OR UPDATE OF sales_contact_id,sales_lead_id,assigned_user_id,workspace_id
ON public.communication_threads FOR EACH ROW EXECUTE FUNCTION public.enforce_personal_communication_references();
COMMIT;
