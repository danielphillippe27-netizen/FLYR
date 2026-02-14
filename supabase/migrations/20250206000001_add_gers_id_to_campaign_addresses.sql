-- =====================================================
-- Add GERS ID Columns to campaign_addresses
-- 
-- Extends campaign_addresses table to store GERS IDs
-- for direct building-to-address linking.
-- =====================================================

-- Add gers_id columns if they don't exist
ALTER TABLE public.campaign_addresses 
ADD COLUMN IF NOT EXISTS gers_id UUID;

ALTER TABLE public.campaign_addresses 
ADD COLUMN IF NOT EXISTS building_gers_id UUID;

-- Create indexes for fast GERS ID lookups
CREATE INDEX IF NOT EXISTS idx_campaign_addresses_gers_id 
    ON public.campaign_addresses(gers_id) 
    WHERE gers_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_campaign_addresses_building_gers_id 
    ON public.campaign_addresses(building_gers_id) 
    WHERE building_gers_id IS NOT NULL;

-- Add comments
COMMENT ON COLUMN public.campaign_addresses.gers_id IS 'Primary GERS ID linking this address to an Overture Maps building';
COMMENT ON COLUMN public.campaign_addresses.building_gers_id IS 'Alternative GERS ID field for backward compatibility';

-- =====================================================
-- Notify PostgREST to reload schema
-- =====================================================

NOTIFY pgrst, 'reload schema';
