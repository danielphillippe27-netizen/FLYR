-- Updated fn_addr_nearest_v2 function with lat/lon coordinates for Swift compatibility
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

grant execute on function public.fn_addr_nearest_v2(double precision,double precision,integer,text)
  to anon, authenticated, service_role;

-- Also create a v2 version of the same street function for consistency
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

grant execute on function public.fn_addr_same_street_v2(text,text,double precision,double precision,integer,text)
  to anon, authenticated, service_role;

select pg_notify('pgrst','reload schema');
