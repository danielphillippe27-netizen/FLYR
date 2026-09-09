-- Workspace-wide, source-grounded company research for Sales lists and the dialler.

ALTER TABLE public.sales_companies
  ADD COLUMN IF NOT EXISTS google_place_id text,
  ADD COLUMN IF NOT EXISTS identity_key text;

CREATE UNIQUE INDEX IF NOT EXISTS sales_companies_workspace_google_place_unique
  ON public.sales_companies(workspace_id, google_place_id)
  WHERE google_place_id IS NOT NULL AND google_place_id <> '' AND merged_into_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS sales_companies_workspace_identity_key_idx
  ON public.sales_companies(workspace_id, identity_key)
  WHERE identity_key IS NOT NULL AND identity_key <> '' AND merged_into_id IS NULL;

CREATE TABLE IF NOT EXISTS public.sales_company_research_batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  smart_list_id uuid REFERENCES public.smart_lists(id) ON DELETE SET NULL,
  smart_list_name text,
  requested_by_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  refresh_all boolean NOT NULL DEFAULT false,
  requested_count integer NOT NULL DEFAULT 0 CHECK (requested_count >= 0 AND requested_count <= 100),
  skipped_count integer NOT NULL DEFAULT 0 CHECK (skipped_count >= 0),
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'researching', 'completed', 'partial', 'failed')),
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.sales_company_research (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.sales_companies(id) ON DELETE CASCADE,
  batch_id uuid REFERENCES public.sales_company_research_batches(id) ON DELETE SET NULL,
  requested_by_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  trigger_kind text NOT NULL DEFAULT 'single' CHECK (trigger_kind IN ('single', 'list')),
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'researching', 'completed', 'partial', 'failed')),
  identity_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  result jsonb,
  sources jsonb NOT NULL DEFAULT '[]'::jsonb,
  overall_confidence text CHECK (overall_confidence IN ('high', 'medium', 'low')),
  model text NOT NULL,
  openai_response_id text,
  input_tokens integer,
  output_tokens integer,
  total_tokens integer,
  web_search_calls integer NOT NULL DEFAULT 0 CHECK (web_search_calls >= 0),
  attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  started_at timestamptz,
  completed_at timestamptz,
  expires_at timestamptz,
  error_code text,
  error_message text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS sales_company_research_company_latest_idx
  ON public.sales_company_research(workspace_id, company_id, created_at DESC);

CREATE INDEX IF NOT EXISTS sales_company_research_queue_idx
  ON public.sales_company_research(status, next_attempt_at, created_at)
  WHERE status IN ('queued', 'researching');

CREATE UNIQUE INDEX IF NOT EXISTS sales_company_research_one_active_company_idx
  ON public.sales_company_research(company_id)
  WHERE status IN ('queued', 'researching');

CREATE INDEX IF NOT EXISTS sales_company_research_batch_idx
  ON public.sales_company_research(batch_id, status)
  WHERE batch_id IS NOT NULL;

DROP TRIGGER IF EXISTS sales_company_research_set_updated_at ON public.sales_company_research;
CREATE TRIGGER sales_company_research_set_updated_at
BEFORE UPDATE ON public.sales_company_research
FOR EACH ROW EXECUTE FUNCTION public.sales_pro_set_updated_at();

DROP TRIGGER IF EXISTS sales_company_research_batches_set_updated_at ON public.sales_company_research_batches;
CREATE TRIGGER sales_company_research_batches_set_updated_at
BEFORE UPDATE ON public.sales_company_research_batches
FOR EACH ROW EXECUTE FUNCTION public.sales_pro_set_updated_at();

ALTER TABLE public.sales_company_research ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_company_research_batches ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS sales_company_research_workspace_members_select ON public.sales_company_research;
CREATE POLICY sales_company_research_workspace_members_select
ON public.sales_company_research FOR SELECT
USING (public.sales_workspace_member(workspace_id));

DROP POLICY IF EXISTS sales_company_research_workspace_members_insert ON public.sales_company_research;
CREATE POLICY sales_company_research_workspace_members_insert
ON public.sales_company_research FOR INSERT
WITH CHECK (public.sales_workspace_member(workspace_id) AND requested_by_user_id = auth.uid());

DROP POLICY IF EXISTS sales_company_research_batches_workspace_members_select ON public.sales_company_research_batches;
CREATE POLICY sales_company_research_batches_workspace_members_select
ON public.sales_company_research_batches FOR SELECT
USING (public.sales_workspace_member(workspace_id));

DROP POLICY IF EXISTS sales_company_research_batches_workspace_members_insert ON public.sales_company_research_batches;
CREATE POLICY sales_company_research_batches_workspace_members_insert
ON public.sales_company_research_batches FOR INSERT
WITH CHECK (public.sales_workspace_member(workspace_id) AND requested_by_user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.claim_due_company_research_jobs(batch_size integer DEFAULT 2)
RETURNS SETOF public.sales_company_research
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH due AS (
    SELECT research.id
    FROM public.sales_company_research research
    WHERE research.status = 'queued'
      AND research.next_attempt_at <= now()
      AND research.attempt_count < 3
    ORDER BY research.created_at
    FOR UPDATE SKIP LOCKED
    LIMIT LEAST(GREATEST(batch_size, 1), 2)
  ), claimed AS (
    UPDATE public.sales_company_research research
    SET status = 'researching',
        started_at = COALESCE(research.started_at, now()),
        attempt_count = research.attempt_count + 1,
        error_code = NULL,
        error_message = NULL
    FROM due
    WHERE research.id = due.id
    RETURNING research.*
  )
  SELECT * FROM claimed;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_due_company_research_jobs(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_due_company_research_jobs(integer) TO service_role;
