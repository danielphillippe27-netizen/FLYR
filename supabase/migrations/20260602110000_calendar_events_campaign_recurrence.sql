ALTER TABLE public.calendar_events
    ADD COLUMN IF NOT EXISTS campaign_id UUID REFERENCES public.campaigns(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS campaign_name TEXT,
    ADD COLUMN IF NOT EXISTS recurrence_rule TEXT NOT NULL DEFAULT 'none',
    ADD COLUMN IF NOT EXISTS recurrence_until TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_calendar_events_campaign_id
    ON public.calendar_events(campaign_id)
    WHERE campaign_id IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_calendar_events_recurrence
    ON public.calendar_events(recurrence_rule, recurrence_until)
    WHERE recurrence_rule <> 'none' AND deleted_at IS NULL;
