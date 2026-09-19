BEGIN;

-- Retain established contact ownership; never infer an owner from a current
-- workspace membership or another user's present lead assignment.
DO $$ BEGIN
 IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='sales_contacts' AND column_name='user_id') THEN
  EXECUTE 'UPDATE public.sales_contacts SET owner_user_id = user_id WHERE owner_user_id IS NULL AND user_id IS NOT NULL';
 END IF;
END $$;

DO $$
DECLARE item record;
BEGIN
  FOR item IN SELECT * FROM (VALUES
    ('sales_contacts','owner_user_id'), ('sales_companies','owner_user_id'),
    ('sales_leads','assigned_user_id'), ('sales_tasks','assigned_user_id'),
    ('sales_bookings','assigned_user_id')
  ) AS scope(table_name,owner_column) LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', item.table_name);
    EXECUTE format('CREATE POLICY personal_record_owner ON public.%I AS RESTRICTIVE FOR ALL TO authenticated USING (%I = auth.uid()) WITH CHECK (%I = auth.uid())', item.table_name,item.owner_column,item.owner_column);
  END LOOP;
END $$;

-- Two reps may keep independent notes for the same company/source record.
DROP INDEX IF EXISTS public.sales_companies_workspace_domain_unique;
CREATE UNIQUE INDEX sales_companies_personal_domain_unique ON public.sales_companies(workspace_id,owner_user_id,lower(website_domain)) WHERE website_domain IS NOT NULL AND merged_into_id IS NULL;
DROP INDEX IF EXISTS public.sales_contacts_workspace_source_uidx;
CREATE UNIQUE INDEX sales_contacts_personal_source_uidx ON public.sales_contacts(workspace_id,owner_user_id,source,external_id) WHERE source IS NOT NULL AND source <> '' AND external_id IS NOT NULL AND external_id <> '';

CREATE OR REPLACE FUNCTION public.merge_sales_contacts(target_workspace_id uuid, survivor_contact_id uuid, merged_contact_id uuid, actor_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE merged_snapshot jsonb;
BEGIN
  IF actor_id IS NULL OR (auth.role() IS DISTINCT FROM 'service_role' AND actor_id IS DISTINCT FROM auth.uid()) THEN
    RAISE EXCEPTION 'Authenticated actor required.';
  END IF;
  IF (SELECT count(*) FROM public.sales_contacts WHERE workspace_id = target_workspace_id
      AND owner_user_id = actor_id AND id IN (survivor_contact_id, merged_contact_id)) <> 2 THEN
    RAISE EXCEPTION 'Personal records not found.';
  END IF;
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
  IF actor_id IS NULL OR (auth.role() IS DISTINCT FROM 'service_role' AND actor_id IS DISTINCT FROM auth.uid()) THEN
    RAISE EXCEPTION 'Authenticated actor required.';
  END IF;
  IF (SELECT count(*) FROM public.sales_companies WHERE workspace_id = target_workspace_id
      AND owner_user_id = actor_id AND id IN (survivor_company_id, merged_company_id)) <> 2 THEN
    RAISE EXCEPTION 'Personal records not found.';
  END IF;
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


COMMIT;
