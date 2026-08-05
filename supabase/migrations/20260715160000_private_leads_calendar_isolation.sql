-- Leads, contacts, their activities, and calendar events are user-owned.
-- workspace_id/campaign_id remain useful context but never grant access.

ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "workspace members can manage contacts" ON public.contacts;
DROP POLICY IF EXISTS "workspace members or campaign collaborators can manage contacts" ON public.contacts;
DROP POLICY IF EXISTS "contacts_select_own" ON public.contacts;
DROP POLICY IF EXISTS "contacts_insert_own" ON public.contacts;
DROP POLICY IF EXISTS "contacts_update_own" ON public.contacts;
DROP POLICY IF EXISTS "contacts_delete_own" ON public.contacts;
CREATE POLICY "contacts_select_own" ON public.contacts FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "contacts_insert_own" ON public.contacts FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "contacts_update_own" ON public.contacts FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "contacts_delete_own" ON public.contacts FOR DELETE TO authenticated USING (user_id = auth.uid());

ALTER TABLE public.field_leads ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "field_leads_select_own" ON public.field_leads;
DROP POLICY IF EXISTS "field_leads_insert_own" ON public.field_leads;
DROP POLICY IF EXISTS "field_leads_update_own" ON public.field_leads;
DROP POLICY IF EXISTS "field_leads_delete_own" ON public.field_leads;
CREATE POLICY "field_leads_select_own" ON public.field_leads FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "field_leads_insert_own" ON public.field_leads FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "field_leads_update_own" ON public.field_leads FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "field_leads_delete_own" ON public.field_leads FOR DELETE TO authenticated USING (user_id = auth.uid());

ALTER TABLE public.contact_activities ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "contact_activities_select_own" ON public.contact_activities;
DROP POLICY IF EXISTS "contact_activities_insert_own" ON public.contact_activities;
DROP POLICY IF EXISTS "contact_activities_update_own" ON public.contact_activities;
DROP POLICY IF EXISTS "contact_activities_delete_own" ON public.contact_activities;
CREATE POLICY "contact_activities_select_own" ON public.contact_activities FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM public.contacts c WHERE c.id = contact_id AND c.user_id = auth.uid()));
CREATE POLICY "contact_activities_insert_own" ON public.contact_activities FOR INSERT TO authenticated
WITH CHECK (EXISTS (SELECT 1 FROM public.contacts c WHERE c.id = contact_id AND c.user_id = auth.uid()));
CREATE POLICY "contact_activities_update_own" ON public.contact_activities FOR UPDATE TO authenticated
USING (EXISTS (SELECT 1 FROM public.contacts c WHERE c.id = contact_id AND c.user_id = auth.uid()))
WITH CHECK (EXISTS (SELECT 1 FROM public.contacts c WHERE c.id = contact_id AND c.user_id = auth.uid()));
CREATE POLICY "contact_activities_delete_own" ON public.contact_activities FOR DELETE TO authenticated
USING (EXISTS (SELECT 1 FROM public.contacts c WHERE c.id = contact_id AND c.user_id = auth.uid()));

ALTER TABLE public.calendar_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "calendar_events_select_own" ON public.calendar_events;
DROP POLICY IF EXISTS "calendar_events_insert_own" ON public.calendar_events;
DROP POLICY IF EXISTS "calendar_events_update_own" ON public.calendar_events;
DROP POLICY IF EXISTS "calendar_events_delete_own" ON public.calendar_events;
DROP POLICY IF EXISTS "Calendar events are readable by owner or workspace members" ON public.calendar_events;
DROP POLICY IF EXISTS "Calendar events are insertable by owner or workspace members" ON public.calendar_events;
DROP POLICY IF EXISTS "Calendar events are updatable by owner or workspace members" ON public.calendar_events;
DROP POLICY IF EXISTS "Calendar events are deletable by owner or workspace members" ON public.calendar_events;
CREATE POLICY "calendar_events_select_own" ON public.calendar_events FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "calendar_events_insert_own" ON public.calendar_events FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "calendar_events_update_own" ON public.calendar_events FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "calendar_events_delete_own" ON public.calendar_events FOR DELETE TO authenticated USING (user_id = auth.uid());
