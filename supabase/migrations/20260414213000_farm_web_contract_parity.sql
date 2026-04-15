BEGIN;

ALTER TABLE public.farms
    ADD COLUMN IF NOT EXISTS workspace_id uuid REFERENCES public.workspaces(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS description text,
    ADD COLUMN IF NOT EXISTS is_active boolean DEFAULT true,
    ADD COLUMN IF NOT EXISTS touches_per_interval integer,
    ADD COLUMN IF NOT EXISTS touches_interval text DEFAULT 'month',
    ADD COLUMN IF NOT EXISTS goal_type text,
    ADD COLUMN IF NOT EXISTS goal_target integer,
    ADD COLUMN IF NOT EXISTS cycle_completion_window_days integer,
    ADD COLUMN IF NOT EXISTS touch_types text[] DEFAULT ARRAY[]::text[],
    ADD COLUMN IF NOT EXISTS annual_budget_cents integer,
    ADD COLUMN IF NOT EXISTS home_limit integer DEFAULT 5000,
    ADD COLUMN IF NOT EXISTS address_count integer DEFAULT 0,
    ADD COLUMN IF NOT EXISTS last_generated_at timestamptz;

UPDATE public.farms
SET
    workspace_id = COALESCE(workspace_id, public.primary_workspace_id(owner_id)),
    is_active = COALESCE(is_active, true),
    touches_per_interval = COALESCE(touches_per_interval, frequency),
    touches_interval = COALESCE(touches_interval, 'month'),
    goal_type = COALESCE(goal_type, 'touches_per_cycle'),
    goal_target = COALESCE(goal_target, touches_per_interval, frequency),
    touch_types = COALESCE(touch_types, ARRAY[]::text[]),
    home_limit = COALESCE(home_limit, 5000),
    address_count = COALESCE(address_count, 0)
WHERE workspace_id IS NULL
   OR is_active IS NULL
   OR touches_per_interval IS NULL
   OR touches_interval IS NULL
   OR goal_type IS NULL
   OR goal_target IS NULL
   OR touch_types IS NULL
   OR home_limit IS NULL
   OR address_count IS NULL;

CREATE INDEX IF NOT EXISTS idx_farms_workspace_id ON public.farms(workspace_id);

DROP POLICY IF EXISTS "Users can read their own farms" ON public.farms;
DROP POLICY IF EXISTS "Users can insert their own farms" ON public.farms;
DROP POLICY IF EXISTS "Users can update their own farms" ON public.farms;
DROP POLICY IF EXISTS "Users can delete their own farms" ON public.farms;
DROP POLICY IF EXISTS "farms_workspace_members" ON public.farms;

CREATE POLICY "farms_workspace_members"
    ON public.farms
    FOR ALL
    TO authenticated
    USING (
        owner_id = auth.uid()
        OR (workspace_id IS NOT NULL AND public.is_workspace_member(workspace_id))
    )
    WITH CHECK (
        owner_id = auth.uid()
        OR (workspace_id IS NOT NULL AND public.is_workspace_member(workspace_id))
    );

DROP VIEW IF EXISTS public.farms_with_geojson;

CREATE VIEW public.farms_with_geojson AS
SELECT
    id,
    owner_id,
    workspace_id,
    name,
    description,
    CASE
        WHEN polygon IS NOT NULL THEN ST_AsGeoJSON(polygon)::text
        ELSE NULL
    END AS polygon,
    start_date,
    end_date,
    frequency,
    created_at,
    updated_at,
    area_label,
    is_active,
    touches_per_interval,
    touches_interval,
    goal_type,
    goal_target,
    cycle_completion_window_days,
    touch_types,
    annual_budget_cents,
    home_limit,
    address_count,
    last_generated_at
FROM public.farms;

ALTER VIEW public.farms_with_geojson SET (security_invoker = true);
GRANT SELECT ON public.farms_with_geojson TO authenticated;

COMMENT ON VIEW public.farms_with_geojson IS 'Workspace-aware farm view with polygon converted to GeoJSON and web contract columns.';

COMMIT;
