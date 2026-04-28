BEGIN;

CREATE TABLE IF NOT EXISTS public.workspace_invites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid()
);

ALTER TABLE public.workspace_invites
    ADD COLUMN IF NOT EXISTS workspace_id UUID REFERENCES public.workspaces(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS campaign_id UUID REFERENCES public.campaigns(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS accepted_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS email TEXT,
    ADD COLUMN IF NOT EXISTS role TEXT DEFAULT 'member',
    ADD COLUMN IF NOT EXISTS invite_token TEXT,
    ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW(),
    ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

UPDATE public.workspace_invites
SET role = 'member'
WHERE role IS NULL
   OR role NOT IN ('admin', 'member');

UPDATE public.workspace_invites
SET created_at = NOW()
WHERE created_at IS NULL;

ALTER TABLE public.workspace_invites
    ALTER COLUMN role SET DEFAULT 'member',
    ALTER COLUMN created_at SET DEFAULT NOW();

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'workspace_invites'
          AND column_name = 'workspace_id'
    ) AND NOT EXISTS (
        SELECT 1
        FROM public.workspace_invites
        WHERE workspace_id IS NULL
    ) THEN
        EXECUTE 'ALTER TABLE public.workspace_invites ALTER COLUMN workspace_id SET NOT NULL';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'workspace_invites'
          AND column_name = 'created_by'
    ) AND NOT EXISTS (
        SELECT 1
        FROM public.workspace_invites
        WHERE created_by IS NULL
    ) THEN
        EXECUTE 'ALTER TABLE public.workspace_invites ALTER COLUMN created_by SET NOT NULL';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'workspace_invites'
          AND column_name = 'role'
    ) AND NOT EXISTS (
        SELECT 1
        FROM public.workspace_invites
        WHERE role IS NULL
    ) THEN
        EXECUTE 'ALTER TABLE public.workspace_invites ALTER COLUMN role SET NOT NULL';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'workspace_invites'
          AND column_name = 'created_at'
    ) AND NOT EXISTS (
        SELECT 1
        FROM public.workspace_invites
        WHERE created_at IS NULL
    ) THEN
        EXECUTE 'ALTER TABLE public.workspace_invites ALTER COLUMN created_at SET NOT NULL';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'workspace_invites_role_check'
    ) THEN
        ALTER TABLE public.workspace_invites
            ADD CONSTRAINT workspace_invites_role_check
            CHECK (role IN ('admin', 'member'));
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_workspace_invites_token_unique
    ON public.workspace_invites(invite_token)
    WHERE invite_token IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_workspace_invites_workspace_id
    ON public.workspace_invites(workspace_id);

CREATE INDEX IF NOT EXISTS idx_workspace_invites_campaign_id
    ON public.workspace_invites(campaign_id)
    WHERE campaign_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_workspace_invites_expires_at
    ON public.workspace_invites(expires_at)
    WHERE expires_at IS NOT NULL;

ALTER TABLE public.workspace_invites ENABLE ROW LEVEL SECURITY;

GRANT ALL ON public.workspace_invites TO service_role;

COMMENT ON TABLE public.workspace_invites
    IS 'Shareable workspace and campaign invite links used by the iOS join flow.';

COMMENT ON COLUMN public.workspace_invites.campaign_id
    IS 'Optional campaign anchor so an invite can start from a specific live session campaign.';

COMMENT ON COLUMN public.workspace_invites.email
    IS 'Optional email restriction for private invites. Null means any authenticated recipient can accept.';

COMMENT ON COLUMN public.workspace_invites.invite_token
    IS 'Opaque join token shared via /join?token=... links.';

COMMIT;
