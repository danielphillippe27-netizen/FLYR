BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_get_campaign_address_status_rows_for_farm_cycle(
    p_campaign_id uuid,
    p_cycle_number integer
)
RETURNS TABLE (
    id uuid,
    campaign_address_id uuid,
    campaign_id uuid,
    status text,
    last_visited_at timestamptz,
    notes text,
    visit_count bigint,
    last_action_by uuid,
    last_session_id uuid,
    last_home_event_id uuid,
    created_at timestamptz,
    updated_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
WITH scoped_session_events AS (
    SELECT
        se.id,
        se.address_id AS campaign_address_id,
        s.campaign_id,
        COALESCE(NULLIF(TRIM(se.metadata ->> 'address_status'), ''), 'none') AS status,
        se.created_at,
        NULLIF(TRIM(se.metadata ->> 'notes'), '') AS notes,
        se.user_id AS last_action_by,
        se.session_id AS last_session_id,
        se.id AS last_home_event_id
    FROM public.session_events se
    JOIN public.sessions s
        ON s.id = se.session_id
    JOIN public.farm_touches ft
        ON ft.id = s.farm_touch_id
    WHERE s.campaign_id = p_campaign_id
      AND ft.cycle_number = p_cycle_number
      AND se.address_id IS NOT NULL
      AND COALESCE(NULLIF(TRIM(se.metadata ->> 'address_status'), ''), '') <> ''
),
scoped_farm_outcomes AS (
    SELECT
        fta.id,
        ca.id AS campaign_address_id,
        ca.campaign_id,
        fta.status,
        fta.occurred_at AS created_at,
        NULLIF(TRIM(fta.notes), '') AS notes,
        fta.created_by AS last_action_by,
        ft.session_id AS last_session_id,
        NULL::uuid AS last_home_event_id
    FROM public.farm_touch_addresses fta
    JOIN public.farm_touches ft
        ON ft.id = fta.farm_touch_id
    JOIN public.farm_addresses fa
        ON fa.id = fta.farm_address_id
    JOIN public.campaign_addresses ca
        ON ca.id = COALESCE(fta.campaign_address_id, fa.campaign_address_id)
    WHERE ft.cycle_number = p_cycle_number
      AND ca.campaign_id = p_campaign_id
      AND fta.status <> 'none'
),
scoped_events AS (
    SELECT * FROM scoped_session_events
    UNION ALL
    SELECT * FROM scoped_farm_outcomes
),
latest AS (
    SELECT DISTINCT ON (campaign_address_id)
        id,
        campaign_address_id,
        campaign_id,
        status,
        created_at AS last_visited_at,
        notes,
        last_action_by,
        last_session_id,
        last_home_event_id,
        created_at,
        created_at AS updated_at
    FROM scoped_events
    ORDER BY campaign_address_id, created_at DESC, id DESC
),
counts AS (
    SELECT
        campaign_address_id,
        COUNT(*) FILTER (WHERE status <> 'none') AS visit_count
    FROM scoped_events
    GROUP BY campaign_address_id
)
SELECT
    COALESCE(latest.id, latest.campaign_address_id) AS id,
    latest.campaign_address_id,
    latest.campaign_id,
    latest.status,
    latest.last_visited_at,
    latest.notes,
    COALESCE(counts.visit_count, 0) AS visit_count,
    latest.last_action_by,
    latest.last_session_id,
    latest.last_home_event_id,
    latest.created_at,
    latest.updated_at
FROM latest
LEFT JOIN counts
    ON counts.campaign_address_id = latest.campaign_address_id;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_campaign_address_status_rows_for_farm_cycle(uuid, integer)
    TO authenticated, service_role;

COMMIT;
