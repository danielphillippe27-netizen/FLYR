-- Allow workspace members to read campaign_snapshots and building_units for campaigns in their workspace.
-- Without this, only campaign owner could read; GET /api/campaigns/[id]/buildings (when using user JWT) would see no snapshot for workspace members.

BEGIN;

-- campaign_snapshots: allow workspace members to SELECT
DROP POLICY IF EXISTS "Users can view snapshots for their campaigns" ON public.campaign_snapshots;
CREATE POLICY "Users can view snapshots for their campaigns"
    ON public.campaign_snapshots
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.campaigns c
            WHERE c.id = campaign_snapshots.campaign_id
            AND (
                c.owner_id = auth.uid()
                OR (c.workspace_id IS NOT NULL AND public.is_workspace_member(c.workspace_id))
            )
        )
    );

-- building_units: allow workspace members to SELECT
DROP POLICY IF EXISTS "Users can view building_units for their campaigns" ON public.building_units;
CREATE POLICY "Users can view building_units for their campaigns"
    ON public.building_units
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.campaigns c
            WHERE c.id = building_units.campaign_id
            AND (
                c.owner_id = auth.uid()
                OR (c.workspace_id IS NOT NULL AND public.is_workspace_member(c.workspace_id))
            )
        )
    );

COMMIT;
