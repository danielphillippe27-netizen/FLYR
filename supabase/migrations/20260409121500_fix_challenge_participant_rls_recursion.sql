-- Repair recursive RLS introduced by multi-participant challenges.
-- The original policy on challenge_participants queried challenges,
-- while challenges policies also queried challenge_participants.
-- Postgres treats that cycle as an invalid object definition.

DROP POLICY IF EXISTS "challenge_participants_select_visible" ON public.challenge_participants;

CREATE POLICY "challenge_participants_select_visible"
ON public.challenge_participants
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
);
