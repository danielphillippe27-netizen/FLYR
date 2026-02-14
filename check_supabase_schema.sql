-- FLYR App Schema Verification Script
-- Run this in your Supabase SQL Editor to check your current schema

-- 1. Check if required tables exist
SELECT 
    'Tables Check' as check_type,
    table_name,
    CASE 
        WHEN table_name IN ('campaigns', 'campaign_addresses') THEN '✅ Required table exists'
        ELSE '⚠️ Extra table found'
    END as status
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name IN ('campaigns', 'campaign_addresses')
ORDER BY table_name;

-- 2. Check campaigns table structure
SELECT 
    'Campaigns Table Structure' as check_type,
    column_name,
    data_type,
    is_nullable,
    column_default,
    CASE 
        WHEN column_name = 'id' AND data_type = 'uuid' THEN '✅ Primary key'
        WHEN column_name = 'owner_id' AND data_type = 'uuid' THEN '✅ Foreign key to auth.users'
        WHEN column_name = 'title' AND data_type = 'text' THEN '✅ Campaign name'
        WHEN column_name = 'description' AND data_type = 'text' THEN '✅ Campaign description'
        WHEN column_name = 'total_flyers' AND data_type = 'integer' THEN '✅ Total flyers count'
        WHEN column_name = 'scans' AND data_type = 'integer' THEN '✅ Scans count'
        WHEN column_name = 'conversions' AND data_type = 'integer' THEN '✅ Conversions count'
        WHEN column_name = 'region' AND data_type = 'text' THEN '✅ Seed query region'
        WHEN column_name = 'created_at' AND data_type = 'timestamp with time zone' THEN '✅ Created timestamp'
        ELSE '⚠️ Unexpected column'
    END as status
FROM information_schema.columns 
WHERE table_name = 'campaigns' 
AND table_schema = 'public'
ORDER BY ordinal_position;

-- 3. Check campaign_addresses table structure
SELECT 
    'Addresses Table Structure' as check_type,
    column_name,
    data_type,
    is_nullable,
    column_default,
    CASE 
        WHEN column_name = 'id' AND data_type = 'uuid' THEN '✅ Primary key'
        WHEN column_name = 'campaign_id' AND data_type = 'uuid' THEN '✅ Foreign key to campaigns'
        WHEN column_name = 'formatted' AND data_type = 'text' THEN '✅ Address text'
        WHEN column_name = 'postal_code' AND data_type = 'text' THEN '✅ Postal code'
        WHEN column_name = 'source' AND data_type = 'text' THEN '✅ Address source'
        WHEN column_name = 'seq' AND data_type = 'integer' THEN '✅ Sequence number'
        WHEN column_name = 'visited' AND data_type = 'boolean' THEN '✅ Visited flag'
        WHEN column_name = 'geom' AND data_type = 'USER-DEFINED' THEN '✅ PostGIS geometry'
        WHEN column_name = 'created_at' AND data_type = 'timestamp with time zone' THEN '✅ Created timestamp'
        ELSE '⚠️ Unexpected column'
    END as status
FROM information_schema.columns 
WHERE table_name = 'campaign_addresses' 
AND table_schema = 'public'
ORDER BY ordinal_position;

-- 4. Check PostGIS extension
SELECT 
    'PostGIS Extension' as check_type,
    CASE 
        WHEN EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'postgis') THEN '✅ PostGIS is enabled'
        ELSE '❌ PostGIS not found - run: CREATE EXTENSION postgis;'
    END as status;

-- 5. Check if geom column has correct type
SELECT 
    'Geometry Column Type' as check_type,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_name = 'campaign_addresses' 
            AND column_name = 'geom' 
            AND udt_name = 'geometry'
        ) THEN '✅ Geometry column exists with correct type'
        ELSE '❌ Geometry column missing or wrong type'
    END as status;

-- 6. Check indexes
SELECT 
    'Indexes' as check_type,
    indexname,
    tablename,
    CASE 
        WHEN indexname LIKE '%owner_id%' THEN '✅ Owner index'
        WHEN indexname LIKE '%campaign_id%' THEN '✅ Campaign index'
        WHEN indexname LIKE '%geom%' THEN '✅ Geometry index'
        ELSE '⚠️ Other index'
    END as status
FROM pg_indexes 
WHERE tablename IN ('campaigns', 'campaign_addresses')
ORDER BY tablename, indexname;

-- 7. Check RLS policies
SELECT 
    'RLS Policies' as check_type,
    schemaname,
    tablename,
    policyname,
    CASE 
        WHEN policyname LIKE '%own%' THEN '✅ User isolation policy'
        ELSE '⚠️ Other policy'
    END as status
FROM pg_policies 
WHERE tablename IN ('campaigns', 'campaign_addresses')
ORDER BY tablename, policyname;

-- 8. Check functions
SELECT 
    'Functions' as check_type,
    routine_name,
    CASE 
        WHEN routine_name = 'add_campaign_addresses' THEN '✅ Bulk insert function'
        WHEN routine_name = 'get_campaign_with_addresses' THEN '✅ Campaign fetch function'
        WHEN routine_name = 'update_campaign_progress' THEN '✅ Progress update function'
        WHEN routine_name = 'update_updated_at_column' THEN '✅ Trigger function'
        ELSE '⚠️ Other function'
    END as status
FROM information_schema.routines 
WHERE routine_schema = 'public'
AND routine_name IN ('add_campaign_addresses', 'get_campaign_with_addresses', 'update_campaign_progress', 'update_updated_at_column')
ORDER BY routine_name;

-- 9. Sample data check (if any exists)
SELECT 
    'Sample Data' as check_type,
    'campaigns' as table_name,
    COUNT(*) as record_count,
    CASE 
        WHEN COUNT(*) > 0 THEN '✅ Has data'
        ELSE 'ℹ️ No data yet'
    END as status
FROM campaigns
UNION ALL
SELECT 
    'Sample Data' as check_type,
    'campaign_addresses' as table_name,
    COUNT(*) as record_count,
    CASE 
        WHEN COUNT(*) > 0 THEN '✅ Has data'
        ELSE 'ℹ️ No data yet'
    END as status
FROM campaign_addresses;

-- 10. Test PostGIS functionality
SELECT 
    'PostGIS Test' as check_type,
    CASE 
        WHEN ST_AsGeoJSON(ST_MakePoint(-79.3832, 43.6532)) IS NOT NULL THEN '✅ PostGIS working correctly'
        ELSE '❌ PostGIS not working'
    END as status;








