-- Performance Validation Script for FLYR Address Optimization
-- This script tests the fn_addr_nearest_v2 function performance to ensure <200ms execution times

-- Test coordinates (Toronto area)
-- Latitude: 43.6532, Longitude: -79.3832 (Toronto City Hall)

-- 1. Test fn_addr_nearest_v2 with EXPLAIN ANALYZE
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) 
SELECT * FROM public.fn_addr_nearest_v2(43.6532, -79.3832, 50, 'ON');

-- 2. Test fn_addr_same_street_v2 with EXPLAIN ANALYZE  
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT * FROM public.fn_addr_same_street_v2('KING ST', 'TORONTO', -79.3832, 43.6532, 50, 'ON');

-- 3. Test with different limits to verify scaling
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT * FROM public.fn_addr_nearest_v2(43.6532, -79.3832, 10, 'ON');

EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT * FROM public.fn_addr_nearest_v2(43.6532, -79.3832, 100, 'ON');

-- 4. Test with different provinces
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT * FROM public.fn_addr_nearest_v2(43.6532, -79.3832, 50, 'BC');

-- 5. Test with no province filter (all provinces)
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT * FROM public.fn_addr_nearest_v2(43.6532, -79.3832, 50, NULL);

-- 6. Check index usage
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes 
WHERE tablename = 'addresses_master'
ORDER BY idx_scan DESC;

-- 7. Check table statistics
SELECT 
    schemaname,
    tablename,
    n_tup_ins,
    n_tup_upd,
    n_tup_del,
    n_live_tup,
    n_dead_tup,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze
FROM pg_stat_user_tables 
WHERE tablename = 'addresses_master';

-- 8. Check if spatial index is being used
SELECT 
    indexname,
    indexdef
FROM pg_indexes 
WHERE tablename = 'addresses_master' 
AND indexdef LIKE '%gist%';

-- 9. Test query performance with timing
\timing on

-- Test 1: Basic nearest search
SELECT 'Test 1: Basic nearest search' as test_name;
SELECT COUNT(*) as result_count, 
       MIN(distance_m) as min_distance,
       MAX(distance_m) as max_distance
FROM public.fn_addr_nearest_v2(43.6532, -79.3832, 50, 'ON');

-- Test 2: Same street search
SELECT 'Test 2: Same street search' as test_name;
SELECT COUNT(*) as result_count,
       MIN(distance_m) as min_distance,
       MAX(distance_m) as max_distance
FROM public.fn_addr_same_street_v2('KING ST', 'TORONTO', -79.3832, 43.6532, 50, 'ON');

-- Test 3: High limit test
SELECT 'Test 3: High limit test' as test_name;
SELECT COUNT(*) as result_count,
       MIN(distance_m) as min_distance,
       MAX(distance_m) as max_distance
FROM public.fn_addr_nearest_v2(43.6532, -79.3832, 200, 'ON');

-- Test 4: Different location (Vancouver)
SELECT 'Test 4: Different location (Vancouver)' as test_name;
SELECT COUNT(*) as result_count,
       MIN(distance_m) as min_distance,
       MAX(distance_m) as max_distance
FROM public.fn_addr_nearest_v2(49.2827, -123.1207, 50, 'BC');

\timing off

-- 10. Performance summary
SELECT 
    'Performance Test Complete' as status,
    'Check execution times above - should be <200ms for all queries' as note;
