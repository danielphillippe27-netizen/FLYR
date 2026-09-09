BEGIN;
CREATE OR REPLACE FUNCTION public.claim_next_dialer_session_lead(
  p_session_id uuid, p_workspace_id uuid, p_user_id uuid
) RETURNS public.dialer_session_leads
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_row public.dialer_session_leads;
BEGIN
  IF p_user_id IS NULL OR (auth.role() IS DISTINCT FROM 'service_role' AND auth.uid() IS DISTINCT FROM p_user_id) THEN
    RAISE EXCEPTION 'Dialer user identity is not authorized.' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dialer_sessions s WHERE s.id = p_session_id
    AND s.workspace_id = p_workspace_id AND s.user_id = p_user_id) THEN
    RAISE EXCEPTION 'Dialer session not found.' USING ERRCODE = '42501';
  END IF;
  WITH next_row AS (
    SELECT dsl.id FROM public.dialer_session_leads dsl
    WHERE dsl.session_id = p_session_id AND dsl.workspace_id = p_workspace_id
      AND dsl.status = 'pending'
      AND EXISTS (SELECT 1 FROM public.contacts c WHERE c.id = dsl.contact_id
        AND c.workspace_id = p_workspace_id AND c.user_id = p_user_id)
    ORDER BY dsl.position ASC LIMIT 1 FOR UPDATE SKIP LOCKED
  )
  UPDATE public.dialer_session_leads dsl SET status = 'claimed',
    claimed_by_user_id = p_user_id, claimed_at = now(), updated_at = now()
  FROM next_row WHERE dsl.id = next_row.id RETURNING dsl.* INTO v_row;
  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.claim_next_dialer_session_lead(uuid,uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_next_dialer_session_lead(uuid,uuid,uuid) TO authenticated, service_role;
COMMIT;
