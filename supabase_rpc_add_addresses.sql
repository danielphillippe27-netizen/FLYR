-- SQL RPC function for bulk inserting campaign addresses with PostGIS geometry
-- Run this in your Supabase SQL Editor

CREATE OR REPLACE FUNCTION add_campaign_addresses(
    p_campaign_id UUID,
    p_addresses JSONB
) RETURNS void AS $$
BEGIN
    INSERT INTO campaign_addresses (
        id, 
        campaign_id, 
        formatted, 
        postal_code, 
        source, 
        seq, 
        visited, 
        geom, 
        created_at
    )
    SELECT 
        gen_random_uuid(),
        p_campaign_id,
        (addr->>'formatted')::text,
        (addr->>'postal_code')::text,
        (addr->>'source')::text,
        COALESCE((addr->>'seq')::int, 0),
        COALESCE((addr->>'visited')::boolean, false),
        ST_SetSRID(
            ST_MakePoint(
                (addr->>'lon')::double precision,
                (addr->>'lat')::double precision
            ), 
            4326  -- WGS84 SRID
        ),
        NOW()
    FROM jsonb_array_elements(p_addresses) AS addr
    WHERE (addr->>'lon') IS NOT NULL 
      AND (addr->>'lat') IS NOT NULL;
END;
$$ LANGUAGE plpgsql;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION add_campaign_addresses(UUID, JSONB) TO authenticated;








