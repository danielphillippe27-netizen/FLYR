-- Add idempotency keys for offline outbox replays that can otherwise create duplicate events
-- when the app crashes after the remote write but before marking the local outbox row synced.

ALTER TABLE public.building_touches
ADD COLUMN IF NOT EXISTS client_mutation_id text;

CREATE UNIQUE INDEX IF NOT EXISTS idx_building_touches_client_mutation_id
ON public.building_touches(client_mutation_id)
WHERE client_mutation_id IS NOT NULL AND client_mutation_id <> '';

CREATE UNIQUE INDEX IF NOT EXISTS idx_session_events_client_mutation_id
ON public.session_events((metadata ->> 'client_mutation_id'))
WHERE metadata ? 'client_mutation_id'
  AND COALESCE(metadata ->> 'client_mutation_id', '') <> '';
