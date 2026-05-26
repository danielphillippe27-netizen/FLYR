BEGIN;

UPDATE public.campaigns
SET map_mode = 'hybrid'
WHERE map_mode IS DISTINCT FROM 'hybrid';

DO $$
DECLARE
  constraint_record RECORD;
BEGIN
  FOR constraint_record IN
    SELECT con.conname
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
    WHERE nsp.nspname = 'public'
      AND rel.relname = 'campaigns'
      AND con.contype = 'c'
      AND pg_get_constraintdef(con.oid) LIKE '%map_mode%'
  LOOP
    EXECUTE format('ALTER TABLE public.campaigns DROP CONSTRAINT IF EXISTS %I', constraint_record.conname);
  END LOOP;
END $$;

ALTER TABLE public.campaigns
  ADD CONSTRAINT campaigns_map_mode_check
  CHECK (map_mode = 'hybrid');

COMMENT ON COLUMN public.campaigns.map_mode IS
'Campaign map presentation mode. FLYR currently supports one mode: hybrid.';

COMMIT;
