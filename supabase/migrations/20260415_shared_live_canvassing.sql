BEGIN;

-- ---------------------------------------------------------------------------
-- 1) campaign_members
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.campaign_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id UUID NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'member')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (campaign_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_campaign_members_campaign_id
    ON public.campaign_members(campaign_id);

CREATE INDEX IF NOT EXISTS idx_campaign_members_user_id
    ON public.campaign_members(user_id);

ALTER TABLE public.campaign_members ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.is_campaign_member(
    p_campaign_id UUID,
    p_user_id UUID DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.campaigns c
        WHERE c.id = p_campaign_id
          AND (
              (c.owner_id::text) = (p_user_id::text)
              OR (c.workspace_id IS NOT NULL AND EXISTS (
                  SELECT 1
                  FROM public.workspaces w
                  WHERE w.id = c.workspace_id
                    AND (w.owner_id::text) = (p_user_id::text)
              ))
              OR (c.workspace_id IS NOT NULL AND EXISTS (
                  SELECT 1
                  FROM public.workspace_members wm
                  WHERE wm.workspace_id = c.workspace_id
                    AND (wm.user_id::text) = (p_user_id::text)
              ))
              OR EXISTS (
                  SELECT 1
                  FROM public.campaign_members cm
                  WHERE cm.campaign_id = p_campaign_id
                    AND (cm.user_id::text) = (p_user_id::text)
              )
          )
    );
$$;

COMMENT ON FUNCTION public.is_campaign_member(uuid, uuid)
    IS 'True when the given user is the campaign owner, a workspace member on the campaign workspace, or explicitly listed in campaign_members.';

DROP POLICY IF EXISTS "campaign_members_select_member" ON public.campaign_members;
CREATE POLICY "campaign_members_select_member"
    ON public.campaign_members
    FOR SELECT TO authenticated
    USING (public.is_campaign_member(campaign_id));

DROP POLICY IF EXISTS "campaign_members_insert_owner" ON public.campaign_members;
CREATE POLICY "campaign_members_insert_owner"
    ON public.campaign_members
    FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.campaigns c
            WHERE c.id = campaign_members.campaign_id
              AND (c.owner_id::text) = (auth.uid()::text)
        )
    );

DROP POLICY IF EXISTS "campaign_members_update_owner" ON public.campaign_members;
CREATE POLICY "campaign_members_update_owner"
    ON public.campaign_members
    FOR UPDATE TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.campaigns c
            WHERE c.id = campaign_members.campaign_id
              AND (c.owner_id::text) = (auth.uid()::text)
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.campaigns c
            WHERE c.id = campaign_members.campaign_id
              AND (c.owner_id::text) = (auth.uid()::text)
        )
    );

DROP POLICY IF EXISTS "campaign_members_delete_owner" ON public.campaign_members;
CREATE POLICY "campaign_members_delete_owner"
    ON public.campaign_members
    FOR DELETE TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.campaigns c
            WHERE c.id = campaign_members.campaign_id
              AND (c.owner_id::text) = (auth.uid()::text)
        )
    );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.campaign_members TO authenticated;
GRANT ALL ON public.campaign_members TO service_role;
GRANT EXECUTE ON FUNCTION public.is_campaign_member(uuid, uuid) TO authenticated, service_role;

INSERT INTO public.campaign_members (campaign_id, user_id, role)
SELECT c.id, c.owner_id, 'owner'
FROM public.campaigns c
JOIN auth.users au
    ON au.id = c.owner_id
ON CONFLICT (campaign_id, user_id) DO UPDATE
SET role = 'owner';

INSERT INTO public.campaign_members (campaign_id, user_id, role)
SELECT
    c.id,
    wm.user_id,
    CASE
        WHEN wm.role = 'owner' THEN 'owner'
        WHEN wm.role = 'admin' THEN 'admin'
        ELSE 'member'
    END
FROM public.campaigns c
JOIN public.workspace_members wm
    ON wm.workspace_id = c.workspace_id
JOIN auth.users au
    ON au.id = wm.user_id
WHERE c.workspace_id IS NOT NULL
ON CONFLICT (campaign_id, user_id) DO UPDATE
SET role = CASE
    WHEN public.campaign_members.role = 'owner' THEN public.campaign_members.role
    ELSE EXCLUDED.role
END;

CREATE OR REPLACE FUNCTION public.sync_campaign_members_from_campaign()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.owner_id IS NOT NULL
       AND EXISTS (
           SELECT 1
           FROM auth.users au
           WHERE au.id = NEW.owner_id
       ) THEN
        INSERT INTO public.campaign_members (campaign_id, user_id, role)
        VALUES (NEW.id, NEW.owner_id, 'owner')
        ON CONFLICT (campaign_id, user_id) DO UPDATE
        SET role = 'owner';
    END IF;

    IF NEW.workspace_id IS NOT NULL THEN
        INSERT INTO public.campaign_members (campaign_id, user_id, role)
        SELECT
            NEW.id,
            wm.user_id,
            CASE
                WHEN wm.role = 'owner' THEN 'owner'
                WHEN wm.role = 'admin' THEN 'admin'
                ELSE 'member'
            END
        FROM public.workspace_members wm
        JOIN auth.users au
            ON au.id = wm.user_id
        WHERE wm.workspace_id = NEW.workspace_id
        ON CONFLICT (campaign_id, user_id) DO UPDATE
        SET role = CASE
            WHEN public.campaign_members.role = 'owner' THEN public.campaign_members.role
            ELSE EXCLUDED.role
        END;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_campaign_members_from_campaign ON public.campaigns;
CREATE TRIGGER sync_campaign_members_from_campaign
    AFTER INSERT ON public.campaigns
    FOR EACH ROW
    EXECUTE FUNCTION public.sync_campaign_members_from_campaign();

CREATE OR REPLACE FUNCTION public.sync_campaign_members_from_workspace_member()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM auth.users au
        WHERE au.id = NEW.user_id
    ) THEN
        INSERT INTO public.campaign_members (campaign_id, user_id, role)
        SELECT
            c.id,
            NEW.user_id,
            CASE
                WHEN NEW.role = 'owner' THEN 'owner'
                WHEN NEW.role = 'admin' THEN 'admin'
                ELSE 'member'
            END
        FROM public.campaigns c
        WHERE c.workspace_id = NEW.workspace_id
        ON CONFLICT (campaign_id, user_id) DO UPDATE
        SET role = CASE
            WHEN public.campaign_members.role = 'owner' THEN public.campaign_members.role
            ELSE EXCLUDED.role
        END;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_campaign_members_from_workspace_member ON public.workspace_members;
CREATE TRIGGER sync_campaign_members_from_workspace_member
    AFTER INSERT ON public.workspace_members
    FOR EACH ROW
    EXECUTE FUNCTION public.sync_campaign_members_from_workspace_member();

CREATE OR REPLACE FUNCTION public.rpc_get_campaign_member_directory(p_campaign_id UUID)
RETURNS TABLE (
    user_id UUID,
    role TEXT,
    display_name TEXT,
    email TEXT,
    avatar_url TEXT,
    created_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        cm.user_id,
        cm.role,
        COALESCE(
            NULLIF(TRIM(COALESCE(p.nickname, '')), ''),
            NULLIF(TRIM(COALESCE(p.full_name, '')), ''),
            NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)), ''),
            NULLIF(SPLIT_PART(COALESCE(p.email, ''), '@', 1), ''),
            LEFT(cm.user_id::text, 8)
        ) AS display_name,
        p.email,
        COALESCE(NULLIF(TRIM(COALESCE(p.profile_image_url, '')), ''), p.avatar_url) AS avatar_url,
        cm.created_at
    FROM public.campaign_members cm
    LEFT JOIN public.profiles p
        ON p.id = cm.user_id
    WHERE cm.campaign_id = p_campaign_id
      AND public.is_campaign_member(p_campaign_id)
    ORDER BY
        CASE cm.role
            WHEN 'owner' THEN 0
            WHEN 'admin' THEN 1
            ELSE 2
        END,
        lower(
            COALESCE(
                NULLIF(TRIM(COALESCE(p.nickname, '')), ''),
                NULLIF(TRIM(COALESCE(p.full_name, '')), ''),
                NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)), ''),
                NULLIF(SPLIT_PART(COALESCE(p.email, ''), '@', 1), ''),
                cm.user_id::text
            )
        );
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_campaign_member_directory(uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) campaign_presence
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.campaign_presence (
    campaign_id UUID NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id UUID NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
    lat DOUBLE PRECISION,
    lng DOUBLE PRECISION,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paused', 'inactive')),
    PRIMARY KEY (campaign_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_campaign_presence_campaign_updated
    ON public.campaign_presence(campaign_id, updated_at DESC);

ALTER TABLE public.campaign_presence ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "campaign_presence_select_member" ON public.campaign_presence;
CREATE POLICY "campaign_presence_select_member"
    ON public.campaign_presence
    FOR SELECT TO authenticated
    USING (public.is_campaign_member(campaign_id));

DROP POLICY IF EXISTS "campaign_presence_insert_self" ON public.campaign_presence;
CREATE POLICY "campaign_presence_insert_self"
    ON public.campaign_presence
    FOR INSERT TO authenticated
    WITH CHECK (
        (user_id::text) = (auth.uid()::text)
        AND public.is_campaign_member(campaign_id)
    );

DROP POLICY IF EXISTS "campaign_presence_update_self" ON public.campaign_presence;
CREATE POLICY "campaign_presence_update_self"
    ON public.campaign_presence
    FOR UPDATE TO authenticated
    USING (
        (user_id::text) = (auth.uid()::text)
        AND public.is_campaign_member(campaign_id)
    )
    WITH CHECK (
        (user_id::text) = (auth.uid()::text)
        AND public.is_campaign_member(campaign_id)
    );

DROP POLICY IF EXISTS "campaign_presence_delete_self" ON public.campaign_presence;
CREATE POLICY "campaign_presence_delete_self"
    ON public.campaign_presence
    FOR DELETE TO authenticated
    USING (
        (user_id::text) = (auth.uid()::text)
        AND public.is_campaign_member(campaign_id)
    );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.campaign_presence TO authenticated;
GRANT ALL ON public.campaign_presence TO service_role;

-- ---------------------------------------------------------------------------
-- 3) campaign_home_events
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.campaign_home_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id UUID NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
    campaign_address_id UUID NOT NULL REFERENCES public.campaign_addresses(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id UUID NULL REFERENCES public.sessions(id) ON DELETE SET NULL,
    action_type TEXT NOT NULL,
    note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_campaign_home_events_campaign_created
    ON public.campaign_home_events(campaign_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_campaign_home_events_campaign_address_created
    ON public.campaign_home_events(campaign_address_id, created_at DESC);

ALTER TABLE public.campaign_home_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "campaign_home_events_select_member" ON public.campaign_home_events;
CREATE POLICY "campaign_home_events_select_member"
    ON public.campaign_home_events
    FOR SELECT TO authenticated
    USING (public.is_campaign_member(campaign_id));

GRANT SELECT ON public.campaign_home_events TO authenticated;
GRANT ALL ON public.campaign_home_events TO service_role;

-- ---------------------------------------------------------------------------
-- 4) address_statuses attribution columns
-- ---------------------------------------------------------------------------
ALTER TABLE public.address_statuses
    ADD COLUMN IF NOT EXISTS last_action_by UUID,
    ADD COLUMN IF NOT EXISTS last_session_id UUID,
    ADD COLUMN IF NOT EXISTS last_home_event_id UUID;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'address_statuses_last_action_by_fkey'
    ) THEN
        ALTER TABLE public.address_statuses
            ADD CONSTRAINT address_statuses_last_action_by_fkey
            FOREIGN KEY (last_action_by)
            REFERENCES auth.users(id)
            ON DELETE SET NULL;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'address_statuses_last_session_id_fkey'
    ) THEN
        ALTER TABLE public.address_statuses
            ADD CONSTRAINT address_statuses_last_session_id_fkey
            FOREIGN KEY (last_session_id)
            REFERENCES public.sessions(id)
            ON DELETE SET NULL;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'address_statuses_last_home_event_id_fkey'
    ) THEN
        ALTER TABLE public.address_statuses
            ADD CONSTRAINT address_statuses_last_home_event_id_fkey
            FOREIGN KEY (last_home_event_id)
            REFERENCES public.campaign_home_events(id)
            ON DELETE SET NULL;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 5) Canonical RPCs: preserve canonical path, add events + attribution
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
  v_actor_user_id uuid := auth.uid();
  v_campaign_address_id uuid := coalesce(p_campaign_address_id, p_address_id);
  v_status text := lower(trim(coalesce(p_status, 'none')));
  v_notes text := nullif(trim(coalesce(p_notes, '')), '');
  v_visited boolean;
  v_session_user_id uuid;
  v_session_campaign_id uuid;
  v_session_event_id uuid;
  v_session_event_building_id uuid;
  v_home_event_id uuid;
  v_has_campaign_address_fk boolean;
  v_has_address_id_fk boolean;
  v_has_campaign_id_fk boolean;
  v_result jsonb;
begin
  if v_actor_user_id is null then
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
  where ca.id = v_campaign_address_id
    and ca.campaign_id = p_campaign_id
    and public.is_campaign_member(ca.campaign_id, v_actor_user_id);

  if not found then
    raise exception 'Campaign address not found or access denied';
  end if;

  if p_session_id is not null then
    select user_id, campaign_id
    into v_session_user_id, v_session_campaign_id
    from public.sessions
    where id = p_session_id;

    if v_session_user_id is null or (v_session_user_id::text) is distinct from (v_actor_user_id::text) then
      raise exception 'Session not found or access denied';
    end if;

    if v_session_campaign_id is distinct from p_campaign_id then
      raise exception 'Session campaign does not match campaign address outcome campaign';
    end if;
  end if;

  insert into public.campaign_home_events (
    campaign_id,
    campaign_address_id,
    user_id,
    session_id,
    action_type,
    note,
    created_at
  ) values (
    p_campaign_id,
    v_campaign_address_id,
    v_actor_user_id,
    p_session_id,
    v_status,
    v_notes,
    p_occurred_at
  )
  returning id into v_home_event_id;

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
          last_action_by,
          last_session_id,
          last_home_event_id,
          updated_at
        ) values (
          $1,
          $2,
          $3,
          $4,
          case when $5 then $6 else null end,
          case when $5 then 1 else 0 end,
          $7,
          $8,
          $9,
          now()
        )
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
          last_action_by = excluded.last_action_by,
          last_session_id = excluded.last_session_id,
          last_home_event_id = excluded.last_home_event_id,
          updated_at = now()
        returning jsonb_build_object(
          'campaign_address_id', campaign_address_id,
          'campaign_id', campaign_id,
          'status', status,
          'notes', notes,
          'visit_count', visit_count,
          'last_visited_at', last_visited_at,
          'updated_at', updated_at,
          'last_action_by', last_action_by,
          'last_session_id', last_session_id,
          'last_home_event_id', last_home_event_id
        )
      $sql$
      into v_result
      using
        v_campaign_address_id,
        p_campaign_id,
        v_status,
        v_notes,
        v_visited,
        p_occurred_at,
        v_actor_user_id,
        p_session_id,
        v_home_event_id;
    else
      execute $sql$
        insert into public.address_statuses (
          campaign_address_id,
          status,
          notes,
          last_visited_at,
          visit_count,
          last_action_by,
          last_session_id,
          last_home_event_id,
          updated_at
        ) values (
          $1,
          $2,
          $3,
          case when $4 then $5 else null end,
          case when $4 then 1 else 0 end,
          $6,
          $7,
          $8,
          now()
        )
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
          last_action_by = excluded.last_action_by,
          last_session_id = excluded.last_session_id,
          last_home_event_id = excluded.last_home_event_id,
          updated_at = now()
        returning jsonb_build_object(
          'campaign_address_id', campaign_address_id,
          'status', status,
          'notes', notes,
          'visit_count', visit_count,
          'last_visited_at', last_visited_at,
          'updated_at', updated_at,
          'last_action_by', last_action_by,
          'last_session_id', last_session_id,
          'last_home_event_id', last_home_event_id
        )
      $sql$
      into v_result
      using
        v_campaign_address_id,
        v_status,
        v_notes,
        v_visited,
        p_occurred_at,
        v_actor_user_id,
        p_session_id,
        v_home_event_id;
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
        last_action_by,
        last_session_id,
        last_home_event_id,
        updated_at
      ) values (
        $1,
        $2,
        $3,
        $4,
        case when $5 then $6 else null end,
        case when $5 then 1 else 0 end,
        $7,
        $8,
        $9,
        now()
      )
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
        last_action_by = excluded.last_action_by,
        last_session_id = excluded.last_session_id,
        last_home_event_id = excluded.last_home_event_id,
        updated_at = now()
      returning jsonb_build_object(
        'address_id', address_id,
        'campaign_id', campaign_id,
        'status', status,
        'notes', notes,
        'visit_count', visit_count,
        'last_visited_at', last_visited_at,
        'updated_at', updated_at,
        'last_action_by', last_action_by,
        'last_session_id', last_session_id,
        'last_home_event_id', last_home_event_id
      )
    $sql$
    into v_result
    using
      v_campaign_address_id,
      p_campaign_id,
      v_status,
      v_notes,
      v_visited,
      p_occurred_at,
      v_actor_user_id,
      p_session_id,
      v_home_event_id;
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
    'session_event_id', v_session_event_id,
    'campaign_home_event_id', v_home_event_id
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
  v_actor_user_id uuid := auth.uid();
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
  if v_actor_user_id is null then
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
  where ca.id = any(v_campaign_address_ids)
    and ca.campaign_id = p_campaign_id
    and public.is_campaign_member(ca.campaign_id, v_actor_user_id);

  if v_validated_count <> coalesce(array_length(v_campaign_address_ids, 1), 0) then
    raise exception 'One or more campaign addresses were not found or access was denied';
  end if;

  if p_session_id is not null then
    select user_id, campaign_id
    into v_session_user_id, v_session_campaign_id
    from public.sessions
    where id = p_session_id;

    if v_session_user_id is null or (v_session_user_id::text) is distinct from (v_actor_user_id::text) then
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
        p_occurred_at => p_occurred_at,
        p_session_id => p_session_id,
        p_session_target_id => p_session_target_id,
        p_session_event_type => null,
        p_lat => p_lat,
        p_lon => p_lon
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

GRANT EXECUTE ON FUNCTION public.record_campaign_address_outcome(uuid, uuid, uuid, text, text, timestamptz, uuid, text, text, double precision, double precision)
    TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.record_campaign_target_outcome(uuid, uuid[], text, text, timestamptz, uuid, text, text, double precision, double precision)
    TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 6) Realtime publication
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_publication
        WHERE pubname = 'supabase_realtime'
    ) THEN
        IF NOT EXISTS (
            SELECT 1
            FROM pg_publication_tables
            WHERE pubname = 'supabase_realtime'
              AND schemaname = 'public'
              AND tablename = 'campaign_presence'
        ) THEN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.campaign_presence;
        END IF;

        IF NOT EXISTS (
            SELECT 1
            FROM pg_publication_tables
            WHERE pubname = 'supabase_realtime'
              AND schemaname = 'public'
              AND tablename = 'address_statuses'
        ) THEN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.address_statuses;
        END IF;
    END IF;
END $$;

COMMIT;
