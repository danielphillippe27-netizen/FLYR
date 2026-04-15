-- Canonical session_events.event_type for visit outcomes (flyer_left, conversation, address_tap)
-- plus lifecycle/legacy values. Align record_campaign_*_outcome validation and completed_count.
-- Harden text vs uuid comparisons in rpc_get_session_with_events and campaign/address_status RLS.

-- ---------------------------------------------------------------------------
-- 1) session_events.event_type CHECK (expand to include app + legacy + lifecycle)
-- ---------------------------------------------------------------------------
ALTER TABLE public.session_events DROP CONSTRAINT IF EXISTS session_events_event_type_check;

ALTER TABLE public.session_events ADD CONSTRAINT session_events_event_type_check CHECK (
  event_type = ANY (ARRAY[
    'address_tap'::text,
    'conversation'::text,
    'flyer_left'::text,
    'session_started'::text,
    'session_paused'::text,
    'session_resumed'::text,
    'session_ended'::text,
    'completed_manual'::text,
    'completed_auto'::text,
    'completion_undone'::text
  ])
);

-- ---------------------------------------------------------------------------
-- 2) RLS: avoid operator does not exist: text = uuid on campaign_id joins
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "campaign_addresses_owner_or_workspace_member_all" ON public.campaign_addresses;
CREATE POLICY "campaign_addresses_owner_or_workspace_member_all"
    ON public.campaign_addresses
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.campaigns c
            WHERE (c.id::text) = (campaign_addresses.campaign_id::text)
              AND (
                  (c.owner_id::text) = (auth.uid()::text)
                  OR (c.workspace_id IS NOT NULL AND public.is_workspace_member(c.workspace_id))
              )
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.campaigns c
            WHERE (c.id::text) = (campaign_addresses.campaign_id::text)
              AND (
                  (c.owner_id::text) = (auth.uid()::text)
                  OR (c.workspace_id IS NOT NULL AND public.is_workspace_member(c.workspace_id))
              )
        )
    );

DROP POLICY IF EXISTS "address_statuses_select_owner_or_member" ON public.address_statuses;
DROP POLICY IF EXISTS "address_statuses_insert_owner_or_member" ON public.address_statuses;
DROP POLICY IF EXISTS "address_statuses_update_owner_or_member" ON public.address_statuses;
DROP POLICY IF EXISTS "address_statuses_delete_owner_or_member" ON public.address_statuses;

CREATE POLICY "address_statuses_select_owner_or_member"
    ON public.address_statuses
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.campaigns c
            WHERE (c.id::text) = (address_statuses.campaign_id::text)
              AND (
                  (c.owner_id::text) = (auth.uid()::text)
                  OR (c.workspace_id IS NOT NULL AND public.is_workspace_member(c.workspace_id))
              )
        )
    );

CREATE POLICY "address_statuses_insert_owner_or_member"
    ON public.address_statuses
    FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.campaigns c
            WHERE (c.id::text) = (address_statuses.campaign_id::text)
              AND (
                  (c.owner_id::text) = (auth.uid()::text)
                  OR (c.workspace_id IS NOT NULL AND public.is_workspace_member(c.workspace_id))
              )
        )
    );

CREATE POLICY "address_statuses_update_owner_or_member"
    ON public.address_statuses
    FOR UPDATE TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.campaigns c
            WHERE (c.id::text) = (address_statuses.campaign_id::text)
              AND (
                  (c.owner_id::text) = (auth.uid()::text)
                  OR (c.workspace_id IS NOT NULL AND public.is_workspace_member(c.workspace_id))
              )
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.campaigns c
            WHERE (c.id::text) = (address_statuses.campaign_id::text)
              AND (
                  (c.owner_id::text) = (auth.uid()::text)
                  OR (c.workspace_id IS NOT NULL AND public.is_workspace_member(c.workspace_id))
              )
        )
    );

CREATE POLICY "address_statuses_delete_owner_or_member"
    ON public.address_statuses
    FOR DELETE TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.campaigns c
            WHERE (c.id::text) = (address_statuses.campaign_id::text)
              AND (
                  (c.owner_id::text) = (auth.uid()::text)
                  OR (c.workspace_id IS NOT NULL AND public.is_workspace_member(c.workspace_id))
              )
        )
    );

-- ---------------------------------------------------------------------------
-- 3) rpc_get_session_with_events: text-safe user match
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_get_session_with_events(p_session_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'session', to_jsonb(s),
        'events', COALESCE(
            (SELECT jsonb_agg(to_jsonb(e) ORDER BY e.created_at)
             FROM public.session_events e WHERE e.session_id = p_session_id),
            '[]'::jsonb
        )
    )
    FROM public.sessions s
    WHERE s.id = p_session_id AND (s.user_id::text) = (auth.uid()::text);
$$;

-- ---------------------------------------------------------------------------
-- 4) rpc_complete_building_in_session: count flyer_left / conversation like completions
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_complete_building_in_session(
    p_session_id UUID,
    p_building_id TEXT,
    p_event_type TEXT,
    p_lat DOUBLE PRECISION DEFAULT NULL,
    p_lon DOUBLE PRECISION DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_address_id UUID;
    v_campaign_id UUID;
    v_user_id UUID;
    v_event_id UUID;
    v_building_id UUID;
BEGIN
    SELECT campaign_id, user_id INTO v_campaign_id, v_user_id
    FROM public.sessions WHERE id = p_session_id;
    IF v_user_id IS NULL OR (v_user_id::text) IS DISTINCT FROM (auth.uid()::text) THEN
        RAISE EXCEPTION 'Session not found or access denied';
    END IF;

    SELECT b.id INTO v_building_id
    FROM public.buildings b
    WHERE LOWER(b.gers_id::text) = LOWER(p_building_id)
    LIMIT 1;

    IF v_campaign_id IS NOT NULL THEN
        SELECT bal.address_id INTO v_address_id
        FROM public.building_address_links bal
        WHERE bal.building_id = v_building_id
          AND bal.campaign_id = v_campaign_id
        LIMIT 1;
    END IF;

    INSERT INTO public.session_events (
        session_id, building_id, address_id, event_type,
        lat, lon, event_location, metadata, user_id
    ) VALUES (
        p_session_id,
        v_building_id,
        v_address_id,
        p_event_type,
        p_lat,
        p_lon,
        CASE WHEN p_lon IS NOT NULL AND p_lat IS NOT NULL
             THEN ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography
             ELSE NULL END,
        p_metadata,
        v_user_id
    )
    RETURNING id INTO v_event_id;

    IF p_event_type IN ('completed_manual', 'completed_auto', 'flyer_left', 'conversation') THEN
        UPDATE public.sessions
        SET completed_count = completed_count + 1, updated_at = now()
        WHERE id = p_session_id;
    ELSIF p_event_type = 'completion_undone' THEN
        UPDATE public.sessions
        SET completed_count = GREATEST(0, completed_count - 1), updated_at = now()
        WHERE id = p_session_id;
    END IF;

    IF p_event_type IN ('completed_manual', 'completed_auto', 'flyer_left', 'conversation')
       AND v_campaign_id IS NOT NULL AND NULLIF(TRIM(p_building_id), '') IS NOT NULL THEN
        UPDATE public.building_stats
        SET status = 'visited', last_scan_at = now(), updated_at = now()
        WHERE LOWER(TRIM(gers_id::text)) = LOWER(TRIM(p_building_id)) AND campaign_id = v_campaign_id;

        IF NOT FOUND AND v_building_id IS NOT NULL THEN
            INSERT INTO public.building_stats (building_id, gers_id, campaign_id, status, scans_total, scans_today, last_scan_at)
            SELECT
                v_building_id,
                b.gers_id,
                v_campaign_id,
                'visited',
                0,
                0,
                now()
            FROM public.buildings b
            WHERE b.id = v_building_id;
        END IF;

        IF v_address_id IS NOT NULL THEN
            UPDATE public.campaign_addresses
            SET visited = true
            WHERE id = v_address_id;
        END IF;
    END IF;

    RETURN jsonb_build_object('event_id', v_event_id, 'address_id', v_address_id);
END;
$$;

-- ---------------------------------------------------------------------------
-- 5) record_campaign_address_outcome (canonical visit types + completed_count)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_campaign_address_outcome(
  p_campaign_id uuid,
  p_campaign_address_id uuid DEFAULT NULL::uuid,
  p_address_id uuid DEFAULT NULL::uuid,
  p_status text DEFAULT 'none'::text,
  p_notes text DEFAULT NULL::text,
  p_occurred_at timestamp with time zone DEFAULT now(),
  p_session_id uuid DEFAULT NULL::uuid,
  p_session_target_id text DEFAULT NULL::text,
  p_session_event_type text DEFAULT NULL::text,
  p_lat double precision DEFAULT NULL::double precision,
  p_lon double precision DEFAULT NULL::double precision
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_campaign_address_id uuid := coalesce(p_campaign_address_id, p_address_id);
  v_status text := lower(trim(coalesce(p_status, 'none')));
  v_notes text := nullif(trim(coalesce(p_notes, '')), '');
  v_visited boolean;
  v_session_user_id uuid;
  v_session_campaign_id uuid;
  v_session_event_id uuid;
  v_session_event_building_id uuid;
  v_has_campaign_address_fk boolean;
  v_has_address_id_fk boolean;
  v_has_campaign_id_fk boolean;
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if v_campaign_address_id is null then
    raise exception 'campaign address id is required';
  end if;

  if v_status not in (
    'none',
    'no_answer',
    'delivered',
    'talked',
    'appointment',
    'do_not_knock',
    'future_seller',
    'hot_lead'
  ) then
    raise exception 'Unsupported address status: %', v_status;
  end if;

  if p_session_event_type is not null and p_session_event_type not in (
    'flyer_left',
    'conversation',
    'address_tap',
    'completed_manual',
    'completed_auto',
    'completion_undone'
  ) then
    raise exception 'Unsupported session event type: %', p_session_event_type;
  end if;

  perform 1
  from public.campaign_addresses ca
  join public.campaigns c on c.id = ca.campaign_id
  where ca.id = v_campaign_address_id
    and ca.campaign_id = p_campaign_id
    and (
      (c.owner_id::text) = (auth.uid()::text)
      or (c.workspace_id is not null and public.is_workspace_member(c.workspace_id))
    );

  if not found then
    raise exception 'Campaign address not found or access denied';
  end if;

  if p_session_id is not null then
    select user_id, campaign_id
    into v_session_user_id, v_session_campaign_id
    from public.sessions
    where id = p_session_id;

    if v_session_user_id is null or (v_session_user_id::text) is distinct from (auth.uid()::text) then
      raise exception 'Session not found or access denied';
    end if;

    if v_session_campaign_id is distinct from p_campaign_id then
      raise exception 'Session campaign does not match campaign address outcome campaign';
    end if;
  end if;

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'address_statuses'
      and column_name = 'campaign_address_id'
  ) into v_has_campaign_address_fk;

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'address_statuses'
      and column_name = 'address_id'
  ) into v_has_address_id_fk;

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'address_statuses'
      and column_name = 'campaign_id'
  ) into v_has_campaign_id_fk;

  if not v_has_campaign_address_fk and not (v_has_address_id_fk and v_has_campaign_id_fk) then
    raise exception 'address_statuses is missing a supported address foreign key shape';
  end if;

  v_visited := v_status <> 'none';

  if v_has_campaign_address_fk then
    if v_has_campaign_id_fk then
      execute $sql$
        insert into public.address_statuses (
          campaign_address_id,
          campaign_id,
          status,
          notes,
          last_visited_at,
          visit_count,
          updated_at
        ) values ($1, $2, $3, $4, case when $5 then $6 else null end, case when $5 then 1 else 0 end, now())
        on conflict (campaign_address_id)
        do update set
          campaign_id = excluded.campaign_id,
          status = excluded.status,
          notes = coalesce(excluded.notes, public.address_statuses.notes),
          last_visited_at = case
            when excluded.status = 'none' then public.address_statuses.last_visited_at
            else excluded.last_visited_at
          end,
          visit_count = case
            when excluded.status = 'none' then public.address_statuses.visit_count
            else public.address_statuses.visit_count + 1
          end,
          updated_at = now()
        returning jsonb_build_object(
          'campaign_address_id', campaign_address_id,
          'campaign_id', campaign_id,
          'status', status,
          'visit_count', visit_count,
          'last_visited_at', last_visited_at,
          'updated_at', updated_at
        )
      $sql$
      into v_result
      using v_campaign_address_id, p_campaign_id, v_status, v_notes, v_visited, p_occurred_at;
    else
      execute $sql$
        insert into public.address_statuses (
          campaign_address_id,
          status,
          notes,
          last_visited_at,
          visit_count,
          updated_at
        ) values ($1, $2, $3, case when $4 then $5 else null end, case when $4 then 1 else 0 end, now())
        on conflict (campaign_address_id)
        do update set
          status = excluded.status,
          notes = coalesce(excluded.notes, public.address_statuses.notes),
          last_visited_at = case
            when excluded.status = 'none' then public.address_statuses.last_visited_at
            else excluded.last_visited_at
          end,
          visit_count = case
            when excluded.status = 'none' then public.address_statuses.visit_count
            else public.address_statuses.visit_count + 1
          end,
          updated_at = now()
        returning jsonb_build_object(
          'campaign_address_id', campaign_address_id,
          'status', status,
          'visit_count', visit_count,
          'last_visited_at', last_visited_at,
          'updated_at', updated_at
        )
      $sql$
      into v_result
      using v_campaign_address_id, v_status, v_notes, v_visited, p_occurred_at;
    end if;
  else
    execute $sql$
      insert into public.address_statuses (
        address_id,
        campaign_id,
        status,
        notes,
        last_visited_at,
        visit_count,
        updated_at
      ) values ($1, $2, $3, $4, case when $5 then $6 else null end, case when $5 then 1 else 0 end, now())
      on conflict (address_id, campaign_id)
      do update set
        status = excluded.status,
        notes = coalesce(excluded.notes, public.address_statuses.notes),
        last_visited_at = case
          when excluded.status = 'none' then public.address_statuses.last_visited_at
          else excluded.last_visited_at
        end,
        visit_count = case
          when excluded.status = 'none' then public.address_statuses.visit_count
          else public.address_statuses.visit_count + 1
        end,
        updated_at = now()
      returning jsonb_build_object(
        'address_id', address_id,
        'campaign_id', campaign_id,
        'status', status,
        'visit_count', visit_count,
        'last_visited_at', last_visited_at,
        'updated_at', updated_at
      )
    $sql$
    into v_result
    using v_campaign_address_id, p_campaign_id, v_status, v_notes, v_visited, p_occurred_at;
  end if;

  update public.campaign_addresses
  set visited = v_visited
  where id = v_campaign_address_id;

  if p_session_id is not null and p_session_event_type is not null then
    v_session_event_building_id := null;
    if nullif(trim(coalesce(p_session_target_id, '')), '') is not null then
      begin
        v_session_event_building_id := nullif(trim(coalesce(p_session_target_id, '')), '')::uuid;
      exception when invalid_text_representation then
        v_session_event_building_id := null;
      end;
    end if;

    insert into public.session_events (
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
    ) values (
      p_session_id,
      v_session_event_building_id,
      v_campaign_address_id,
      p_session_event_type,
      p_occurred_at,
      p_lat,
      p_lon,
      case
        when p_lon is not null and p_lat is not null
          then st_setsrid(st_makepoint(p_lon, p_lat), 4326)::geography
        else null
      end,
      jsonb_build_object(
        'address_status', v_status,
        'source', 'record_campaign_address_outcome'
      ),
      v_session_user_id
    )
    returning id into v_session_event_id;

    if p_session_event_type in (
      'flyer_left',
      'conversation',
      'completed_manual',
      'completed_auto'
    ) then
      update public.sessions
      set completed_count = completed_count + 1,
          updated_at = now()
      where id = p_session_id;
    elsif p_session_event_type = 'completion_undone' then
      update public.sessions
      set completed_count = greatest(0, completed_count - 1),
          updated_at = now()
      where id = p_session_id;
    end if;
  end if;

  return v_result || jsonb_build_object(
    'visited', v_visited,
    'session_event_id', v_session_event_id
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 6) record_campaign_target_outcome (same session event contract)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_campaign_target_outcome(
  p_campaign_id uuid,
  p_campaign_address_ids uuid[],
  p_status text DEFAULT 'none'::text,
  p_notes text DEFAULT NULL::text,
  p_occurred_at timestamp with time zone DEFAULT now(),
  p_session_id uuid DEFAULT NULL::uuid,
  p_session_target_id text DEFAULT NULL::text,
  p_session_event_type text DEFAULT NULL::text,
  p_lat double precision DEFAULT NULL::double precision,
  p_lon double precision DEFAULT NULL::double precision
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_campaign_address_ids uuid[];
  v_campaign_address_id uuid;
  v_status text := lower(trim(coalesce(p_status, 'none')));
  v_notes text := nullif(trim(coalesce(p_notes, '')), '');
  v_visited boolean;
  v_session_user_id uuid;
  v_session_campaign_id uuid;
  v_session_event_id uuid;
  v_session_event_building_id uuid;
  v_validated_count integer;
  v_address_outcomes jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select coalesce(array_agg(address_id order by first_ordinal), array[]::uuid[])
  into v_campaign_address_ids
  from (
    select address_id, min(ordinality) as first_ordinal
    from unnest(coalesce(p_campaign_address_ids, array[]::uuid[])) with ordinality as input(address_id, ordinality)
    where address_id is not null
    group by address_id
  ) deduped;

  if coalesce(array_length(v_campaign_address_ids, 1), 0) = 0 then
    raise exception 'campaign address ids are required';
  end if;

  if v_status not in (
    'none',
    'no_answer',
    'delivered',
    'talked',
    'appointment',
    'do_not_knock',
    'future_seller',
    'hot_lead'
  ) then
    raise exception 'Unsupported address status: %', v_status;
  end if;

  if p_session_event_type is not null and p_session_event_type not in (
    'flyer_left',
    'conversation',
    'address_tap',
    'completed_manual',
    'completed_auto',
    'completion_undone'
  ) then
    raise exception 'Unsupported session event type: %', p_session_event_type;
  end if;

  select count(*)
  into v_validated_count
  from public.campaign_addresses ca
  join public.campaigns c on c.id = ca.campaign_id
  where ca.id = any(v_campaign_address_ids)
    and ca.campaign_id = p_campaign_id
    and (
      (c.owner_id::text) = (auth.uid()::text)
      or (c.workspace_id is not null and public.is_workspace_member(c.workspace_id))
    );

  if v_validated_count <> coalesce(array_length(v_campaign_address_ids, 1), 0) then
    raise exception 'One or more campaign addresses were not found or access was denied';
  end if;

  if p_session_id is not null then
    select user_id, campaign_id
    into v_session_user_id, v_session_campaign_id
    from public.sessions
    where id = p_session_id;

    if v_session_user_id is null or (v_session_user_id::text) is distinct from (auth.uid()::text) then
      raise exception 'Session not found or access denied';
    end if;

    if v_session_campaign_id is distinct from p_campaign_id then
      raise exception 'Session campaign does not match campaign address outcome campaign';
    end if;
  end if;

  foreach v_campaign_address_id in array v_campaign_address_ids loop
    v_address_outcomes := v_address_outcomes || jsonb_build_array(
      public.record_campaign_address_outcome(
        p_campaign_id => p_campaign_id,
        p_campaign_address_id => v_campaign_address_id,
        p_status => v_status,
        p_notes => v_notes,
        p_occurred_at => p_occurred_at
      )
    );
  end loop;

  v_visited := v_status <> 'none';

  if p_session_id is not null and p_session_event_type is not null then
    v_session_event_building_id := null;
    if nullif(trim(coalesce(p_session_target_id, '')), '') is not null then
      begin
        v_session_event_building_id := nullif(trim(coalesce(p_session_target_id, '')), '')::uuid;
      exception when invalid_text_representation then
        v_session_event_building_id := null;
      end;
    end if;

    insert into public.session_events (
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
    ) values (
      p_session_id,
      v_session_event_building_id,
      v_campaign_address_ids[1],
      p_session_event_type,
      p_occurred_at,
      p_lat,
      p_lon,
      case
        when p_lon is not null and p_lat is not null
          then st_setsrid(st_makepoint(p_lon, p_lat), 4326)::geography
        else null
      end,
      jsonb_build_object(
        'address_status', v_status,
        'source', 'record_campaign_target_outcome',
        'campaign_address_ids', to_jsonb(v_campaign_address_ids),
        'address_count', coalesce(array_length(v_campaign_address_ids, 1), 0)
      ),
      v_session_user_id
    )
    returning id into v_session_event_id;

    if p_session_event_type in (
      'flyer_left',
      'conversation',
      'completed_manual',
      'completed_auto'
    ) then
      update public.sessions
      set completed_count = completed_count + 1,
          updated_at = now()
      where id = p_session_id;
    elsif p_session_event_type = 'completion_undone' then
      update public.sessions
      set completed_count = greatest(0, completed_count - 1),
          updated_at = now()
      where id = p_session_id;
    end if;
  end if;

  return jsonb_build_object(
    'campaign_address_ids', to_jsonb(v_campaign_address_ids),
    'status', v_status,
    'visited', v_visited,
    'affected_count', coalesce(array_length(v_campaign_address_ids, 1), 0),
    'address_outcomes', v_address_outcomes,
    'session_event_id', v_session_event_id
  );
end;
$function$;
