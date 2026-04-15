-- Campaign address_source for provision rules (map vs other).
-- Align address_statuses with record_campaign_address_outcome (campaign_address_id).
-- RLS + RPC: allow workspace members, not only campaign owner.

ALTER TABLE public.campaigns
  ADD COLUMN IF NOT EXISTS address_source text;

-- Rename legacy address_id -> campaign_address_id when needed
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'address_statuses' AND column_name = 'address_id'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'address_statuses' AND column_name = 'campaign_address_id'
  ) THEN
    ALTER TABLE public.address_statuses RENAME COLUMN address_id TO campaign_address_id;
  END IF;
END $$;

-- One status row per campaign_address (FK to campaign_addresses.id)
CREATE UNIQUE INDEX IF NOT EXISTS idx_address_statuses_campaign_address_id_unique
  ON public.address_statuses (campaign_address_id);

-- RLS: owner OR workspace member
DROP POLICY IF EXISTS "Users can view statuses for their own campaigns" ON public.address_statuses;
DROP POLICY IF EXISTS "Users can insert statuses for their own campaigns" ON public.address_statuses;
DROP POLICY IF EXISTS "Users can update statuses for their own campaigns" ON public.address_statuses;
DROP POLICY IF EXISTS "Users can delete statuses for their own campaigns" ON public.address_statuses;

CREATE POLICY "address_statuses_select_member"
  ON public.address_statuses FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.campaigns c
      WHERE c.id = address_statuses.campaign_id
        AND (
          c.owner_id = auth.uid()
          OR EXISTS (
            SELECT 1 FROM public.workspace_members wm
            WHERE wm.workspace_id = c.workspace_id AND wm.user_id = auth.uid()
          )
        )
    )
  );

CREATE POLICY "address_statuses_insert_member"
  ON public.address_statuses FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.campaigns c
      WHERE c.id = address_statuses.campaign_id
        AND (
          c.owner_id = auth.uid()
          OR EXISTS (
            SELECT 1 FROM public.workspace_members wm
            WHERE wm.workspace_id = c.workspace_id AND wm.user_id = auth.uid()
          )
        )
    )
  );

CREATE POLICY "address_statuses_update_member"
  ON public.address_statuses FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.campaigns c
      WHERE c.id = address_statuses.campaign_id
        AND (
          c.owner_id = auth.uid()
          OR EXISTS (
            SELECT 1 FROM public.workspace_members wm
            WHERE wm.workspace_id = c.workspace_id AND wm.user_id = auth.uid()
          )
        )
    )
  );

CREATE POLICY "address_statuses_delete_member"
  ON public.address_statuses FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.campaigns c
      WHERE c.id = address_statuses.campaign_id
        AND (
          c.owner_id = auth.uid()
          OR EXISTS (
            SELECT 1 FROM public.workspace_members wm
            WHERE wm.workspace_id = c.workspace_id AND wm.user_id = auth.uid()
          )
        )
    )
  );

-- record_campaign_address_outcome: workspace access
CREATE OR REPLACE FUNCTION public.record_campaign_address_outcome(
  p_campaign_id uuid,
  p_campaign_address_id uuid DEFAULT NULL,
  p_address_id uuid DEFAULT NULL,
  p_status text DEFAULT 'none',
  p_notes text DEFAULT NULL,
  p_occurred_at timestamptz DEFAULT now(),
  p_session_id uuid DEFAULT NULL,
  p_session_target_id text DEFAULT NULL,
  p_session_event_type text DEFAULT NULL,
  p_lat double precision DEFAULT NULL,
  p_lon double precision DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_campaign_address_id uuid := COALESCE(p_campaign_address_id, p_address_id);
  v_status text := lower(trim(coalesce(p_status, 'none')));
  v_notes text := nullif(trim(coalesce(p_notes, '')), '');
  v_visited boolean;
  v_row public.address_statuses%ROWTYPE;
  v_session_user_id uuid;
  v_session_campaign_id uuid;
  v_session_event_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF v_campaign_address_id IS NULL THEN
    RAISE EXCEPTION 'campaign address id is required';
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
    RAISE EXCEPTION 'Unsupported address status: %', v_status;
  END IF;

  IF p_session_event_type IS NOT NULL AND p_session_event_type NOT IN (
    'completed_manual',
    'completed_auto',
    'completion_undone'
  ) THEN
    RAISE EXCEPTION 'Unsupported session event type: %', p_session_event_type;
  END IF;

  PERFORM 1
  FROM public.campaign_addresses ca
  JOIN public.campaigns c ON c.id = ca.campaign_id
  WHERE ca.id = v_campaign_address_id
    AND ca.campaign_id = p_campaign_id
    AND (
      c.owner_id = auth.uid()
      OR EXISTS (
        SELECT 1 FROM public.workspace_members wm
        WHERE wm.workspace_id = c.workspace_id AND wm.user_id = auth.uid()
      )
    );

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Campaign address not found or access denied';
  END IF;

  IF p_session_id IS NOT NULL THEN
    SELECT user_id, campaign_id
    INTO v_session_user_id, v_session_campaign_id
    FROM public.sessions
    WHERE id = p_session_id;

    IF v_session_user_id IS NULL OR v_session_user_id != auth.uid() THEN
      RAISE EXCEPTION 'Session not found or access denied';
    END IF;

    IF v_session_campaign_id IS DISTINCT FROM p_campaign_id THEN
      RAISE EXCEPTION 'Session campaign does not match campaign address outcome campaign';
    END IF;
  END IF;

  v_visited := v_status <> 'none';

  INSERT INTO public.address_statuses (
    campaign_address_id,
    campaign_id,
    status,
    notes,
    last_visited_at,
    visit_count,
    updated_at
  ) VALUES (
    v_campaign_address_id,
    p_campaign_id,
    v_status,
    v_notes,
    CASE WHEN v_visited THEN p_occurred_at ELSE NULL END,
    CASE WHEN v_visited THEN 1 ELSE 0 END,
    now()
  )
  ON CONFLICT (campaign_address_id)
  DO UPDATE SET
    status = EXCLUDED.status,
    notes = COALESCE(EXCLUDED.notes, public.address_statuses.notes),
    last_visited_at = CASE
      WHEN EXCLUDED.status = 'none' THEN public.address_statuses.last_visited_at
      ELSE EXCLUDED.last_visited_at
    END,
    visit_count = CASE
      WHEN EXCLUDED.status = 'none' THEN public.address_statuses.visit_count
      ELSE public.address_statuses.visit_count + 1
    END,
    updated_at = now()
  RETURNING * INTO v_row;

  UPDATE public.campaign_addresses
  SET visited = v_visited
  WHERE id = v_campaign_address_id;

  IF p_session_id IS NOT NULL AND p_session_event_type IS NOT NULL THEN
    INSERT INTO public.session_events (
      session_id,
      building_id,
      address_id,
      event_type,
      created_at,
      lat,
      lon,
      event_location,
      metadata,
      user_id
    ) VALUES (
      p_session_id,
      nullif(trim(coalesce(p_session_target_id, '')), ''),
      v_campaign_address_id,
      p_session_event_type,
      p_occurred_at,
      p_lat,
      p_lon,
      CASE
        WHEN p_lon IS NOT NULL AND p_lat IS NOT NULL
          THEN ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography
        ELSE NULL
      END,
      jsonb_build_object(
        'address_status', v_status,
        'source', 'record_campaign_address_outcome'
      ),
      v_session_user_id
    )
    RETURNING id INTO v_session_event_id;

    IF p_session_event_type IN ('completed_manual', 'completed_auto') THEN
      UPDATE public.sessions
      SET completed_count = completed_count + 1,
          updated_at = now()
      WHERE id = p_session_id;
    ELSIF p_session_event_type = 'completion_undone' THEN
      UPDATE public.sessions
      SET completed_count = GREATEST(0, completed_count - 1),
          updated_at = now()
      WHERE id = p_session_id;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'campaign_address_id', v_row.campaign_address_id,
    'status', v_row.status,
    'visited', v_visited,
    'visit_count', v_row.visit_count,
    'last_visited_at', v_row.last_visited_at,
    'updated_at', v_row.updated_at,
    'session_event_id', v_session_event_id
  );
END;
$$;

COMMENT ON FUNCTION public.record_campaign_address_outcome(uuid, uuid, uuid, text, text, timestamptz, uuid, text, text, double precision, double precision)
IS 'Canonical house outcome write path. Upserts address_statuses; owner or workspace member.';

-- record_campaign_target_outcome: workspace access on validation (body otherwise unchanged)
CREATE OR REPLACE FUNCTION public.record_campaign_target_outcome(
  p_campaign_id uuid,
  p_campaign_address_ids uuid[],
  p_status text DEFAULT 'none',
  p_notes text DEFAULT NULL,
  p_occurred_at timestamptz DEFAULT now(),
  p_session_id uuid DEFAULT NULL,
  p_session_target_id text DEFAULT NULL,
  p_session_event_type text DEFAULT NULL,
  p_lat double precision DEFAULT NULL,
  p_lon double precision DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_campaign_address_ids uuid[];
  v_campaign_address_id uuid;
  v_status text := lower(trim(coalesce(p_status, 'none')));
  v_notes text := nullif(trim(coalesce(p_notes, '')), '');
  v_visited boolean;
  v_session_user_id uuid;
  v_session_campaign_id uuid;
  v_session_event_id uuid;
  v_validated_count integer;
  v_address_outcomes jsonb := '[]'::jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT COALESCE(array_agg(address_id ORDER BY first_ordinal), ARRAY[]::uuid[])
  INTO v_campaign_address_ids
  FROM (
    SELECT address_id, MIN(ordinality) AS first_ordinal
    FROM unnest(coalesce(p_campaign_address_ids, ARRAY[]::uuid[])) WITH ORDINALITY AS input(address_id, ordinality)
    WHERE address_id IS NOT NULL
    GROUP BY address_id
  ) deduped;

  IF COALESCE(array_length(v_campaign_address_ids, 1), 0) = 0 THEN
    RAISE EXCEPTION 'campaign address ids are required';
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
    RAISE EXCEPTION 'Unsupported address status: %', v_status;
  END IF;

  IF p_session_event_type IS NOT NULL AND p_session_event_type NOT IN (
    'completed_manual',
    'completed_auto',
    'completion_undone'
  ) THEN
    RAISE EXCEPTION 'Unsupported session event type: %', p_session_event_type;
  END IF;

  SELECT COUNT(*)
  INTO v_validated_count
  FROM public.campaign_addresses ca
  JOIN public.campaigns c ON c.id = ca.campaign_id
  WHERE ca.id = ANY(v_campaign_address_ids)
    AND ca.campaign_id = p_campaign_id
    AND (
      c.owner_id = auth.uid()
      OR EXISTS (
        SELECT 1 FROM public.workspace_members wm
        WHERE wm.workspace_id = c.workspace_id AND wm.user_id = auth.uid()
      )
    );

  IF v_validated_count <> COALESCE(array_length(v_campaign_address_ids, 1), 0) THEN
    RAISE EXCEPTION 'One or more campaign addresses were not found or access was denied';
  END IF;

  IF p_session_id IS NOT NULL THEN
    SELECT user_id, campaign_id
    INTO v_session_user_id, v_session_campaign_id
    FROM public.sessions
    WHERE id = p_session_id;

    IF v_session_user_id IS NULL OR v_session_user_id != auth.uid() THEN
      RAISE EXCEPTION 'Session not found or access denied';
    END IF;

    IF v_session_campaign_id IS DISTINCT FROM p_campaign_id THEN
      RAISE EXCEPTION 'Session campaign does not match campaign address outcome campaign';
    END IF;
  END IF;

  FOREACH v_campaign_address_id IN ARRAY v_campaign_address_ids LOOP
    v_address_outcomes := v_address_outcomes || jsonb_build_array(
      public.record_campaign_address_outcome(
        p_campaign_id => p_campaign_id,
        p_campaign_address_id => v_campaign_address_id,
        p_status => v_status,
        p_notes => v_notes,
        p_occurred_at => p_occurred_at
      )
    );
  END LOOP;

  v_visited := v_status <> 'none';

  IF p_session_id IS NOT NULL AND p_session_event_type IS NOT NULL THEN
    INSERT INTO public.session_events (
      session_id,
      building_id,
      address_id,
      event_type,
      created_at,
      lat,
      lon,
      event_location,
      metadata,
      user_id
    ) VALUES (
      p_session_id,
      nullif(trim(coalesce(p_session_target_id, '')), ''),
      v_campaign_address_ids[1],
      p_session_event_type,
      p_occurred_at,
      p_lat,
      p_lon,
      CASE
        WHEN p_lon IS NOT NULL AND p_lat IS NOT NULL
          THEN ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography
        ELSE NULL
      END,
      jsonb_build_object(
        'address_status', v_status,
        'source', 'record_campaign_target_outcome',
        'campaign_address_ids', to_jsonb(v_campaign_address_ids),
        'address_count', COALESCE(array_length(v_campaign_address_ids, 1), 0)
      ),
      v_session_user_id
    )
    RETURNING id INTO v_session_event_id;

    IF p_session_event_type IN ('completed_manual', 'completed_auto') THEN
      UPDATE public.sessions
      SET completed_count = completed_count + 1,
          updated_at = now()
      WHERE id = p_session_id;
    ELSIF p_session_event_type = 'completion_undone' THEN
      UPDATE public.sessions
      SET completed_count = GREATEST(0, completed_count - 1),
          updated_at = now()
      WHERE id = p_session_id;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'campaign_address_ids', to_jsonb(v_campaign_address_ids),
    'status', v_status,
    'visited', v_visited,
    'affected_count', COALESCE(array_length(v_campaign_address_ids, 1), 0),
    'address_outcomes', v_address_outcomes,
    'session_event_id', v_session_event_id
  );
END;
$$;

COMMENT ON FUNCTION public.record_campaign_target_outcome(uuid, uuid[], text, text, timestamptz, uuid, text, text, double precision, double precision)
IS 'Canonical multi-address target outcome write path. Persists all child house outcomes, then atomically logs one session completion event and session counter update.';

GRANT EXECUTE ON FUNCTION public.record_campaign_target_outcome(uuid, uuid[], text, text, timestamptz, uuid, text, text, double precision, double precision) TO authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.record_campaign_address_outcome(uuid, uuid, uuid, text, text, timestamptz, uuid, text, text, double precision, double precision) TO authenticated, service_role;
