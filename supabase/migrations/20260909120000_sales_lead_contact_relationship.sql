BEGIN;
-- Some standalone sales databases created sales_leads without its contact FK.
-- PostgREST cannot embed owned leads from contacts without that relationship.
-- NOT VALID preserves existing orphan rows for separate reconciliation while
-- enforcing referential integrity for new links.
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_constraint c
 JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=ANY(c.conkey)
 WHERE c.contype='f' AND c.conrelid='public.sales_leads'::regclass
 AND c.confrelid='public.sales_contacts'::regclass AND a.attname='sales_contact_id') THEN
  ALTER TABLE public.sales_leads ADD CONSTRAINT sales_leads_sales_contact_id_fkey
  FOREIGN KEY (sales_contact_id) REFERENCES public.sales_contacts(id) ON DELETE SET NULL NOT VALID;
 END IF;
END $$;
NOTIFY pgrst, 'reload schema';
COMMIT;
