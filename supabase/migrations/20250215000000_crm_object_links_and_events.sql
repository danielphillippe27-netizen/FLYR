-- =====================================================
-- CRM object links: map FLYR lead/address to FUB person
-- Enables reusing same FUB person before field_lead exists (by address_id) and when lead exists (by lead_id).
-- =====================================================

CREATE TABLE IF NOT EXISTS public.crm_object_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    crm_type TEXT NOT NULL DEFAULT 'fub' CHECK (crm_type IN ('fub')),
    flyr_lead_id UUID NULL,
    flyr_address_id UUID NULL,
    fub_person_id BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT crm_object_links_lead_or_address CHECK (flyr_lead_id IS NOT NULL OR flyr_address_id IS NOT NULL)
);

-- Unique by lead (when present)
CREATE UNIQUE INDEX IF NOT EXISTS idx_crm_object_links_user_crm_lead
    ON public.crm_object_links (user_id, crm_type, flyr_lead_id)
    WHERE flyr_lead_id IS NOT NULL;

-- Unique by address (when present)
CREATE UNIQUE INDEX IF NOT EXISTS idx_crm_object_links_user_crm_address
    ON public.crm_object_links (user_id, crm_type, flyr_address_id)
    WHERE flyr_address_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_crm_object_links_user_id ON public.crm_object_links(user_id);
CREATE INDEX IF NOT EXISTS idx_crm_object_links_fub_person ON public.crm_object_links(fub_person_id);

ALTER TABLE public.crm_object_links ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "crm_object_links_select_own" ON public.crm_object_links;
CREATE POLICY "crm_object_links_select_own"
    ON public.crm_object_links FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "crm_object_links_insert_own" ON public.crm_object_links;
CREATE POLICY "crm_object_links_insert_own"
    ON public.crm_object_links FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "crm_object_links_update_own" ON public.crm_object_links;
CREATE POLICY "crm_object_links_update_own"
    ON public.crm_object_links FOR UPDATE TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "crm_object_links_delete_own" ON public.crm_object_links;
CREATE POLICY "crm_object_links_delete_own"
    ON public.crm_object_links FOR DELETE TO authenticated
    USING (auth.uid() = user_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.crm_object_links TO authenticated;
GRANT ALL ON public.crm_object_links TO service_role;

COMMENT ON TABLE public.crm_object_links IS 'Maps FLYR lead_id and/or address_id to FUB person_id for voice-log and CRM sync.';

-- =====================================================
-- CRM events: idempotency for voice-log (flyr_event_id from device)
-- =====================================================

CREATE TABLE IF NOT EXISTS public.crm_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    crm_type TEXT NOT NULL DEFAULT 'fub' CHECK (crm_type IN ('fub')),
    flyr_event_id UUID NOT NULL,
    fub_person_id BIGINT NULL,
    fub_note_id BIGINT NULL,
    fub_task_id BIGINT NULL,
    fub_appointment_id BIGINT NULL,
    transcript TEXT NULL,
    ai_json JSONB NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, flyr_event_id)
);

CREATE INDEX IF NOT EXISTS idx_crm_events_user_id ON public.crm_events(user_id);
CREATE INDEX IF NOT EXISTS idx_crm_events_flyr_event_id ON public.crm_events(user_id, flyr_event_id);

ALTER TABLE public.crm_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "crm_events_select_own" ON public.crm_events;
CREATE POLICY "crm_events_select_own"
    ON public.crm_events FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "crm_events_insert_own" ON public.crm_events;
CREATE POLICY "crm_events_insert_own"
    ON public.crm_events FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);

-- Backend uses service_role for upsert; authenticated can only read/insert own
GRANT SELECT, INSERT ON public.crm_events TO authenticated;
GRANT ALL ON public.crm_events TO service_role;

COMMENT ON TABLE public.crm_events IS 'Idempotency for voice-log: one row per (user_id, flyr_event_id). Stores FUB note/task/appointment ids.';

NOTIFY pgrst, 'reload schema';
