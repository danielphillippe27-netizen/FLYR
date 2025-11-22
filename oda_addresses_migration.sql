-- =====================================================
-- Ontario ODA Address Database Migration
-- Purpose: Create fast, local address lookup using Ontario Open Data
-- =====================================================

-- 1) Table for Ontario ODA addresses (lean, fast)
create table if not exists public.oda_on_addresses (
  id uuid primary key default gen_random_uuid(),
  latitude double precision not null,
  longitude double precision not null,
  street_no text,
  street text not null,
  str_name text,
  str_type text,
  str_dir text,
  unit text,
  postal_code text,
  city text,
  full_addr text not null,
  cscode text,
  geom geography(Point, 4326) not null,
  created_at timestamptz default now()
);

-- 2) Indexes for speed
create index if not exists idx_oda_on_geom on public.oda_on_addresses using gist (geom);
create index if not exists idx_oda_on_street on public.oda_on_addresses (upper(street));
create index if not exists idx_oda_on_city on public.oda_on_addresses (upper(city));
create index if not exists idx_oda_on_postal on public.oda_on_addresses (upper(postal_code));

-- 3) RLS: read-only for now (tighten later to your roles)
alter table public.oda_on_addresses enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where policyname='oda_on_read_all') then
    create policy oda_on_read_all on public.oda_on_addresses
      for select using (true);
  end if;
end $$;

-- 4) RPC: nearest addresses by distance
create or replace function public.fn_oda_on_nearest(
  p_lon double precision,
  p_lat double precision,
  p_limit integer default 25
) returns table (
  address text,
  number text,
  street text,
  postal_code text,
  city text,
  geom_json text
) language sql stable as $$
  select
    oa.full_addr as address,
    coalesce(oa.street_no, '') as number,
    oa.street,
    oa.postal_code,
    oa.city,
    ST_AsGeoJSON(oa.geom)::text as geom_json
  from public.oda_on_addresses oa
  order by oa.geom <-> ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography
  limit greatest(1, p_limit);
$$;

-- 5) RPC: same street near a seed (optional locality scope)
create or replace function public.fn_oda_on_same_street(
  p_street text,
  p_locality text default null,
  p_lon double precision,
  p_lat double precision,
  p_limit integer default 25
) returns table (
  address text,
  number text,
  street text,
  postal_code text,
  city text,
  geom_json text
) language sql stable as $$
  select
    oa.full_addr as address,
    coalesce(oa.street_no, '') as number,
    oa.street,
    oa.postal_code,
    oa.city,
    ST_AsGeoJSON(oa.geom)::text as geom_json
  from public.oda_on_addresses oa
  where upper(oa.street) = upper(p_street)
    and (p_locality is null or upper(oa.city) = upper(p_locality))
  order by oa.geom <-> ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography
  limit greatest(1, p_limit);
$$;

-- 6) Grant permissions
grant select on public.oda_on_addresses to authenticated;
grant execute on function public.fn_oda_on_nearest to authenticated;
grant execute on function public.fn_oda_on_same_street to authenticated;

-- =====================================================
-- IMPORT INSTRUCTIONS
-- =====================================================

-- After CSV import, set geom if not set in upload mapping:
-- update public.oda_on_addresses
-- set geom = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography
-- where geom is null;

-- ✅ Quick sanity tests (edit coords/street/locality as needed):
-- select * from fn_oda_on_nearest(-78.62245, 43.98785, 5);
-- select * from fn_oda_on_same_street('MAIN STREET','ORONO',-78.62245,43.98785,25);

-- =====================================================
-- Migration complete
-- =====================================================







