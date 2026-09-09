-- WolfSocial shared workspaces for standalone web, embedded Sales, and Sales iOS.
create extension if not exists pgcrypto;

create table if not exists public.social_workspaces (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  name text not null default 'My WolfSocial',
  slug text not null unique,
  settings jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.social_workspace_members (
  social_workspace_id uuid not null references public.social_workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'owner' check (role in ('owner', 'admin', 'member')),
  created_at timestamptz not null default now(),
  primary key (social_workspace_id, user_id)
);

-- Backfill one workspace for every user that already owns social data.
insert into public.social_workspaces (owner_user_id, name, slug)
select distinct u.user_id, 'My WolfSocial', 'wolf-' || replace(u.user_id::text, '-', '')
from (
  select user_id from public.social_connections
  union select user_id from public.social_media_assets
  union select user_id from public.social_posts
  union select user_id from public.social_interactions
) u
on conflict (slug) do nothing;

insert into public.social_workspace_members (social_workspace_id, user_id, role)
select id, owner_user_id, 'owner' from public.social_workspaces
on conflict do nothing;

alter table public.social_connections add column if not exists social_workspace_id uuid references public.social_workspaces(id) on delete cascade;
alter table public.social_media_assets add column if not exists social_workspace_id uuid references public.social_workspaces(id) on delete cascade;
alter table public.social_posts add column if not exists social_workspace_id uuid references public.social_workspaces(id) on delete cascade;
alter table public.social_interactions add column if not exists social_workspace_id uuid references public.social_workspaces(id) on delete cascade;

update public.social_connections c set social_workspace_id = w.id from public.social_workspaces w where c.social_workspace_id is null and w.owner_user_id = c.user_id;
update public.social_media_assets a set social_workspace_id = w.id from public.social_workspaces w where a.social_workspace_id is null and w.owner_user_id = a.user_id;
update public.social_posts p set social_workspace_id = w.id from public.social_workspaces w where p.social_workspace_id is null and w.owner_user_id = p.user_id;
update public.social_interactions i set social_workspace_id = w.id from public.social_workspaces w where i.social_workspace_id is null and w.owner_user_id = i.user_id;

alter table public.social_connections alter column social_workspace_id set not null;
alter table public.social_media_assets alter column social_workspace_id set not null;
alter table public.social_posts alter column social_workspace_id set not null;
alter table public.social_interactions alter column social_workspace_id set not null;

-- Multiple connections per provider are allowed; uniqueness is workspace/account based.
alter table public.social_connections drop constraint if exists social_connections_user_id_platform_external_account_id_key;
alter table public.social_connections add constraint social_connections_workspace_platform_account_key unique (social_workspace_id, platform, external_account_id);

-- Add Facebook Pages to every normalized provider check.
alter table public.social_connections drop constraint if exists social_connections_platform_check;
alter table public.social_connections add constraint social_connections_platform_check check (platform in ('facebook', 'instagram', 'tiktok', 'youtube'));
alter table public.social_post_targets drop constraint if exists social_post_targets_platform_check;
alter table public.social_post_targets add constraint social_post_targets_platform_check check (platform in ('facebook', 'instagram', 'tiktok', 'youtube'));
alter table public.social_interactions drop constraint if exists social_interactions_platform_check;
alter table public.social_interactions add constraint social_interactions_platform_check check (platform in ('facebook', 'instagram', 'tiktok', 'youtube'));
alter table public.social_webhook_events drop constraint if exists social_webhook_events_platform_check;
alter table public.social_webhook_events add constraint social_webhook_events_platform_check check (platform in ('facebook', 'instagram', 'tiktok', 'youtube'));

alter table public.social_post_targets add column if not exists format text;
alter table public.social_post_targets add column if not exists caption text;
alter table public.social_post_targets add column if not exists title text;
alter table public.social_post_targets add column if not exists settings jsonb not null default '{}';
alter table public.social_post_targets add column if not exists next_attempt_at timestamptz;
alter table public.social_post_targets add column if not exists idempotency_key text;
create unique index if not exists social_target_idempotency_idx on public.social_post_targets(idempotency_key) where idempotency_key is not null;

create table if not exists public.social_contacts (
  id uuid primary key default gen_random_uuid(),
  social_workspace_id uuid not null references public.social_workspaces(id) on delete cascade,
  connection_id uuid references public.social_connections(id) on delete set null,
  platform text not null check (platform in ('facebook', 'instagram', 'tiktok', 'youtube')),
  external_id text not null,
  display_name text,
  username text,
  avatar_url text,
  email text,
  phone text,
  sales_lead_id uuid,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (social_workspace_id, platform, external_id)
);

create table if not exists public.social_threads (
  id uuid primary key default gen_random_uuid(),
  social_workspace_id uuid not null references public.social_workspaces(id) on delete cascade,
  connection_id uuid not null references public.social_connections(id) on delete cascade,
  contact_id uuid references public.social_contacts(id) on delete set null,
  platform text not null check (platform in ('facebook', 'instagram', 'tiktok', 'youtube')),
  kind text not null check (kind in ('comment', 'message')),
  external_id text not null,
  subject text,
  last_message_at timestamptz,
  unread_count integer not null default 0,
  needs_reply boolean not null default false,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (connection_id, external_id)
);

alter table public.social_interactions add column if not exists thread_id uuid references public.social_threads(id) on delete cascade;
alter table public.social_interactions add column if not exists contact_id uuid references public.social_contacts(id) on delete set null;
alter table public.social_interactions add column if not exists status text not null default 'received' check (status in ('received', 'queued', 'sent', 'failed'));

create table if not exists public.social_post_metrics (
  id uuid primary key default gen_random_uuid(),
  social_workspace_id uuid not null references public.social_workspaces(id) on delete cascade,
  target_id uuid not null references public.social_post_targets(id) on delete cascade,
  captured_at timestamptz not null default now(),
  impressions bigint,
  reach bigint,
  views bigint,
  likes bigint,
  comments bigint,
  shares bigint,
  saves bigint,
  watch_time_seconds numeric,
  raw_payload jsonb not null default '{}'
);

create table if not exists public.social_oauth_states (
  state_hash text primary key,
  social_workspace_id uuid not null references public.social_workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  platform text not null check (platform in ('facebook', 'instagram', 'tiktok', 'youtube')),
  initiating_surface text not null check (initiating_surface in ('standalone', 'sales_web', 'sales_ios')),
  return_to text,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists social_members_user_idx on public.social_workspace_members(user_id);
create index if not exists social_connections_workspace_idx on public.social_connections(social_workspace_id, platform);
create index if not exists social_assets_workspace_idx on public.social_media_assets(social_workspace_id, created_at desc);
create index if not exists social_posts_workspace_idx on public.social_posts(social_workspace_id, created_at desc);
create index if not exists social_threads_inbox_idx on public.social_threads(social_workspace_id, needs_reply, last_message_at desc);
create index if not exists social_metrics_target_idx on public.social_post_metrics(target_id, captured_at desc);

create or replace function public.is_social_workspace_member(workspace uuid)
returns boolean language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.social_workspace_members m where m.social_workspace_id = workspace and m.user_id = auth.uid()) $$;
revoke all on function public.is_social_workspace_member(uuid) from public;
grant execute on function public.is_social_workspace_member(uuid) to authenticated;

alter table public.social_workspaces enable row level security;
alter table public.social_workspace_members enable row level security;
alter table public.social_contacts enable row level security;
alter table public.social_threads enable row level security;
alter table public.social_post_metrics enable row level security;
alter table public.social_oauth_states enable row level security;

drop policy if exists "social connections are private" on public.social_connections;
drop policy if exists "social assets are private" on public.social_media_assets;
drop policy if exists "social posts are private" on public.social_posts;
drop policy if exists "social post assets follow post owner" on public.social_post_assets;
drop policy if exists "social targets follow post owner" on public.social_post_targets;
drop policy if exists "social interactions are private" on public.social_interactions;

create policy "members read social workspaces" on public.social_workspaces for select using (public.is_social_workspace_member(id));
create policy "owners update social workspaces" on public.social_workspaces for update using (owner_user_id = auth.uid()) with check (owner_user_id = auth.uid());
create policy "members read memberships" on public.social_workspace_members for select using (public.is_social_workspace_member(social_workspace_id));
create policy "workspace connections" on public.social_connections for all using (public.is_social_workspace_member(social_workspace_id)) with check (public.is_social_workspace_member(social_workspace_id));
create policy "workspace assets" on public.social_media_assets for all using (public.is_social_workspace_member(social_workspace_id)) with check (public.is_social_workspace_member(social_workspace_id));
create policy "workspace posts" on public.social_posts for all using (public.is_social_workspace_member(social_workspace_id)) with check (public.is_social_workspace_member(social_workspace_id));
create policy "workspace post assets" on public.social_post_assets for all using (exists (select 1 from public.social_posts p where p.id = post_id and public.is_social_workspace_member(p.social_workspace_id))) with check (exists (select 1 from public.social_posts p where p.id = post_id and public.is_social_workspace_member(p.social_workspace_id)));
create policy "workspace targets" on public.social_post_targets for all using (exists (select 1 from public.social_posts p where p.id = post_id and public.is_social_workspace_member(p.social_workspace_id))) with check (exists (select 1 from public.social_posts p where p.id = post_id and public.is_social_workspace_member(p.social_workspace_id)));
create policy "workspace contacts" on public.social_contacts for all using (public.is_social_workspace_member(social_workspace_id)) with check (public.is_social_workspace_member(social_workspace_id));
create policy "workspace threads" on public.social_threads for all using (public.is_social_workspace_member(social_workspace_id)) with check (public.is_social_workspace_member(social_workspace_id));
create policy "workspace interactions" on public.social_interactions for all using (public.is_social_workspace_member(social_workspace_id)) with check (public.is_social_workspace_member(social_workspace_id));
create policy "workspace metrics" on public.social_post_metrics for select using (public.is_social_workspace_member(social_workspace_id));
create policy "own oauth states" on public.social_oauth_states for select using (user_id = auth.uid());

-- Server-side helper used after public signup and by existing users on first access.
create or replace function public.ensure_social_workspace(target_user uuid, workspace_name text default 'My WolfSocial')
returns uuid language plpgsql security definer set search_path = public
as $$
declare workspace uuid;
begin
  if target_user <> auth.uid() and auth.role() <> 'service_role' then raise exception 'not allowed'; end if;
  select social_workspace_id into workspace from public.social_workspace_members where user_id = target_user order by created_at limit 1;
  if workspace is not null then return workspace; end if;
  insert into public.social_workspaces(owner_user_id, name, slug)
  values(target_user, coalesce(nullif(workspace_name, ''), 'My WolfSocial'), 'wolf-' || replace(target_user::text, '-', ''))
  on conflict(slug) do update set updated_at = now()
  returning id into workspace;
  insert into public.social_workspace_members(social_workspace_id, user_id, role) values(workspace, target_user, 'owner') on conflict do nothing;
  return workspace;
end;
$$;
revoke all on function public.ensure_social_workspace(uuid, text) from public, anon;
grant execute on function public.ensure_social_workspace(uuid, text) to authenticated, service_role;

-- Claim target-level jobs with bounded retries and skip-locked concurrency.
create or replace function public.claim_due_social_targets(batch_size integer default 10)
returns setof public.social_post_targets
language plpgsql security definer set search_path = public
as $$
begin
  return query
  with due as (
    select t.id from public.social_post_targets t
    join public.social_posts p on p.id = t.post_id
    where p.status in ('scheduled', 'publishing', 'partial_failed', 'failed')
      and coalesce(p.scheduled_for, now()) <= now()
      and t.status in ('pending', 'failed')
      and t.attempt_count < 5
      and coalesce(t.next_attempt_at, now()) <= now()
    order by coalesce(p.scheduled_for, p.created_at), t.created_at
    for update of t skip locked
    limit greatest(1, least(batch_size, 50))
  )
  update public.social_post_targets t
  set status = 'uploading', attempt_count = t.attempt_count + 1, last_attempt_at = now(), updated_at = now()
  from due where t.id = due.id returning t.*;
end;
$$;
revoke all on function public.claim_due_social_targets(integer) from public, anon, authenticated;
grant execute on function public.claim_due_social_targets(integer) to service_role;
