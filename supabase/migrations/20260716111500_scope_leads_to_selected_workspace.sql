-- Leads are shared inside one workspace, while clients must filter by the
-- currently selected workspace_id. Rows without a workspace remain private.

DROP POLICY IF EXISTS "contacts_select_own" ON public.contacts;
DROP POLICY IF EXISTS "contacts_insert_own" ON public.contacts;
DROP POLICY IF EXISTS "contacts_update_own" ON public.contacts;
DROP POLICY IF EXISTS "contacts_delete_own" ON public.contacts;
DROP POLICY IF EXISTS "workspace members or campaign collaborators can manage contacts" ON public.contacts;
CREATE POLICY "workspace members can select contacts" ON public.contacts FOR SELECT TO authenticated
USING (
    (workspace_id IS NOT NULL AND public.is_workspace_member(workspace_id))
    OR (workspace_id IS NULL AND user_id = auth.uid())
);
CREATE POLICY "workspace members can insert contacts" ON public.contacts FOR INSERT TO authenticated
WITH CHECK (
    user_id = auth.uid()
    AND (workspace_id IS NULL OR public.is_workspace_member(workspace_id))
);
CREATE POLICY "workspace members can update contacts" ON public.contacts FOR UPDATE TO authenticated
USING (
    (workspace_id IS NOT NULL AND public.is_workspace_member(workspace_id))
    OR (workspace_id IS NULL AND user_id = auth.uid())
)
WITH CHECK (
    (workspace_id IS NOT NULL AND public.is_workspace_member(workspace_id))
    OR (workspace_id IS NULL AND user_id = auth.uid())
);
CREATE POLICY "workspace members can delete contacts" ON public.contacts FOR DELETE TO authenticated
USING (
    (workspace_id IS NOT NULL AND public.is_workspace_member(workspace_id))
    OR (workspace_id IS NULL AND user_id = auth.uid())
);

DROP POLICY IF EXISTS "field_leads_select_own" ON public.field_leads;
DROP POLICY IF EXISTS "field_leads_insert_own" ON public.field_leads;
DROP POLICY IF EXISTS "field_leads_update_own" ON public.field_leads;
DROP POLICY IF EXISTS "field_leads_delete_own" ON public.field_leads;
CREATE POLICY "workspace members can select field leads" ON public.field_leads FOR SELECT TO authenticated
USING (
    (workspace_id IS NOT NULL AND public.is_workspace_member(workspace_id))
    OR (workspace_id IS NULL AND user_id = auth.uid())
);
CREATE POLICY "workspace members can insert field leads" ON public.field_leads FOR INSERT TO authenticated
WITH CHECK (
    user_id = auth.uid()
    AND (workspace_id IS NULL OR public.is_workspace_member(workspace_id))
);
CREATE POLICY "workspace members can update field leads" ON public.field_leads FOR UPDATE TO authenticated
USING (
    (workspace_id IS NOT NULL AND public.is_workspace_member(workspace_id))
    OR (workspace_id IS NULL AND user_id = auth.uid())
)
WITH CHECK (
    (workspace_id IS NOT NULL AND public.is_workspace_member(workspace_id))
    OR (workspace_id IS NULL AND user_id = auth.uid())
);
CREATE POLICY "workspace members can delete field leads" ON public.field_leads FOR DELETE TO authenticated
USING (
    (workspace_id IS NOT NULL AND public.is_workspace_member(workspace_id))
    OR (workspace_id IS NULL AND user_id = auth.uid())
);

DROP POLICY IF EXISTS "contact_activities_select_own" ON public.contact_activities;
DROP POLICY IF EXISTS "contact_activities_insert_own" ON public.contact_activities;
DROP POLICY IF EXISTS "contact_activities_update_own" ON public.contact_activities;
DROP POLICY IF EXISTS "contact_activities_delete_own" ON public.contact_activities;
CREATE POLICY "workspace members can select contact activities" ON public.contact_activities FOR SELECT TO authenticated
USING (EXISTS (
    SELECT 1 FROM public.contacts c
    WHERE c.id = contact_id
      AND ((c.workspace_id IS NOT NULL AND public.is_workspace_member(c.workspace_id))
        OR (c.workspace_id IS NULL AND c.user_id = auth.uid()))
));
CREATE POLICY "workspace members can insert contact activities" ON public.contact_activities FOR INSERT TO authenticated
WITH CHECK (EXISTS (
    SELECT 1 FROM public.contacts c
    WHERE c.id = contact_id
      AND ((c.workspace_id IS NOT NULL AND public.is_workspace_member(c.workspace_id))
        OR (c.workspace_id IS NULL AND c.user_id = auth.uid()))
));
CREATE POLICY "workspace members can update contact activities" ON public.contact_activities FOR UPDATE TO authenticated
USING (EXISTS (
    SELECT 1 FROM public.contacts c
    WHERE c.id = contact_id
      AND ((c.workspace_id IS NOT NULL AND public.is_workspace_member(c.workspace_id))
        OR (c.workspace_id IS NULL AND c.user_id = auth.uid()))
))
WITH CHECK (EXISTS (
    SELECT 1 FROM public.contacts c
    WHERE c.id = contact_id
      AND ((c.workspace_id IS NOT NULL AND public.is_workspace_member(c.workspace_id))
        OR (c.workspace_id IS NULL AND c.user_id = auth.uid()))
));
CREATE POLICY "workspace members can delete contact activities" ON public.contact_activities FOR DELETE TO authenticated
USING (EXISTS (
    SELECT 1 FROM public.contacts c
    WHERE c.id = contact_id
      AND ((c.workspace_id IS NOT NULL AND public.is_workspace_member(c.workspace_id))
        OR (c.workspace_id IS NULL AND c.user_id = auth.uid()))
));
