BEGIN;

-- Keep the database aligned with the pipeline API/detail contract. These two
-- fields were added to the TypeScript model and API select list without a
-- corresponding database migration, which made every pipeline read fail.
ALTER TABLE public.sales_leads
  ADD COLUMN IF NOT EXISTS objection text,
  ADD COLUMN IF NOT EXISTS last_product_active_at timestamptz;

COMMENT ON COLUMN public.sales_leads.objection IS
  'The current objection or blocker recorded for this sales opportunity.';
COMMENT ON COLUMN public.sales_leads.last_product_active_at IS
  'Latest observed product activity for a matched signup workspace.';

-- New workspaces created after the original Sales Pro migration did not get
-- pipeline stages. Keep the defaults here and install a trigger for future
-- workspaces so the board always has a usable starting workflow.
CREATE OR REPLACE FUNCTION public.seed_default_sales_pipeline_stages()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.sales_pipeline_stages (
    workspace_id,
    stage_key,
    name,
    color,
    position,
    terminal_kind
  )
  VALUES
    (NEW.id, 'new', 'New Lead', '#64748B', 10, NULL),
    (NEW.id, 'contacted', 'Contacted', '#2563EB', 20, NULL),
    (NEW.id, 'conversation', 'Conversation', '#7C3AED', 30, NULL),
    (NEW.id, 'meeting_booked', 'Meeting Booked', '#0891B2', 40, NULL),
    (NEW.id, 'proposal', 'Proposal', '#D97706', 50, NULL),
    (NEW.id, 'won', 'Won', '#16A34A', 60, 'won'),
    (NEW.id, 'lost', 'Lost', '#DC2626', 70, 'lost')
  ON CONFLICT DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS workspaces_seed_sales_pipeline_stages ON public.workspaces;
CREATE TRIGGER workspaces_seed_sales_pipeline_stages
AFTER INSERT ON public.workspaces
FOR EACH ROW EXECUTE FUNCTION public.seed_default_sales_pipeline_stages();

-- Repair workspaces that were created after the original one-time seed.
INSERT INTO public.sales_pipeline_stages (
  workspace_id,
  stage_key,
  name,
  color,
  position,
  terminal_kind
)
SELECT
  workspace.id,
  seed.stage_key,
  seed.name,
  seed.color,
  seed.position,
  seed.terminal_kind
FROM public.workspaces AS workspace
CROSS JOIN (VALUES
  ('new', 'New Lead', '#64748B', 10, NULL::text),
  ('contacted', 'Contacted', '#2563EB', 20, NULL::text),
  ('conversation', 'Conversation', '#7C3AED', 30, NULL::text),
  ('meeting_booked', 'Meeting Booked', '#0891B2', 40, NULL::text),
  ('proposal', 'Proposal', '#D97706', 50, NULL::text),
  ('won', 'Won', '#16A34A', 60, 'won'),
  ('lost', 'Lost', '#DC2626', 70, 'lost')
) AS seed(stage_key, name, color, position, terminal_kind)
ON CONFLICT DO NOTHING;

-- Leads created after the original backfill could have a null custom stage and
-- therefore disappeared from the board. Put them in the matching legacy stage,
-- falling back to the first active stage in their workspace.
WITH lead_stage AS (
  SELECT
    lead.id AS lead_id,
    stage.id AS stage_id
  FROM public.sales_leads AS lead
  LEFT JOIN LATERAL (
    SELECT candidate.id
    FROM public.sales_pipeline_stages AS candidate
    WHERE candidate.workspace_id = lead.workspace_id
      AND candidate.is_archived = false
    ORDER BY
      CASE
        WHEN candidate.stage_key = CASE
          WHEN lead.pipeline_stage = 'new_lead' THEN 'new'
          WHEN lead.pipeline_stage IN ('attempting_contact', 'nurture') THEN 'contacted'
          WHEN lead.pipeline_stage = 'connected' THEN 'conversation'
          WHEN lead.pipeline_stage IN ('demo_sent', 'trial_sent', 'trial_active', 'closing') THEN 'proposal'
          WHEN lead.pipeline_stage = 'won' THEN 'won'
          WHEN lead.pipeline_stage = 'lost' THEN 'lost'
          ELSE 'new'
        END THEN 0
        ELSE 1
      END,
      candidate.position,
      candidate.id
    LIMIT 1
  ) AS stage ON true
  WHERE lead.pipeline_stage_id IS NULL
)
UPDATE public.sales_leads AS lead
SET pipeline_stage_id = lead_stage.stage_id
FROM lead_stage
WHERE lead.id = lead_stage.lead_id
  AND lead_stage.stage_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.assign_default_sales_pipeline_stage()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  preferred_stage_key text;
BEGIN
  IF NEW.pipeline_stage_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  preferred_stage_key := CASE
    WHEN NEW.pipeline_stage = 'new_lead' THEN 'new'
    WHEN NEW.pipeline_stage IN ('attempting_contact', 'nurture') THEN 'contacted'
    WHEN NEW.pipeline_stage = 'connected' THEN 'conversation'
    WHEN NEW.pipeline_stage IN ('demo_sent', 'trial_sent', 'trial_active', 'closing') THEN 'proposal'
    WHEN NEW.pipeline_stage = 'won' THEN 'won'
    WHEN NEW.pipeline_stage = 'lost' THEN 'lost'
    ELSE 'new'
  END;

  SELECT stage.id
  INTO NEW.pipeline_stage_id
  FROM public.sales_pipeline_stages AS stage
  WHERE stage.workspace_id = NEW.workspace_id
    AND stage.is_archived = false
  ORDER BY
    CASE WHEN stage.stage_key = preferred_stage_key THEN 0 ELSE 1 END,
    stage.position,
    stage.id
  LIMIT 1;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sales_leads_assign_default_pipeline_stage ON public.sales_leads;
CREATE TRIGGER sales_leads_assign_default_pipeline_stage
BEFORE INSERT OR UPDATE OF workspace_id, pipeline_stage, pipeline_stage_id
ON public.sales_leads
FOR EACH ROW EXECUTE FUNCTION public.assign_default_sales_pipeline_stage();

COMMIT;
