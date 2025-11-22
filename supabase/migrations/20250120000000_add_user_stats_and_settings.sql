-- FLYR User Stats and Settings Migration
-- Creates tables for user statistics and settings

-- 1. Create user_stats table
CREATE TABLE IF NOT EXISTS public.user_stats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    day_streak INTEGER NOT NULL DEFAULT 0,
    best_streak INTEGER NOT NULL DEFAULT 0,
    doors_knocked INTEGER NOT NULL DEFAULT 0,
    flyers INTEGER NOT NULL DEFAULT 0,
    conversations INTEGER NOT NULL DEFAULT 0,
    leads_created INTEGER NOT NULL DEFAULT 0,
    qr_codes_scanned INTEGER NOT NULL DEFAULT 0,
    distance_walked DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    conversation_per_door DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    conversation_lead_rate DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    qr_code_scan_rate DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    qr_code_lead_rate DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    streak_days JSONB DEFAULT '[]'::jsonb,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id)
);

-- 2. Create user_settings table
CREATE TABLE IF NOT EXISTS public.user_settings (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    exclude_weekends BOOLEAN NOT NULL DEFAULT false,
    dark_mode BOOLEAN NOT NULL DEFAULT true,
    follow_up_boss_key TEXT,
    member_since TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. Create indexes
CREATE INDEX IF NOT EXISTS idx_user_stats_user_id ON public.user_stats(user_id);
CREATE INDEX IF NOT EXISTS idx_user_stats_updated_at ON public.user_stats(updated_at DESC);

-- 4. Enable RLS
ALTER TABLE public.user_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;

-- 5. RLS Policies for user_stats
-- Users can only see their own stats
DROP POLICY IF EXISTS "user_stats_select_own" ON public.user_stats;
CREATE POLICY "user_stats_select_own"
    ON public.user_stats
    FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

-- Users can insert their own stats
DROP POLICY IF EXISTS "user_stats_insert_own" ON public.user_stats;
CREATE POLICY "user_stats_insert_own"
    ON public.user_stats
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

-- Users can update their own stats
DROP POLICY IF EXISTS "user_stats_update_own" ON public.user_stats;
CREATE POLICY "user_stats_update_own"
    ON public.user_stats
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- 6. RLS Policies for user_settings
-- Users can only see their own settings
DROP POLICY IF EXISTS "user_settings_select_own" ON public.user_settings;
CREATE POLICY "user_settings_select_own"
    ON public.user_settings
    FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

-- Users can insert their own settings
DROP POLICY IF EXISTS "user_settings_insert_own" ON public.user_settings;
CREATE POLICY "user_settings_insert_own"
    ON public.user_settings
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

-- Users can update their own settings
DROP POLICY IF EXISTS "user_settings_update_own" ON public.user_settings;
CREATE POLICY "user_settings_update_own"
    ON public.user_settings
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- 7. Create updated_at trigger function (if not exists)
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 8. Create triggers for updated_at
DROP TRIGGER IF EXISTS update_user_stats_updated_at ON public.user_stats;
CREATE TRIGGER update_user_stats_updated_at
    BEFORE UPDATE ON public.user_stats
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_user_settings_updated_at ON public.user_settings;
CREATE TRIGGER update_user_settings_updated_at
    BEFORE UPDATE ON public.user_settings
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- 9. Grant permissions
GRANT SELECT, INSERT, UPDATE ON public.user_stats TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.user_settings TO authenticated;

-- 10. Add comments
COMMENT ON TABLE public.user_stats IS 'User statistics and performance metrics';
COMMENT ON TABLE public.user_settings IS 'User preferences and settings';





