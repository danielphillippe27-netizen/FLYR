BEGIN;

ALTER TABLE public.workspaces
    ADD COLUMN IF NOT EXISTS referral_code TEXT;

COMMENT ON COLUMN public.workspaces.referral_code IS
    'Referral code captured from onboarding or paywall purchase attribution.';

COMMIT;
