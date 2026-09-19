-- Multi-channel social publishing for the salesperson workspace.
create extension if not exists pgcrypto;

create table if not exists public.social_connections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  salesperson_id uuid references public.salespeople(id) on delete cascade,
  platform text not null check (platform in ('instagram', 'tiktok', 'youtube')),
  external_account_id text not null,
  account_name text,
  account_avatar_url text,
  access_token_encrypted text not null,
  refresh_token_encrypted text,
  scopes text[] not null default '{}',
  token_expires_at timestamptz,
  status text not null default 'active' check (status in ('active', 'expired', 'revoked', 'error')),
  metadata jsonb not null default '{}',
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, platform, external_account_id)
);

create table if not exists public.social_media_assets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  storage_path text not null unique,
  mime_type text not null,
  byte_size bigint not null,
  width integer,
  height integer,
  duration_seconds numeric,
  original_name text,
  created_at timestamptz not null default now()
);

create table if not exists public.social_posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  caption text not null default '',
  title text,
  content_type text not null check (content_type in ('feed', 'carousel', 'reel', 'story', 'short', 'tiktok_video', 'tiktok_photo')),
  status text not null default 'draft' check (status in ('draft', 'scheduled', 'publishing', 'published', 'partial_failed', 'failed', 'cancelled')),
  scheduled_for timestamptz,
  claimed_at timestamptz,
  published_at timestamptz,
  timezone text,
  settings jsonb not null default '{}',
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.social_post_assets (
  post_id uuid not null references public.social_posts(id) on delete cascade,
  asset_id uuid not null references public.social_media_assets(id) on delete cascade,
  position integer not null default 0,
  primary key (post_id, asset_id)
);

create table if not exists public.social_post_targets (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.social_posts(id) on delete cascade,
  connection_id uuid not null references public.social_connections(id) on delete cascade,
  platform text not null check (platform in ('instagram', 'tiktok', 'youtube')),
  status text not null default 'pending' check (status in ('pending', 'uploading', 'processing', 'published', 'failed', 'cancelled')),
  external_publish_id text,
  external_post_id text,
  external_url text,
  attempt_count integer not null default 0,
  last_attempt_at timestamptz,
  last_error text,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (post_id, connection_id)
);

create table if not exists public.social_interactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  connection_id uuid not null references public.social_connections(id) on delete cascade,
  platform text not null check (platform in ('instagram', 'tiktok', 'youtube')),
  kind text not null check (kind in ('comment', 'reply', 'message')),
  external_id text not null,
  external_parent_id text,
  external_post_id text,
  sender_external_id text,
  sender_name text,
  body text not null default '',
  direction text not null default 'inbound' check (direction in ('inbound', 'outbound')),
  needs_reply boolean not null default false,
  occurred_at timestamptz not null,
  raw_payload jsonb not null default '{}',
  created_at timestamptz not null default now(),
  unique (platform, connection_id, external_id)
);

create table if not exists public.social_webhook_events (
  id uuid primary key default gen_random_uuid(),
  platform text not null check (platform in ('instagram', 'tiktok', 'youtube')),
  event_key text not null unique,
  payload jsonb not null,
  processed_at timestamptz,
  error text,
  created_at timestamptz not null default now()
);

create index if not exists social_posts_due_idx on public.social_posts (scheduled_for)
  where status = 'scheduled';
create index if not exists social_interactions_inbox_idx on public.social_interactions (user_id, needs_reply, occurred_at desc);

alter table public.social_connections enable row level security;
alter table public.social_media_assets enable row level security;
alter table public.social_posts enable row level security;
alter table public.social_post_assets enable row level security;
alter table public.social_post_targets enable row level security;
alter table public.social_interactions enable row level security;
alter table public.social_webhook_events enable row level security;

create policy "social connections are private" on public.social_connections for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "social assets are private" on public.social_media_assets for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "social posts are private" on public.social_posts for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "social post assets follow post owner" on public.social_post_assets for all using (exists (select 1 from public.social_posts p where p.id = post_id and p.user_id = auth.uid())) with check (exists (select 1 from public.social_posts p where p.id = post_id and p.user_id = auth.uid()));
create policy "social targets follow post owner" on public.social_post_targets for all using (exists (select 1 from public.social_posts p where p.id = post_id and p.user_id = auth.uid())) with check (exists (select 1 from public.social_posts p where p.id = post_id and p.user_id = auth.uid()));
create policy "social interactions are private" on public.social_interactions for all using (user_id = auth.uid()) with check (user_id = auth.uid());

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('social-media', 'social-media', false, 4294967296, array['image/jpeg','image/png','image/webp','video/mp4','video/quicktime','video/webm'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create policy "salespeople upload their social media" on storage.objects for insert to authenticated
with check (bucket_id = 'social-media' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "salespeople read their social media" on storage.objects for select to authenticated
using (bucket_id = 'social-media' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "salespeople delete their social media" on storage.objects for delete to authenticated
using (bucket_id = 'social-media' and (storage.foldername(name))[1] = auth.uid()::text);

create or replace function public.claim_due_social_posts(batch_size integer default 10)
returns setof public.social_posts
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with due as (
    select id from public.social_posts
    where status = 'scheduled' and scheduled_for <= now()
    order by scheduled_for
    for update skip locked
    limit greatest(1, least(batch_size, 50))
  )
  update public.social_posts p
  set status = 'publishing', claimed_at = now(), updated_at = now()
  from due
  where p.id = due.id
  returning p.*;
end;
$$;

revoke all on function public.claim_due_social_posts(integer) from public, anon, authenticated;
grant execute on function public.claim_due_social_posts(integer) to service_role;
