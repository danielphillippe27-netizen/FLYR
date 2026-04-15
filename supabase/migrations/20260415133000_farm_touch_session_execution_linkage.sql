BEGIN;

ALTER TABLE public.sessions
    ADD COLUMN IF NOT EXISTS farm_id uuid REFERENCES public.farms(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS farm_touch_id uuid REFERENCES public.farm_touches(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS farm_phase_id uuid REFERENCES public.farm_phases(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_sessions_farm_id
    ON public.sessions (farm_id)
    WHERE farm_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_sessions_farm_touch_id
    ON public.sessions (farm_touch_id)
    WHERE farm_touch_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_sessions_farm_phase_id
    ON public.sessions (farm_phase_id)
    WHERE farm_phase_id IS NOT NULL;

ALTER TABLE public.farm_touches
    ADD COLUMN IF NOT EXISTS phase_id uuid REFERENCES public.farm_phases(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS session_id uuid REFERENCES public.sessions(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS completed_at timestamptz,
    ADD COLUMN IF NOT EXISTS completed_by_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS execution_metrics jsonb DEFAULT '{}'::jsonb;

CREATE INDEX IF NOT EXISTS idx_farm_touches_phase_id
    ON public.farm_touches (phase_id)
    WHERE phase_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_farm_touches_session_id
    ON public.farm_touches (session_id)
    WHERE session_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_farm_touches_completed_at
    ON public.farm_touches (completed_at DESC)
    WHERE completed_at IS NOT NULL;

COMMENT ON COLUMN public.sessions.farm_id IS
    'Optional farm context for sessions started from a farm plan.';

COMMENT ON COLUMN public.sessions.farm_touch_id IS
    'Optional farm touch that launched this session.';

COMMENT ON COLUMN public.sessions.farm_phase_id IS
    'Optional farm phase/cycle associated with the planned touch that launched this session.';

COMMENT ON COLUMN public.farm_touches.phase_id IS
    'Optional explicit phase/cycle link for a planned farm touch.';

COMMENT ON COLUMN public.farm_touches.session_id IS
    'Session used to execute this planned touch.';

COMMENT ON COLUMN public.farm_touches.completed_at IS
    'Timestamp when the touch was completed from a live session or manual completion.';

COMMENT ON COLUMN public.farm_touches.completed_by_user_id IS
    'User who completed the touch.';

COMMENT ON COLUMN public.farm_touches.execution_metrics IS
    'JSON summary of the session that executed the touch: doors, flyers, conversations, leads, distance, minutes.';

COMMIT;
