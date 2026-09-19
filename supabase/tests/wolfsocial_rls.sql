-- Run with: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/wolfsocial_rls.sql
-- The transaction rolls back every fixture.
begin;

create temporary table wolfsocial_test_users as
select id, row_number() over (order by created_at) as position
from auth.users
order by created_at
limit 2;

do $$
begin
  if (select count(*) from wolfsocial_test_users) < 2 then
    raise exception 'WolfSocial RLS test requires two existing auth users';
  end if;
end;
$$;

create temporary table wolfsocial_test_workspaces (id uuid, owner_user_id uuid, position bigint);
with inserted as (
  insert into public.social_workspaces (owner_user_id, name, slug)
  select id, 'RLS Test ' || position, 'rls-test-' || replace(id::text, '-', '') || '-' || floor(extract(epoch from clock_timestamp()))::bigint
  from wolfsocial_test_users
  returning id, owner_user_id
)
insert into wolfsocial_test_workspaces
select inserted.id, inserted.owner_user_id, users.position
from inserted join wolfsocial_test_users users on users.id = inserted.owner_user_id;

insert into public.social_workspace_members (social_workspace_id, user_id, role)
select id, owner_user_id, 'owner' from wolfsocial_test_workspaces;

grant select on wolfsocial_test_users, wolfsocial_test_workspaces to authenticated;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', (select owner_user_id from wolfsocial_test_workspaces where position = 1), 'role', 'authenticated')::text,
  true
);
set local role authenticated;

do $$
declare own_count integer; foreign_count integer; first_user uuid; foreign_workspace uuid;
begin
  select owner_user_id into first_user from wolfsocial_test_workspaces where position = 1;
  select id into foreign_workspace from wolfsocial_test_workspaces where position = 2;
  select count(*) into own_count from public.social_workspaces where owner_user_id = first_user;
  select count(*) into foreign_count from public.social_workspaces where id = foreign_workspace;
  if own_count < 1 then raise exception 'Member could not read own social workspace'; end if;
  if foreign_count <> 0 then raise exception 'Cross-workspace read was not denied'; end if;

  begin
    insert into public.social_connections (
      social_workspace_id, user_id, platform, external_account_id, access_token_encrypted
    ) values (foreign_workspace, first_user, 'youtube', 'rls-denied', 'encrypted-test-token');
    raise exception 'Cross-workspace connection insert unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;

reset role;
rollback;
