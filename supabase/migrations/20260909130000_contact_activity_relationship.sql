BEGIN;
-- Legacy activity metrics join the contact to constrain the workspace while
-- attribution stays with communication_owner_user_id. Some sales schemas omit
-- this relationship. Preserve existing orphans, enforce future references.
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_constraint c
 JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=ANY(c.conkey)
 WHERE c.contype='f' AND c.conrelid='public.contact_activities'::regclass
 AND c.confrelid='public.contacts'::regclass AND a.attname='contact_id') THEN
  ALTER TABLE public.contact_activities ADD CONSTRAINT contact_activities_contact_id_fkey
  FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE NOT VALID;
 END IF;
END $$;
NOTIFY pgrst, 'reload schema';
COMMIT;
