CREATE TABLE IF NOT EXISTS public.calendar_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    workspace_id UUID REFERENCES public.workspaces(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    start_at TIMESTAMPTZ NOT NULL,
    end_at TIMESTAMPTZ NOT NULL,
    is_all_day BOOLEAN NOT NULL DEFAULT FALSE,
    event_type TEXT NOT NULL DEFAULT 'appointment',
    contact_id UUID REFERENCES public.contacts(id) ON DELETE SET NULL,
    contact_name TEXT,
    contact_address TEXT,
    notes TEXT,
    location TEXT,
    color_key TEXT NOT NULL DEFAULT 'red',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_calendar_events_user_range
    ON public.calendar_events(user_id, start_at, end_at)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_calendar_events_workspace_range
    ON public.calendar_events(workspace_id, start_at, end_at)
    WHERE deleted_at IS NULL;

ALTER TABLE public.calendar_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Calendar events are readable by owner or workspace members"
    ON public.calendar_events;
CREATE POLICY "Calendar events are readable by owner or workspace members"
    ON public.calendar_events
    FOR SELECT
    USING (
        auth.uid() = user_id
        OR (workspace_id IS NOT NULL AND public.is_workspace_member(workspace_id))
    );

DROP POLICY IF EXISTS "Calendar events are insertable by owner or workspace members"
    ON public.calendar_events;
CREATE POLICY "Calendar events are insertable by owner or workspace members"
    ON public.calendar_events
    FOR INSERT
    WITH CHECK (
        auth.uid() = user_id
        OR (workspace_id IS NOT NULL AND public.is_workspace_member(workspace_id))
    );

DROP POLICY IF EXISTS "Calendar events are updatable by owner or workspace members"
    ON public.calendar_events;
CREATE POLICY "Calendar events are updatable by owner or workspace members"
    ON public.calendar_events
    FOR UPDATE
    USING (
        auth.uid() = user_id
        OR (workspace_id IS NOT NULL AND public.is_workspace_member(workspace_id))
    )
    WITH CHECK (
        auth.uid() = user_id
        OR (workspace_id IS NOT NULL AND public.is_workspace_member(workspace_id))
    );

DROP POLICY IF EXISTS "Calendar events are deletable by owner or workspace members"
    ON public.calendar_events;
CREATE POLICY "Calendar events are deletable by owner or workspace members"
    ON public.calendar_events
    FOR DELETE
    USING (
        auth.uid() = user_id
        OR (workspace_id IS NOT NULL AND public.is_workspace_member(workspace_id))
    );
