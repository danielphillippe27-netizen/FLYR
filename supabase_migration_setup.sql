-- FLYR App Supabase Migration Script
-- Run this in your Supabase SQL Editor to set up the required schema

-- Enable PostGIS extension (if not already enabled)
CREATE EXTENSION IF NOT EXISTS postgis;

-- 1. Create campaigns table (if it doesn't exist)
CREATE TABLE IF NOT EXISTS campaigns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    total_flyers INTEGER NOT NULL DEFAULT 0,
    scans INTEGER NOT NULL DEFAULT 0,
    conversions INTEGER NOT NULL DEFAULT 0,
    region TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Create campaign_addresses table (if it doesn't exist)
CREATE TABLE IF NOT EXISTS campaign_addresses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id UUID NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
    formatted TEXT NOT NULL,
    postal_code TEXT,
    source TEXT,
    seq INTEGER DEFAULT 0,
    visited BOOLEAN NOT NULL DEFAULT FALSE,
    geom GEOMETRY(POINT, 4326), -- PostGIS geometry with WGS84 SRID
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_campaigns_owner_id ON campaigns(owner_id);
CREATE INDEX IF NOT EXISTS idx_campaigns_created_at ON campaigns(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_campaign_addresses_campaign_id ON campaign_addresses(campaign_id);
CREATE INDEX IF NOT EXISTS idx_campaign_addresses_geom ON campaign_addresses USING GIST(geom);

-- 4. Create updated_at trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 5. Create triggers for updated_at
DROP TRIGGER IF EXISTS update_campaigns_updated_at ON campaigns;
CREATE TRIGGER update_campaigns_updated_at
    BEFORE UPDATE ON campaigns
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- 6. Create RPC function for bulk address insertion
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

-- 7. Grant permissions to authenticated users
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL ON campaigns TO authenticated;
GRANT ALL ON campaign_addresses TO authenticated;
GRANT EXECUTE ON FUNCTION add_campaign_addresses(UUID, JSONB) TO authenticated;

-- 8. Enable Row Level Security (RLS)
ALTER TABLE campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaign_addresses ENABLE ROW LEVEL SECURITY;

-- 9. Create RLS policies
-- Users can only see their own campaigns
CREATE POLICY "Users can view own campaigns" ON campaigns
    FOR SELECT USING (auth.uid() = owner_id);

CREATE POLICY "Users can insert own campaigns" ON campaigns
    FOR INSERT WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "Users can update own campaigns" ON campaigns
    FOR UPDATE USING (auth.uid() = owner_id);

CREATE POLICY "Users can delete own campaigns" ON campaigns
    FOR DELETE USING (auth.uid() = owner_id);

-- Users can only see addresses for their own campaigns
CREATE POLICY "Users can view addresses for own campaigns" ON campaign_addresses
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM campaigns 
            WHERE campaigns.id = campaign_addresses.campaign_id 
            AND campaigns.owner_id = auth.uid()
        )
    );

CREATE POLICY "Users can insert addresses for own campaigns" ON campaign_addresses
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM campaigns 
            WHERE campaigns.id = campaign_addresses.campaign_id 
            AND campaigns.owner_id = auth.uid()
        )
    );

CREATE POLICY "Users can update addresses for own campaigns" ON campaign_addresses
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM campaigns 
            WHERE campaigns.id = campaign_addresses.campaign_id 
            AND campaigns.owner_id = auth.uid()
        )
    );

CREATE POLICY "Users can delete addresses for own campaigns" ON campaign_addresses
    FOR DELETE USING (
        EXISTS (
            SELECT 1 FROM campaigns 
            WHERE campaigns.id = campaign_addresses.campaign_id 
            AND campaigns.owner_id = auth.uid()
        )
    );

-- 10. Create helper function to get campaign with addresses
CREATE OR REPLACE FUNCTION get_campaign_with_addresses(p_campaign_id UUID)
RETURNS TABLE (
    campaign_id UUID,
    title TEXT,
    description TEXT,
    total_flyers INTEGER,
    scans INTEGER,
    conversions INTEGER,
    region TEXT,
    created_at TIMESTAMPTZ,
    addresses JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.id,
        c.title,
        c.description,
        c.total_flyers,
        c.scans,
        c.conversions,
        c.region,
        c.created_at,
        COALESCE(
            (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', ca.id,
                        'formatted', ca.formatted,
                        'postal_code', ca.postal_code,
                        'source', ca.source,
                        'seq', ca.seq,
                        'visited', ca.visited,
                        'geom', ST_AsGeoJSON(ca.geom)::jsonb,
                        'created_at', ca.created_at
                    )
                )
                FROM campaign_addresses ca
                WHERE ca.campaign_id = c.id
            ),
            '[]'::jsonb
        ) as addresses
    FROM campaigns c
    WHERE c.id = p_campaign_id
    AND c.owner_id = auth.uid();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_campaign_with_addresses(UUID) TO authenticated;

-- 11. Create function to update campaign progress
CREATE OR REPLACE FUNCTION update_campaign_progress(
    p_campaign_id UUID,
    p_scans INTEGER
) RETURNS void AS $$
BEGIN
    UPDATE campaigns 
    SET scans = p_scans,
        updated_at = NOW()
    WHERE id = p_campaign_id 
    AND owner_id = auth.uid();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION update_campaign_progress(UUID, INTEGER) TO authenticated;

-- 12. Verify the setup
DO $$
BEGIN
    -- Check if tables exist
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'campaigns') THEN
        RAISE EXCEPTION 'campaigns table not created';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'campaign_addresses') THEN
        RAISE EXCEPTION 'campaign_addresses table not created';
    END IF;
    
    -- Check if PostGIS is available
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'postgis') THEN
        RAISE EXCEPTION 'PostGIS extension not available';
    END IF;
    
    RAISE NOTICE 'FLYR database schema setup completed successfully!';
END $$;







