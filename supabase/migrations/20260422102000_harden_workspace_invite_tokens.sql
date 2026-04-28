BEGIN;

ALTER TABLE public.workspace_invites
    ADD COLUMN IF NOT EXISTS invite_token_hash TEXT;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'workspace_invites'
          AND column_name = 'token'
    ) THEN
        EXECUTE $sql$
            UPDATE public.workspace_invites
            SET invite_token_hash = CASE
                WHEN invite_token IS NOT NULL AND invite_token ~ '^[0-9a-f]{64}$' THEN lower(invite_token)
                WHEN token IS NOT NULL AND token ~ '^[0-9a-f]{64}$' THEN lower(token)
                WHEN invite_token IS NOT NULL THEN encode(digest(invite_token, 'sha256'), 'hex')
                WHEN token IS NOT NULL THEN encode(digest(token, 'sha256'), 'hex')
                ELSE invite_token_hash
            END
            WHERE invite_token_hash IS NULL
        $sql$;
    ELSE
        UPDATE public.workspace_invites
        SET invite_token_hash = CASE
            WHEN invite_token IS NOT NULL AND invite_token ~ '^[0-9a-f]{64}$' THEN lower(invite_token)
            WHEN invite_token IS NOT NULL THEN encode(digest(invite_token, 'sha256'), 'hex')
            ELSE invite_token_hash
        END
        WHERE invite_token_hash IS NULL;
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_workspace_invites_token_hash_unique
    ON public.workspace_invites(invite_token_hash)
    WHERE invite_token_hash IS NOT NULL;

COMMENT ON COLUMN public.workspace_invites.invite_token_hash
    IS 'SHA-256 hash of the opaque join token. Raw invite tokens are never stored after hardening.';

UPDATE public.workspace_invites
SET invite_token = NULL
WHERE invite_token_hash IS NOT NULL
  AND invite_token IS NOT NULL
  AND invite_token !~ '^[0-9a-f]{64}$';

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'workspace_invites'
          AND column_name = 'token'
    ) THEN
        EXECUTE $sql$
            UPDATE public.workspace_invites
            SET token = NULL
            WHERE invite_token_hash IS NOT NULL
              AND token IS NOT NULL
              AND token !~ '^[0-9a-f]{64}$'
        $sql$;
    END IF;
END $$;

COMMIT;
