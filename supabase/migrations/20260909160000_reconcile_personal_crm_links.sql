BEGIN;
CREATE TABLE IF NOT EXISTS public.personal_crm_link_quarantine (
 source_table text NOT NULL, source_id uuid NOT NULL, reference_column text NOT NULL,
 previous_reference_id uuid NOT NULL, owner_user_id uuid, workspace_id uuid,
 quarantined_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(source_table,source_id,reference_column,previous_reference_id)
);
ALTER TABLE public.personal_crm_link_quarantine ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.personal_crm_link_quarantine FROM PUBLIC,anon,authenticated;
GRANT ALL ON public.personal_crm_link_quarantine TO service_role;
DO $$
DECLARE tbl text; owner_col text; pair text[];
BEGIN
 -- ALTER acquires table locks for this transaction; no concurrent writer can
 -- insert unchecked links while the validation triggers are suspended.
 FOREACH tbl IN ARRAY ARRAY['sales_contacts','sales_leads','sales_tasks','sales_bookings'] LOOP
  EXECUTE format('ALTER TABLE public.%I DISABLE TRIGGER personal_crm_references',tbl);
 END LOOP;
 FOREACH tbl IN ARRAY ARRAY['sales_contacts','sales_leads','sales_tasks','sales_bookings'] LOOP
  owner_col := CASE WHEN tbl='sales_contacts' THEN 'owner_user_id' ELSE 'assigned_user_id' END;
  FOREACH pair SLICE 1 IN ARRAY ARRAY[
   ['company_id','sales_companies','owner_user_id'],
   ['sales_contact_id','sales_contacts','owner_user_id'],
   ['sales_lead_id','sales_leads','assigned_user_id']
  ] LOOP
   IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name=tbl AND column_name=pair[1]) THEN CONTINUE; END IF;
   EXECUTE format('INSERT INTO public.personal_crm_link_quarantine(source_table,source_id,reference_column,previous_reference_id,owner_user_id,workspace_id)
    SELECT %L,src.id,%L,src.%I,src.%I,src.workspace_id FROM public.%I src
    WHERE src.%I IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.%I target WHERE target.id=src.%I AND target.workspace_id=src.workspace_id AND target.%I=src.%I)
    ON CONFLICT DO NOTHING',tbl,pair[1],pair[1],owner_col,tbl,pair[1],pair[2],pair[1],pair[3],owner_col);
   EXECUTE format('UPDATE public.%I src SET %I=NULL WHERE src.%I IS NOT NULL AND NOT EXISTS
    (SELECT 1 FROM public.%I target WHERE target.id=src.%I AND target.workspace_id=src.workspace_id AND target.%I=src.%I)',tbl,pair[1],pair[1],pair[2],pair[1],pair[3],owner_col);
  END LOOP;
 END LOOP;
 FOREACH tbl IN ARRAY ARRAY['sales_contacts','sales_leads','sales_tasks','sales_bookings'] LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE TRIGGER personal_crm_references',tbl);
 END LOOP;
END $$;
-- Repair only summaries whose task links were detached, preserving unrelated
-- manually entered follow-up values. No task body, contact or lead is deleted.
UPDATE public.sales_leads lead SET (next_follow_up_at,next_task_title,next_task_type)=(
 SELECT due_at,title,task_type FROM public.sales_tasks task
 WHERE task.sales_lead_id=lead.id AND task.assigned_user_id=lead.assigned_user_id
  AND task.workspace_id=lead.workspace_id AND task.status='open'
 ORDER BY due_at NULLS LAST,created_at,id LIMIT 1)
WHERE lead.id IN (SELECT previous_reference_id FROM public.personal_crm_link_quarantine
 WHERE source_table='sales_tasks' AND reference_column='sales_lead_id');
UPDATE public.sales_contacts contact SET next_action_at=(
 SELECT due_at FROM public.sales_tasks task
 WHERE task.sales_contact_id=contact.id AND task.assigned_user_id=contact.owner_user_id
  AND task.workspace_id=contact.workspace_id AND task.status='open'
 ORDER BY due_at NULLS LAST,created_at,id LIMIT 1)
WHERE contact.id IN (SELECT previous_reference_id FROM public.personal_crm_link_quarantine
 WHERE source_table='sales_tasks' AND reference_column='sales_contact_id');
COMMIT;
