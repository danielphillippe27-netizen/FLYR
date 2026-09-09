BEGIN;
ALTER TABLE public.smart_lists ENABLE ROW LEVEL SECURITY;
CREATE POLICY personal_smart_list_access ON public.smart_lists FOR ALL TO authenticated
USING(created_by_user_id=auth.uid()) WITH CHECK(created_by_user_id=auth.uid());
CREATE POLICY personal_smart_list_boundary ON public.smart_lists AS RESTRICTIVE FOR ALL TO authenticated
USING(created_by_user_id=auth.uid()) WITH CHECK(created_by_user_id=auth.uid());
COMMIT;
