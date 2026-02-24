-- get_or_create_support_thread: RPC to create support thread as current user, bypassing RLS
-- so the app always succeeds when the user is authenticated (avoids "new row violates row-level security").
-- The function only creates a row for auth.uid() and ensures profile exists.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_or_create_support_thread()
RETURNS public.support_threads
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid;
  row_count int;
  out_row public.support_threads;
BEGIN
  uid := auth.uid();
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Ensure profile exists (support_threads.user_id FK references profiles.id)
  INSERT INTO public.profiles (id, email, full_name, avatar_url, created_at, updated_at)
  SELECT
    uid,
    COALESCE(au.email, ''),
    COALESCE(au.raw_user_meta_data->>'full_name', au.raw_user_meta_data->>'name'),
    au.raw_user_meta_data->>'avatar_url',
    now(),
    now()
  FROM auth.users au
  WHERE au.id = uid
  ON CONFLICT (id) DO NOTHING;

  -- Return existing thread if any
  SELECT t.* INTO out_row
  FROM public.support_threads t
  WHERE t.user_id = uid
  LIMIT 1;

  IF FOUND THEN
    RETURN out_row;
  END IF;

  -- Insert new thread (we are SECURITY DEFINER so RLS does not apply)
  INSERT INTO public.support_threads (id, user_id, status, last_message_at, created_at)
  VALUES (gen_random_uuid(), uid, 'open', now(), now())
  RETURNING * INTO out_row;

  RETURN out_row;
END;
$$;

-- Allow authenticated users to call this
GRANT EXECUTE ON FUNCTION public.get_or_create_support_thread() TO authenticated;

COMMENT ON FUNCTION public.get_or_create_support_thread() IS 'Get existing support thread for current user or create one; avoids RLS insert issues from client.';

COMMIT;
