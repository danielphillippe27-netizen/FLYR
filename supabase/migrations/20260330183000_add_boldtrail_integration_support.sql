-- Add BoldTrail / kvCORE as a first-class CRM provider and allow generic remote object links.

-- Normalize common legacy aliases before re-applying stricter checks.
update public.user_integrations
set provider = 'fub'
where lower(btrim(provider)) in ('followupboss', 'follow_up_boss', 'follow-up-boss');

update public.user_integrations
set provider = 'kvcore'
where lower(btrim(provider)) in ('kv core', 'kv-core');

update public.user_integrations
set provider = 'monday'
where lower(btrim(provider)) in ('monday.com', 'mondaycom');

update public.user_integrations
set provider = 'zapier'
where lower(btrim(provider)) in ('webhook', 'webhooks');

update public.user_integrations
set provider = 'boldtrail'
where lower(btrim(provider)) in ('boldtrail / kvcore', 'boldtrail/kvcore', 'boldtrail kvcore');

update public.crm_connections
set provider = 'fub'
where lower(btrim(provider)) in ('followupboss', 'follow_up_boss', 'follow-up-boss');

update public.crm_connections
set provider = 'kvcore'
where lower(btrim(provider)) in ('kv core', 'kv-core');

update public.crm_connections
set provider = 'monday'
where lower(btrim(provider)) in ('monday.com', 'mondaycom');

update public.crm_connections
set provider = 'zapier'
where lower(btrim(provider)) in ('webhook', 'webhooks');

update public.crm_connections
set provider = 'boldtrail'
where lower(btrim(provider)) in ('boldtrail / kvcore', 'boldtrail/kvcore', 'boldtrail kvcore');

update public.crm_object_links
set crm_type = 'fub'
where lower(btrim(crm_type)) in ('followupboss', 'follow_up_boss', 'follow-up-boss');

update public.crm_object_links
set crm_type = 'kvcore'
where lower(btrim(crm_type)) in ('kv core', 'kv-core');

update public.crm_object_links
set crm_type = 'monday'
where lower(btrim(crm_type)) in ('monday.com', 'mondaycom');

update public.crm_object_links
set crm_type = 'boldtrail'
where lower(btrim(crm_type)) in ('boldtrail / kvcore', 'boldtrail/kvcore', 'boldtrail kvcore');

do $$
declare
  invalid_user_integrations text;
  invalid_crm_connections text;
  invalid_crm_object_links text;
begin
  select string_agg(distinct provider, ', ' order by provider)
  into invalid_user_integrations
  from public.user_integrations
  where provider not in ('fub', 'kvcore', 'boldtrail', 'hubspot', 'monday', 'zapier');

  if invalid_user_integrations is not null then
    raise exception 'Unsupported user_integrations.provider values remain: %', invalid_user_integrations;
  end if;

  select string_agg(distinct provider, ', ' order by provider)
  into invalid_crm_connections
  from public.crm_connections
  where provider not in ('fub', 'kvcore', 'boldtrail', 'hubspot', 'monday', 'zapier');

  if invalid_crm_connections is not null then
    raise exception 'Unsupported crm_connections.provider values remain: %', invalid_crm_connections;
  end if;

  select string_agg(distinct crm_type, ', ' order by crm_type)
  into invalid_crm_object_links
  from public.crm_object_links
  where crm_type not in ('fub', 'kvcore', 'monday', 'boldtrail');

  if invalid_crm_object_links is not null then
    raise exception 'Unsupported crm_object_links.crm_type values remain: %', invalid_crm_object_links;
  end if;
end $$;

alter table public.user_integrations
  drop constraint if exists user_integrations_provider_check;

alter table public.user_integrations
  add constraint user_integrations_provider_check
  check (provider in ('fub', 'kvcore', 'boldtrail', 'hubspot', 'monday', 'zapier'));

alter table public.crm_connections
  drop constraint if exists crm_connections_provider_check;

alter table public.crm_connections
  add constraint crm_connections_provider_check
  check (provider in ('fub', 'kvcore', 'boldtrail', 'hubspot', 'monday', 'zapier'));

alter table public.crm_object_links
  drop constraint if exists crm_object_links_crm_type_check;

alter table public.crm_object_links
  add constraint crm_object_links_crm_type_check
  check (crm_type in ('fub', 'kvcore', 'monday', 'boldtrail'));

comment on constraint user_integrations_provider_check on public.user_integrations is 'Supported user_integrations providers.';
comment on constraint crm_connections_provider_check on public.crm_connections is 'Supported secure CRM connection providers.';
comment on constraint crm_object_links_crm_type_check on public.crm_object_links is 'Supported CRM remote object link providers.';

notify pgrst, 'reload schema';
