BEGIN;

CREATE OR REPLACE FUNCTION public.ensure_farm_touch_for_cycle(
    p_farm_id uuid,
    p_cycle_number integer,
    p_campaign_id uuid,
    p_touch_type text DEFAULT 'flyer',
    p_touch_title text DEFAULT NULL,
    p_touch_date date DEFAULT CURRENT_DATE
)
RETURNS public.farm_touches
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result public.farm_touches%ROWTYPE;
    v_order_index integer := 0;
    v_touch_type text := COALESCE(NULLIF(trim(p_touch_type), ''), 'flyer');
    v_touch_title text := COALESCE(NULLIF(trim(p_touch_title), ''), format('Cycle %s', p_cycle_number));
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF p_farm_id IS NULL OR p_cycle_number IS NULL OR p_campaign_id IS NULL THEN
        RAISE EXCEPTION 'farm id, cycle number, and campaign id are required';
    END IF;

    IF v_touch_type NOT IN ('flyer', 'door_knock', 'event', 'newsletter', 'ad', 'custom') THEN
        RAISE EXCEPTION 'Unsupported touch type: %', v_touch_type;
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

    SELECT ft.*
    INTO v_result
    FROM public.farm_touches ft
    WHERE ft.farm_id = p_farm_id
      AND ft.cycle_number = p_cycle_number
      AND ft.campaign_id = p_campaign_id
    ORDER BY ft.date ASC, ft.created_at ASC, ft.id ASC
    LIMIT 1;

    IF FOUND THEN
        RETURN v_result;
    END IF;

    WITH reusable_touch AS (
        SELECT ft.id
        FROM public.farm_touches ft
        WHERE ft.farm_id = p_farm_id
          AND ft.cycle_number = p_cycle_number
          AND ft.campaign_id IS NULL
        ORDER BY ft.date ASC, ft.created_at ASC, ft.id ASC
        LIMIT 1
        FOR UPDATE
    )
    UPDATE public.farm_touches ft
    SET campaign_id = p_campaign_id
    FROM reusable_touch
    WHERE ft.id = reusable_touch.id
    RETURNING ft.* INTO v_result;

    IF FOUND THEN
        RETURN v_result;
    END IF;

    SELECT COALESCE(MAX(ft.order_index), -1) + 1
    INTO v_order_index
    FROM public.farm_touches ft
    WHERE ft.farm_id = p_farm_id
      AND ft.cycle_number = p_cycle_number;

    INSERT INTO public.farm_touches (
        farm_id,
        cycle_number,
        date,
        type,
        title,
        order_index,
        completed,
        campaign_id
    )
    VALUES (
        p_farm_id,
        p_cycle_number,
        COALESCE(p_touch_date, CURRENT_DATE),
        v_touch_type,
        v_touch_title,
        v_order_index,
        false,
        p_campaign_id
    )
    RETURNING * INTO v_result;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.ensure_farm_touch_for_cycle(uuid, integer, uuid, text, text, date)
    TO authenticated, service_role;

COMMENT ON FUNCTION public.ensure_farm_touch_for_cycle(uuid, integer, uuid, text, text, date) IS
'Ensures a cycle has a usable farm_touches row for the requested campaign, reusing an existing or unassigned touch when possible.';

NOTIFY pgrst, 'reload schema';

COMMIT;
