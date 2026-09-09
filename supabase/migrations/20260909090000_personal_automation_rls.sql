BEGIN;
ALTER TABLE public.sales_automation_definitions ENABLE ROW LEVEL SECURITY;
CREATE POLICY personal_automation_creator ON public.sales_automation_definitions AS RESTRICTIVE FOR ALL TO authenticated
USING (created_by_user_id=auth.uid()) WITH CHECK (created_by_user_id=auth.uid());
ALTER TABLE public.sales_automation_versions ENABLE ROW LEVEL SECURITY;
CREATE POLICY personal_automation_version ON public.sales_automation_versions AS RESTRICTIVE FOR ALL TO authenticated
USING (EXISTS (SELECT 1 FROM public.sales_automation_definitions d WHERE d.id=sales_automation_versions.automation_id AND d.created_by_user_id=auth.uid()))
WITH CHECK (EXISTS (SELECT 1 FROM public.sales_automation_definitions d WHERE d.id=sales_automation_versions.automation_id AND d.created_by_user_id=auth.uid()));
ALTER TABLE public.sales_sequence_enrollments ENABLE ROW LEVEL SECURITY;
CREATE POLICY personal_automation_enrollment ON public.sales_sequence_enrollments AS RESTRICTIVE FOR ALL TO authenticated
USING (owner_user_id=auth.uid()) WITH CHECK (owner_user_id=auth.uid()
 AND EXISTS (SELECT 1 FROM public.sales_automation_definitions d WHERE d.id=sales_sequence_enrollments.automation_id AND d.workspace_id=sales_sequence_enrollments.workspace_id AND d.created_by_user_id=auth.uid()));
ALTER TABLE public.sales_automation_executions ENABLE ROW LEVEL SECURITY;
CREATE POLICY personal_automation_execution ON public.sales_automation_executions AS RESTRICTIVE FOR ALL TO authenticated
USING (EXISTS (SELECT 1 FROM public.sales_sequence_enrollments e WHERE e.id=sales_automation_executions.enrollment_id AND e.workspace_id=sales_automation_executions.workspace_id AND e.owner_user_id=auth.uid()))
WITH CHECK (EXISTS (SELECT 1 FROM public.sales_sequence_enrollments e WHERE e.id=sales_automation_executions.enrollment_id AND e.workspace_id=sales_automation_executions.workspace_id AND e.owner_user_id=auth.uid()));
-- Only the trusted scheduler may claim execution jobs; direct callers must not
-- bypass the personal policies through this SECURITY DEFINER function.
REVOKE ALL ON FUNCTION public.claim_due_sales_automation_executions(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_due_sales_automation_executions(integer) TO service_role;
COMMIT;
