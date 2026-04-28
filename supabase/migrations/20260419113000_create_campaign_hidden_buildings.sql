CREATE TABLE IF NOT EXISTS public.campaign_hidden_buildings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id UUID NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
    public_building_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_campaign_hidden_building UNIQUE (campaign_id, public_building_id)
);

CREATE INDEX IF NOT EXISTS idx_campaign_hidden_buildings_campaign_id
    ON public.campaign_hidden_buildings(campaign_id);

CREATE INDEX IF NOT EXISTS idx_campaign_hidden_buildings_public_building_id
    ON public.campaign_hidden_buildings(public_building_id);

ALTER TABLE public.campaign_hidden_buildings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "campaign_hidden_buildings_select_owner_or_member" ON public.campaign_hidden_buildings;
CREATE POLICY "campaign_hidden_buildings_select_owner_or_member"
    ON public.campaign_hidden_buildings
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
            WHERE c.id = campaign_hidden_buildings.campaign_id
              AND (
                  c.owner_id = auth.uid()
                  OR wm.user_id IS NOT NULL
                  OR w.owner_id = auth.uid()
              )
        )
    );

CREATE POLICY "campaign_hidden_buildings_insert_owner_or_member"
    ON public.campaign_hidden_buildings
    FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.campaigns c
            LEFT JOIN public.workspace_members wm
                ON wm.workspace_id = c.workspace_id
               AND wm.user_id = auth.uid()
            LEFT JOIN public.workspaces w
                ON w.id = c.workspace_id
            WHERE c.id = campaign_hidden_buildings.campaign_id
              AND (
                  c.owner_id = auth.uid()
                  OR wm.user_id IS NOT NULL
                  OR w.owner_id = auth.uid()
              )
        )
    );

CREATE POLICY "campaign_hidden_buildings_delete_owner_or_member"
    ON public.campaign_hidden_buildings
    FOR DELETE
    USING (
        EXISTS (
            SELECT 1
            FROM public.campaigns c
            LEFT JOIN public.workspace_members wm
                ON wm.workspace_id = c.workspace_id
               AND wm.user_id = auth.uid()
            LEFT JOIN public.workspaces w
                ON w.id = c.workspace_id
            WHERE c.id = campaign_hidden_buildings.campaign_id
              AND (
                  c.owner_id = auth.uid()
                  OR wm.user_id IS NOT NULL
                  OR w.owner_id = auth.uid()
              )
        )
    );

GRANT SELECT, INSERT, DELETE ON public.campaign_hidden_buildings TO authenticated;

COMMENT ON TABLE public.campaign_hidden_buildings IS 'Campaign-scoped building suppressions used to hide deleted buildings from RPC and snapshot-backed map payloads.';
COMMENT ON COLUMN public.campaign_hidden_buildings.public_building_id IS 'Normalized public building identifier (prefer gers_id, fallback buildings.id / feature id).';
