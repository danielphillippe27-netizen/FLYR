-- Shared attempt history is keyed by workspace + canonical phone, across lead IDs.
BEGIN;

CREATE INDEX IF NOT EXISTS dialer_calls_shared_phone_history
  ON public.dialer_calls (workspace_id, to_number_e164, created_at DESC)
  WHERE direction = 'outbound';

CREATE OR REPLACE FUNCTION public.guard_duplicate_lead_call()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  previous public.dialer_calls%ROWTYPE;
  caller_name text;
BEGIN
  -- Historical/provider event ingestion must remain possible. Guard call requests.
  IF NEW.direction IS DISTINCT FROM 'outbound' OR NEW.status IS DISTINCT FROM 'pending'
     OR NEW.call_request_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.to_number_e164 IS NULL OR NEW.to_number_e164 !~ '^\+[1-9][0-9]{7,14}$' THEN
    RAISE EXCEPTION 'A canonical phone number is required before dialing.' USING ERRCODE = '22023';
  END IF;

  -- Transaction-scoped lock serializes simultaneous attempts, even for different
  -- lead records, lists, users and devices. A failed insert releases the lock.
  PERFORM pg_advisory_xact_lock(hashtextextended(NEW.workspace_id::text || ':' || NEW.to_number_e164, 0));
  SELECT * INTO previous FROM public.dialer_calls
    WHERE workspace_id = NEW.workspace_id AND to_number_e164 = NEW.to_number_e164
      AND direction = 'outbound'
    ORDER BY created_at DESC, id DESC LIMIT 1;

  IF FOUND AND previous.created_at > clock_timestamp() - interval '24 hours' THEN
    -- An explicit double dial is only valid for the same rep after no connection.
    IF NOT (NEW.user_id IS NOT NULL AND NEW.user_id = previous.user_id
      AND coalesce(NEW.status_payload->>'doubleDial', 'false') = 'true'
      AND coalesce(previous.status_payload->>'doubleDial', 'false') <> 'true'
      AND previous.status IN ('no-answer', 'busy', 'failed', 'canceled', 'cancelled')) THEN
      SELECT left(coalesce(nullif(raw_user_meta_data->>'full_name', ''),
                           nullif(raw_user_meta_data->>'name', ''), 'A teammate'), 100)
        INTO caller_name FROM auth.users WHERE id = previous.user_id;
      RAISE EXCEPTION 'This number was recently called.' USING ERRCODE = 'PDC01',
        DETAIL = jsonb_build_object('last_called_at', previous.created_at,
          'last_called_by', coalesce(caller_name, 'A teammate'),
          'last_called_by_user_id', previous.user_id,
          'retry_after', previous.created_at + interval '24 hours')::text;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.guard_duplicate_lead_call() FROM PUBLIC;
DROP TRIGGER IF EXISTS guard_duplicate_lead_call ON public.dialer_calls;
CREATE TRIGGER guard_duplicate_lead_call BEFORE INSERT ON public.dialer_calls
  FOR EACH ROW EXECUTE FUNCTION public.guard_duplicate_lead_call();

-- Only the authenticated API's service client may read cross-owner summaries.
-- Do not expose recordings, notes, email addresses or other reps' lead records.
CREATE OR REPLACE FUNCTION public.shared_lead_call_history(p_workspace_id uuid, p_phones text[])
RETURNS TABLE(phone text, last_called_at timestamptz, last_called_by text, last_called_by_user_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT requested.phone, latest.created_at,
    left(coalesce(nullif(u.raw_user_meta_data->>'full_name', ''),
                  nullif(u.raw_user_meta_data->>'name', ''), 'A teammate'), 100), latest.user_id
  FROM (SELECT DISTINCT unnest(p_phones) AS phone) requested
  CROSS JOIN LATERAL (
    SELECT c.created_at, c.user_id FROM public.dialer_calls c
      WHERE c.workspace_id = p_workspace_id AND c.to_number_e164 = requested.phone
        AND c.direction = 'outbound'
      ORDER BY c.created_at DESC, c.id DESC LIMIT 1
  ) latest
  LEFT JOIN auth.users u ON u.id = latest.user_id;
$$;
REVOKE ALL ON FUNCTION public.shared_lead_call_history(uuid, text[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.shared_lead_call_history(uuid, text[]) TO service_role;
NOTIFY pgrst, 'reload schema';
COMMIT;
