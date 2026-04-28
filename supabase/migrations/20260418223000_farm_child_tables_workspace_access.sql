BEGIN;

-- Bring farm child-table access in line with the workspace-aware farms policy.

DROP POLICY IF EXISTS "Users can read their own farm touches" ON public.farm_touches;
DROP POLICY IF EXISTS "Users can insert their own farm touches" ON public.farm_touches;
DROP POLICY IF EXISTS "Users can update their own farm touches" ON public.farm_touches;
DROP POLICY IF EXISTS "Users can delete their own farm touches" ON public.farm_touches;

CREATE POLICY "farm_touches_owner_or_workspace_member"
    ON public.farm_touches
    FOR ALL
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.farms f
            WHERE f.id = farm_touches.farm_id
              AND (
                  f.owner_id = auth.uid()
                  OR (f.workspace_id IS NOT NULL AND public.is_workspace_member(f.workspace_id))
              )
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.farms f
            WHERE f.id = farm_touches.farm_id
              AND (
                  f.owner_id = auth.uid()
                  OR (f.workspace_id IS NOT NULL AND public.is_workspace_member(f.workspace_id))
              )
        )
    );

DROP POLICY IF EXISTS "Users can read their own farm leads" ON public.farm_leads;
DROP POLICY IF EXISTS "Users can insert their own farm leads" ON public.farm_leads;
DROP POLICY IF EXISTS "Users can update their own farm leads" ON public.farm_leads;
DROP POLICY IF EXISTS "Users can delete their own farm leads" ON public.farm_leads;

CREATE POLICY "farm_leads_owner_or_workspace_member"
    ON public.farm_leads
    FOR ALL
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.farms f
            WHERE f.id = farm_leads.farm_id
              AND (
                  f.owner_id = auth.uid()
                  OR (f.workspace_id IS NOT NULL AND public.is_workspace_member(f.workspace_id))
              )
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.farms f
            WHERE f.id = farm_leads.farm_id
              AND (
                  f.owner_id = auth.uid()
                  OR (f.workspace_id IS NOT NULL AND public.is_workspace_member(f.workspace_id))
              )
        )
    );

DROP POLICY IF EXISTS "Users can read their own farm phases" ON public.farm_phases;
DROP POLICY IF EXISTS "Users can insert their own farm phases" ON public.farm_phases;
DROP POLICY IF EXISTS "Users can update their own farm phases" ON public.farm_phases;
DROP POLICY IF EXISTS "Users can delete their own farm phases" ON public.farm_phases;

CREATE POLICY "farm_phases_owner_or_workspace_member"
    ON public.farm_phases
    FOR ALL
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.farms f
            WHERE f.id = farm_phases.farm_id
              AND (
                  f.owner_id = auth.uid()
                  OR (f.workspace_id IS NOT NULL AND public.is_workspace_member(f.workspace_id))
              )
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.farms f
            WHERE f.id = farm_phases.farm_id
              AND (
                  f.owner_id = auth.uid()
                  OR (f.workspace_id IS NOT NULL AND public.is_workspace_member(f.workspace_id))
              )
        )
    );

COMMIT;
