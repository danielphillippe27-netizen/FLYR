BEGIN;
-- Restrictive policies prevent older workspace-wide policies from widening access.
DO $$
DECLARE table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY['contacts','field_leads','dialer_sessions'] LOOP
    IF to_regclass('public.' || table_name) IS NULL THEN CONTINUE; END IF;
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name);
    EXECUTE format('CREATE POLICY personal_legacy_owner ON public.%I AS RESTRICTIVE FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid())', table_name);
  END LOOP;
  IF to_regclass('public.dialer_session_leads') IS NOT NULL THEN
    ALTER TABLE public.dialer_session_leads ENABLE ROW LEVEL SECURITY;
    CREATE POLICY personal_session_lead_owner ON public.dialer_session_leads
    AS RESTRICTIVE FOR ALL TO authenticated
    USING (EXISTS (SELECT 1 FROM public.dialer_sessions s WHERE s.id = dialer_session_leads.session_id AND s.workspace_id = dialer_session_leads.workspace_id AND s.user_id = auth.uid()))
    WITH CHECK (EXISTS (SELECT 1 FROM public.dialer_sessions s WHERE s.id = dialer_session_leads.session_id AND s.workspace_id = dialer_session_leads.workspace_id AND s.user_id = auth.uid())
      AND EXISTS (SELECT 1 FROM public.contacts c WHERE c.id = dialer_session_leads.contact_id AND c.user_id = auth.uid()));
  END IF;
END $$;
COMMIT;
