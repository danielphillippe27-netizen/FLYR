-- Challenge: phone invites, scoring mode, cover image, leads type

-- Allow leads challenge type
ALTER TABLE public.challenges DROP CONSTRAINT IF EXISTS challenges_type_check;
ALTER TABLE public.challenges
  ADD CONSTRAINT challenges_type_check
  CHECK (type IN ('door_knock', 'flyer_drop', 'follow_up', 'custom', 'leads'));

-- New columns
ALTER TABLE public.challenges
  ADD COLUMN IF NOT EXISTS invited_phone TEXT,
  ADD COLUMN IF NOT EXISTS scoring_mode TEXT NOT NULL DEFAULT 'reach_goal',
  ADD COLUMN IF NOT EXISTS cover_image_path TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'challenges_scoring_mode_check'
      AND conrelid = 'public.challenges'::regclass
  ) THEN
    ALTER TABLE public.challenges
      ADD CONSTRAINT challenges_scoring_mode_check
      CHECK (scoring_mode IN ('reach_goal', 'most_in_timeframe'));
  END IF;
END
$$;

COMMENT ON COLUMN public.challenges.invited_phone IS 'E.164 or digit-only target for private phone invites.';
COMMENT ON COLUMN public.challenges.scoring_mode IS 'reach_goal = first to goal; most_in_timeframe = best count when time ends.';
COMMENT ON COLUMN public.challenges.cover_image_path IS 'Storage path for optional challenge cover image.';

CREATE OR REPLACE FUNCTION public.normalize_challenge_phone(p TEXT)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
AS $$
  SELECT NULLIF(regexp_replace(COALESCE(p, ''), '\D', '', 'g'), '');
$$;

DROP FUNCTION IF EXISTS public.validate_challenge_invite(TEXT);

CREATE OR REPLACE FUNCTION public.validate_challenge_invite(p_token TEXT)
RETURNS TABLE (
  valid BOOLEAN,
  challenge_id UUID,
  title TEXT,
  description TEXT,
  creator_name TEXT,
  invited_email TEXT,
  invited_phone TEXT,
  visibility TEXT,
  type TEXT,
  goal_count INTEGER,
  time_limit_hours INTEGER,
  scoring_mode TEXT,
  cover_image_path TEXT,
  expires_at TIMESTAMPTZ,
  already_joined BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    TRUE AS valid,
    c.id,
    c.title,
    c.description,
    c.creator_name,
    c.invited_email,
    c.invited_phone,
    c.visibility,
    c.type,
    c.goal_count,
    c.time_limit_hours,
    c.scoring_mode,
    c.cover_image_path,
    c.expires_at,
    (c.participant_id IS NOT NULL) AS already_joined
  FROM public.challenges c
  WHERE c.invite_token = NULLIF(trim(p_token), '')
    AND c.status = 'active'
    AND (
      c.expires_at IS NULL
      OR c.expires_at > now()
      OR c.participant_id IS NULL
    )
  LIMIT 1;
END;
$$;

DROP FUNCTION IF EXISTS public.accept_challenge_invite(TEXT, TEXT, TEXT, INTEGER);

DROP FUNCTION IF EXISTS public.accept_challenge_invite(TEXT, TEXT, TEXT, INTEGER);

CREATE OR REPLACE FUNCTION public.accept_challenge_invite(
  p_token TEXT,
  p_participant_name TEXT DEFAULT NULL,
  p_participant_email TEXT DEFAULT NULL,
  p_participant_phone TEXT DEFAULT NULL,
  p_baseline_count INTEGER DEFAULT 0
)
RETURNS public.challenges
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_challenge public.challenges%ROWTYPE;
  v_email TEXT := lower(trim(COALESCE(p_participant_email, '')));
  v_phone TEXT := public.normalize_challenge_phone(p_participant_phone);
  v_invited_phone TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  SELECT *
  INTO v_challenge
  FROM public.challenges
  WHERE invite_token = NULLIF(trim(p_token), '')
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Challenge invite not found.';
  END IF;

  v_invited_phone := public.normalize_challenge_phone(v_challenge.invited_phone);

  IF v_challenge.status <> 'active' THEN
    RAISE EXCEPTION 'This challenge is no longer active.';
  END IF;

  IF v_challenge.creator_id = v_uid THEN
    RAISE EXCEPTION 'You cannot accept your own challenge.';
  END IF;

  IF v_challenge.participant_id IS NOT NULL THEN
    IF v_challenge.participant_id = v_uid THEN
      RETURN v_challenge;
    END IF;

    RAISE EXCEPTION 'This challenge has already been accepted.';
  END IF;

  IF v_invited_phone IS NOT NULL THEN
    IF v_phone IS NULL OR v_phone <> v_invited_phone THEN
      RAISE EXCEPTION 'This invite was sent to a different phone number.';
    END IF;
  ELSIF v_challenge.invited_email IS NOT NULL
     AND lower(trim(v_challenge.invited_email)) <> v_email THEN
    RAISE EXCEPTION 'This invite was sent to a different email address.';
  END IF;

  UPDATE public.challenges
  SET participant_id = v_uid,
      participant_name = NULLIF(trim(COALESCE(p_participant_name, '')), ''),
      accepted_at = now(),
      baseline_count = GREATEST(COALESCE(p_baseline_count, 0), 0),
      progress_count = 0,
      expires_at = CASE
        WHEN v_challenge.time_limit_hours IS NULL THEN v_challenge.expires_at
        ELSE now() + make_interval(hours => v_challenge.time_limit_hours)
      END
  WHERE id = v_challenge.id
  RETURNING * INTO v_challenge;

  RETURN v_challenge;
END;
$$;

GRANT EXECUTE ON FUNCTION public.validate_challenge_invite(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.accept_challenge_invite(TEXT, TEXT, TEXT, TEXT, INTEGER) TO authenticated;
