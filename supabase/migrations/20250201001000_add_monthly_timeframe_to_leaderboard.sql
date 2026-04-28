drop function if exists public.get_leaderboard(text, text);

create or replace function public.get_leaderboard(metric text, timeframe text)
returns table (
  user_id uuid,
  full_name text,
  flyers integer,
  leads integer,
  conversations integer,
  distance numeric,
  rank integer
)
language plpgsql
security definer
as $function$
begin
  return query
  with base as (
    select
      u.id as user_id,
      u.email::text as full_name,
      coalesce(sum(s.flyers), 0)::int as flyers,
      coalesce(sum(s.leads_created), 0)::int as leads,
      coalesce(sum(s.conversations), 0)::int as conversations,
      coalesce(sum(s.distance_walked), 0)::numeric as distance
    from auth.users u
    left join public.user_stats s
      on s.user_id = u.id
      and (
        (timeframe = 'weekly' and s.created_at >= now() - interval '7 days')
        or (timeframe = 'daily' and s.created_at >= now() - interval '1 day')
        or (timeframe = 'monthly' and s.created_at >= date_trunc('month', now()))
        or (timeframe = 'all')
      )
    group by u.id, u.email
  ),
  ranked as (
    select *,
      case
        when metric = 'flyers' then rank() over (order by base.flyers desc)::int
        when metric = 'leads' then rank() over (order by base.leads desc)::int
        when metric = 'conversations' then rank() over (order by base.conversations desc)::int
        when metric = 'distance' then rank() over (order by base.distance desc)::int
        else rank() over (order by base.flyers desc)::int
      end as rank
    from base
  )
  select * from ranked;
end;
$function$;









