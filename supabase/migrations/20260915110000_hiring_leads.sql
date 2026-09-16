-- Public hiring signals are shared by active salespeople. Review state is private
-- to the authenticated salesperson and all access is through authenticated APIs.
BEGIN;

CREATE TABLE public.hiring_leads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fingerprint text NOT NULL UNIQUE,
  country text NOT NULL CHECK (country IN ('CA', 'US')),
  company text NOT NULL,
  title text NOT NULL,
  location text NOT NULL,
  category text,
  first_seen_at timestamptz NOT NULL DEFAULT now(),
  latest_posting_seen_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX hiring_leads_recent ON public.hiring_leads(latest_posting_seen_at DESC, id DESC);
CREATE INDEX hiring_leads_country_recent ON public.hiring_leads(country, latest_posting_seen_at DESC);

CREATE TABLE public.hiring_postings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id uuid NOT NULL REFERENCES public.hiring_leads ON DELETE CASCADE,
  provider text NOT NULL,
  external_id text NOT NULL,
  country text NOT NULL CHECK (country IN ('CA', 'US')),
  url text NOT NULL CHECK (url ~ '^https?://'),
  posted_at timestamptz NOT NULL,
  first_seen_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  salary_min numeric,
  salary_max numeric,
  currency text,
  company_url text,
  contact_name text,
  contact_email text,
  contact_phone text,
  source_url text,
  source_discovered_at timestamptz,
  closed_at timestamptz,
  hiring_team jsonb NOT NULL DEFAULT '[]'::jsonb,
  UNIQUE(provider, country, external_id)
);
CREATE INDEX hiring_postings_lead ON public.hiring_postings(lead_id);

CREATE TABLE public.hiring_closed_postings (
  external_id text PRIMARY KEY,
  closed_at timestamptz NOT NULL
);
ALTER TABLE public.hiring_closed_postings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.hiring_closed_postings FROM anon, authenticated;
GRANT ALL ON public.hiring_closed_postings TO service_role;

CREATE TABLE public.hiring_lead_reviews (
  user_id uuid NOT NULL REFERENCES auth.users ON DELETE CASCADE,
  lead_id uuid NOT NULL REFERENCES public.hiring_leads ON DELETE CASCADE,
  status text NOT NULL CHECK (status IN ('new', 'saved', 'contacted', 'dismissed')),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(user_id, lead_id)
);

CREATE TABLE public.hiring_collection_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL,
  country text NOT NULL CHECK (country IN ('CA', 'US')),
  run_day date NOT NULL,
  status text NOT NULL CHECK (status IN ('running', 'complete', 'partial', 'failed')),
  started_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  fetched integer NOT NULL DEFAULT 0,
  rejected integer NOT NULL DEFAULT 0,
  available integer,
  error_message text,
  UNIQUE(provider, country, run_day)
);

ALTER TABLE public.hiring_leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hiring_postings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hiring_lead_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hiring_collection_runs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.hiring_leads, public.hiring_postings,
  public.hiring_lead_reviews, public.hiring_collection_runs FROM anon, authenticated;
GRANT ALL ON public.hiring_leads, public.hiring_postings,
  public.hiring_lead_reviews, public.hiring_collection_runs TO service_role;

CREATE FUNCTION public.ingest_hiring_postings(p_postings jsonb)
RETURNS integer LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE item jsonb; target_id uuid; inserted_posting_id uuid; handled integer := 0;
BEGIN
  IF jsonb_typeof(p_postings) <> 'array' OR jsonb_array_length(p_postings) > 100 THEN
    RAISE EXCEPTION 'Expected at most 100 postings';
  END IF;
  -- Serialize posting arrivals against closure events, including closure-before-arrival.
  PERFORM pg_advisory_xact_lock(hashtextextended('hiring:' || k.provider || ':' || k.external_id, 0))
    FROM (SELECT DISTINCT value->>'provider' AS provider, value->>'external_id' AS external_id
      FROM jsonb_array_elements(p_postings) ORDER BY 1, 2) k;
  -- Stable lead lock order prevents overlapping batches from deadlocking.
  FOR item IN SELECT value FROM jsonb_array_elements(p_postings)
    ORDER BY value->>'fingerprint', value->>'provider', value->>'external_id'
  LOOP
    INSERT INTO public.hiring_leads(fingerprint, country, company, title, location, category)
    VALUES (item->>'fingerprint', item->>'country', item->>'company', item->>'title', item->>'location', item->>'category')
    ON CONFLICT (fingerprint) DO UPDATE SET last_seen_at = now(),
      category = COALESCE(EXCLUDED.category, hiring_leads.category)
    RETURNING id INTO target_id;

    INSERT INTO public.hiring_postings(lead_id, provider, external_id, country, url, posted_at,
      salary_min, salary_max, currency, company_url, contact_name, contact_email, contact_phone,
      source_url, source_discovered_at, closed_at, hiring_team)
    VALUES (target_id, item->>'provider', item->>'external_id', item->>'country', item->>'url',
      (item->>'posted_at')::timestamptz, (item->>'salary_min')::numeric, (item->>'salary_max')::numeric,
      item->>'currency', item->>'company_url', item->>'contact_name', item->>'contact_email', item->>'contact_phone',
      item->>'source_url', (item->>'source_discovered_at')::timestamptz,
      GREATEST((item->>'closed_at')::timestamptz, (SELECT c.closed_at FROM public.hiring_closed_postings c
        WHERE item->>'provider' = 'theirstack' AND c.external_id = item->>'external_id')),
      COALESCE(item->'hiring_team', '[]'::jsonb))
    ON CONFLICT (provider, country, external_id) DO NOTHING
    RETURNING id INTO inserted_posting_id;
    IF inserted_posting_id IS NOT NULL THEN
      UPDATE public.hiring_leads SET latest_posting_seen_at = now() WHERE id = target_id;
    ELSE
      UPDATE public.hiring_postings SET
        lead_id = target_id, url = item->>'url', posted_at = (item->>'posted_at')::timestamptz,
        last_seen_at = now(), salary_min = (item->>'salary_min')::numeric,
        salary_max = (item->>'salary_max')::numeric, currency = item->>'currency',
        company_url = item->>'company_url', contact_name = item->>'contact_name',
        contact_email = item->>'contact_email', contact_phone = item->>'contact_phone',
        source_url = item->>'source_url', source_discovered_at = (item->>'source_discovered_at')::timestamptz,
        closed_at = GREATEST(hiring_postings.closed_at, (item->>'closed_at')::timestamptz),
        hiring_team = COALESCE(item->'hiring_team', '[]'::jsonb)
      WHERE provider = item->>'provider' AND country = item->>'country' AND external_id = item->>'external_id';
    END IF;
    handled := handled + 1;
  END LOOP;
  RETURN handled;
END;
$$;

CREATE FUNCTION public.close_hiring_posting(p_external_id text, p_closed_at timestamptz)
RETURNS void LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('hiring:theirstack:' || p_external_id, 0));
  INSERT INTO public.hiring_closed_postings(external_id, closed_at) VALUES(p_external_id, p_closed_at)
  ON CONFLICT(external_id) DO UPDATE SET closed_at = GREATEST(hiring_closed_postings.closed_at, EXCLUDED.closed_at);
  UPDATE public.hiring_postings SET closed_at = GREATEST(closed_at, p_closed_at)
    WHERE provider = 'theirstack' AND external_id = p_external_id;
END;
$$;
REVOKE ALL ON FUNCTION public.close_hiring_posting(text,timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.close_hiring_posting(text,timestamptz) TO service_role;

CREATE FUNCTION public.hiring_delivery_summary()
RETURNS jsonb LANGUAGE sql STABLE SET search_path = public, pg_temp AS $$
  SELECT jsonb_build_object('receivedLast24h', count(DISTINCT external_id) FILTER (WHERE first_seen_at >= now()-interval '24 hours'),
    'lastReceivedAt', max(first_seen_at)) FROM public.hiring_postings WHERE provider='theirstack';
$$;
REVOKE ALL ON FUNCTION public.hiring_delivery_summary() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.hiring_delivery_summary() TO service_role;

-- A transaction claims each country/day once; failed or abandoned runs can retry.
CREATE FUNCTION public.claim_hiring_collection(p_country text)
RETURNS uuid LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE claimed uuid;
BEGIN
  INSERT INTO public.hiring_collection_runs(provider, country, run_day, status)
    VALUES ('adzuna', p_country, (now() AT TIME ZONE 'UTC')::date, 'running')
  ON CONFLICT(provider, country, run_day) DO UPDATE SET
    id = gen_random_uuid(), started_at = now(), finished_at = NULL, status = 'running',
    fetched = 0, rejected = 0, available = NULL, error_message = NULL
  WHERE hiring_collection_runs.status = 'failed'
    OR (hiring_collection_runs.status = 'running' AND hiring_collection_runs.started_at < now() - interval '10 minutes')
  RETURNING id INTO claimed;
  RETURN claimed;
END;
$$;

CREATE FUNCTION public.list_hiring_leads(
  p_user_id uuid, p_country text DEFAULT 'all', p_status text DEFAULT 'all',
  p_search text DEFAULT '', p_days integer DEFAULT 7, p_offset integer DEFAULT 0
) RETURNS jsonb LANGUAGE sql STABLE SET search_path = public, pg_temp AS $$
  WITH selected AS (
    SELECT l.*, COALESCE(r.status, 'new') AS status
    FROM public.hiring_leads l
    LEFT JOIN public.hiring_lead_reviews r ON r.lead_id = l.id AND r.user_id = p_user_id
    WHERE (p_country = 'all' OR l.country = p_country)
      AND (p_status = 'all' OR COALESCE(r.status, 'new') = p_status)
      AND l.latest_posting_seen_at >= now() - make_interval(days => LEAST(GREATEST(p_days, 1), 90))
      AND (p_search = '' OR strpos(lower(concat_ws(' ', l.company, l.title, l.location, l.category)), lower(p_search)) > 0)
      AND EXISTS (SELECT 1 FROM public.hiring_postings p WHERE p.lead_id = l.id)
    ORDER BY l.latest_posting_seen_at DESC, l.id DESC
    LIMIT 51 OFFSET LEAST(GREATEST(p_offset, 0), 100000)
  ), rows AS (
    SELECT s.*, (
      SELECT jsonb_agg(to_jsonb(p) - 'lead_id' ORDER BY p.posted_at DESC, p.id)
      FROM public.hiring_postings p WHERE p.lead_id = s.id
    ) AS postings
    FROM selected s ORDER BY s.latest_posting_seen_at DESC, s.id DESC LIMIT 50
  ) SELECT jsonb_build_object(
    'leads', COALESCE((SELECT jsonb_agg(to_jsonb(rows) - 'fingerprint' ORDER BY latest_posting_seen_at DESC, id DESC) FROM rows), '[]'::jsonb),
    'hasMore', (SELECT count(*) > 50 FROM selected)
  );
$$;

REVOKE ALL ON FUNCTION public.ingest_hiring_postings(jsonb), public.claim_hiring_collection(text),
  public.list_hiring_leads(uuid,text,text,text,integer,integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ingest_hiring_postings(jsonb), public.claim_hiring_collection(text),
  public.list_hiring_leads(uuid,text,text,text,integer,integer) TO service_role;
COMMIT;
