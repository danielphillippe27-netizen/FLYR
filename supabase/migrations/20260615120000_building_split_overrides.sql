BEGIN;

CREATE TABLE IF NOT EXISTS public.building_split_overrides (
  campaign_id UUID NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
  parent_building_id TEXT NOT NULL,
  split_axis_mode TEXT NOT NULL DEFAULT 'auto'
    CHECK (split_axis_mode IN ('auto', 'long', 'short')),
  reverse_order BOOLEAN NOT NULL DEFAULT FALSE,
  manual_angle_degrees DOUBLE PRECISION,
  updated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (campaign_id, parent_building_id)
);

CREATE INDEX IF NOT EXISTS idx_building_split_overrides_campaign
  ON public.building_split_overrides(campaign_id);

ALTER TABLE public.building_split_overrides ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "building_split_overrides_select_owner_or_member"
  ON public.building_split_overrides;
CREATE POLICY "building_split_overrides_select_owner_or_member"
  ON public.building_split_overrides
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.campaigns c
      LEFT JOIN public.workspace_members wm
        ON wm.workspace_id = c.workspace_id
        AND wm.user_id = auth.uid()
      LEFT JOIN public.workspaces w
        ON w.id = c.workspace_id
      WHERE c.id = building_split_overrides.campaign_id
        AND (
          c.owner_id = auth.uid()
          OR wm.user_id IS NOT NULL
          OR w.owner_id = auth.uid()
        )
    )
  );

DROP POLICY IF EXISTS "building_split_overrides_service_manage"
  ON public.building_split_overrides;
CREATE POLICY "building_split_overrides_service_manage"
  ON public.building_split_overrides
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

GRANT SELECT ON public.building_split_overrides TO authenticated;
GRANT ALL ON public.building_split_overrides TO service_role;

CREATE OR REPLACE FUNCTION public.touch_building_split_overrides_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS touch_building_split_overrides_updated_at
  ON public.building_split_overrides;
CREATE TRIGGER touch_building_split_overrides_updated_at
  BEFORE UPDATE ON public.building_split_overrides
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_building_split_overrides_updated_at();

DO $$
BEGIN
  IF to_regclass('public.building_split_overrides') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS invalidate_polished_buildings_on_split_overrides
      ON public.building_split_overrides;
    CREATE TRIGGER invalidate_polished_buildings_on_split_overrides
      AFTER INSERT OR UPDATE OR DELETE ON public.building_split_overrides
      FOR EACH ROW
      EXECUTE FUNCTION public.invalidate_campaign_polished_building_features();
  END IF;
END $$;

COMMENT ON TABLE public.building_split_overrides IS
'Per-campaign manual townhouse split controls. The splitter reads these values when rebuilding building_units.';
COMMENT ON COLUMN public.building_split_overrides.split_axis_mode IS
'auto uses the street-facing edge heuristic; long and short force the split axis to the parent footprint long or short edge.';
COMMENT ON COLUMN public.building_split_overrides.reverse_order IS
'When true, reverses which linked address receives each generated unit slice.';

COMMIT;
