-- Repair drifted databases where session_events is missing or lacks columns
-- required by record_campaign_address_outcome / rpc_complete_building_in_session.
-- After deploy, reload PostgREST schema cache if needed (Dashboard API or NOTIFY pgrst, 'reload schema').

-- Some long-lived environments recorded the original session-recording migration
-- even though the table was never created (or was removed later).  ALTER TABLE
-- alone raises 42P01 in those environments, so restore the canonical relation
-- before applying the column repair.  Existing installations are unaffected.
CREATE TABLE IF NOT EXISTS public.session_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  building_id UUID,
  address_id UUID REFERENCES public.campaign_addresses(id) ON DELETE SET NULL,
  event_type TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  event_location GEOGRAPHY(Point, 4326),
  lat DOUBLE PRECISION,
  lon DOUBLE PRECISION,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_session_events_session_id
  ON public.session_events(session_id);
CREATE INDEX IF NOT EXISTS idx_session_events_building_id
  ON public.session_events(building_id);
CREATE INDEX IF NOT EXISTS idx_session_events_created_at
  ON public.session_events(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_session_events_event_type
  ON public.session_events(event_type);

ALTER TABLE public.session_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.session_events
  ADD COLUMN IF NOT EXISTS lat DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS lon DOUBLE PRECISION;

-- event_location used by RPCs; safe if column already exists
ALTER TABLE public.session_events
  ADD COLUMN IF NOT EXISTS event_location geography(Point, 4326);
