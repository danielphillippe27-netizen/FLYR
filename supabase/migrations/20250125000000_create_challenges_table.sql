-- FLYR Challenges Migration
-- Creates table for challenge system with door knock, flyer drop, and follow-up challenges

-- 1. Create challenges table
CREATE TABLE IF NOT EXISTS public.challenges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    participant_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    type TEXT NOT NULL CHECK (type IN ('door_knock', 'flyer_drop', 'follow_up', 'custom')),
    title TEXT NOT NULL,
    description TEXT,
    goal_count INTEGER NOT NULL,
    progress_count INTEGER NOT NULL DEFAULT 0,
    time_limit_hours INTEGER,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'failed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ
);

-- 2. Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_challenges_participant_id ON public.challenges(participant_id);
CREATE INDEX IF NOT EXISTS idx_challenges_creator_id ON public.challenges(creator_id);
CREATE INDEX IF NOT EXISTS idx_challenges_status ON public.challenges(status);
CREATE INDEX IF NOT EXISTS idx_challenges_expires_at ON public.challenges(expires_at);
CREATE INDEX IF NOT EXISTS idx_challenges_type ON public.challenges(type);

-- 3. Enable RLS
ALTER TABLE public.challenges ENABLE ROW LEVEL SECURITY;

-- 4. RLS Policies for challenges
-- Users can read challenges where they are creator or participant
DROP POLICY IF EXISTS "challenges_select_own" ON public.challenges;
CREATE POLICY "challenges_select_own"
    ON public.challenges
    FOR SELECT
    TO authenticated
    USING (
        auth.uid() = creator_id OR 
        auth.uid() = participant_id
    );

-- Users can insert challenges they create
DROP POLICY IF EXISTS "challenges_insert_own" ON public.challenges;
CREATE POLICY "challenges_insert_own"
    ON public.challenges
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = creator_id);

-- Users can update challenges they created or are participating in
DROP POLICY IF EXISTS "challenges_update_own" ON public.challenges;
CREATE POLICY "challenges_update_own"
    ON public.challenges
    FOR UPDATE
    TO authenticated
    USING (
        auth.uid() = creator_id OR 
        auth.uid() = participant_id
    )
    WITH CHECK (
        auth.uid() = creator_id OR 
        auth.uid() = participant_id
    );

-- 5. Grant permissions
GRANT SELECT, INSERT, UPDATE ON public.challenges TO authenticated;

-- 6. Add comments
COMMENT ON TABLE public.challenges IS 'User challenges for door knocking, flyer drops, and follow-ups';
COMMENT ON COLUMN public.challenges.type IS 'Type of challenge: door_knock, flyer_drop, follow_up, or custom';
COMMENT ON COLUMN public.challenges.status IS 'Challenge status: active, completed, or failed';
COMMENT ON COLUMN public.challenges.time_limit_hours IS 'Time limit in hours from creation (null = no limit)';
COMMENT ON COLUMN public.challenges.expires_at IS 'Calculated expiration timestamp (created_at + time_limit_hours)';



