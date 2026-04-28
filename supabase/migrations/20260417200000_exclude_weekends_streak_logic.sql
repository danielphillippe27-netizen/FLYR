BEGIN;

CREATE OR REPLACE FUNCTION public.refresh_user_stats_from_sessions(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_doors_knocked INTEGER := 0;
    v_flyers INTEGER := 0;
    v_conversations INTEGER := 0;
    v_leads_created INTEGER := 0;
    v_appointments INTEGER := 0;
    v_distance_walked DOUBLE PRECISION := 0.0;
    v_time_tracked INTEGER := 0;
    v_day_streak INTEGER := 0;
    v_best_streak INTEGER := 0;
    v_streak_days JSONB := '[]'::JSONB;
    v_exclude_weekends BOOLEAN := FALSE;
    v_current_streak_threshold DATE := CURRENT_DATE - 1;
BEGIN
    SELECT COALESCE(us.exclude_weekends, FALSE)
    INTO v_exclude_weekends
    FROM public.user_settings us
    WHERE us.user_id = p_user_id;

    IF v_exclude_weekends THEN
        v_current_streak_threshold := CASE EXTRACT(ISODOW FROM CURRENT_DATE)::INTEGER
            WHEN 1 THEN CURRENT_DATE - 3
            WHEN 7 THEN CURRENT_DATE - 2
            WHEN 6 THEN CURRENT_DATE - 1
            ELSE CURRENT_DATE - 1
        END;
    END IF;

    WITH session_metrics AS (
        SELECT
            s.id,
            s.user_id,
            (s.start_time AT TIME ZONE 'UTC')::DATE AS session_day,
            GREATEST(COALESCE(s.doors_hit, s.completed_count, s.flyers_delivered, 0), 0)::INTEGER AS doors_knocked,
            GREATEST(COALESCE(s.flyers_delivered, s.completed_count, 0), 0)::INTEGER AS flyers,
            GREATEST(COALESCE(s.conversations, 0), 0)::INTEGER AS conversations,
            GREATEST(COALESCE(s.leads_created, 0), 0)::INTEGER AS leads_created,
            GREATEST(COALESCE(s.distance_meters, 0), 0)::DOUBLE PRECISION / 1000.0 AS distance_walked,
            GREATEST(
                COALESCE(
                    FLOOR(COALESCE(s.active_seconds, EXTRACT(EPOCH FROM (s.end_time - s.start_time))) / 60.0)::INTEGER,
                    0
                ),
                0
            ) AS time_tracked,
            COALESCE(appts.appointments_count, 0)::INTEGER AS appointments
        FROM public.sessions s
        LEFT JOIN LATERAL (
            SELECT COUNT(*)::INTEGER AS appointments_count
            FROM public.crm_events ce
            WHERE ce.user_id = s.user_id
              AND ce.fub_appointment_id IS NOT NULL
              AND ce.created_at >= s.start_time
              AND ce.created_at < s.end_time
        ) appts ON TRUE
        WHERE s.user_id = p_user_id
          AND s.end_time IS NOT NULL
    ),
    totals AS (
        SELECT
            COALESCE(SUM(sm.doors_knocked), 0)::INTEGER AS doors_knocked,
            COALESCE(SUM(sm.flyers), 0)::INTEGER AS flyers,
            COALESCE(SUM(sm.conversations), 0)::INTEGER AS conversations,
            COALESCE(SUM(sm.leads_created), 0)::INTEGER AS leads_created,
            COALESCE(SUM(sm.appointments), 0)::INTEGER AS appointments,
            COALESCE(SUM(sm.distance_walked), 0.0)::DOUBLE PRECISION AS distance_walked,
            COALESCE(SUM(sm.time_tracked), 0)::INTEGER AS time_tracked
        FROM session_metrics sm
    ),
    distinct_days AS (
        SELECT DISTINCT sm.session_day
        FROM session_metrics sm
        WHERE NOT v_exclude_weekends
           OR EXTRACT(ISODOW FROM sm.session_day) < 6
    ),
    streak_base AS (
        SELECT
            dd.session_day,
            LAG(dd.session_day) OVER (ORDER BY dd.session_day) AS previous_session_day
        FROM distinct_days dd
    ),
    streak_markers AS (
        SELECT
            sb.session_day,
            CASE
                WHEN sb.previous_session_day IS NULL THEN 1
                WHEN v_exclude_weekends
                    AND sb.session_day = (
                        sb.previous_session_day
                        + CASE
                            WHEN EXTRACT(ISODOW FROM sb.previous_session_day) = 5
                                THEN INTERVAL '3 days'
                            ELSE INTERVAL '1 day'
                        END
                    )::DATE THEN 0
                WHEN NOT v_exclude_weekends
                    AND sb.session_day = (sb.previous_session_day + INTERVAL '1 day')::DATE THEN 0
                ELSE 1
            END AS starts_new_group
        FROM streak_base sb
    ),
    streak_groups AS (
        SELECT
            MIN(sgm.session_day) AS streak_start,
            MAX(sgm.session_day) AS streak_end,
            COUNT(*)::INTEGER AS streak_length
        FROM (
            SELECT
                sm.session_day,
                SUM(sm.starts_new_group) OVER (ORDER BY sm.session_day) AS streak_group
            FROM streak_markers sm
        ) sgm
        GROUP BY sgm.streak_group
    ),
    streak_summary AS (
        SELECT
            COALESCE(MAX(sg.streak_length), 0)::INTEGER AS best_streak,
            COALESCE(
                MAX(
                    CASE
                        WHEN sg.streak_end >= v_current_streak_threshold THEN sg.streak_length
                        ELSE 0
                    END
                ),
                0
            )::INTEGER AS day_streak
        FROM streak_groups sg
    ),
    streak_days AS (
        SELECT COALESCE(
            jsonb_agg(to_char(dd.session_day, 'YYYY-MM-DD') ORDER BY dd.session_day DESC),
            '[]'::JSONB
        ) AS days
        FROM distinct_days dd
    )
    SELECT
        t.doors_knocked,
        t.flyers,
        t.conversations,
        t.leads_created,
        t.appointments,
        t.distance_walked,
        t.time_tracked,
        ss.day_streak,
        ss.best_streak,
        sd.days
    INTO
        v_doors_knocked,
        v_flyers,
        v_conversations,
        v_leads_created,
        v_appointments,
        v_distance_walked,
        v_time_tracked,
        v_day_streak,
        v_best_streak,
        v_streak_days
    FROM totals t
    CROSS JOIN streak_summary ss
    CROSS JOIN streak_days sd;

    INSERT INTO public.user_stats (
        user_id,
        day_streak,
        best_streak,
        streak_days,
        doors_knocked,
        flyers,
        conversations,
        leads_created,
        appointments,
        distance_walked,
        time_tracked,
        conversation_per_door,
        conversation_lead_rate,
        qr_code_scan_rate,
        qr_code_lead_rate
    )
    VALUES (
        p_user_id,
        v_day_streak,
        v_best_streak,
        v_streak_days,
        v_doors_knocked,
        v_flyers,
        v_conversations,
        v_leads_created,
        v_appointments,
        v_distance_walked,
        v_time_tracked,
        CASE
            WHEN v_doors_knocked > 0 THEN v_conversations::DOUBLE PRECISION / v_doors_knocked::DOUBLE PRECISION
            ELSE 0.0
        END,
        CASE
            WHEN v_conversations > 0 THEN v_leads_created::DOUBLE PRECISION / v_conversations::DOUBLE PRECISION
            ELSE 0.0
        END,
        0.0,
        0.0
    )
    ON CONFLICT (user_id) DO UPDATE SET
        day_streak = EXCLUDED.day_streak,
        best_streak = EXCLUDED.best_streak,
        streak_days = EXCLUDED.streak_days,
        doors_knocked = EXCLUDED.doors_knocked,
        flyers = EXCLUDED.flyers,
        conversations = EXCLUDED.conversations,
        leads_created = EXCLUDED.leads_created,
        appointments = EXCLUDED.appointments,
        distance_walked = EXCLUDED.distance_walked,
        time_tracked = EXCLUDED.time_tracked,
        conversation_per_door = EXCLUDED.conversation_per_door,
        conversation_lead_rate = EXCLUDED.conversation_lead_rate,
        qr_code_scan_rate = CASE
            WHEN EXCLUDED.flyers > 0 THEN public.user_stats.qr_codes_scanned::DOUBLE PRECISION / EXCLUDED.flyers::DOUBLE PRECISION
            ELSE 0.0
        END,
        qr_code_lead_rate = CASE
            WHEN public.user_stats.qr_codes_scanned > 0 THEN EXCLUDED.leads_created::DOUBLE PRECISION / public.user_stats.qr_codes_scanned::DOUBLE PRECISION
            ELSE 0.0
        END,
        updated_at = NOW();
END;
$$;

GRANT EXECUTE ON FUNCTION public.refresh_user_stats_from_sessions(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.refresh_user_stats_from_settings()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public.refresh_user_stats_from_sessions(NEW.user_id);
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_refresh_user_stats_from_settings ON public.user_settings;

CREATE TRIGGER trigger_refresh_user_stats_from_settings
    AFTER INSERT OR UPDATE OF exclude_weekends
    ON public.user_settings
    FOR EACH ROW
    EXECUTE FUNCTION public.refresh_user_stats_from_settings();

DO $$
DECLARE
    v_user_id UUID;
BEGIN
    FOR v_user_id IN
        SELECT DISTINCT us.user_id
        FROM public.user_settings us
        WHERE us.exclude_weekends
    LOOP
        PERFORM public.refresh_user_stats_from_sessions(v_user_id);
    END LOOP;
END;
$$;

COMMIT;
