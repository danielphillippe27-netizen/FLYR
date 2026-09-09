BEGIN;
-- Security-definer predicate avoids recursive policies between links and members.
-- It exposes only whether the current authenticated user may access a link.
CREATE FUNCTION public.personal_booking_link_access(link_id uuid, writing boolean DEFAULT false)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
 SELECT EXISTS (SELECT 1 FROM public.sales_booking_links l
 JOIN public.workspace_members wm ON wm.workspace_id=l.workspace_id AND wm.user_id=auth.uid()
 WHERE l.id=link_id AND (l.owner_user_id=auth.uid() OR (l.mode='round_robin' AND (
 wm.role IN ('owner','admin') OR (NOT writing AND EXISTS (
 SELECT 1 FROM public.sales_booking_link_members m WHERE m.booking_link_id=l.id AND m.user_id=auth.uid() AND m.is_active))))));
$$;
REVOKE ALL ON FUNCTION public.personal_booking_link_access(uuid,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.personal_booking_link_access(uuid,boolean) TO authenticated,service_role;
ALTER TABLE public.sales_booking_links ENABLE ROW LEVEL SECURITY;
CREATE POLICY personal_booking_link_read ON public.sales_booking_links AS RESTRICTIVE FOR SELECT TO authenticated USING (public.personal_booking_link_access(id));
CREATE POLICY personal_booking_link_insert ON public.sales_booking_links AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (
 owner_user_id=auth.uid() OR (mode='round_robin' AND EXISTS (SELECT 1 FROM public.workspace_members wm WHERE wm.workspace_id=sales_booking_links.workspace_id AND wm.user_id=auth.uid() AND wm.role IN ('owner','admin'))));
CREATE POLICY personal_booking_link_update ON public.sales_booking_links AS RESTRICTIVE FOR UPDATE TO authenticated
USING (public.personal_booking_link_access(id,true)) WITH CHECK (
 owner_user_id=auth.uid() OR (mode='round_robin' AND EXISTS (SELECT 1 FROM public.workspace_members wm WHERE wm.workspace_id=sales_booking_links.workspace_id AND wm.user_id=auth.uid() AND wm.role IN ('owner','admin'))));
CREATE POLICY personal_booking_link_delete ON public.sales_booking_links AS RESTRICTIVE FOR DELETE TO authenticated USING (public.personal_booking_link_access(id,true));
ALTER TABLE public.sales_booking_link_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY personal_booking_member_read ON public.sales_booking_link_members AS RESTRICTIVE FOR SELECT TO authenticated USING (public.personal_booking_link_access(booking_link_id));
CREATE POLICY personal_booking_member_insert ON public.sales_booking_link_members AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (
 public.personal_booking_link_access(booking_link_id,true) AND EXISTS (
 SELECT 1 FROM public.sales_booking_links l JOIN public.workspace_members wm ON wm.workspace_id=l.workspace_id
 WHERE l.id=booking_link_id AND wm.user_id=sales_booking_link_members.user_id AND (l.mode='round_robin' OR l.owner_user_id=sales_booking_link_members.user_id)));
CREATE POLICY personal_booking_member_update ON public.sales_booking_link_members AS RESTRICTIVE FOR UPDATE TO authenticated
USING (public.personal_booking_link_access(booking_link_id,true)) WITH CHECK (
 public.personal_booking_link_access(booking_link_id,true) AND EXISTS (
 SELECT 1 FROM public.sales_booking_links l JOIN public.workspace_members wm ON wm.workspace_id=l.workspace_id
 WHERE l.id=booking_link_id AND wm.user_id=sales_booking_link_members.user_id AND (l.mode='round_robin' OR l.owner_user_id=sales_booking_link_members.user_id)));
CREATE POLICY personal_booking_member_delete ON public.sales_booking_link_members AS RESTRICTIVE FOR DELETE TO authenticated USING (public.personal_booking_link_access(booking_link_id,true));
ALTER TABLE public.sales_availability_rules ENABLE ROW LEVEL SECURITY;
CREATE POLICY personal_availability_rules ON public.sales_availability_rules AS RESTRICTIVE FOR ALL TO authenticated USING (user_id=auth.uid()) WITH CHECK (user_id=auth.uid());
ALTER TABLE public.sales_availability_overrides ENABLE ROW LEVEL SECURITY;
CREATE POLICY personal_availability_overrides ON public.sales_availability_overrides AS RESTRICTIVE FOR ALL TO authenticated USING (user_id=auth.uid()) WITH CHECK (user_id=auth.uid());
COMMIT;
