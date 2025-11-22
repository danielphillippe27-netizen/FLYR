-- Nearest N Ontario addresses
create or replace function public.fn_oda_on_nearest(
  p_lon double precision, p_lat double precision, p_limit int default 25
) returns table (
  full_address text, street_number text, street_name text, city text, postal_code text, geom_json text
) language sql stable as $$
  select
    full_address, street_number, street_name, city, postal_code,
    ST_AsGeoJSON(geom)::text
  from public.oda_addresses
  where province='ON' and geom is not null
  order by geom <-> ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)
  limit greatest(1,p_limit);
$$;

-- Same-street (Ontario) near a point
create or replace function public.fn_oda_on_same_street(
  p_street text, p_city text, p_lon double precision, p_lat double precision, p_limit int default 100
) returns table (
  full_address text, street_number text, street_name text, city text, postal_code text, geom_json text
) language sql stable as $$
  select
    full_address, street_number, street_name, city, postal_code,
    ST_AsGeoJSON(geom)::text
  from public.oda_addresses
  where province='ON'
    and geom is not null
    and upper(street_name)=upper(p_street)
    and (p_city is null or upper(city)=upper(p_city))
  order by geom <-> ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)
  limit greatest(1,p_limit);
$$;







