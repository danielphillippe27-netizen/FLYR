-- =====================================================
-- Add Voice Note (Zero-Typing) columns to campaign_addresses
-- AI-derived data and raw transcript from voice notes
-- =====================================================

ALTER TABLE public.campaign_addresses
ADD COLUMN IF NOT EXISTS contact_name TEXT,
ADD COLUMN IF NOT EXISTS lead_status TEXT DEFAULT 'new',
ADD COLUMN IF NOT EXISTS product_interest TEXT,
ADD COLUMN IF NOT EXISTS follow_up_date TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS raw_transcript TEXT,
ADD COLUMN IF NOT EXISTS ai_summary TEXT;

COMMENT ON COLUMN public.campaign_addresses.contact_name IS 'Contact name extracted from voice note (e.g. door-knock follow-up)';
COMMENT ON COLUMN public.campaign_addresses.lead_status IS 'AI-derived lead status: new, interested, not_home, not_interested, follow_up';
COMMENT ON COLUMN public.campaign_addresses.product_interest IS 'Product/service interest from voice note';
COMMENT ON COLUMN public.campaign_addresses.follow_up_date IS 'Suggested follow-up date from voice note (ISO)';
COMMENT ON COLUMN public.campaign_addresses.raw_transcript IS 'Raw Whisper transcript of the voice note';
COMMENT ON COLUMN public.campaign_addresses.ai_summary IS 'GPT summary/extraction from the voice note';

NOTIFY pgrst, 'reload schema';
