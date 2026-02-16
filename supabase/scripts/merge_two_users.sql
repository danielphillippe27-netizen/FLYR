-- Merge two users: move all sessions and user_stats from SOURCE user into TARGET user.
-- Use when you have two accounts (e.g. one showing "You" with no activity, one with doors counted).
-- Run in Supabase SQL Editor (Dashboard → SQL Editor) as a superuser or with sufficient privileges.
--
-- 1. SOURCE = the auth.users id that currently has the activity (e.g. "Daniel Phillippe" with 7 doors)
-- 2. TARGET = the auth.users id you want to keep (the one you're signed in as, "You")
--
-- How to find IDs: Supabase Dashboard → Authentication → Users, or run:
--   SELECT id, email, raw_user_meta_data->>'full_name' FROM auth.users;
-- Table Editor → sessions: check user_id for the account that has the door counts.

DO $$
DECLARE
    v_source UUID := '00000000-0000-0000-0000-000000000000';  -- SOURCE: user with activity
    v_target UUID := '00000000-0000-0000-0000-000000000000';  -- TARGET: user to keep
    v_sessions_updated INT;
    v_stats_deleted INT;
BEGIN
    IF v_source = '00000000-0000-0000-0000-000000000000' OR v_target = '00000000-0000-0000-0000-000000000000' THEN
        RAISE EXCEPTION 'Replace v_source and v_target with real UUIDs from auth.users';
    END IF;
    IF v_source = v_target THEN
        RAISE EXCEPTION 'Source and target must be different';
    END IF;

    -- 1. Move all sessions from source to target
    UPDATE public.sessions SET user_id = v_target WHERE user_id = v_source;
    GET DIAGNOSTICS v_sessions_updated = ROW_COUNT;
    RAISE NOTICE 'Updated % session(s) to target user', v_sessions_updated;

    -- 2. Delete source user's user_stats (target will be recomputed below)
    DELETE FROM public.user_stats WHERE user_id = v_source;
    GET DIAGNOSTICS v_stats_deleted = ROW_COUNT;
    RAISE NOTICE 'Deleted % user_stats row(s) for source user', v_stats_deleted;

    -- 3. Recompute target user's user_stats from their sessions (now including former source sessions)
    INSERT INTO public.user_stats (
        user_id,
        flyers,
        conversations,
        distance_walked,
        time_tracked,
        updated_at,
        created_at
    )
    SELECT
        v_target,
        COALESCE(SUM(s.flyers_delivered), 0)::INTEGER,
        COALESCE(SUM(s.conversations), 0)::INTEGER,
        COALESCE(SUM(s.distance_meters), 0) / 1000.0,
        COALESCE(SUM(EXTRACT(EPOCH FROM (s.end_time - s.start_time)) / 60.0), 0)::INTEGER,
        NOW(),
        NOW()
    FROM public.sessions s
    WHERE s.user_id = v_target AND s.end_time IS NOT NULL
    ON CONFLICT (user_id) DO UPDATE SET
        flyers = EXCLUDED.flyers,
        conversations = EXCLUDED.conversations,
        distance_walked = EXCLUDED.distance_walked,
        time_tracked = EXCLUDED.time_tracked,
        updated_at = NOW();

    RAISE NOTICE 'Merge complete. Target user now has all sessions and updated stats.';
END $$;
