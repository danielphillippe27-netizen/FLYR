BEGIN;

-- Final cleanup pass after migrating farm execution from phase-scoped rows
-- to touch-based cycles. This keeps partially migrated environments from
-- retaining obsolete functions/columns and documents the canonical schema.

DROP FUNCTION IF EXISTS public.rpc_get_campaign_full_features_for_farm_phase(uuid, uuid);
DROP FUNCTION IF EXISTS public.rpc_get_campaign_address_status_rows_for_farm_phase(uuid, uuid);

DROP INDEX IF EXISTS idx_sessions_farm_phase_id;
ALTER TABLE public.sessions
    DROP COLUMN IF EXISTS farm_phase_id;

DROP INDEX IF EXISTS idx_farm_touches_phase_id;
ALTER TABLE public.farm_touches
    DROP COLUMN IF EXISTS phase_id;

DROP TABLE IF EXISTS public.farm_phases;

COMMENT ON COLUMN public.farm_touches.cycle_number IS
'Canonical farm cycle identifier. Cycles are derived from touch planning/execution, not farm_phases rows.';

COMMENT ON FUNCTION public.rpc_get_campaign_address_status_rows_for_farm_cycle(uuid, integer) IS
'Returns the latest per-address campaign status rows scoped to a farm cycle_number.';

COMMENT ON FUNCTION public.record_farm_address_outcome(uuid, uuid, uuid, uuid, text, text, timestamptz) IS
'Canonical farm house outcome write path. Persists per-touch farm house state and updates farm_addresses history.';

COMMIT;
