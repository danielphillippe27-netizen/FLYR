ALTER TABLE public.campaign_addresses
  ADD COLUMN IF NOT EXISTS country TEXT;

COMMENT ON COLUMN public.campaign_addresses.country IS
'Country name or code captured from manual/reverse-geocoded campaign addresses.';

NOTIFY pgrst, 'reload schema';
