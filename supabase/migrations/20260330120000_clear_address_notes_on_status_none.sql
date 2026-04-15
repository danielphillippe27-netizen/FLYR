-- When resetting a home to status none, empty p_notes must clear address_statuses.notes.
-- Previously coalesce(excluded.notes, ...) kept old notes when excluded.notes was NULL.

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
          notes = case when excluded.status = 'none'::text then excluded.notes else coalesce(excluded.notes, public.address_statuses.notes) end,
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
          notes = case when excluded.status = 'none'::text then excluded.notes else coalesce(excluded.notes, public.address_statuses.notes) end,
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
        notes = case when excluded.status = 'none'::text then excluded.notes else coalesce(excluded.notes, public.address_statuses.notes) end,
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
