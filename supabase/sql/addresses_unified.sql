-- Unified addresses view - wraps addresses_master for RPC compatibility
-- This view provides the schema expected by fn_addr_nearest_v2 and fn_addr_same_street_v2

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

-- Grant permissions
grant select on public.addresses_unified to anon, authenticated, service_role;

-- Add comment for documentation
comment on view public.addresses_unified is 'Unified view of addresses_master for RPC compatibility with fn_addr_nearest_v2';
