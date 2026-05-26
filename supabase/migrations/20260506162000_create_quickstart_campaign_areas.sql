-- Track every area added to a reusable Quick Start campaign.
-- The campaign itself remains the durable map; this table records the user/location
-- history that produced the accumulated set of campaign_addresses.

BEGIN;

CREATE TABLE IF NOT EXISTS public.quickstart_campaign_areas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id UUID NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
    workspace_id UUID REFERENCES public.workspaces(id) ON DELETE SET NULL,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    center_lat DOUBLE PRECISION,
    center_lng DOUBLE PRECISION,
    radius_m INTEGER,
    area_boundary JSONB NOT NULL,
    area_hash TEXT NOT NULL,
    addresses_before INTEGER NOT NULL DEFAULT 0,
    addresses_after INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (campaign_id, area_hash)
);

CREATE INDEX IF NOT EXISTS idx_quickstart_campaign_areas_campaign
    ON public.quickstart_campaign_areas(campaign_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_quickstart_campaign_areas_workspace
    ON public.quickstart_campaign_areas(workspace_id, created_at DESC);

ALTER TABLE public.quickstart_campaign_areas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "quickstart_areas_owner_or_workspace_member_select" ON public.quickstart_campaign_areas;
CREATE POLICY "quickstart_areas_owner_or_workspace_member_select"
    ON public.quickstart_campaign_areas
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.campaigns c
            WHERE c.id = quickstart_campaign_areas.campaign_id
              AND (
                c.owner_id = auth.uid()
                OR (
                    c.workspace_id IS NOT NULL
                    AND EXISTS (
                        SELECT 1
                        FROM public.workspace_members wm
                        WHERE wm.workspace_id = c.workspace_id
                          AND wm.user_id = auth.uid()
                    )
                )
              )
        )
    );

DROP POLICY IF EXISTS "quickstart_areas_owner_or_workspace_admin_insert" ON public.quickstart_campaign_areas;
CREATE POLICY "quickstart_areas_owner_or_workspace_admin_insert"
    ON public.quickstart_campaign_areas
    FOR INSERT
    TO authenticated
    WITH CHECK (
        created_by = auth.uid()
        AND EXISTS (
            SELECT 1
            FROM public.campaigns c
            WHERE c.id = quickstart_campaign_areas.campaign_id
              AND (
                c.owner_id = auth.uid()
                OR (
                    c.workspace_id IS NOT NULL
                    AND EXISTS (
                        SELECT 1
                        FROM public.workspace_members wm
                        WHERE wm.workspace_id = c.workspace_id
                          AND wm.user_id = auth.uid()
                          AND wm.role IN ('owner', 'admin')
                    )
                )
              )
        )
    );

DROP POLICY IF EXISTS "quickstart_areas_owner_or_workspace_admin_update" ON public.quickstart_campaign_areas;
CREATE POLICY "quickstart_areas_owner_or_workspace_admin_update"
    ON public.quickstart_campaign_areas
    FOR UPDATE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.campaigns c
            WHERE c.id = quickstart_campaign_areas.campaign_id
              AND (
                c.owner_id = auth.uid()
                OR (
                    c.workspace_id IS NOT NULL
                    AND EXISTS (
                        SELECT 1
                        FROM public.workspace_members wm
                        WHERE wm.workspace_id = c.workspace_id
                          AND wm.user_id = auth.uid()
                          AND wm.role IN ('owner', 'admin')
                    )
                )
              )
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.campaigns c
            WHERE c.id = quickstart_campaign_areas.campaign_id
              AND (
                c.owner_id = auth.uid()
                OR (
                    c.workspace_id IS NOT NULL
                    AND EXISTS (
                        SELECT 1
                        FROM public.workspace_members wm
                        WHERE wm.workspace_id = c.workspace_id
                          AND wm.user_id = auth.uid()
                          AND wm.role IN ('owner', 'admin')
                    )
                )
              )
        )
    );

GRANT SELECT, INSERT, UPDATE ON public.quickstart_campaign_areas TO authenticated;
GRANT ALL ON public.quickstart_campaign_areas TO service_role;

COMMENT ON TABLE public.quickstart_campaign_areas IS
'History of geographic areas appended to a reusable Quick Start campaign.';

COMMIT;
