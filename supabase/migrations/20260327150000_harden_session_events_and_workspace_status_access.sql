-- Targeted hardening for session start/session events + workspace address status access.
-- Safe to run multiple times.

BEGIN;

-- ============================================================================
-- 1) Canonical session_events RLS (remove duplicate/overlapping policies)
-- ============================================================================
ALTER TABLE public.session_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own session events" ON public.session_events;
DROP POLICY IF EXISTS "Users can insert own session events" ON public.session_events;
DROP POLICY IF EXISTS "Users can read events for their own sessions" ON public.session_events;
DROP POLICY IF EXISTS "Users can insert events for their own sessions" ON public.session_events;
DROP POLICY IF EXISTS "Users can update events for their own sessions" ON public.session_events;
DROP POLICY IF EXISTS "Users can delete events for their own sessions" ON public.session_events;

CREATE POLICY "session_events_select_own_session"
    ON public.session_events
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.sessions s
            WHERE s.id = session_events.session_id
              AND (s.user_id::text) = (auth.uid()::text)
        )
    );

CREATE POLICY "session_events_insert_own_session"
    ON public.session_events
    FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.sessions s
            WHERE s.id = session_events.session_id
              AND (s.user_id::text) = (auth.uid()::text)
        )
    );

CREATE POLICY "session_events_update_own_session"
    ON public.session_events
    FOR UPDATE TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.sessions s
            WHERE s.id = session_events.session_id
              AND (s.user_id::text) = (auth.uid()::text)
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.sessions s
            WHERE s.id = session_events.session_id
              AND (s.user_id::text) = (auth.uid()::text)
        )
    );

CREATE POLICY "session_events_delete_own_session"
    ON public.session_events
    FOR DELETE TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.sessions s
            WHERE s.id = session_events.session_id
              AND (s.user_id::text) = (auth.uid()::text)
        )
    );

-- ============================================================================
-- 2) Workspace-member access for campaign_addresses and address_statuses
--    (owner or workspace member)
-- ============================================================================
ALTER TABLE public.campaign_addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.address_statuses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can access addresses for their campaigns" ON public.campaign_addresses;
DROP POLICY IF EXISTS "Users can view addresses of their campaigns" ON public.campaign_addresses;
DROP POLICY IF EXISTS "Users can update addresses of their campaigns" ON public.campaign_addresses;
DROP POLICY IF EXISTS "Users can delete addresses of their campaigns" ON public.campaign_addresses;

CREATE POLICY "campaign_addresses_owner_or_workspace_member_all"
    ON public.campaign_addresses
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.campaigns c
            WHERE c.id = campaign_addresses.campaign_id
              AND (
                  c.owner_id = auth.uid()
                  OR (c.workspace_id IS NOT NULL AND public.is_workspace_member(c.workspace_id))
              )
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.campaigns c
            WHERE c.id = campaign_addresses.campaign_id
              AND (
                  c.owner_id = auth.uid()
                  OR (c.workspace_id IS NOT NULL AND public.is_workspace_member(c.workspace_id))
              )
        )
    );

DROP POLICY IF EXISTS "Users can view statuses for their own campaigns" ON public.address_statuses;
DROP POLICY IF EXISTS "Users can insert statuses for their own campaigns" ON public.address_statuses;
DROP POLICY IF EXISTS "Users can update statuses for their own campaigns" ON public.address_statuses;
DROP POLICY IF EXISTS "Users can delete statuses for their own campaigns" ON public.address_statuses;

CREATE POLICY "address_statuses_select_owner_or_member"
    ON public.address_statuses
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.campaigns c
            WHERE c.id = address_statuses.campaign_id
              AND (
                  c.owner_id = auth.uid()
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
            WHERE c.id = address_statuses.campaign_id
              AND (
                  c.owner_id = auth.uid()
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
            WHERE c.id = address_statuses.campaign_id
              AND (
                  c.owner_id = auth.uid()
                  OR (c.workspace_id IS NOT NULL AND public.is_workspace_member(c.workspace_id))
              )
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.campaigns c
            WHERE c.id = address_statuses.campaign_id
              AND (
                  c.owner_id = auth.uid()
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
            WHERE c.id = address_statuses.campaign_id
              AND (
                  c.owner_id = auth.uid()
                  OR (c.workspace_id IS NOT NULL AND public.is_workspace_member(c.workspace_id))
              )
        )
    );

-- ============================================================================
-- 3) Canonical outcome functions: allow owner OR workspace member
-- ============================================================================
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
      c.owner_id = auth.uid()
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

    if v_session_user_id is null or v_session_user_id != auth.uid() then
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
      nullif(trim(coalesce(p_session_target_id, '')), ''),
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

    if p_session_event_type in ('completed_manual', 'completed_auto') then
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
      c.owner_id = auth.uid()
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

    if v_session_user_id is null or v_session_user_id != auth.uid() then
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
      nullif(trim(coalesce(p_session_target_id, '')), ''),
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

    if p_session_event_type in ('completed_manual', 'completed_auto') then
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

-- ============================================================================
-- 4) Harden session->user_stats rollup trigger to count ended sessions once
-- ============================================================================
DROP TRIGGER IF EXISTS trigger_update_user_stats_from_session ON public.sessions;

CREATE OR REPLACE FUNCTION public.update_user_stats_from_session()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
    IF NEW.end_time IS NULL THEN
        RETURN NEW;
    END IF;

    -- Only count once: on insert already-ended or first active->ended transition.
    IF TG_OP = 'UPDATE' AND OLD.end_time IS NOT NULL THEN
        RETURN NEW;
    END IF;

    INSERT INTO public.user_stats (
        user_id, flyers, conversations, distance_walked, time_tracked
    )
    VALUES (
        NEW.user_id,
        GREATEST(COALESCE(NEW.flyers_delivered, 0), 0),
        GREATEST(COALESCE(NEW.conversations, 0), 0),
        GREATEST(COALESCE(NEW.distance_meters, 0), 0) / 1000.0,
        GREATEST(COALESCE(FLOOR(EXTRACT(EPOCH FROM (NEW.end_time - NEW.start_time)) / 60.0)::INTEGER, 0), 0)
    )
    ON CONFLICT (user_id) DO UPDATE SET
        flyers = public.user_stats.flyers + EXCLUDED.flyers,
        conversations = public.user_stats.conversations + EXCLUDED.conversations,
        distance_walked = public.user_stats.distance_walked + EXCLUDED.distance_walked,
        time_tracked = public.user_stats.time_tracked + EXCLUDED.time_tracked,
        updated_at = NOW();

    RETURN NEW;
END;
$function$;

CREATE TRIGGER trigger_update_user_stats_from_session
    AFTER INSERT OR UPDATE OF end_time ON public.sessions
    FOR EACH ROW
    WHEN (NEW.end_time IS NOT NULL)
    EXECUTE FUNCTION public.update_user_stats_from_session();

COMMIT;

NOTIFY pgrst, 'reload schema';
