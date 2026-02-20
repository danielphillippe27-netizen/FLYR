-- Enable Realtime for field_leads so the web app can show leads created on iOS without refresh.
-- Dashboard: Database → Replication → supabase_realtime (or run this migration).

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'field_leads'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.field_leads;
  END IF;
END
$$;

COMMENT ON TABLE public.field_leads IS 'Field-captured leads from door sessions; optional sync to external CRM. Realtime enabled for web sync.';
