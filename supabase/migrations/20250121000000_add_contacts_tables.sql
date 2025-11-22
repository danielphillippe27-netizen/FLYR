-- FLYR Contacts CRM Migration
-- Creates tables for contact management and activity tracking

-- 1. Create contacts table
CREATE TABLE IF NOT EXISTS public.contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    phone TEXT,
    email TEXT,
    address TEXT NOT NULL,
    campaign_id UUID REFERENCES public.campaigns(id) ON DELETE SET NULL,
    farm_id UUID, -- Future reference to farms table
    status TEXT NOT NULL DEFAULT 'new' CHECK (status IN ('hot', 'warm', 'cold', 'new')),
    last_contacted TIMESTAMPTZ,
    notes TEXT,
    reminder_date TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. Create contact_activities table
CREATE TABLE IF NOT EXISTS public.contact_activities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contact_id UUID NOT NULL REFERENCES public.contacts(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('knock', 'call', 'flyer', 'note', 'text', 'email', 'meeting')),
    note TEXT,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. Create indexes
CREATE INDEX IF NOT EXISTS idx_contacts_user_id ON public.contacts(user_id);
CREATE INDEX IF NOT EXISTS idx_contacts_campaign_id ON public.contacts(campaign_id);
CREATE INDEX IF NOT EXISTS idx_contacts_farm_id ON public.contacts(farm_id);
CREATE INDEX IF NOT EXISTS idx_contacts_status ON public.contacts(status);
CREATE INDEX IF NOT EXISTS idx_contacts_last_contacted ON public.contacts(last_contacted DESC);
CREATE INDEX IF NOT EXISTS idx_contacts_created_at ON public.contacts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_contact_activities_contact_id ON public.contact_activities(contact_id);
CREATE INDEX IF NOT EXISTS idx_contact_activities_timestamp ON public.contact_activities(timestamp DESC);

-- 4. Enable RLS
ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contact_activities ENABLE ROW LEVEL SECURITY;

-- 5. RLS Policies for contacts
-- Users can only see their own contacts
DROP POLICY IF EXISTS "contacts_select_own" ON public.contacts;
CREATE POLICY "contacts_select_own"
    ON public.contacts
    FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

-- Users can insert their own contacts
DROP POLICY IF EXISTS "contacts_insert_own" ON public.contacts;
CREATE POLICY "contacts_insert_own"
    ON public.contacts
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

-- Users can update their own contacts
DROP POLICY IF EXISTS "contacts_update_own" ON public.contacts;
CREATE POLICY "contacts_update_own"
    ON public.contacts
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Users can delete their own contacts
DROP POLICY IF EXISTS "contacts_delete_own" ON public.contacts;
CREATE POLICY "contacts_delete_own"
    ON public.contacts
    FOR DELETE
    TO authenticated
    USING (auth.uid() = user_id);

-- 6. RLS Policies for contact_activities
-- Users can only see activities for their own contacts
DROP POLICY IF EXISTS "contact_activities_select_own" ON public.contact_activities;
CREATE POLICY "contact_activities_select_own"
    ON public.contact_activities
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.contacts
            WHERE contacts.id = contact_activities.contact_id
            AND contacts.user_id = auth.uid()
        )
    );

-- Users can insert activities for their own contacts
DROP POLICY IF EXISTS "contact_activities_insert_own" ON public.contact_activities;
CREATE POLICY "contact_activities_insert_own"
    ON public.contact_activities
    FOR INSERT
    TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.contacts
            WHERE contacts.id = contact_activities.contact_id
            AND contacts.user_id = auth.uid()
        )
    );

-- Users can update activities for their own contacts
DROP POLICY IF EXISTS "contact_activities_update_own" ON public.contact_activities;
CREATE POLICY "contact_activities_update_own"
    ON public.contact_activities
    FOR UPDATE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.contacts
            WHERE contacts.id = contact_activities.contact_id
            AND contacts.user_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.contacts
            WHERE contacts.id = contact_activities.contact_id
            AND contacts.user_id = auth.uid()
        )
    );

-- Users can delete activities for their own contacts
DROP POLICY IF EXISTS "contact_activities_delete_own" ON public.contact_activities;
CREATE POLICY "contact_activities_delete_own"
    ON public.contact_activities
    FOR DELETE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.contacts
            WHERE contacts.id = contact_activities.contact_id
            AND contacts.user_id = auth.uid()
        )
    );

-- 7. Create updated_at trigger function (if not exists)
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 8. Create triggers for updated_at
DROP TRIGGER IF EXISTS update_contacts_updated_at ON public.contacts;
CREATE TRIGGER update_contacts_updated_at
    BEFORE UPDATE ON public.contacts
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- 9. Create trigger to update last_contacted when activity is logged
CREATE OR REPLACE FUNCTION update_contact_last_contacted()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.contacts
    SET last_contacted = NEW.timestamp
    WHERE id = NEW.contact_id
    AND (last_contacted IS NULL OR NEW.timestamp > last_contacted);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_contact_last_contacted ON public.contact_activities;
CREATE TRIGGER trigger_update_contact_last_contacted
    AFTER INSERT ON public.contact_activities
    FOR EACH ROW
    EXECUTE FUNCTION update_contact_last_contacted();

-- 10. Grant permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON public.contacts TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.contact_activities TO authenticated;

-- 11. Add comments
COMMENT ON TABLE public.contacts IS 'CRM contacts for prospecting and farming campaigns';
COMMENT ON TABLE public.contact_activities IS 'Activity history for contacts (knocks, calls, flyers, etc.)';





