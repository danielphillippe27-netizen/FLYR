BEGIN;
-- These security-definer writers must not bypass the API's booking validation
-- or allow anonymous callers to choose another user's social account identity.
DO $$
DECLARE fn regprocedure; signature text;
BEGIN
 FOREACH signature IN ARRAY ARRAY[
  'public.create_sales_booking_hold(uuid,timestamptz,timestamptz,text,text,text,text,text)',
  'public.claim_due_company_research_jobs(integer)',
  'public.claim_due_social_posts(integer)',
  'public.claim_due_social_targets(integer)',
  'public.claim_due_sales_automation_executions(integer)'
 ] LOOP
 fn := to_regprocedure(signature);
 IF fn IS NOT NULL THEN
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', fn);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', fn);
 END IF;
 END LOOP;
 fn := to_regprocedure('public.ensure_social_workspace(uuid,text)');
 IF fn IS NOT NULL THEN
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', fn);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', fn);
 END IF;
END $$;
COMMIT;
