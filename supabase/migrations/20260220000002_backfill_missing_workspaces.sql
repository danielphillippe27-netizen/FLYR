-- Backfill missing workspace ownership/membership for existing users.
-- This prevents workspace-scoped screens from failing with "No workspace selected."

BEGIN;

-- 1) Create a workspace for users who have neither:
--    - an owned workspace
--    - a workspace_members row
WITH users_missing_workspace AS (
    SELECT
        u.id AS user_id,
        COALESCE(
            NULLIF(
                TRIM(
                    CONCAT(
                        COALESCE(p.first_name, ''),
                        CASE WHEN p.first_name IS NOT NULL AND p.last_name IS NOT NULL THEN ' ' ELSE '' END,
                        COALESCE(p.last_name, '')
                    )
                ),
                ''
            ),
            split_part(COALESCE(u.email, 'FLYR User'), '@', 1)
        ) AS base_name
    FROM auth.users u
    LEFT JOIN public.profiles p ON p.id = u.id
    LEFT JOIN public.workspaces owned ON owned.owner_id = u.id
    LEFT JOIN public.workspace_members member ON member.user_id = u.id
    WHERE owned.id IS NULL
      AND member.id IS NULL
)
INSERT INTO public.workspaces (id, name, owner_id)
SELECT
    gen_random_uuid(),
    CONCAT(base_name, '''s Workspace'),
    user_id
FROM users_missing_workspace;

-- 2) Ensure every workspace owner is present in workspace_members as role='owner'.
INSERT INTO public.workspace_members (workspace_id, user_id, role)
SELECT
    w.id,
    w.owner_id,
    'owner'
FROM public.workspaces w
LEFT JOIN public.workspace_members wm
    ON wm.workspace_id = w.id
   AND wm.user_id = w.owner_id
WHERE w.owner_id IS NOT NULL
  AND wm.id IS NULL;

-- 3) Backfill workspace_id on workspace-scoped records when missing.
UPDATE public.campaigns c
SET workspace_id = public.primary_workspace_id(c.owner_id)
WHERE c.workspace_id IS NULL
  AND c.owner_id IS NOT NULL
  AND public.primary_workspace_id(c.owner_id) IS NOT NULL;

UPDATE public.sessions s
SET workspace_id = public.primary_workspace_id(s.user_id)
WHERE s.workspace_id IS NULL
  AND s.user_id IS NOT NULL
  AND public.primary_workspace_id(s.user_id) IS NOT NULL;

UPDATE public.field_leads fl
SET workspace_id = public.primary_workspace_id(fl.user_id)
WHERE fl.workspace_id IS NULL
  AND fl.user_id IS NOT NULL
  AND public.primary_workspace_id(fl.user_id) IS NOT NULL;

UPDATE public.contacts ct
SET workspace_id = public.primary_workspace_id(ct.user_id)
WHERE ct.workspace_id IS NULL
  AND ct.user_id IS NOT NULL
  AND public.primary_workspace_id(ct.user_id) IS NOT NULL;

COMMIT;
