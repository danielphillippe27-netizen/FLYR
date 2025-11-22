-- Migration: Add QR Code tables for address content and scan tracking
-- Created: 2025-01-20

-- Enable UUID extension if not already enabled
create extension if not exists "uuid-ossp";

-- ============================================================================
-- address_content table
-- Stores videos, images, and forms for each address landing page
-- ============================================================================

create table if not exists public.address_content (
    id uuid primary key default uuid_generate_v4(),
    address_id uuid not null,
    title text not null default '',
    videos text[] default array[]::text[],
    images text[] default array[]::text[],
    forms jsonb default '[]'::jsonb,
    updated_at timestamptz default now(),
    created_at timestamptz default now(),
    
    -- Foreign key to campaign_addresses (or farm_addresses in future)
    constraint fk_address_content_address_id 
        foreign key (address_id) 
        references public.campaign_addresses(id) 
        on delete cascade
);

-- Index for fast lookups by address_id
create index if not exists idx_address_content_address_id 
    on public.address_content(address_id);

-- Index for updated_at for sorting
create index if not exists idx_address_content_updated_at 
    on public.address_content(updated_at desc);

-- Trigger to auto-update updated_at
create or replace function update_address_content_updated_at()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;

create trigger trigger_address_content_updated_at
    before update on public.address_content
    for each row
    execute function update_address_content_updated_at();

-- ============================================================================
-- qr_code_scans table
-- Tracks when QR codes are scanned for analytics
-- ============================================================================

create table if not exists public.qr_code_scans (
    id uuid primary key default uuid_generate_v4(),
    address_id uuid not null,
    scanned_at timestamptz default now(),
    device_info text,
    user_agent text,
    ip_address inet,
    referrer text,
    
    -- Foreign key to campaign_addresses
    constraint fk_qr_code_scans_address_id 
        foreign key (address_id) 
        references public.campaign_addresses(id) 
        on delete cascade
);

-- Index for fast lookups by address_id
create index if not exists idx_qr_code_scans_address_id 
    on public.qr_code_scans(address_id);

-- Index for scanned_at for time-based queries
create index if not exists idx_qr_code_scans_scanned_at 
    on public.qr_code_scans(scanned_at desc);

-- Composite index for analytics queries (address + time)
create index if not exists idx_qr_code_scans_address_time 
    on public.qr_code_scans(address_id, scanned_at desc);

-- ============================================================================
-- Row Level Security (RLS) Policies
-- ============================================================================

-- Enable RLS
alter table public.address_content enable row level security;
alter table public.qr_code_scans enable row level security;

-- address_content policies
-- Users can read all content (public landing pages)
create policy "Anyone can read address content"
    on public.address_content
    for select
    using (true);

-- Users can only insert/update their own content
create policy "Users can insert their own address content"
    on public.address_content
    for insert
    with check (
        exists (
            select 1 from public.campaign_addresses ca
            join public.campaigns c on c.id = ca.campaign_id
            where ca.id = address_content.address_id
            and c.owner_id = auth.uid()
        )
    );

create policy "Users can update their own address content"
    on public.address_content
    for update
    using (
        exists (
            select 1 from public.campaign_addresses ca
            join public.campaigns c on c.id = ca.campaign_id
            where ca.id = address_content.address_id
            and c.owner_id = auth.uid()
        )
    );

-- qr_code_scans policies
-- Anyone can insert scans (public tracking)
create policy "Anyone can insert QR code scans"
    on public.qr_code_scans
    for insert
    with check (true);

-- Users can only read scans for their own campaigns
create policy "Users can read scans for their campaigns"
    on public.qr_code_scans
    for select
    using (
        exists (
            select 1 from public.campaign_addresses ca
            join public.campaigns c on c.id = ca.campaign_id
            where ca.id = qr_code_scans.address_id
            and c.owner_id = auth.uid()
        )
    );

-- ============================================================================
-- Helper Functions
-- ============================================================================

-- Function to get scan count for an address
create or replace function get_address_scan_count(p_address_id uuid)
returns bigint as $$
begin
    return (
        select count(*)::bigint
        from public.qr_code_scans
        where address_id = p_address_id
    );
end;
$$ language plpgsql security definer;

-- Function to get scan count for a campaign
create or replace function get_campaign_scan_count(p_campaign_id uuid)
returns bigint as $$
begin
    return (
        select count(*)::bigint
        from public.qr_code_scans qcs
        join public.campaign_addresses ca on ca.id = qcs.address_id
        where ca.campaign_id = p_campaign_id
    );
end;
$$ language plpgsql security definer;

-- ============================================================================
-- Comments
-- ============================================================================

comment on table public.address_content is 'Stores videos, images, and forms for address landing pages';
comment on table public.qr_code_scans is 'Tracks QR code scans for analytics';
comment on function get_address_scan_count(uuid) is 'Returns the total scan count for a specific address';
comment on function get_campaign_scan_count(uuid) is 'Returns the total scan count for all addresses in a campaign';





