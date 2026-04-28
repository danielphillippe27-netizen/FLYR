BEGIN;

CREATE OR REPLACE FUNCTION public.sync_workspace_scoped_record_from_campaign()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_campaign_workspace_id uuid;
BEGIN
    IF NEW.campaign_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT c.workspace_id
    INTO v_campaign_workspace_id
    FROM public.campaigns c
    WHERE c.id = NEW.campaign_id;

    NEW.workspace_id := v_campaign_workspace_id;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.sync_workspace_scoped_record_from_campaign()
    IS 'Aligns workspace-scoped lead/contact rows to the campaign workspace when a campaign_id is present.';

DROP TRIGGER IF EXISTS sync_contacts_workspace_from_campaign ON public.contacts;
CREATE TRIGGER sync_contacts_workspace_from_campaign
    BEFORE INSERT OR UPDATE OF campaign_id, workspace_id
    ON public.contacts
    FOR EACH ROW
    EXECUTE FUNCTION public.sync_workspace_scoped_record_from_campaign();

DROP TRIGGER IF EXISTS sync_field_leads_workspace_from_campaign ON public.field_leads;
CREATE TRIGGER sync_field_leads_workspace_from_campaign
    BEFORE INSERT OR UPDATE OF campaign_id, workspace_id
    ON public.field_leads
    FOR EACH ROW
    EXECUTE FUNCTION public.sync_workspace_scoped_record_from_campaign();

UPDATE public.contacts ct
SET workspace_id = c.workspace_id
FROM public.campaigns c
WHERE ct.campaign_id = c.id
  AND ct.workspace_id IS DISTINCT FROM c.workspace_id;

UPDATE public.field_leads fl
SET workspace_id = c.workspace_id
FROM public.campaigns c
WHERE fl.campaign_id = c.id
  AND fl.workspace_id IS DISTINCT FROM c.workspace_id;

DROP POLICY IF EXISTS "workspace members can manage contacts" ON public.contacts;
CREATE POLICY "workspace members or campaign collaborators can manage contacts"
    ON public.contacts
    FOR ALL
    TO authenticated
    USING (
        (contacts.campaign_id IS NOT NULL AND public.is_campaign_member(contacts.campaign_id))
        OR (contacts.workspace_id IS NOT NULL AND public.is_workspace_member(contacts.workspace_id))
        OR (contacts.workspace_id IS NULL AND contacts.user_id = auth.uid())
    )
    WITH CHECK (
        (contacts.campaign_id IS NOT NULL AND public.is_campaign_member(contacts.campaign_id))
        OR (contacts.workspace_id IS NOT NULL AND public.is_workspace_member(contacts.workspace_id))
        OR (contacts.workspace_id IS NULL AND contacts.user_id = auth.uid())
    );

DROP POLICY IF EXISTS "contact_activities_select_own" ON public.contact_activities;
CREATE POLICY "contact_activities_select_own"
    ON public.contact_activities
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.contacts
            WHERE contacts.id = contact_activities.contact_id
              AND (
                  (contacts.campaign_id IS NOT NULL AND public.is_campaign_member(contacts.campaign_id))
                  OR (contacts.workspace_id IS NOT NULL AND public.is_workspace_member(contacts.workspace_id))
                  OR (contacts.workspace_id IS NULL AND contacts.user_id = auth.uid())
              )
        )
    );

DROP POLICY IF EXISTS "contact_activities_insert_own" ON public.contact_activities;
CREATE POLICY "contact_activities_insert_own"
    ON public.contact_activities
    FOR INSERT
    TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.contacts
            WHERE contacts.id = contact_activities.contact_id
              AND (
                  (contacts.campaign_id IS NOT NULL AND public.is_campaign_member(contacts.campaign_id))
                  OR (contacts.workspace_id IS NOT NULL AND public.is_workspace_member(contacts.workspace_id))
                  OR (contacts.workspace_id IS NULL AND contacts.user_id = auth.uid())
              )
        )
    );

DROP POLICY IF EXISTS "contact_activities_update_own" ON public.contact_activities;
CREATE POLICY "contact_activities_update_own"
    ON public.contact_activities
    FOR UPDATE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.contacts
            WHERE contacts.id = contact_activities.contact_id
              AND (
                  (contacts.campaign_id IS NOT NULL AND public.is_campaign_member(contacts.campaign_id))
                  OR (contacts.workspace_id IS NOT NULL AND public.is_workspace_member(contacts.workspace_id))
                  OR (contacts.workspace_id IS NULL AND contacts.user_id = auth.uid())
              )
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.contacts
            WHERE contacts.id = contact_activities.contact_id
              AND (
                  (contacts.campaign_id IS NOT NULL AND public.is_campaign_member(contacts.campaign_id))
                  OR (contacts.workspace_id IS NOT NULL AND public.is_workspace_member(contacts.workspace_id))
                  OR (contacts.workspace_id IS NULL AND contacts.user_id = auth.uid())
              )
        )
    );

DROP POLICY IF EXISTS "contact_activities_delete_own" ON public.contact_activities;
CREATE POLICY "contact_activities_delete_own"
    ON public.contact_activities
    FOR DELETE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.contacts
            WHERE contacts.id = contact_activities.contact_id
              AND (
                  (contacts.campaign_id IS NOT NULL AND public.is_campaign_member(contacts.campaign_id))
                  OR (contacts.workspace_id IS NOT NULL AND public.is_workspace_member(contacts.workspace_id))
                  OR (contacts.workspace_id IS NULL AND contacts.user_id = auth.uid())
              )
        )
    );

DROP POLICY IF EXISTS "field_leads_select_own" ON public.field_leads;
CREATE POLICY "field_leads_select_own"
    ON public.field_leads
    FOR SELECT
    TO authenticated
    USING (
        auth.uid() = user_id
        OR (campaign_id IS NOT NULL AND public.is_campaign_member(campaign_id))
        OR (workspace_id IS NOT NULL AND public.is_workspace_member(workspace_id))
    );

DROP POLICY IF EXISTS "field_leads_insert_own" ON public.field_leads;
CREATE POLICY "field_leads_insert_own"
    ON public.field_leads
    FOR INSERT
    TO authenticated
    WITH CHECK (
        auth.uid() = user_id
        OR (campaign_id IS NOT NULL AND public.is_campaign_member(campaign_id))
        OR (workspace_id IS NOT NULL AND public.is_workspace_member(workspace_id))
    );

DROP POLICY IF EXISTS "field_leads_update_own" ON public.field_leads;
CREATE POLICY "field_leads_update_own"
    ON public.field_leads
    FOR UPDATE
    TO authenticated
    USING (
        auth.uid() = user_id
        OR (campaign_id IS NOT NULL AND public.is_campaign_member(campaign_id))
        OR (workspace_id IS NOT NULL AND public.is_workspace_member(workspace_id))
    )
    WITH CHECK (
        auth.uid() = user_id
        OR (campaign_id IS NOT NULL AND public.is_campaign_member(campaign_id))
        OR (workspace_id IS NOT NULL AND public.is_workspace_member(workspace_id))
    );

DROP POLICY IF EXISTS "field_leads_delete_own" ON public.field_leads;
CREATE POLICY "field_leads_delete_own"
    ON public.field_leads
    FOR DELETE
    TO authenticated
    USING (
        auth.uid() = user_id
        OR (campaign_id IS NOT NULL AND public.is_campaign_member(campaign_id))
        OR (workspace_id IS NOT NULL AND public.is_workspace_member(workspace_id))
    );

DROP POLICY IF EXISTS "campaigns_select_campaign_members" ON public.campaigns;
CREATE POLICY "campaigns_select_campaign_members"
    ON public.campaigns
    FOR SELECT
    TO authenticated
    USING (public.is_campaign_member(id));

DROP POLICY IF EXISTS "sessions_select_campaign_members" ON public.sessions;
CREATE POLICY "sessions_select_campaign_members"
    ON public.sessions
    FOR SELECT
    TO authenticated
    USING (
        auth.uid() = user_id
        OR (campaign_id IS NOT NULL AND public.is_campaign_member(campaign_id))
        OR (workspace_id IS NOT NULL AND public.is_workspace_member(workspace_id))
    );

COMMIT;
