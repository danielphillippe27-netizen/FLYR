-- Repair drifted databases where session_events exists but lacks columns
-- required by record_campaign_address_outcome / rpc_complete_building_in_session.
-- After deploy, reload PostgREST schema cache if needed (Dashboard API or NOTIFY pgrst, 'reload schema').

ALTER TABLE public.session_events
  ADD COLUMN IF NOT EXISTS lat DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS lon DOUBLE PRECISION;

-- event_location used by RPCs; safe if column already exists
ALTER TABLE public.session_events
  ADD COLUMN IF NOT EXISTS event_location geography(Point, 4326);
