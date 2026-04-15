-- Expand challenges to support private friend invites and searchable challenge discovery.

ALTER TABLE public.challenges
  ADD COLUMN IF NOT EXISTS visibility TEXT NOT NULL DEFAULT 'private',
  ADD COLUMN IF NOT EXISTS creator_name TEXT,
  ADD COLUMN IF NOT EXISTS participant_name TEXT,
  ADD COLUMN IF NOT EXISTS invited_email TEXT,
  ADD COLUMN IF NOT EXISTS invite_token TEXT,
  ADD COLUMN IF NOT EXISTS baseline_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMPTZ;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'challenges_visibility_check'
      AND conrelid = 'public.challenges'::regclass
  ) THEN
    ALTER TABLE public.challenges
      ADD CONSTRAINT challenges_visibility_check
      CHECK (visibility IN ('private', 'searchable'));
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_challenges_visibility ON public.challenges (visibility);
CREATE UNIQUE INDEX IF NOT EXISTS idx_challenges_invite_token_unique ON public.challenges (invite_token)
  WHERE invite_token IS NOT NULL;

DROP POLICY IF EXISTS "challenges_select_own" ON public.challenges;
CREATE POLICY "challenges_select_own"
  ON public.challenges
  FOR SELECT
  TO authenticated
  USING (
    auth.uid() = creator_id
    OR auth.uid() = participant_id
    OR (visibility = 'searchable' AND participant_id IS NULL)
  );

COMMENT ON COLUMN public.challenges.visibility IS 'Challenge visibility: private invite-only or searchable in the app.';
COMMENT ON COLUMN public.challenges.creator_name IS 'Snapshot of creator display name for challenge cards and invite previews.';
COMMENT ON COLUMN public.challenges.participant_name IS 'Snapshot of participant display name once a challenge is accepted.';
COMMENT ON COLUMN public.challenges.invited_email IS 'Optional invite target for private challenges.';
COMMENT ON COLUMN public.challenges.invite_token IS 'Share token used for private and shared challenge invite links.';
COMMENT ON COLUMN public.challenges.baseline_count IS 'Tracked metric baseline captured when the active participant starts the challenge.';
COMMENT ON COLUMN public.challenges.accepted_at IS 'When the participant accepted or joined the challenge.';

DROP FUNCTION IF EXISTS public.validate_challenge_invite(TEXT);

CREATE OR REPLACE FUNCTION public.validate_challenge_invite(p_token TEXT)
RETURNS TABLE (
  valid BOOLEAN,
  challenge_id UUID,
  title TEXT,
  description TEXT,
  creator_name TEXT,
  invited_email TEXT,
  visibility TEXT,
  type TEXT,
  goal_count INTEGER,
  time_limit_hours INTEGER,
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
    c.visibility,
    c.type,
    c.goal_count,
    c.time_limit_hours,
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

CREATE OR REPLACE FUNCTION public.accept_challenge_invite(
  p_token TEXT,
  p_participant_name TEXT DEFAULT NULL,
  p_participant_email TEXT DEFAULT NULL,
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

  IF v_challenge.invited_email IS NOT NULL
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

DROP FUNCTION IF EXISTS public.join_searchable_challenge(UUID, TEXT, INTEGER);

CREATE OR REPLACE FUNCTION public.join_searchable_challenge(
  p_challenge_id UUID,
  p_participant_name TEXT DEFAULT NULL,
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
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  SELECT *
  INTO v_challenge
  FROM public.challenges
  WHERE id = p_challenge_id
    AND visibility = 'searchable'
    AND status = 'active'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Challenge not found.';
  END IF;

  IF v_challenge.creator_id = v_uid THEN
    RAISE EXCEPTION 'You cannot join your own challenge.';
  END IF;

  IF v_challenge.participant_id IS NOT NULL THEN
    IF v_challenge.participant_id = v_uid THEN
      RETURN v_challenge;
    END IF;

    RAISE EXCEPTION 'This challenge has already been claimed.';
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
GRANT EXECUTE ON FUNCTION public.accept_challenge_invite(TEXT, TEXT, TEXT, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.join_searchable_challenge(UUID, TEXT, INTEGER) TO authenticated;
