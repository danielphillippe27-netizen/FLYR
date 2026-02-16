-- Fix campaigns_status_check so archive works.
-- Some environments may have had a stricter constraint that omitted 'archived' (and possibly 'paused').
-- Ensures status IN ('draft', 'active', 'completed', 'paused', 'archived').

ALTER TABLE public.campaigns
    DROP CONSTRAINT IF EXISTS campaigns_status_check;

ALTER TABLE public.campaigns
    ADD CONSTRAINT campaigns_status_check
    CHECK (status IN ('draft', 'active', 'completed', 'paused', 'archived'));
