-- Best-record view across overlapping sources
create or replace view public.addresses_best as
with ranked as (
  select
    a.*,
    row_number() over (
      partition by norm_key
      order by confidence desc,
               (case when source='durham_open' then 1
                     when source='oda'         then 2
                     when source='osm'         then 3
                     when source='user'        then 4
                     when source='fallback'    then 5
                     else 9 end),
               (case when geom is not null then 1 else 2 end),
               updated_at desc
    ) as rnk
  from public.addresses_master a
)
select * from ranked where rnk=1;







