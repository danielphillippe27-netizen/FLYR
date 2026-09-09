BEGIN;

-- Email and names are display fields, not authorization identities. No broad
-- workspace/founder policy may expose another rep's personal account or metrics.
ALTER TABLE public.salespeople ENABLE ROW LEVEL SECURITY;
CREATE POLICY personal_salesperson_identity ON public.salespeople
AS RESTRICTIVE FOR ALL TO authenticated
USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

DO $$
DECLARE table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'salesperson_referrals', 'salesperson_commissions',
    'salesperson_click_events', 'salesperson_demo_video_events',
    'salesperson_demo_links', 'salesperson_dialer_settings',
    'salesperson_meeting_conferences', 'salesperson_revenue_snapshots'
  ] LOOP
    -- Some installations do not enable all attribution/meeting modules.
    IF to_regclass('public.' || table_name) IS NULL THEN CONTINUE; END IF;
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name);
    EXECUTE format(
      'CREATE POLICY personal_salesperson_owner ON public.%I AS RESTRICTIVE FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM public.salespeople s WHERE s.id = salesperson_id AND s.user_id = auth.uid())) WITH CHECK (EXISTS (SELECT 1 FROM public.salespeople s WHERE s.id = salesperson_id AND s.user_id = auth.uid()))',
      table_name
    );
  END LOOP;
END $$;

CREATE INDEX IF NOT EXISTS communication_events_personal_metrics_idx
ON public.communication_events(workspace_id, actor_user_id, direction, occurred_at);

COMMIT;
