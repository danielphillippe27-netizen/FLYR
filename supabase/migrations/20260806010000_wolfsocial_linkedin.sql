-- LinkedIn personal profile publishing for WolfSocial.
alter table public.social_connections drop constraint if exists social_connections_platform_check;
alter table public.social_connections add constraint social_connections_platform_check check (platform in ('facebook', 'instagram', 'tiktok', 'youtube', 'linkedin'));

alter table public.social_post_targets drop constraint if exists social_post_targets_platform_check;
alter table public.social_post_targets add constraint social_post_targets_platform_check check (platform in ('facebook', 'instagram', 'tiktok', 'youtube', 'linkedin'));

alter table public.social_interactions drop constraint if exists social_interactions_platform_check;
alter table public.social_interactions add constraint social_interactions_platform_check check (platform in ('facebook', 'instagram', 'tiktok', 'youtube', 'linkedin'));

alter table public.social_webhook_events drop constraint if exists social_webhook_events_platform_check;
alter table public.social_webhook_events add constraint social_webhook_events_platform_check check (platform in ('facebook', 'instagram', 'tiktok', 'youtube', 'linkedin'));

alter table public.social_contacts drop constraint if exists social_contacts_platform_check;
alter table public.social_contacts add constraint social_contacts_platform_check check (platform in ('facebook', 'instagram', 'tiktok', 'youtube', 'linkedin'));

alter table public.social_threads drop constraint if exists social_threads_platform_check;
alter table public.social_threads add constraint social_threads_platform_check check (platform in ('facebook', 'instagram', 'tiktok', 'youtube', 'linkedin'));

alter table public.social_oauth_states drop constraint if exists social_oauth_states_platform_check;
alter table public.social_oauth_states add constraint social_oauth_states_platform_check check (platform in ('facebook', 'instagram', 'tiktok', 'youtube', 'linkedin'));
