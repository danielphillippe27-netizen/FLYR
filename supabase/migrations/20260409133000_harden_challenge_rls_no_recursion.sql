-- Harden challenge RLS to avoid policy recursion between
-- public.challenges and public.challenge_participants.

CREATE OR REPLACE FUNCTION public.is_challenge_participant(
  p_challenge_id UUID,
  p_user_id UUID DEFAULT auth.uid()
)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.challenge_participants cp
    WHERE cp.challenge_id = p_challenge_id
      AND cp.user_id = p_user_id
  );
$$;

CREATE OR REPLACE FUNCTION public.can_select_challenge(
  p_challenge_id UUID,
  p_creator_id UUID,
  p_visibility TEXT,
  p_user_id UUID DEFAULT auth.uid()
)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    p_user_id = p_creator_id
    OR p_visibility = 'searchable'
    OR public.is_challenge_participant(p_challenge_id, p_user_id);
$$;

DROP POLICY IF EXISTS "challenges_select_own" ON public.challenges;
CREATE POLICY "challenges_select_own"
  ON public.challenges
  FOR SELECT
  TO authenticated
  USING (
    public.can_select_challenge(id, creator_id, visibility, auth.uid())
  );

DROP POLICY IF EXISTS "challenges_insert_own" ON public.challenges;
CREATE POLICY "challenges_insert_own"
  ON public.challenges
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = creator_id);

DROP POLICY IF EXISTS "challenges_update_own" ON public.challenges;
CREATE POLICY "challenges_update_own"
  ON public.challenges
  FOR UPDATE
  TO authenticated
  USING (
    auth.uid() = creator_id
    OR public.is_challenge_participant(id, auth.uid())
  )
  WITH CHECK (
    auth.uid() = creator_id
    OR public.is_challenge_participant(id, auth.uid())
  );

GRANT EXECUTE ON FUNCTION public.is_challenge_participant(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_select_challenge(UUID, UUID, TEXT, UUID) TO authenticated;
