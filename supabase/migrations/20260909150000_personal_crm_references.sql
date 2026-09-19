BEGIN;
CREATE FUNCTION public.enforce_personal_crm_references() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
DECLARE row_data jsonb := to_jsonb(NEW); owner_id uuid; target_id uuid; target_table text; owner_column text; valid boolean; pair text[];
BEGIN
 owner_id := (row_data ->> CASE WHEN TG_TABLE_NAME='sales_contacts' THEN 'owner_user_id' ELSE 'assigned_user_id' END)::uuid;
 FOREACH pair SLICE 1 IN ARRAY ARRAY[
  ['company_id','sales_companies','owner_user_id'],
  ['sales_contact_id','sales_contacts','owner_user_id'],
  ['sales_lead_id','sales_leads','assigned_user_id']
 ] LOOP
  target_id := (row_data ->> pair[1])::uuid;
  IF target_id IS NULL THEN CONTINUE; END IF;
  EXECUTE format('SELECT EXISTS (SELECT 1 FROM public.%I WHERE id=$1 AND workspace_id=$2 AND %I=$3)',pair[2],pair[3])
   INTO valid USING target_id,NEW.workspace_id,owner_id;
  IF NOT valid THEN RAISE EXCEPTION 'Personal CRM reference owner does not match.' USING ERRCODE='42501'; END IF;
 END LOOP;
 RETURN NEW;
END $$;
DO $$ DECLARE table_name text; BEGIN
 FOREACH table_name IN ARRAY ARRAY['sales_contacts','sales_leads','sales_tasks','sales_bookings'] LOOP
  EXECUTE format('CREATE TRIGGER personal_crm_references BEFORE INSERT OR UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.enforce_personal_crm_references()', table_name);
 END LOOP;
END $$;

-- Definer privileges are needed to refresh summaries, never to mix users' tasks.
CREATE OR REPLACE FUNCTION public.sales_pro_refresh_next_action() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE task_row record;
BEGIN
 FOR task_row IN SELECT DISTINCT * FROM (
  SELECT (to_jsonb(NEW)->>'sales_lead_id')::uuid lead_id,(to_jsonb(NEW)->>'sales_contact_id')::uuid contact_id,
         (to_jsonb(NEW)->>'assigned_user_id')::uuid owner_id,(to_jsonb(NEW)->>'workspace_id')::uuid workspace_id
  UNION
  SELECT (to_jsonb(OLD)->>'sales_lead_id')::uuid,(to_jsonb(OLD)->>'sales_contact_id')::uuid,
         (to_jsonb(OLD)->>'assigned_user_id')::uuid,(to_jsonb(OLD)->>'workspace_id')::uuid
 ) refs LOOP
  UPDATE public.sales_leads lead SET (next_follow_up_at,next_task_title,next_task_type)=(
   SELECT due_at,title,task_type FROM public.sales_tasks task
   WHERE task.sales_lead_id=lead.id AND task.assigned_user_id=lead.assigned_user_id
    AND task.workspace_id=lead.workspace_id AND task.status='open'
   ORDER BY due_at NULLS LAST,created_at,id LIMIT 1)
  WHERE lead.id=task_row.lead_id AND lead.assigned_user_id=task_row.owner_id AND lead.workspace_id=task_row.workspace_id;
  UPDATE public.sales_contacts contact SET next_action_at=(
   SELECT due_at FROM public.sales_tasks task
   WHERE task.sales_contact_id=contact.id AND task.assigned_user_id=contact.owner_user_id
    AND task.workspace_id=contact.workspace_id AND task.status='open'
   ORDER BY due_at NULLS LAST,created_at,id LIMIT 1)
  WHERE contact.id=task_row.contact_id AND contact.owner_user_id=task_row.owner_id AND contact.workspace_id=task_row.workspace_id;
 END LOOP;
 RETURN COALESCE(NEW,OLD);
END $$;
COMMIT;
