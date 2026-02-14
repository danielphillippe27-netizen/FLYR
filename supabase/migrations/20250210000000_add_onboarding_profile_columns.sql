-- Onboarding profile columns (auth-at-end flow)
-- Adds columns used when syncing onboarding data after signup

ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS contact_preference TEXT,
    ADD COLUMN IF NOT EXISTS session_duration TEXT,
    ADD COLUMN IF NOT EXISTS industry TEXT,
    ADD COLUMN IF NOT EXISTS territory_type TEXT,
    ADD COLUMN IF NOT EXISTS experience_level TEXT,
    ADD COLUMN IF NOT EXISTS first_session_goal TEXT,
    ADD COLUMN IF NOT EXISTS weekly_plan TEXT,
    ADD COLUMN IF NOT EXISTS primary_goal TEXT,
    ADD COLUMN IF NOT EXISTS tracking_preference TEXT,
    ADD COLUMN IF NOT EXISTS property_focus TEXT;

COMMENT ON COLUMN public.profiles.contact_preference IS 'Onboarding: preferred contact method';
COMMENT ON COLUMN public.profiles.session_duration IS 'Onboarding: typical session length';
COMMENT ON COLUMN public.profiles.industry IS 'Onboarding: industry (real_estate, mortgage, etc.)';
COMMENT ON COLUMN public.profiles.territory_type IS 'Onboarding: urban, suburban, rural, mixed';
COMMENT ON COLUMN public.profiles.experience_level IS 'Onboarding: door-knocking experience';
COMMENT ON COLUMN public.profiles.first_session_goal IS 'Onboarding: first session door count';
COMMENT ON COLUMN public.profiles.weekly_plan IS 'Onboarding: days per week';
COMMENT ON COLUMN public.profiles.primary_goal IS 'Onboarding: primary goal';
COMMENT ON COLUMN public.profiles.tracking_preference IS 'Onboarding: full or minimal tracking';
COMMENT ON COLUMN public.profiles.property_focus IS 'Onboarding: residential, commercial, both';
