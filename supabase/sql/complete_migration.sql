-- Complete Supabase Migration for FLYR Address Optimization
-- This script ensures all required database objects exist for the optimized address lookup system

-- 1. Enable required extensions
create extension if not exists postgis;
create extension if not exists btree_gist;

-- 2. Create addresses_master table if it doesn't exist
create table if not exists public.addresses_master (
  id            bigserial primary key,
  source        text not null,                    -- 'durham_open','osm','user','fallback'
  source_id     text,
  full_address  text not null,
  street_number text,
  street_name   text not null,
  city          text,
  province      text not null,
  postal_code   text,
  geom          geometry(Point,4326),
  confidence    real default 0.90,                -- Durham ~0.95, fallback ~0.70
  updated_at    timestamptz default now(),
  norm_key      text generated always as
    (trim(both from upper(
      coalesce(street_number,'') || ' ' || 
      coalesce(street_name,'') || ' ' || 
      coalesce(city,'')
    ))) stored
);

-- 3. Create spatial indexes for performance
create index if not exists idx_addresses_master_geom
  on public.addresses_master using gist (geom);

create index if not exists idx_addresses_master_province
  on public.addresses_master (province);

create index if not exists idx_addresses_master_norm_key
  on public.addresses_master (norm_key);

create index if not exists idx_addresses_master_source
  on public.addresses_master (source);

-- 4. Create addresses_unified view
create or replace view public.addresses_unified as
select 
  'master'::text as source_priority,
  m.id::text     as address_id,
  m.full_address, 
  m.street_number, 
  m.street_name, 
  m.city, 
  m.province, 
  m.postal_code, 
  m.geom
from public.addresses_master m
where m.geom is not null;

-- 5. Create optimized RPC functions
create or replace function public.fn_addr_nearest_v2(
  p_lat double precision,
  p_lon double precision,
  p_limit integer default 100,
  p_province text default 'ON'
)
returns table (
  address_id   text,
  full_address text,
  street_no    text,
  street_name  text,
  city         text,
  province     text,
  postal_code  text,
  distance_m   double precision,
  lat          double precision,
  lon          double precision
)
language plpgsql
stable
security definer
as $$
begin
  perform set_config('statement_timeout','5000', true);
  return query
  with origin as (
    select 
      st_setsrid(st_makepoint(p_lon, p_lat), 4326) as g4326,
      st_setsrid(st_makepoint(p_lon, p_lat), 4326)::geography as geog
  )
  select
    u.address_id,
    u.full_address,
    u.street_number::text as street_no,
    u.street_name::text   as street_name,
    u.city::text          as city,
    u.province,
    u.postal_code::text   as postal_code,
    st_distance(u.geom::geography, o.geog) as distance_m,
    st_y(u.geom) as lat,
    st_x(u.geom) as lon
  from public.addresses_unified u
  cross join origin o
  where (p_province is null or u.province = p_province)
    and st_srid(u.geom) in (0,4326)
  order by u.geom <-> o.g4326
  limit greatest(1, p_limit);
end;
$$;

create or replace function public.fn_addr_same_street_v2(
  p_street text,
  p_city text,
  p_lon double precision,
  p_lat double precision,
  p_limit integer default 100,
  p_province text default 'ON'
)
returns table (
  address_id   text,
  full_address text,
  street_no    text,
  street_name  text,
  city         text,
  province     text,
  postal_code  text,
  distance_m   double precision,
  lat          double precision,
  lon          double precision
)
language plpgsql
stable
security definer
as $$
begin
  perform set_config('statement_timeout','5000', true);
  return query
  with origin as (
    select 
      st_setsrid(st_makepoint(p_lon, p_lat), 4326) as g4326,
      st_setsrid(st_makepoint(p_lon, p_lat), 4326)::geography as geog
  )
  select
    u.address_id,
    u.full_address,
    u.street_number::text as street_no,
    u.street_name::text   as street_name,
    u.city::text          as city,
    u.province,
    u.postal_code::text   as postal_code,
    st_distance(u.geom::geography, o.geog) as distance_m,
    st_y(u.geom) as lat,
    st_x(u.geom) as lon
  from public.addresses_unified u
  cross join origin o
  where upper(u.street_name) = upper(p_street)
    and (p_city is null or upper(u.city) = upper(p_city))
    and (p_province is null or u.province = p_province)
    and st_srid(u.geom) in (0,4326)
  order by u.geom <-> o.g4326
  limit greatest(1, p_limit);
end;
$$;

-- 6. Grant permissions
grant execute on function public.fn_addr_nearest_v2(double precision,double precision,integer,text)
  to anon, authenticated, service_role;

grant execute on function public.fn_addr_same_street_v2(text,text,double precision,double precision,integer,text)
  to anon, authenticated, service_role;

grant select on public.addresses_unified to anon, authenticated, service_role;

-- 7. Analyze table for query optimization
analyze public.addresses_master;

-- 8. Notify PostgREST to reload schema
select pg_notify('pgrst','reload schema');

-- 9. Verification queries (commented out - uncomment to test)
/*
-- Check extensions
SELECT extname, extversion FROM pg_extension WHERE extname IN ('postgis', 'btree_gist');

-- Check table structure
\d public.addresses_master

-- Check indexes
SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'addresses_master';

-- Check view
\d+ public.addresses_unified

-- Test RPC function
SELECT * FROM public.fn_addr_nearest_v2(43.6532, -79.3832, 5, 'ON') LIMIT 3;
*/
