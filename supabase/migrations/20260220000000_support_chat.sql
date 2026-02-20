-- Support chat: threads and messages for in-app support, with RLS and optional trigger.
-- One thread per user; support users (profiles.is_support) can see all threads and reply.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Add is_support to profiles (if missing)
-- ---------------------------------------------------------------------------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_support boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.profiles.is_support IS 'If true, user can access Support Inbox and reply to all threads';

-- Allow support staff to read all profiles (for Support Inbox thread list display)
DROP POLICY IF EXISTS "profiles_select_support" ON public.profiles;
CREATE POLICY "profiles_select_support"
  ON public.profiles
  FOR SELECT
  TO authenticated
  USING (public.is_support() = true);

-- Note: If your existing RLS is "auth.uid() = id" only, add this policy so support can read any profile.
-- If you use a single policy with OR, ensure: (id = auth.uid() OR public.is_support()).

-- ---------------------------------------------------------------------------
-- 2) support_threads
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.support_threads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed')),
  last_message_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_support_threads_user_id ON public.support_threads(user_id);
CREATE INDEX IF NOT EXISTS idx_support_threads_last_message_at ON public.support_threads(last_message_at DESC);

ALTER TABLE public.support_threads ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- 3) support_messages
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.support_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id uuid NOT NULL REFERENCES public.support_threads(id) ON DELETE CASCADE,
  sender_type text NOT NULL CHECK (sender_type IN ('user', 'support')),
  sender_user_id uuid NULL REFERENCES public.profiles(id),
  body text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_support_messages_thread_created ON public.support_messages(thread_id, created_at ASC);

ALTER TABLE public.support_messages ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- 4) Helper: is_support()
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_support()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.is_support = true
  );
$$;

-- ---------------------------------------------------------------------------
-- 5) RLS policies: support_threads
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "support_threads_select" ON public.support_threads;
CREATE POLICY "support_threads_select"
  ON public.support_threads
  FOR SELECT
  TO authenticated
  USING (
    (user_id = auth.uid()) OR public.is_support()
  );

DROP POLICY IF EXISTS "support_threads_insert" ON public.support_threads;
CREATE POLICY "support_threads_insert"
  ON public.support_threads
  FOR INSERT
  TO authenticated
  WITH CHECK (
    (user_id = auth.uid()) OR public.is_support()
  );

DROP POLICY IF EXISTS "support_threads_update" ON public.support_threads;
CREATE POLICY "support_threads_update"
  ON public.support_threads
  FOR UPDATE
  TO authenticated
  USING (
    (user_id = auth.uid()) OR public.is_support()
  )
  WITH CHECK (
    (user_id = auth.uid()) OR public.is_support()
  );

-- ---------------------------------------------------------------------------
-- 6) RLS policies: support_messages
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "support_messages_select" ON public.support_messages;
CREATE POLICY "support_messages_select"
  ON public.support_messages
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.support_threads t
      WHERE t.id = thread_id AND (t.user_id = auth.uid() OR public.is_support())
    )
  );

DROP POLICY IF EXISTS "support_messages_insert" ON public.support_messages;
CREATE POLICY "support_messages_insert"
  ON public.support_messages
  FOR INSERT
  TO authenticated
  WITH CHECK (
    (sender_type = 'user' AND EXISTS (
      SELECT 1 FROM public.support_threads t
      WHERE t.id = thread_id AND t.user_id = auth.uid()
    ))
    OR
    (sender_type = 'support' AND public.is_support())
  );

-- ---------------------------------------------------------------------------
-- 7) Trigger: update support_threads.last_message_at on new message
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.support_thread_last_message_at()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.support_threads
  SET last_message_at = NEW.created_at
  WHERE id = NEW.thread_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS support_messages_last_message_at ON public.support_messages;
CREATE TRIGGER support_messages_last_message_at
  AFTER INSERT ON public.support_messages
  FOR EACH ROW
  EXECUTE FUNCTION public.support_thread_last_message_at();

-- ---------------------------------------------------------------------------
-- 8) Realtime: allow postgres_changes on support_messages for subscribed threads
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'support_messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.support_messages;
  END IF;
END $$;

COMMIT;
