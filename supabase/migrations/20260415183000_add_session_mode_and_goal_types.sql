-- Separate session mode from goal type so door-knocking and flyer runs can use
-- different goal strategies without overloading one column.

ALTER TABLE public.sessions
    ADD COLUMN IF NOT EXISTS session_mode TEXT;

UPDATE public.sessions
SET session_mode = CASE
    WHEN goal_type = 'flyers' THEN 'flyer'
    ELSE 'door_knocking'
END
WHERE session_mode IS NULL;

ALTER TABLE public.sessions
    DROP CONSTRAINT IF EXISTS sessions_goal_type_check;

ALTER TABLE public.sessions
    ADD CONSTRAINT sessions_goal_type_check
    CHECK (goal_type IN ('flyers', 'knocks', 'conversations', 'appointments', 'time', 'leads'));

ALTER TABLE public.sessions
    DROP CONSTRAINT IF EXISTS sessions_session_mode_check;

ALTER TABLE public.sessions
    ADD CONSTRAINT sessions_session_mode_check
    CHECK (session_mode IN ('door_knocking', 'flyer'));

ALTER TABLE public.sessions
    ALTER COLUMN session_mode SET DEFAULT 'door_knocking';

UPDATE public.sessions
SET session_mode = 'door_knocking'
WHERE session_mode IS NULL;

ALTER TABLE public.sessions
    ALTER COLUMN session_mode SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_sessions_session_mode
    ON public.sessions(session_mode);

NOTIFY pgrst, 'reload schema';
