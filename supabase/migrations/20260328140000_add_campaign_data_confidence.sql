BEGIN;

ALTER TABLE public.campaigns
    ADD COLUMN IF NOT EXISTS data_confidence_score DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS data_confidence_label TEXT CHECK (data_confidence_label IN ('low', 'medium', 'high')),
    ADD COLUMN IF NOT EXISTS data_confidence_reason TEXT,
    ADD COLUMN IF NOT EXISTS data_confidence_summary JSONB,
    ADD COLUMN IF NOT EXISTS data_confidence_updated_at TIMESTAMPTZ;

COMMENT ON COLUMN public.campaigns.data_confidence_score IS 'Campaign-level data confidence score from 0.0 to 1.0, computed after provisioning.';
COMMENT ON COLUMN public.campaigns.data_confidence_label IS 'Coarse campaign-level confidence bucket: low, medium, or high.';
COMMENT ON COLUMN public.campaigns.data_confidence_reason IS 'Short human-readable explanation of why the campaign received its confidence label.';
COMMENT ON COLUMN public.campaigns.data_confidence_summary IS 'Structured confidence ingredients and metrics used to score the campaign.';
COMMENT ON COLUMN public.campaigns.data_confidence_updated_at IS 'Timestamp of the most recent confidence computation for this campaign.';

COMMIT;
