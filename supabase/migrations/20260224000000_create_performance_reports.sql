-- Performance reports: real-data weekly/monthly/yearly member reports with period-over-period deltas.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) reports table
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scope TEXT NOT NULL DEFAULT 'member' CHECK (scope IN ('member', 'workspace')),
    subject_user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    workspace_id UUID,
    period_type TEXT NOT NULL CHECK (period_type IN ('weekly', 'monthly', 'yearly')),
    period TEXT NOT NULL,
    period_start TIMESTAMPTZ NOT NULL,
    period_end TIMESTAMPTZ NOT NULL,
    metrics JSONB NOT NULL DEFAULT '{}'::jsonb,
    deltas JSONB NOT NULL DEFAULT '{}'::jsonb,
    llm_summary TEXT,
    recommendations JSONB NOT NULL DEFAULT '[]'::jsonb,
    generated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.reports
    ADD COLUMN IF NOT EXISTS scope TEXT DEFAULT 'member',
    ADD COLUMN IF NOT EXISTS subject_user_id UUID,
    ADD COLUMN IF NOT EXISTS workspace_id UUID,
    ADD COLUMN IF NOT EXISTS period_type TEXT,
    ADD COLUMN IF NOT EXISTS period TEXT,
    ADD COLUMN IF NOT EXISTS period_start TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS period_end TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS metrics JSONB DEFAULT '{}'::jsonb,
    ADD COLUMN IF NOT EXISTS deltas JSONB DEFAULT '{}'::jsonb,
    ADD COLUMN IF NOT EXISTS llm_summary TEXT,
    ADD COLUMN IF NOT EXISTS recommendations JSONB DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS generated_at TIMESTAMPTZ DEFAULT now(),
    ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now(),
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

UPDATE public.reports
SET
    scope = COALESCE(scope, 'member'),
    period_type = CASE LOWER(COALESCE(period_type, period, 'weekly'))
        WHEN 'weekly' THEN 'weekly'
        WHEN 'week' THEN 'weekly'
        WHEN 'monthly' THEN 'monthly'
        WHEN 'month' THEN 'monthly'
        WHEN 'yearly' THEN 'yearly'
        WHEN 'year' THEN 'yearly'
        ELSE 'weekly'
    END,
    period = CASE LOWER(COALESCE(period, period_type, 'weekly'))
        WHEN 'weekly' THEN 'weekly'
        WHEN 'week' THEN 'weekly'
        WHEN 'monthly' THEN 'monthly'
        WHEN 'month' THEN 'monthly'
        WHEN 'yearly' THEN 'yearly'
        WHEN 'year' THEN 'yearly'
        ELSE 'weekly'
    END,
    period_start = COALESCE(
        period_start,
        CASE LOWER(COALESCE(period_type, period, 'weekly'))
            WHEN 'monthly' THEN date_trunc('month', COALESCE(created_at, now()))
            WHEN 'month' THEN date_trunc('month', COALESCE(created_at, now()))
            WHEN 'yearly' THEN date_trunc('year', COALESCE(created_at, now()))
            WHEN 'year' THEN date_trunc('year', COALESCE(created_at, now()))
            ELSE date_trunc('week', COALESCE(created_at, now()))
        END
    ),
    period_end = COALESCE(
        period_end,
        CASE LOWER(COALESCE(period_type, period, 'weekly'))
            WHEN 'monthly' THEN date_trunc('month', COALESCE(created_at, now())) + INTERVAL '1 month'
            WHEN 'month' THEN date_trunc('month', COALESCE(created_at, now())) + INTERVAL '1 month'
            WHEN 'yearly' THEN date_trunc('year', COALESCE(created_at, now())) + INTERVAL '1 year'
            WHEN 'year' THEN date_trunc('year', COALESCE(created_at, now())) + INTERVAL '1 year'
            ELSE date_trunc('week', COALESCE(created_at, now())) + INTERVAL '1 week'
        END
    ),
    metrics = COALESCE(metrics, '{}'::jsonb),
    deltas = COALESCE(deltas, '{}'::jsonb),
    recommendations = COALESCE(recommendations, '[]'::jsonb),
    generated_at = COALESCE(generated_at, created_at, now()),
    created_at = COALESCE(created_at, now()),
    updated_at = COALESCE(updated_at, now())
WHERE
    scope IS NULL
    OR period_type IS NULL
    OR period IS NULL
    OR period_start IS NULL
    OR period_end IS NULL
    OR metrics IS NULL
    OR deltas IS NULL
    OR recommendations IS NULL
    OR generated_at IS NULL
    OR created_at IS NULL
    OR updated_at IS NULL;

ALTER TABLE public.reports
    ALTER COLUMN scope SET NOT NULL,
    ALTER COLUMN period_type SET NOT NULL,
    ALTER COLUMN period SET NOT NULL,
    ALTER COLUMN period_start SET NOT NULL,
    ALTER COLUMN period_end SET NOT NULL,
    ALTER COLUMN metrics SET NOT NULL,
    ALTER COLUMN deltas SET NOT NULL,
    ALTER COLUMN recommendations SET NOT NULL,
    ALTER COLUMN generated_at SET NOT NULL,
    ALTER COLUMN created_at SET NOT NULL,
    ALTER COLUMN updated_at SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'reports_scope_check'
          AND conrelid = 'public.reports'::regclass
    ) THEN
        ALTER TABLE public.reports
            ADD CONSTRAINT reports_scope_check
            CHECK (scope IN ('member', 'workspace'));
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'reports_period_type_check'
          AND conrelid = 'public.reports'::regclass
    ) THEN
        ALTER TABLE public.reports
            ADD CONSTRAINT reports_period_type_check
            CHECK (period_type IN ('weekly', 'monthly', 'yearly'));
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'reports_period_matches_type_check'
          AND conrelid = 'public.reports'::regclass
    ) THEN
        ALTER TABLE public.reports
            ADD CONSTRAINT reports_period_matches_type_check
            CHECK (period = period_type);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_reports_subject_period_end
    ON public.reports(subject_user_id, period_end DESC);

CREATE INDEX IF NOT EXISTS idx_reports_workspace_period_end
    ON public.reports(workspace_id, period_end DESC);

CREATE INDEX IF NOT EXISTS idx_reports_scope
    ON public.reports(scope);

CREATE INDEX IF NOT EXISTS idx_reports_subject_period_workspace
    ON public.reports(subject_user_id, period_type, period_start, period_end, workspace_id);

ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS reports_select_own ON public.reports;
CREATE POLICY reports_select_own
    ON public.reports
    FOR SELECT
    TO authenticated
    USING (auth.uid() = subject_user_id);

DROP POLICY IF EXISTS reports_insert_own ON public.reports;
CREATE POLICY reports_insert_own
    ON public.reports
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = subject_user_id);

DROP POLICY IF EXISTS reports_update_own ON public.reports;
CREATE POLICY reports_update_own
    ON public.reports
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = subject_user_id)
    WITH CHECK (auth.uid() = subject_user_id);

GRANT SELECT, INSERT, UPDATE ON public.reports TO authenticated;
GRANT ALL ON public.reports TO service_role;

DROP TRIGGER IF EXISTS update_reports_updated_at ON public.reports;
CREATE TRIGGER update_reports_updated_at
    BEFORE UPDATE ON public.reports
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

COMMENT ON TABLE public.reports IS 'Member/workspace performance reports by period with period-over-period deltas.';
COMMENT ON COLUMN public.reports.metrics IS 'Metric values for the report period.';
COMMENT ON COLUMN public.reports.deltas IS 'Delta objects against previous period: { abs, pct, trend } by metric key.';

-- ---------------------------------------------------------------------------
-- 2) helpers
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public._report_metric_delta(
    p_current NUMERIC,
    p_previous NUMERIC
)
RETURNS JSONB
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_abs NUMERIC;
    v_pct NUMERIC;
    v_trend TEXT;
BEGIN
    v_abs := COALESCE(p_current, 0) - COALESCE(p_previous, 0);

    IF COALESCE(p_previous, 0) = 0 THEN
        IF COALESCE(p_current, 0) = 0 THEN
            v_pct := 0;
        ELSE
            v_pct := 100;
        END IF;
    ELSE
        v_pct := (v_abs / NULLIF(ABS(p_previous), 0)) * 100.0;
    END IF;

    IF v_abs > 0 THEN
        v_trend := 'up';
    ELSIF v_abs < 0 THEN
        v_trend := 'down';
    ELSE
        v_trend := 'flat';
    END IF;

    RETURN jsonb_build_object(
        'abs', ROUND(v_abs::numeric, 3),
        'pct', ROUND(COALESCE(v_pct, 0)::numeric, 3),
        'trend', v_trend
    );
END;
$$;

CREATE OR REPLACE FUNCTION public._compute_member_period_metrics(
    p_subject_user_id UUID,
    p_workspace_id UUID,
    p_period_start TIMESTAMPTZ,
    p_period_end TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_doors BIGINT := 0;
    v_flyers BIGINT := 0;
    v_conversations BIGINT := 0;
    v_distance_meters DOUBLE PRECISION := 0;
    v_time_seconds DOUBLE PRECISION := 0;
    v_sessions BIGINT := 0;
    v_leads BIGINT := 0;
    v_appointments BIGINT := 0;
    v_conv_lead_rate DOUBLE PRECISION := 0;
    v_conv_appt_rate DOUBLE PRECISION := 0;
BEGIN
    SELECT
        COALESCE(SUM(COALESCE(s.completed_count, 0)), 0),
        COALESCE(SUM(COALESCE(s.flyers_delivered, s.completed_count, 0)), 0),
        COALESCE(SUM(COALESCE(s.conversations, 0)), 0),
        COALESCE(SUM(COALESCE(s.distance_meters, 0)), 0),
        COALESCE(SUM(
            CASE
                WHEN s.end_time IS NOT NULL THEN GREATEST(EXTRACT(EPOCH FROM (s.end_time - s.start_time)), 0)
                ELSE GREATEST(COALESCE(s.active_seconds, 0), 0)
            END
        ), 0),
        COALESCE(COUNT(*), 0)
    INTO
        v_doors,
        v_flyers,
        v_conversations,
        v_distance_meters,
        v_time_seconds,
        v_sessions
    FROM public.sessions s
    WHERE s.user_id = p_subject_user_id
      AND s.start_time >= p_period_start
      AND s.start_time < p_period_end
      AND (p_workspace_id IS NULL OR s.workspace_id = p_workspace_id);

    SELECT COALESCE(COUNT(*), 0)
    INTO v_leads
    FROM public.contacts c
    WHERE c.user_id = p_subject_user_id
      AND c.created_at >= p_period_start
      AND c.created_at < p_period_end
      AND (p_workspace_id IS NULL OR c.workspace_id = p_workspace_id);

    SELECT COALESCE(COUNT(*), 0)
    INTO v_appointments
    FROM public.crm_events ce
    WHERE ce.user_id = p_subject_user_id
      AND ce.fub_appointment_id IS NOT NULL
      AND ce.created_at >= p_period_start
      AND ce.created_at < p_period_end;

    IF v_conversations > 0 THEN
        v_conv_lead_rate := (v_leads::DOUBLE PRECISION / v_conversations::DOUBLE PRECISION) * 100.0;
        v_conv_appt_rate := (v_appointments::DOUBLE PRECISION / v_conversations::DOUBLE PRECISION) * 100.0;
    END IF;

    RETURN jsonb_build_object(
        'doors_knocked', v_doors,
        'flyers_delivered', v_flyers,
        'conversations', v_conversations,
        'leads_created', v_leads,
        'appointments_set', v_appointments,
        'distance_walked', ROUND((v_distance_meters / 1000.0)::numeric, 3),
        'time_spent_seconds', ROUND(v_time_seconds::numeric, 0),
        'sessions_count', v_sessions,
        'conversation_to_lead_rate', ROUND(v_conv_lead_rate::numeric, 3),
        'conversation_to_appointment_rate', ROUND(v_conv_appt_rate::numeric, 3)
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public._report_metric_delta(NUMERIC, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION public._compute_member_period_metrics(UUID, UUID, TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3) generation RPCs
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.generate_member_performance_report(
    p_subject_user_id UUID DEFAULT auth.uid(),
    p_workspace_id UUID DEFAULT NULL,
    p_period_type TEXT DEFAULT 'weekly',
    p_force BOOLEAN DEFAULT false
)
RETURNS public.reports
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_subject_user_id UUID;
    v_period_type TEXT;
    v_period_start TIMESTAMPTZ;
    v_period_end TIMESTAMPTZ;
    v_previous_start TIMESTAMPTZ;
    v_previous_end TIMESTAMPTZ;
    v_current_metrics JSONB;
    v_previous_metrics JSONB;
    v_deltas JSONB;
    v_summary TEXT;
    v_recommendations JSONB := '[]'::jsonb;
    v_row public.reports;
    v_conv_lead_rate DOUBLE PRECISION := 0;
    v_conv_appt_rate DOUBLE PRECISION := 0;
BEGIN
    v_subject_user_id := COALESCE(p_subject_user_id, auth.uid());

    IF v_subject_user_id IS NULL THEN
        RAISE EXCEPTION 'No subject user id available for report generation';
    END IF;

    IF auth.uid() IS NOT NULL AND auth.uid() <> v_subject_user_id THEN
        RAISE EXCEPTION 'You can only generate your own reports';
    END IF;

    v_period_type := LOWER(TRIM(COALESCE(p_period_type, 'weekly')));

    CASE v_period_type
        WHEN 'weekly' THEN
            v_period_start := date_trunc('week', now());
            v_period_end := v_period_start + INTERVAL '1 week';
            v_previous_start := v_period_start - INTERVAL '1 week';
            v_previous_end := v_period_start;
        WHEN 'monthly' THEN
            v_period_start := date_trunc('month', now());
            v_period_end := v_period_start + INTERVAL '1 month';
            v_previous_start := v_period_start - INTERVAL '1 month';
            v_previous_end := v_period_start;
        WHEN 'yearly' THEN
            v_period_start := date_trunc('year', now());
            v_period_end := v_period_start + INTERVAL '1 year';
            v_previous_start := v_period_start - INTERVAL '1 year';
            v_previous_end := v_period_start;
        ELSE
            RAISE EXCEPTION 'Unsupported period_type: %', p_period_type;
    END CASE;

    IF NOT p_force THEN
        SELECT r.*
        INTO v_row
        FROM public.reports r
        WHERE r.scope = 'member'
          AND r.subject_user_id = v_subject_user_id
          AND r.period_type = v_period_type
          AND r.period_start = v_period_start
          AND r.period_end = v_period_end
          AND (
                (p_workspace_id IS NULL AND r.workspace_id IS NULL)
                OR r.workspace_id = p_workspace_id
          )
          AND r.generated_at >= now() - INTERVAL '15 minutes'
        ORDER BY r.generated_at DESC
        LIMIT 1;

        IF FOUND THEN
            RETURN v_row;
        END IF;
    END IF;

    v_current_metrics := public._compute_member_period_metrics(v_subject_user_id, p_workspace_id, v_period_start, v_period_end);
    v_previous_metrics := public._compute_member_period_metrics(v_subject_user_id, p_workspace_id, v_previous_start, v_previous_end);

    v_deltas := jsonb_build_object(
        'doors_knocked', public._report_metric_delta((v_current_metrics->>'doors_knocked')::numeric, (v_previous_metrics->>'doors_knocked')::numeric),
        'flyers_delivered', public._report_metric_delta((v_current_metrics->>'flyers_delivered')::numeric, (v_previous_metrics->>'flyers_delivered')::numeric),
        'conversations', public._report_metric_delta((v_current_metrics->>'conversations')::numeric, (v_previous_metrics->>'conversations')::numeric),
        'leads_created', public._report_metric_delta((v_current_metrics->>'leads_created')::numeric, (v_previous_metrics->>'leads_created')::numeric),
        'appointments_set', public._report_metric_delta((v_current_metrics->>'appointments_set')::numeric, (v_previous_metrics->>'appointments_set')::numeric),
        'distance_walked', public._report_metric_delta((v_current_metrics->>'distance_walked')::numeric, (v_previous_metrics->>'distance_walked')::numeric),
        'time_spent_seconds', public._report_metric_delta((v_current_metrics->>'time_spent_seconds')::numeric, (v_previous_metrics->>'time_spent_seconds')::numeric),
        'sessions_count', public._report_metric_delta((v_current_metrics->>'sessions_count')::numeric, (v_previous_metrics->>'sessions_count')::numeric),
        'conversation_to_lead_rate', public._report_metric_delta((v_current_metrics->>'conversation_to_lead_rate')::numeric, (v_previous_metrics->>'conversation_to_lead_rate')::numeric),
        'conversation_to_appointment_rate', public._report_metric_delta((v_current_metrics->>'conversation_to_appointment_rate')::numeric, (v_previous_metrics->>'conversation_to_appointment_rate')::numeric)
    );

    v_conv_lead_rate := COALESCE((v_current_metrics->>'conversation_to_lead_rate')::double precision, 0);
    v_conv_appt_rate := COALESCE((v_current_metrics->>'conversation_to_appointment_rate')::double precision, 0);

    v_summary := format(
        '%s report: %s doors, %s flyers, %s conversations, %s leads, %s appointments.',
        INITCAP(v_period_type),
        COALESCE(v_current_metrics->>'doors_knocked', '0'),
        COALESCE(v_current_metrics->>'flyers_delivered', '0'),
        COALESCE(v_current_metrics->>'conversations', '0'),
        COALESCE(v_current_metrics->>'leads_created', '0'),
        COALESCE(v_current_metrics->>'appointments_set', '0')
    );

    IF v_conv_lead_rate < 15 THEN
        v_recommendations := v_recommendations || jsonb_build_array('Raise conversation-to-lead conversion with stronger qualification questions and clearer next steps.');
    END IF;

    IF v_conv_appt_rate < 8 THEN
        v_recommendations := v_recommendations || jsonb_build_array('Ask for appointment commitment earlier in high-intent conversations to improve booked appointments.');
    END IF;

    IF COALESCE((v_current_metrics->>'conversations')::double precision, 0) < COALESCE((v_previous_metrics->>'conversations')::double precision, 0) THEN
        v_recommendations := v_recommendations || jsonb_build_array('Conversation volume is down versus the previous period. Focus on higher-contact neighborhoods or stronger openers.');
    END IF;

    IF jsonb_array_length(v_recommendations) = 0 THEN
        v_recommendations := jsonb_build_array('Maintain current pace and focus on improving conversion rates for compounding gains.');
    END IF;

    DELETE FROM public.reports r
    WHERE r.scope = 'member'
      AND r.subject_user_id = v_subject_user_id
      AND r.period_type = v_period_type
      AND r.period_start = v_period_start
      AND r.period_end = v_period_end
      AND (
            (p_workspace_id IS NULL AND r.workspace_id IS NULL)
            OR r.workspace_id = p_workspace_id
      );

    INSERT INTO public.reports (
        scope,
        subject_user_id,
        workspace_id,
        period_type,
        period,
        period_start,
        period_end,
        metrics,
        deltas,
        llm_summary,
        recommendations,
        generated_at,
        created_at,
        updated_at
    )
    VALUES (
        'member',
        v_subject_user_id,
        p_workspace_id,
        v_period_type,
        v_period_type,
        v_period_start,
        v_period_end,
        v_current_metrics,
        v_deltas,
        v_summary,
        v_recommendations,
        now(),
        now(),
        now()
    )
    RETURNING * INTO v_row;

    RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.generate_my_performance_reports(
    p_workspace_id UUID DEFAULT NULL,
    p_force BOOLEAN DEFAULT false
)
RETURNS SETOF public.reports
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := auth.uid();

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    RETURN QUERY SELECT * FROM public.generate_member_performance_report(v_user_id, p_workspace_id, 'weekly', p_force);
    RETURN QUERY SELECT * FROM public.generate_member_performance_report(v_user_id, p_workspace_id, 'monthly', p_force);
    RETURN QUERY SELECT * FROM public.generate_member_performance_report(v_user_id, p_workspace_id, 'yearly', p_force);
END;
$$;

GRANT EXECUTE ON FUNCTION public.generate_member_performance_report(UUID, UUID, TEXT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_my_performance_reports(UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_member_performance_report(UUID, UUID, TEXT, BOOLEAN) TO service_role;
GRANT EXECUTE ON FUNCTION public.generate_my_performance_reports(UUID, BOOLEAN) TO service_role;

COMMENT ON FUNCTION public.generate_member_performance_report(UUID, UUID, TEXT, BOOLEAN) IS 'Generates one real-data member report for weekly/monthly/yearly and compares against prior period.';
COMMENT ON FUNCTION public.generate_my_performance_reports(UUID, BOOLEAN) IS 'Generates the caller''s weekly, monthly, and yearly member reports from real data.';

COMMIT;

NOTIFY pgrst, 'reload schema';
