-- Add optional tags column to campaigns (e.g. for filtering/labels)
ALTER TABLE public.campaigns
    ADD COLUMN IF NOT EXISTS tags TEXT DEFAULT NULL;

COMMENT ON COLUMN public.campaigns.tags IS 'Optional comma-separated or free-form tags for the campaign';
