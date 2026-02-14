-- Seed 10 mock leaderboard entries for UI development
-- Run this in Supabase Dashboard → SQL Editor (runs with elevated privileges so RLS is bypassed)
-- Requires: 20250207000000_fix_leaderboard_and_stats.sql and sessions table migrations applied
--
-- To reset and re-seed: run the "Clean up" block below first, then run this whole file again.

-- =============================================================================
-- OPTIONAL: Clean up previous mock data (run this first if re-seeding)
-- =============================================================================
/*
DELETE FROM public.sessions WHERE user_id IN (
    SELECT id FROM auth.users WHERE email LIKE 'mock_leaderboard_%@example.com'
);
DELETE FROM auth.identities WHERE user_id IN (
    SELECT id FROM auth.users WHERE email LIKE 'mock_leaderboard_%@example.com'
);
DELETE FROM auth.users WHERE email LIKE 'mock_leaderboard_%@example.com';
*/

-- Ensure pgcrypto is available for password hashing
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Fixed UUIDs so re-running doesn't create duplicate users; sessions are deleted/re-created by cleanup
DO $$
DECLARE
    v_instance_id UUID;
    v_start_time TIMESTAMPTZ := date_trunc('month', NOW()) + interval '1 day'; -- first day of current month
    v_end_time TIMESTAMPTZ := v_start_time + interval '1 hour';
    v_path_geojson TEXT := '{"type":"LineString","coordinates":[[-79.3,43.6],[-79.31,43.61]]}';
    v_user_ids UUID[] := ARRAY[
        'a1000001-0000-4000-8000-000000000001'::UUID, 'a1000002-0000-4000-8000-000000000002'::UUID,
        'a1000003-0000-4000-8000-000000000003'::UUID, 'a1000004-0000-4000-8000-000000000004'::UUID,
        'a1000005-0000-4000-8000-000000000005'::UUID, 'a1000006-0000-4000-8000-000000000006'::UUID,
        'a1000007-0000-4000-8000-000000000007'::UUID, 'a1000008-0000-4000-8000-000000000008'::UUID,
        'a1000009-0000-4000-8000-000000000009'::UUID, 'a1000010-0000-4000-8000-000000000010'::UUID
    ];
    v_names TEXT[] := ARRAY[
        'Alex Rivera', 'Jordan Kim', 'Sam Chen', 'Morgan Taylor', 'Casey Lee',
        'Riley Walsh', 'Quinn Davis', 'Avery Brown', 'Skyler Jones', 'Blake Martinez'
    ];
    v_flyers INTEGER[] := ARRAY[420, 380, 310, 285, 260, 240, 195, 170, 140, 115];
    v_convos INTEGER[] := ARRAY[48, 42, 35, 31, 28, 24, 20, 17, 14, 11];
    v_dist_km DOUBLE PRECISION[] := ARRAY[12.5, 11.2, 9.8, 8.5, 7.9, 7.2, 6.1, 5.4, 4.2, 3.8];
    i INT;
BEGIN
    SELECT id INTO v_instance_id FROM auth.instances LIMIT 1;
    IF v_instance_id IS NULL THEN
        v_instance_id := '00000000-0000-0000-0000-000000000000';
    END IF;

    -- Remove existing mock sessions so re-running this script refreshes leaderboard data
    DELETE FROM public.sessions
    WHERE user_id IN (SELECT id FROM auth.users WHERE email LIKE 'mock_leaderboard_%@example.com');

    -- Insert 10 mock users into auth.users
    FOR i IN 1..10 LOOP
        INSERT INTO auth.users (
            id,
            instance_id,
            aud,
            role,
            email,
            encrypted_password,
            email_confirmed_at,
            raw_user_meta_data,
            raw_app_meta_data,
            created_at,
            updated_at,
            confirmation_token,
            email_change,
            email_change_token_new,
            recovery_token
        ) VALUES (
            v_user_ids[i],
            v_instance_id,
            'authenticated',
            'authenticated',
            'mock_leaderboard_' || i || '@example.com',
            crypt('MockPass123!', gen_salt('bf')),
            NOW(),
            jsonb_build_object('full_name', v_names[i]),
            '{"provider":"email","providers":["email"]}'::jsonb,
            NOW(),
            NOW(),
            '',
            '',
            '',
            ''
        )
        ON CONFLICT (id) DO NOTHING;
    END LOOP;

    -- Link identities so auth sees them (optional for leaderboard display, but keeps auth consistent)
    FOR i IN 1..10 LOOP
        BEGIN
            INSERT INTO auth.identities (
                id,
                user_id,
                identity_data,
                provider,
                provider_id,
                last_sign_in_at,
                created_at,
                updated_at
            ) VALUES (
                gen_random_uuid(),
                v_user_ids[i],
                jsonb_build_object(
                    'sub', v_user_ids[i]::text,
                    'email', 'mock_leaderboard_' || i || '@example.com',
                    'email_verified', true
                ),
                'email',
                v_user_ids[i]::text,
                NOW(),
                NOW(),
                NOW()
            );
        EXCEPTION WHEN unique_violation THEN NULL; -- ignore if re-running before cleanup
        END;
    END LOOP;

    -- Insert one session per user (current month) so get_leaderboard returns 10 rows for Monthly
    FOR i IN 1..10 LOOP
        INSERT INTO public.sessions (
            user_id,
            start_time,
            end_time,
            distance_meters,
            goal_type,
            goal_amount,
            path_geojson,
            flyers_delivered,
            conversations
        ) VALUES (
            v_user_ids[i],
            v_start_time,
            v_end_time,
            v_dist_km[i] * 1000.0,
            'flyers',
            v_flyers[i],
            v_path_geojson,
            v_flyers[i],
            v_convos[i]
        );
    END LOOP;

    RAISE NOTICE 'Inserted 10 mock leaderboard users and sessions. Refresh the Monthly leaderboard in the app.';
END $$;
