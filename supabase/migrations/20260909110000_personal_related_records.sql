BEGIN;
-- These auxiliary records can contain full snapshots and private follow-up data.
DO $$ DECLARE item record; BEGIN
 FOR item IN SELECT * FROM (VALUES ('sales_merge_audit','actor_user_id'),('sales_company_research','requested_by_user_id'),('sales_company_research_batches','requested_by_user_id')) AS p(table_name,owner_column) LOOP
  IF to_regclass('public.'||item.table_name) IS NULL THEN CONTINUE; END IF;
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',item.table_name);
  EXECUTE format('CREATE POLICY personal_related_owner ON public.%I AS RESTRICTIVE FOR ALL TO authenticated USING (%I=auth.uid()) WITH CHECK (%I=auth.uid())',item.table_name,item.owner_column,item.owner_column);
 END LOOP;
END $$;
ALTER TABLE public.sales_booking_reminders ENABLE ROW LEVEL SECURITY;
CREATE POLICY personal_booking_reminder ON public.sales_booking_reminders AS RESTRICTIVE FOR ALL TO authenticated
USING (EXISTS (SELECT 1 FROM public.sales_bookings b WHERE b.id=sales_booking_reminders.booking_id AND b.workspace_id=sales_booking_reminders.workspace_id AND b.assigned_user_id=auth.uid()))
WITH CHECK (EXISTS (SELECT 1 FROM public.sales_bookings b WHERE b.id=sales_booking_reminders.booking_id AND b.workspace_id=sales_booking_reminders.workspace_id AND b.assigned_user_id=auth.uid()));
ALTER TABLE public.sales_communication_preferences ENABLE ROW LEVEL SECURITY;
CREATE POLICY personal_communication_preference ON public.sales_communication_preferences AS RESTRICTIVE FOR ALL TO authenticated
USING (EXISTS (SELECT 1 FROM public.sales_contacts c WHERE c.id=sales_communication_preferences.sales_contact_id AND c.workspace_id=sales_communication_preferences.workspace_id AND c.owner_user_id=auth.uid()))
WITH CHECK (EXISTS (SELECT 1 FROM public.sales_contacts c WHERE c.id=sales_communication_preferences.sales_contact_id AND c.workspace_id=sales_communication_preferences.workspace_id AND c.owner_user_id=auth.uid()));
ALTER TABLE public.sales_contact_campaigns ENABLE ROW LEVEL SECURITY;
CREATE POLICY personal_contact_campaign ON public.sales_contact_campaigns AS RESTRICTIVE FOR ALL TO authenticated
USING (EXISTS (SELECT 1 FROM public.sales_contacts c WHERE c.id=sales_contact_campaigns.sales_contact_id AND c.workspace_id=sales_contact_campaigns.workspace_id AND c.owner_user_id=auth.uid()))
WITH CHECK (EXISTS (SELECT 1 FROM public.sales_contacts c WHERE c.id=sales_contact_campaigns.sales_contact_id AND c.workspace_id=sales_contact_campaigns.workspace_id AND c.owner_user_id=auth.uid()));
COMMIT;
