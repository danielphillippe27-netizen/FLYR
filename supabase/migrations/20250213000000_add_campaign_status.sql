-- Add status column to campaigns for Active / Completed / Archived buckets.
-- Matches CampaignStatus in app: draft, active, completed, paused, archived.

ALTER TABLE public.campaigns
    ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'active', 'completed', 'paused', 'archived'));

COMMENT ON COLUMN public.campaigns.status IS 'Campaign lifecycle: draft, active, completed, paused, archived. Drives list buckets (Active, Completed, Archived).';

CREATE INDEX IF NOT EXISTS idx_campaigns_status ON public.campaigns(status);
