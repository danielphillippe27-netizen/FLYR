BEGIN;

ALTER TABLE public.farm_touches
    ADD COLUMN IF NOT EXISTS cycle_number integer;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name = 'farm_phases'
    ) AND EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'farm_touches'
          AND column_name = 'phase_id'
    ) THEN
        EXECUTE $sql$
            WITH phase_order AS (
                SELECT
                    fp.id,
                    fp.farm_id,
                    COALESCE(
                        NULLIF(regexp_replace(COALESCE(fp.phase_name, ''), '[^0-9]', '', 'g'), '')::integer,
                        DENSE_RANK() OVER (
                            PARTITION BY fp.farm_id
                            ORDER BY fp.start_date, fp.created_at, fp.id
                        )
                    ) AS resolved_cycle_number
                FROM public.farm_phases fp
            ),
            phase_backfill AS (
                SELECT
                    ft.id,
                    po.resolved_cycle_number
                FROM public.farm_touches ft
                JOIN phase_order po
                    ON po.id = ft.phase_id
                WHERE ft.cycle_number IS NULL
            )
            UPDATE public.farm_touches ft
            SET cycle_number = phase_backfill.resolved_cycle_number
            FROM phase_backfill
            WHERE ft.id = phase_backfill.id
        $sql$;
    END IF;
END $$;

WITH farm_touch_order AS (
    SELECT
        ft.id,
        GREATEST(
            1,
            CEIL(
                ROW_NUMBER() OVER (
                    PARTITION BY ft.farm_id
                    ORDER BY COALESCE(ft.completed_at, ft.date::timestamptz, ft.created_at), ft.created_at, ft.id
                )::numeric
                / GREATEST(COALESCE(f.touches_per_interval, f.frequency, 1), 1)
            )::integer
        ) AS resolved_cycle_number
    FROM public.farm_touches ft
    JOIN public.farms f
        ON f.id = ft.farm_id
    WHERE ft.cycle_number IS NULL
)
UPDATE public.farm_touches ft
SET cycle_number = farm_touch_order.resolved_cycle_number
FROM farm_touch_order
WHERE ft.id = farm_touch_order.id;

ALTER TABLE public.farm_touches
    ALTER COLUMN cycle_number SET DEFAULT 1;

CREATE INDEX IF NOT EXISTS idx_farm_touches_farm_cycle_number
    ON public.farm_touches (farm_id, cycle_number DESC, date DESC);

CREATE TABLE IF NOT EXISTS public.farm_addresses (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_id uuid NOT NULL REFERENCES public.farms(id) ON DELETE CASCADE,
    campaign_address_id uuid,
    gers_id text,
    formatted text NOT NULL,
    house_number text,
    street_name text,
    locality text,
    region text,
    postal_code text,
    source text NOT NULL DEFAULT 'map',
    latitude double precision,
    longitude double precision,
    geom jsonb,
    visited_count integer NOT NULL DEFAULT 0,
    last_visited_at timestamptz,
    last_touch_id uuid REFERENCES public.farm_touches(id) ON DELETE SET NULL,
    last_outcome_status text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_farm_addresses_farm_id
    ON public.farm_addresses(farm_id);

CREATE INDEX IF NOT EXISTS idx_farm_addresses_campaign_address_id
    ON public.farm_addresses(campaign_address_id);

CREATE INDEX IF NOT EXISTS idx_farm_addresses_farm_campaign_address
    ON public.farm_addresses(farm_id, campaign_address_id);

ALTER TABLE public.farm_addresses ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'farm_addresses'
          AND policyname = 'farm_addresses_owner_select'
    ) THEN
        CREATE POLICY farm_addresses_owner_select
            ON public.farm_addresses
            FOR SELECT
            USING (
                EXISTS (
                    SELECT 1
                    FROM public.farms f
                    WHERE f.id = farm_addresses.farm_id
                      AND (
                          f.owner_id = auth.uid()
                          OR (f.workspace_id IS NOT NULL AND public.is_workspace_member(f.workspace_id))
                      )
                )
            );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'farm_addresses'
          AND policyname = 'farm_addresses_owner_insert'
    ) THEN
        CREATE POLICY farm_addresses_owner_insert
            ON public.farm_addresses
            FOR INSERT
            WITH CHECK (
                EXISTS (
                    SELECT 1
                    FROM public.farms f
                    WHERE f.id = farm_addresses.farm_id
                      AND (
                          f.owner_id = auth.uid()
                          OR (f.workspace_id IS NOT NULL AND public.is_workspace_member(f.workspace_id))
                      )
                )
            );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'farm_addresses'
          AND policyname = 'farm_addresses_owner_update'
    ) THEN
        CREATE POLICY farm_addresses_owner_update
            ON public.farm_addresses
            FOR UPDATE
            USING (
                EXISTS (
                    SELECT 1
                    FROM public.farms f
                    WHERE f.id = farm_addresses.farm_id
                      AND (
                          f.owner_id = auth.uid()
                          OR (f.workspace_id IS NOT NULL AND public.is_workspace_member(f.workspace_id))
                      )
                )
            )
            WITH CHECK (
                EXISTS (
                    SELECT 1
                    FROM public.farms f
                    WHERE f.id = farm_addresses.farm_id
                      AND (
                          f.owner_id = auth.uid()
                          OR (f.workspace_id IS NOT NULL AND public.is_workspace_member(f.workspace_id))
                      )
                )
            );
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.farm_touch_addresses (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_id uuid NOT NULL REFERENCES public.farms(id) ON DELETE CASCADE,
    farm_touch_id uuid NOT NULL REFERENCES public.farm_touches(id) ON DELETE CASCADE,
    farm_address_id uuid NOT NULL REFERENCES public.farm_addresses(id) ON DELETE CASCADE,
    campaign_address_id uuid,
    status text NOT NULL DEFAULT 'delivered',
    notes text,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid DEFAULT auth.uid(),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT farm_touch_addresses_status_check CHECK (
        status IN (
            'none',
            'no_answer',
            'delivered',
            'talked',
            'appointment',
            'do_not_knock',
            'future_seller',
            'hot_lead'
        )
    ),
    CONSTRAINT farm_touch_addresses_touch_address_unique UNIQUE (farm_touch_id, farm_address_id)
);

CREATE INDEX IF NOT EXISTS idx_farm_touch_addresses_farm_id
    ON public.farm_touch_addresses(farm_id);

CREATE INDEX IF NOT EXISTS idx_farm_touch_addresses_touch_id
    ON public.farm_touch_addresses(farm_touch_id);

CREATE INDEX IF NOT EXISTS idx_farm_touch_addresses_address_id
    ON public.farm_touch_addresses(farm_address_id);

ALTER TABLE public.farm_touch_addresses ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'farm_touch_addresses'
          AND policyname = 'farm_touch_addresses_owner_select'
    ) THEN
        CREATE POLICY farm_touch_addresses_owner_select
            ON public.farm_touch_addresses
            FOR SELECT
            USING (
                EXISTS (
                    SELECT 1
                    FROM public.farms f
                    WHERE f.id = farm_touch_addresses.farm_id
                      AND (
                          f.owner_id = auth.uid()
                          OR (f.workspace_id IS NOT NULL AND public.is_workspace_member(f.workspace_id))
                      )
                )
            );
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.record_farm_address_outcome(
    p_farm_id uuid,
    p_farm_touch_id uuid,
    p_farm_address_id uuid DEFAULT NULL,
    p_campaign_address_id uuid DEFAULT NULL,
    p_status text DEFAULT 'delivered',
    p_notes text DEFAULT NULL,
    p_occurred_at timestamptz DEFAULT now()
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_status text := lower(trim(coalesce(p_status, 'delivered')));
    v_notes text := nullif(trim(coalesce(p_notes, '')), '');
    v_farm_address_id uuid := p_farm_address_id;
    v_visit_count integer := 0;
    v_latest_visit record;
    v_touch_farm_id uuid;
    v_address_farm_id uuid;
    v_touch_homes_reached integer := 0;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF p_farm_id IS NULL OR p_farm_touch_id IS NULL THEN
        RAISE EXCEPTION 'farm id and farm touch id are required';
    END IF;

    IF v_status NOT IN (
        'none',
        'no_answer',
        'delivered',
        'talked',
        'appointment',
        'do_not_knock',
        'future_seller',
        'hot_lead'
    ) THEN
        RAISE EXCEPTION 'Unsupported farm address status: %', v_status;
    END IF;

    PERFORM 1
    FROM public.farms f
    WHERE f.id = p_farm_id
      AND (
          f.owner_id = auth.uid()
          OR (f.workspace_id IS NOT NULL AND public.is_workspace_member(f.workspace_id))
      );

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Farm not found or access denied';
    END IF;

    SELECT farm_id
    INTO v_touch_farm_id
    FROM public.farm_touches
    WHERE id = p_farm_touch_id;

    IF v_touch_farm_id IS NULL OR v_touch_farm_id IS DISTINCT FROM p_farm_id THEN
        RAISE EXCEPTION 'Farm touch not found or does not belong to the farm';
    END IF;

    IF v_farm_address_id IS NULL AND p_campaign_address_id IS NOT NULL THEN
        SELECT id
        INTO v_farm_address_id
        FROM public.farm_addresses
        WHERE farm_id = p_farm_id
          AND campaign_address_id = p_campaign_address_id
        ORDER BY created_at DESC
        LIMIT 1;
    END IF;

    IF v_farm_address_id IS NULL AND p_campaign_address_id IS NOT NULL THEN
        INSERT INTO public.farm_addresses (
            farm_id,
            campaign_address_id,
            gers_id,
            formatted,
            house_number,
            street_name,
            locality,
            region,
            postal_code,
            source,
            latitude,
            longitude,
            geom
        )
        SELECT
            p_farm_id,
            ca.id,
            ca.gers_id::text,
            COALESCE(
                NULLIF(trim(ca.formatted), ''),
                NULLIF(trim(concat_ws(' ', ca.house_number, ca.street_name)), ''),
                'Unknown address'
            ),
            ca.house_number,
            ca.street_name,
            ca.locality,
            ca.region,
            ca.postal_code,
            'campaign',
            CASE WHEN ca.geom IS NOT NULL THEN ST_Y(ca.geom::geometry) ELSE NULL END,
            CASE WHEN ca.geom IS NOT NULL THEN ST_X(ca.geom::geometry) ELSE NULL END,
            CASE WHEN ca.geom IS NOT NULL THEN ST_AsGeoJSON(ca.geom::geometry)::jsonb ELSE NULL END
        FROM public.campaign_addresses ca
        WHERE ca.id = p_campaign_address_id
        RETURNING id INTO v_farm_address_id;
    END IF;

    IF v_farm_address_id IS NULL THEN
        RAISE EXCEPTION 'farm address id or campaign address id is required';
    END IF;

    SELECT farm_id
    INTO v_address_farm_id
    FROM public.farm_addresses
    WHERE id = v_farm_address_id;

    IF v_address_farm_id IS NULL OR v_address_farm_id IS DISTINCT FROM p_farm_id THEN
        RAISE EXCEPTION 'Farm address not found or does not belong to the farm';
    END IF;

    INSERT INTO public.farm_touch_addresses (
        farm_id,
        farm_touch_id,
        farm_address_id,
        campaign_address_id,
        status,
        notes,
        occurred_at,
        created_by,
        updated_at
    )
    SELECT
        p_farm_id,
        p_farm_touch_id,
        fa.id,
        COALESCE(p_campaign_address_id, fa.campaign_address_id),
        v_status,
        v_notes,
        p_occurred_at,
        auth.uid(),
        now()
    FROM public.farm_addresses fa
    WHERE fa.id = v_farm_address_id
    ON CONFLICT (farm_touch_id, farm_address_id)
    DO UPDATE SET
        status = EXCLUDED.status,
        notes = COALESCE(EXCLUDED.notes, public.farm_touch_addresses.notes),
        occurred_at = EXCLUDED.occurred_at,
        campaign_address_id = COALESCE(EXCLUDED.campaign_address_id, public.farm_touch_addresses.campaign_address_id),
        updated_at = now();

    SELECT COUNT(*)
    INTO v_visit_count
    FROM public.farm_touch_addresses fta
    WHERE fta.farm_address_id = v_farm_address_id
      AND fta.status <> 'none';

    SELECT
        fta.occurred_at,
        fta.farm_touch_id,
        fta.status
    INTO v_latest_visit
    FROM public.farm_touch_addresses fta
    WHERE fta.farm_address_id = v_farm_address_id
      AND fta.status <> 'none'
    ORDER BY fta.occurred_at DESC, fta.updated_at DESC
    LIMIT 1;

    UPDATE public.farm_addresses
    SET
        visited_count = COALESCE(v_visit_count, 0),
        last_visited_at = CASE
            WHEN v_visit_count > 0 THEN v_latest_visit.occurred_at
            ELSE NULL
        END,
        last_touch_id = CASE
            WHEN v_visit_count > 0 THEN v_latest_visit.farm_touch_id
            ELSE NULL
        END,
        last_outcome_status = CASE
            WHEN v_visit_count > 0 THEN v_latest_visit.status
            ELSE NULL
        END
    WHERE id = v_farm_address_id;

    SELECT COUNT(*)
    INTO v_touch_homes_reached
    FROM public.farm_touch_addresses fta
    WHERE fta.farm_touch_id = p_farm_touch_id
      AND fta.status <> 'none';

    RETURN jsonb_build_object(
        'farm_id', p_farm_id,
        'farm_touch_id', p_farm_touch_id,
        'farm_address_id', v_farm_address_id,
        'status', v_status,
        'visited_count', v_visit_count,
        'homes_reached', v_touch_homes_reached,
        'last_touch_id', CASE
            WHEN v_visit_count > 0 THEN v_latest_visit.farm_touch_id
            ELSE NULL
        END,
        'last_outcome_status', CASE
            WHEN v_visit_count > 0 THEN v_latest_visit.status
            ELSE NULL
        END
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_farm_address_outcome(uuid, uuid, uuid, uuid, text, text, timestamptz)
    TO authenticated, service_role;

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
WITH scoped_events AS (
    SELECT
        se.id,
        se.address_id AS campaign_address_id,
        s.campaign_id,
        COALESCE(NULLIF(TRIM(se.metadata ->> 'address_status'), ''), 'none') AS status,
        se.created_at,
        NULLIF(TRIM(se.metadata ->> 'notes'), '') AS notes,
        se.user_id AS last_action_by,
        se.session_id AS last_session_id
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
        id AS last_home_event_id,
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

DROP FUNCTION IF EXISTS public.rpc_get_campaign_full_features_for_farm_phase(uuid, uuid);
DROP FUNCTION IF EXISTS public.rpc_get_campaign_address_status_rows_for_farm_phase(uuid, uuid);

DROP INDEX IF EXISTS idx_sessions_farm_phase_id;
ALTER TABLE public.sessions
    DROP COLUMN IF EXISTS farm_phase_id;

DROP INDEX IF EXISTS idx_farm_touches_phase_id;
ALTER TABLE public.farm_touches
    DROP COLUMN IF EXISTS phase_id;

DROP TABLE IF EXISTS public.farm_phases;

COMMIT;
