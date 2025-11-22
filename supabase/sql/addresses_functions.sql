-- Nearest N (Ontario by default; pass province=null for any)
create or replace function public.fn_addr_nearest(
  p_lon double precision, p_lat double precision,
  p_limit int default 25, p_province text default 'ON'
) returns table (
  full_address text, street_number text, street_name text,
  city text, province text, postal_code text, source text, geom_json text
) language sql stable as $$
  select
    full_address, street_number, street_name, city, province, postal_code, source,
    ST_AsGeoJSON(geom)::text
  from public.addresses_best
  where geom is not null
    and (p_province is null or province = p_province)
  order by geom <-> ST_SetSRID(ST_MakePoint(p_lon, p_lat),4326)
  limit greatest(1,p_limit);
$$;

-- Same-street near a point (Ontario default)
create or replace function public.fn_addr_same_street(
  p_street text, p_city text, p_lon double precision, p_lat double precision,
  p_limit int default 100, p_province text default 'ON'
) returns table (
  full_address text, street_number text, street_name text,
  city text, province text, postal_code text, source text, geom_json text
) language sql stable as $$
  select
    full_address, street_number, street_name, city, province, postal_code, source,
    ST_AsGeoJSON(geom)::text
  from public.addresses_best
  where geom is not null
    and upper(street_name) = upper(p_street)
    and (p_city is null or upper(city) = upper(p_city))
    and (p_province is null or province = p_province)
  order by geom <-> ST_SetSRID(ST_MakePoint(p_lon, p_lat),4326)
  limit greatest(1,p_limit);
$$;







