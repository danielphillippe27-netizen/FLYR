BEGIN;

ALTER TABLE public.campaigns
  ADD COLUMN IF NOT EXISTS provision_error TEXT,
  ADD COLUMN IF NOT EXISTS provision_message TEXT;

COMMENT ON COLUMN public.campaigns.provision_error IS
'Last backend provisioning error message, truncated for display/debugging.';

COMMENT ON COLUMN public.campaigns.provision_message IS
'Human-readable provisioning status or failure message.';

NOTIFY pgrst, 'reload schema';

COMMIT;
