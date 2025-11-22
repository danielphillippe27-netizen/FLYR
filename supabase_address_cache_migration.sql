-- =====================================================
-- Address Cache Migration
-- Purpose: Cache geocoded addresses per street/locality
--          to reduce API calls and speed up repeat searches
-- =====================================================

-- 1. Create address_cache table
CREATE TABLE IF NOT EXISTS public.address_cache (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    street TEXT NOT NULL,
    locality TEXT,
    house_number TEXT NOT NULL,
    formatted_address TEXT NOT NULL,
    lat DOUBLE PRECISION NOT NULL,
    lon DOUBLE PRECISION NOT NULL,
    source TEXT NOT NULL DEFAULT 'street_locked',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    
    -- Ensure street names are normalized (uppercase)
    CONSTRAINT address_cache_street_normalized CHECK (street = UPPER(street)),
    
    -- Unique constraint: one entry per house on a street
    CONSTRAINT address_cache_unique_house UNIQUE (street, house_number, locality)
);

-- 2. Create indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_address_cache_street_locality 
    ON public.address_cache (street, locality);

CREATE INDEX IF NOT EXISTS idx_address_cache_created_at 
    ON public.address_cache (created_at DESC);

-- 3. RPC Function: Get cached addresses for a street
CREATE OR REPLACE FUNCTION public.get_cached_addresses(
    p_street TEXT,
    p_locality TEXT DEFAULT NULL
)
RETURNS TABLE (
    id UUID,
    street TEXT,
    locality TEXT,
    house_number TEXT,
    formatted_address TEXT,
    lat DOUBLE PRECISION,
    lon DOUBLE PRECISION,
    source TEXT,
    created_at TIMESTAMP WITH TIME ZONE
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ac.id,
        ac.street,
        ac.locality,
        ac.house_number,
        ac.formatted_address,
        ac.lat,
        ac.lon,
        ac.source,
        ac.created_at
    FROM public.address_cache ac
    WHERE ac.street = UPPER(p_street)
      AND (p_locality IS NULL OR ac.locality = p_locality)
    ORDER BY ac.house_number;
END;
$$;

-- 4. RPC Function: Cache addresses (bulk insert/update)
CREATE OR REPLACE FUNCTION public.cache_addresses(
    p_addresses JSONB
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_count INTEGER := 0;
    v_address JSONB;
BEGIN
    -- Loop through each address in the JSON array
    FOR v_address IN SELECT * FROM jsonb_array_elements(p_addresses)
    LOOP
        -- Insert or update (upsert) each address
        INSERT INTO public.address_cache (
            street,
            locality,
            house_number,
            formatted_address,
            lat,
            lon,
            source
        )
        VALUES (
            UPPER((v_address->>'street')::TEXT),
            (v_address->>'locality')::TEXT,
            (v_address->>'house_number')::TEXT,
            (v_address->>'formatted_address')::TEXT,
            (v_address->>'lat')::DOUBLE PRECISION,
            (v_address->>'lon')::DOUBLE PRECISION,
            COALESCE((v_address->>'source')::TEXT, 'street_locked')
        )
        ON CONFLICT (street, house_number, locality)
        DO UPDATE SET
            formatted_address = EXCLUDED.formatted_address,
            lat = EXCLUDED.lat,
            lon = EXCLUDED.lon,
            source = EXCLUDED.source,
            created_at = NOW();
        
        v_count := v_count + 1;
    END LOOP;
    
    RETURN v_count;
END;
$$;

-- 5. Row Level Security (RLS) policies
ALTER TABLE public.address_cache ENABLE ROW LEVEL SECURITY;

-- Allow all authenticated users to read cached addresses
DROP POLICY IF EXISTS "Allow authenticated users to read address cache" ON public.address_cache;
CREATE POLICY "Allow authenticated users to read address cache"
    ON public.address_cache
    FOR SELECT
    TO authenticated
    USING (true);

-- Allow all authenticated users to insert/update cached addresses
DROP POLICY IF EXISTS "Allow authenticated users to write address cache" ON public.address_cache;
CREATE POLICY "Allow authenticated users to write address cache"
    ON public.address_cache
    FOR INSERT
    TO authenticated
    WITH CHECK (true);

DROP POLICY IF EXISTS "Allow authenticated users to update address cache" ON public.address_cache;
CREATE POLICY "Allow authenticated users to update address cache"
    ON public.address_cache
    FOR UPDATE
    TO authenticated
    USING (true);

-- 6. Grant permissions
GRANT SELECT, INSERT, UPDATE ON public.address_cache TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_cached_addresses TO authenticated;
GRANT EXECUTE ON FUNCTION public.cache_addresses TO authenticated;

-- =====================================================
-- Migration complete
-- =====================================================








