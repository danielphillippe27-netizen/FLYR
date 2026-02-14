-- Onboarding v2: activity_type, goals, pro_expectations (post-auth sync)
ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS activity_type TEXT,
    ADD COLUMN IF NOT EXISTS goals JSONB DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS pro_expectations JSONB DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS pro_expectations_other TEXT;

COMMENT ON COLUMN public.profiles.activity_type IS 'Onboarding: door knocking, flyers, both';
COMMENT ON COLUMN public.profiles.goals IS 'Onboarding: motivation goals (staying consistent, tracking effort, etc.)';
COMMENT ON COLUMN public.profiles.pro_expectations IS 'Onboarding: what would make PRO worth $30/mo';
COMMENT ON COLUMN public.profiles.pro_expectations_other IS 'Onboarding: free text for "Other" PRO expectation';
