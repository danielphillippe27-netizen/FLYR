-- Repair list loading when shared call-history enrichment is not installed.
BEGIN;

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
