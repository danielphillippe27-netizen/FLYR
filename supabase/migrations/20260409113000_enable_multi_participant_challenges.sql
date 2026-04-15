-- Enable multiple users to join the same challenge while preserving the
-- existing challenges row as the aggregate snapshot for legacy clients.

ALTER TABLE public.challenges
  ADD COLUMN IF NOT EXISTS participant_count INTEGER NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.challenges.participant_count IS 'Number of accepted participants for the challenge.';

CREATE TABLE IF NOT EXISTS public.challenge_participants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  challenge_id UUID NOT NULL REFERENCES public.challenges(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  participant_name TEXT,
  baseline_count INTEGER NOT NULL DEFAULT 0,
  progress_count INTEGER NOT NULL DEFAULT 0,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ,
  last_sync_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT challenge_participants_unique_member UNIQUE (challenge_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_challenge_participants_challenge_id
  ON public.challenge_participants (challenge_id);
CREATE INDEX IF NOT EXISTS idx_challenge_participants_user_id
  ON public.challenge_participants (user_id);
CREATE INDEX IF NOT EXISTS idx_challenge_participants_progress
  ON public.challenge_participants (challenge_id, progress_count DESC);

ALTER TABLE public.challenge_participants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "challenge_participants_select_visible" ON public.challenge_participants;
CREATE POLICY "challenge_participants_select_visible"
ON public.challenge_participants
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
);

DROP POLICY IF EXISTS "challenge_participants_insert_own" ON public.challenge_participants;
CREATE POLICY "challenge_participants_insert_own"
ON public.challenge_participants
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "challenge_participants_update_own" ON public.challenge_participants;
CREATE POLICY "challenge_participants_update_own"
ON public.challenge_participants
FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

GRANT SELECT, INSERT, UPDATE ON public.challenge_participants TO authenticated;

INSERT INTO public.challenge_participants (
  challenge_id,
  user_id,
  participant_name,
  baseline_count,
  progress_count,
  joined_at,
  accepted_at,
  completed_at,
  last_sync_at
)
SELECT
  c.id,
  c.participant_id,
  c.participant_name,
  COALESCE(c.baseline_count, 0),
  COALESCE(c.progress_count, 0),
  COALESCE(c.accepted_at, c.created_at, now()),
  COALESCE(c.accepted_at, c.created_at, now()),
  c.completed_at,
  now()
FROM public.challenges c
WHERE c.participant_id IS NOT NULL
ON CONFLICT (challenge_id, user_id) DO NOTHING;

DROP FUNCTION IF EXISTS public.refresh_challenge_participant_snapshot(UUID);

CREATE OR REPLACE FUNCTION public.refresh_challenge_participant_snapshot(p_challenge_id UUID)
RETURNS public.challenges
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_challenge public.challenges%ROWTYPE;
  v_participant_count INTEGER := 0;
  v_first_accepted_at TIMESTAMPTZ;
  v_leader_user_id UUID;
  v_leader_name TEXT;
  v_leader_baseline INTEGER;
  v_leader_progress INTEGER;
  v_next_status TEXT;
BEGIN
  SELECT *
  INTO v_challenge
  FROM public.challenges
  WHERE id = p_challenge_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Challenge not found.';
  END IF;

  SELECT
    COUNT(*)::INTEGER,
    MIN(cp.accepted_at)
  INTO
    v_participant_count,
    v_first_accepted_at
  FROM public.challenge_participants cp
  WHERE cp.challenge_id = p_challenge_id;

  SELECT
    cp.user_id,
    NULLIF(trim(COALESCE(cp.participant_name, '')), ''),
    cp.baseline_count,
    cp.progress_count
  INTO
    v_leader_user_id,
    v_leader_name,
    v_leader_baseline,
    v_leader_progress
  FROM public.challenge_participants cp
  WHERE cp.challenge_id = p_challenge_id
  ORDER BY cp.progress_count DESC, cp.accepted_at ASC NULLS LAST, cp.joined_at ASC, cp.user_id ASC
  LIMIT 1;

  IF v_challenge.scoring_mode = 'reach_goal' THEN
    IF EXISTS (
      SELECT 1
      FROM public.challenge_participants cp
      WHERE cp.challenge_id = p_challenge_id
        AND cp.progress_count >= v_challenge.goal_count
    ) THEN
      v_next_status := 'completed';
    ELSIF v_challenge.expires_at IS NOT NULL AND v_challenge.expires_at < now() THEN
      v_next_status := 'failed';
    ELSE
      v_next_status := 'active';
    END IF;
  ELSE
    IF v_challenge.expires_at IS NOT NULL AND v_challenge.expires_at < now() THEN
      v_next_status := 'completed';
    ELSE
      v_next_status := 'active';
    END IF;
  END IF;

  UPDATE public.challenges c
  SET participant_count = COALESCE(v_participant_count, 0),
      participant_id = v_leader_user_id,
      participant_name = v_leader_name,
      baseline_count = COALESCE(v_leader_baseline, 0),
      progress_count = COALESCE(v_leader_progress, 0),
      accepted_at = v_first_accepted_at,
      status = v_next_status,
      completed_at = CASE
        WHEN v_next_status = 'completed' THEN COALESCE(c.completed_at, now())
        WHEN v_next_status = 'active' THEN NULL
        ELSE c.completed_at
      END
  WHERE c.id = p_challenge_id
  RETURNING * INTO v_challenge;

  RETURN v_challenge;
END;
$$;

DROP POLICY IF EXISTS "challenges_select_own" ON public.challenges;
CREATE POLICY "challenges_select_own"
  ON public.challenges
  FOR SELECT
  TO authenticated
  USING (
    auth.uid() = creator_id
    OR visibility = 'searchable'
    OR EXISTS (
      SELECT 1
      FROM public.challenge_participants cp
      WHERE cp.challenge_id = public.challenges.id
        AND cp.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "challenges_update_own" ON public.challenges;
CREATE POLICY "challenges_update_own"
  ON public.challenges
  FOR UPDATE
  TO authenticated
  USING (
    auth.uid() = creator_id
    OR EXISTS (
      SELECT 1
      FROM public.challenge_participants cp
      WHERE cp.challenge_id = public.challenges.id
        AND cp.user_id = auth.uid()
    )
  )
  WITH CHECK (
    auth.uid() = creator_id
    OR EXISTS (
      SELECT 1
      FROM public.challenge_participants cp
      WHERE cp.challenge_id = public.challenges.id
        AND cp.user_id = auth.uid()
    )
  );

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
  participant_count INTEGER,
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
    COALESCE(c.participant_count, 0) AS participant_count,
    EXISTS (
      SELECT 1
      FROM public.challenge_participants cp
      WHERE cp.challenge_id = c.id
        AND cp.user_id = auth.uid()
    ) AS already_joined
  FROM public.challenges c
  WHERE c.invite_token = NULLIF(trim(p_token), '')
    AND c.status = 'active'
    AND (
      c.expires_at IS NULL
      OR c.expires_at > now()
      OR c.accepted_at IS NULL
    )
  LIMIT 1;
END;
$$;

DROP FUNCTION IF EXISTS public.accept_challenge_invite(TEXT, TEXT, TEXT, TEXT, INTEGER);

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

  IF v_challenge.expires_at IS NOT NULL
     AND v_challenge.expires_at <= now()
     AND v_challenge.accepted_at IS NOT NULL THEN
    RAISE EXCEPTION 'This challenge has already ended.';
  END IF;

  IF v_invited_phone IS NOT NULL THEN
    IF v_phone IS NULL OR v_phone <> v_invited_phone THEN
      RAISE EXCEPTION 'This invite was sent to a different phone number.';
    END IF;
  ELSIF v_challenge.invited_email IS NOT NULL
     AND lower(trim(v_challenge.invited_email)) <> v_email THEN
    RAISE EXCEPTION 'This invite was sent to a different email address.';
  END IF;

  INSERT INTO public.challenge_participants (
    challenge_id,
    user_id,
    participant_name,
    baseline_count,
    progress_count,
    joined_at,
    accepted_at,
    last_sync_at
  )
  VALUES (
    v_challenge.id,
    v_uid,
    NULLIF(trim(COALESCE(p_participant_name, '')), ''),
    GREATEST(COALESCE(p_baseline_count, 0), 0),
    0,
    now(),
    now(),
    now()
  )
  ON CONFLICT (challenge_id, user_id)
  DO UPDATE
    SET participant_name = COALESCE(
          public.challenge_participants.participant_name,
          EXCLUDED.participant_name
        )
  ;

  UPDATE public.challenges
  SET accepted_at = COALESCE(accepted_at, now()),
      expires_at = CASE
        WHEN expires_at IS NULL AND time_limit_hours IS NOT NULL
          THEN now() + make_interval(hours => time_limit_hours)
        ELSE expires_at
      END
  WHERE id = v_challenge.id;

  RETURN public.refresh_challenge_participant_snapshot(v_challenge.id);
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

  IF v_challenge.expires_at IS NOT NULL
     AND v_challenge.expires_at <= now()
     AND v_challenge.accepted_at IS NOT NULL THEN
    RAISE EXCEPTION 'This challenge has already ended.';
  END IF;

  INSERT INTO public.challenge_participants (
    challenge_id,
    user_id,
    participant_name,
    baseline_count,
    progress_count,
    joined_at,
    accepted_at,
    last_sync_at
  )
  VALUES (
    v_challenge.id,
    v_uid,
    NULLIF(trim(COALESCE(p_participant_name, '')), ''),
    GREATEST(COALESCE(p_baseline_count, 0), 0),
    0,
    now(),
    now(),
    now()
  )
  ON CONFLICT (challenge_id, user_id)
  DO UPDATE
    SET participant_name = COALESCE(
          public.challenge_participants.participant_name,
          EXCLUDED.participant_name
        )
  ;

  UPDATE public.challenges
  SET accepted_at = COALESCE(accepted_at, now()),
      expires_at = CASE
        WHEN expires_at IS NULL AND time_limit_hours IS NOT NULL
          THEN now() + make_interval(hours => time_limit_hours)
        ELSE expires_at
      END
  WHERE id = v_challenge.id;

  RETURN public.refresh_challenge_participant_snapshot(v_challenge.id);
END;
$$;

DROP FUNCTION IF EXISTS public.sync_challenge_progress(UUID, INTEGER);

CREATE OR REPLACE FUNCTION public.sync_challenge_progress(
  p_challenge_id UUID,
  p_progress_count INTEGER
)
RETURNS public.challenges
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_challenge public.challenges%ROWTYPE;
  v_normalized_progress INTEGER := GREATEST(COALESCE(p_progress_count, 0), 0);
  v_next_status TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  SELECT *
  INTO v_challenge
  FROM public.challenges
  WHERE id = p_challenge_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Challenge not found.';
  END IF;

  IF v_challenge.title = '30 Day Challenge' AND v_challenge.goal_count = 30 THEN
    IF v_normalized_progress >= v_challenge.goal_count THEN
      v_next_status := 'completed';
    ELSIF v_challenge.expires_at IS NOT NULL AND v_challenge.expires_at < now() THEN
      v_next_status := 'failed';
    ELSE
      v_next_status := 'active';
    END IF;

    UPDATE public.challenges c
    SET progress_count = v_normalized_progress,
        status = v_next_status,
        completed_at = CASE
          WHEN v_next_status = 'completed' THEN COALESCE(c.completed_at, now())
          WHEN v_next_status = 'active' THEN NULL
          ELSE c.completed_at
        END
    WHERE c.id = p_challenge_id
    RETURNING * INTO v_challenge;

    RETURN v_challenge;
  END IF;

  UPDATE public.challenge_participants cp
  SET progress_count = v_normalized_progress,
      last_sync_at = now(),
      completed_at = CASE
        WHEN v_normalized_progress >= v_challenge.goal_count THEN COALESCE(cp.completed_at, now())
        ELSE NULL
      END
  WHERE cp.challenge_id = p_challenge_id
    AND cp.user_id = v_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'You have not joined this challenge.';
  END IF;

  RETURN public.refresh_challenge_participant_snapshot(p_challenge_id);
END;
$$;

UPDATE public.challenges c
SET participant_count = counts.participant_count
FROM (
  SELECT challenge_id, COUNT(*)::INTEGER AS participant_count
  FROM public.challenge_participants
  GROUP BY challenge_id
) counts
WHERE c.id = counts.challenge_id;

UPDATE public.challenges
SET participant_count = 0
WHERE participant_count IS NULL;

SELECT public.refresh_challenge_participant_snapshot(id)
FROM public.challenges
WHERE title <> '30 Day Challenge';

DROP POLICY IF EXISTS "profile_images_select_own" ON storage.objects;
CREATE POLICY "profile_images_select_own"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'profile_images'
  AND (
    lower(name) = 'profile_' || lower(auth.uid()::text) || '.jpg'
    OR owner_id = auth.uid()::text
    OR EXISTS (
      SELECT 1
      FROM public.challenges c
      WHERE COALESCE(to_jsonb(c) ->> 'cover_image_path', '') = storage.objects.name
        AND (
          c.creator_id = auth.uid()
          OR c.visibility = 'searchable'
          OR EXISTS (
            SELECT 1
            FROM public.challenge_participants cp
            WHERE cp.challenge_id = c.id
              AND cp.user_id = auth.uid()
          )
        )
    )
  )
);

GRANT EXECUTE ON FUNCTION public.validate_challenge_invite(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.accept_challenge_invite(TEXT, TEXT, TEXT, TEXT, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.join_searchable_challenge(UUID, TEXT, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_challenge_progress(UUID, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_challenge_participant_snapshot(UUID) TO authenticated;
