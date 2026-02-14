# FLYR Address Service Verification Report
## DB-First Auto-Recovery Implementation

**Version:** v2.0  
**Date:** October 28, 2025  
**Status:** ⚠️ **HISTORICAL** – ODA/DB-first logic has been removed. Address lookups now use Mapbox only. This document is kept for reference.

---

## Executive Summary

Successfully implemented DB-first auto-recovery address lookup pipeline with:
- ✅ Optimistic database attempts with 1200ms timeout
- ✅ Real-time health tracking with `ignoreTTL` support
- ✅ Instant Mapbox fallback on DB timeout/failure
- ✅ Comprehensive latency and source logging
- ✅ No health check gating (always attempts DB first)

---

## 1. Database Schema Verification

### Expected RPC Functions

Both functions should exist with identical return structure:

```sql
-- Verification Query
select proname, pg_get_function_result(p.oid)
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where proname in ('fn_addr_nearest_v2','fn_addr_same_street_v2');
```

**Expected Columns:**
- `address_id` TEXT
- `full_address` TEXT
- `street_no` TEXT
- `street_name` TEXT
- `city` TEXT
- `province` TEXT
- `postal_code` TEXT
- `distance_m` DOUBLE PRECISION
- `lat` DOUBLE PRECISION
- `lon` DOUBLE PRECISION

### Performance Baseline

```sql
-- Test Query (Orono, ON coordinates)
explain analyze select * from public.fn_addr_nearest_v2(43.987854,-78.622448,25,'ON');
```

**Target Performance:**
- Execution Time: < 300ms (target: < 200ms)
- Planning Time: < 10ms
- Index Usage: KNN index on `addresses_unified.geom`

---

## 2. Swift-SQL Schema Mapping Verification

### ODAProvider Row Structure

**File:** `FLYR/Feautures/Addresses/Providers/ODAProvider.swift`

| SQL Column | Swift Property | CodingKey | Type |
|------------|---------------|-----------|------|
| `address_id` | `addressId` | `address_id` | `String` |
| `full_address` | `fullAddress` | `full_address` | `String` |
| `street_no` | `streetNo` | `street_no` | `String` |
| `street_name` | `streetName` | `street_name` | `String` |
| `city` | `city` | `city` | `String` |
| `province` | `province` | `province` | `String` |
| `postal_code` | `postalCode` | `postal_code` | `String?` |
| `distance_m` | `distanceM` | `distance_m` | `Double` |
| `lat` | `lat` | `lat` | `Double` |
| `lon` | `lon` | `lon` | `Double` |

✅ **Status:** All mappings verified and consistent with SQL schema.

### Health Test Row Structure

**File:** `FLYR/Feautures/Addresses/AddressServiceHealth.swift`

Identical mapping as ODAProvider for health checks.

---

## 3. Implementation Verification Checklist

### 3.1 AddressServiceHealth.swift

**✅ Implemented:**
- `ignoreTTL: Bool = false` parameter added to `probe()` method
- TTL check: 300 seconds (5 minutes)
- Max response time threshold: 1.5 seconds
- Real-time health updates after every DB call

**Key Code:**
```swift
func probe(lat: Double, lon: Double, ignoreTTL: Bool = false) async {
    if !ignoreTTL, let lastProbe = lastProbeTime, Date().timeIntervalSince(lastProbe) < (ttlMinutes * 60) {
        print("🏥 [HEALTH] Using cached health status: \(dbHealthy ? "healthy" : "unhealthy")")
        return
    }
    // ... probe logic
}
```

**Test Commands:**
```swift
// Force fresh probe (ignore TTL)
await AddressServiceHealth.shared.probe(lat:43.987854, lon:-78.622448, ignoreTTL:true)

// Check TTL behavior
await AddressServiceHealth.shared.checkHealth(lat:43.987854, lon:-78.622448)
```

**Expected Logs:**
- `🏥 [HEALTH] Probing database health at 43.987854, -78.622448`
- `✅ [HEALTH] Database healthy (response time: 0.XXX s)`

---

### 3.2 ODAProvider.swift

**✅ Implemented:**
1. **Task.sleep(ms:) Extension**
   ```swift
   extension Task where Success == Never, Failure == Never {
       static func sleep(ms: Int) async throws {
           try await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
       }
   }
   ```

2. **tryDBOnce() Method**
   - Uses `withTaskGroup` to race DB call against timeout
   - Default timeout: 1200ms
   - Throws `NSError` with domain "DBTimeout" on timeout
   - Cancels all tasks after first result

**Key Code:**
```swift
func tryDBOnce(center: CLLocationCoordinate2D, limit: Int, timeoutMs: Int = 1200) async throws -> [AddressCandidate] {
    print("🏛️ [DB] Attempting DB fetch with \(timeoutMs)ms timeout")
    
    return try await withTaskGroup(of: [AddressCandidate].self) { group in
        group.addTask { try await self.nearest(center: center, limit: limit) }
        group.addTask { 
            try await Task.sleep(ms: timeoutMs)
            throw NSError(domain: "DBTimeout", code: 1, userInfo: [...])
        }
        
        let first = try await group.next() ?? []
        group.cancelAll()
        return first
    }
}
```

**Test Scenarios:**
```swift
// Normal operation
let results = try await ODAProvider().tryDBOnce(
    center: CLLocationCoordinate2D(latitude: 43.987854, longitude: -78.622448),
    limit: 25
)

// Force timeout
let timeout = try await ODAProvider().tryDBOnce(
    center: CLLocationCoordinate2D(latitude: 43.987854, longitude: -78.622448),
    limit: 25,
    timeoutMs: 1
)
```

---

### 3.3 AddressService.swift

**✅ Implemented:**

#### fetchNearest() - Optimistic DB-First
- ❌ Removed health check gating (lines 46-74 deleted)
- ✅ Always attempts DB via `tryDBOnce()`
- ✅ Updates health after every attempt via `probe(ignoreTTL: true)`
- ✅ Instant Mapbox fallback on failure
- ✅ Latency tracking in milliseconds
- ✅ Source determination (oda/mapbox/hybrid)

**Key Changes:**
```swift
// Always attempt DB first with short timeout
do {
    let startTime = Date()
    let odaResults = try await oda.tryDBOnce(center: center, limit: target * 2)
    let latency = Int(Date().timeIntervalSince(startTime) * 1000)
    
    // Update health to healthy after successful DB call
    await AddressServiceHealth.shared.probe(lat: center.latitude, lon: center.longitude, ignoreTTL: true)
    
    print("✅ [DB] ODA/Durham returned \(odaResults.count) addresses in \(latency)ms")
    // ... dedup and return
} catch {
    // Update health to unhealthy after failed DB call
    await AddressServiceHealth.shared.probe(lat: center.latitude, lon: center.longitude, ignoreTTL: true)
    print("⚠️ [DB] ODA/Durham failed: \(error.localizedDescription)")
}
```

#### fetchSameStreet() - Identical Pattern
- ✅ Same optimistic DB-first pattern
- ✅ Real-time health updates
- ✅ Latency tracking
- ✅ Instant fallback

**Expected Logs:**
```
🔍 [ADDRESS SERVICE] Finding 25 nearest addresses to ...
🏛️ [DB] Attempting DB fetch with 1200ms timeout
🏛️ [DB] Using ODA/Durham unified data for nearest addresses
✅ [DB] ODA/Durham returned 25 addresses in 187ms
🏥 [HEALTH] Probing database health at ...
✅ [HEALTH] Database healthy (response time: 0.187s)
✅ [DB] ODA/Durham provided enough addresses (25)
✅ [ADDRESS SERVICE] Final result: 25 addresses (source: oda)
```

---

### 3.4 MapboxProvider.swift

**✅ Implemented:**
- Added `disableStreetLock: Bool = false` parameter to `nearestExpanded()`
- Skips baseline street detection when disabled
- Removes street filtering when disabled
- Preserves backward compatibility (default: `false`)

**Key Code:**
```swift
func nearestExpanded(center: CLLocationCoordinate2D, limit: Int, disableStreetLock: Bool = false) async throws -> [AddressCandidate] {
    print("🗺️ [MAPBOX EXPANDED] Starting progressive search for \(limit) addresses (street-lock: \(!disableStreetLock))")
    
    var streetLock = !disableStreetLock
    
    if !disableStreetLock {
        // Get baseline street name for filtering
    } else {
        print("🗺️ [MAPBOX EXPANDED] Street-lock disabled by caller")
        baselineStreetName = ""
    }
    // ...
}
```

**Usage:**
```swift
// With street-lock (default)
let results = try await MapboxProvider().nearestExpanded(center: coord, limit: 25)

// Without street-lock (maximizes coverage)
let results = try await MapboxProvider().nearestExpanded(center: coord, limit: 25, disableStreetLock: true)
```

---

## 4. Logging & Observability

### Log Formats

**DB Attempt:**
```
🏛️ [DB] Attempting DB fetch with 1200ms timeout
🏛️ [DB] Using ODA/Durham unified data for nearest addresses
🏛️ [DB] Finding 25 nearest addresses to CLLocationCoordinate2D(...)
```

**Success:**
```
✅ [DB] ODA/Durham returned 25 addresses in 187ms
✅ [HEALTH] Database healthy (response time: 0.187s)
✅ [ADDRESS SERVICE] Final result: 25 addresses (source: oda)
```

**Timeout/Failure:**
```
⚠️ [DB] ODA/Durham failed: Database timeout after 1200ms
❌ [HEALTH] Database probe failed: Database timeout after 1200ms
🗺️ [FALLBACK] Using Mapbox API (confidence: 0.70)
🗺️ [FALLBACK] Filling gaps with Mapbox (need 25 more)
```

**Hybrid:**
```
✅ [DB] ODA/Durham returned 12 addresses in 234ms
🗺️ [FALLBACK] Filling gaps with Mapbox (need 13 more)
✅ [ADDRESS SERVICE] Final result: 25 addresses (source: hybrid)
```

---

## 5. Performance Targets

### Response Time Goals

| Metric | Target | Maximum |
|--------|--------|---------|
| DB p50 latency | < 200ms | < 300ms |
| DB p95 latency | < 400ms | < 600ms |
| DB timeout | 1200ms | 1500ms |
| Health probe | < 1500ms | < 2000ms |
| Total fetch (DB success) | < 300ms | < 500ms |
| Total fetch (Mapbox fallback) | < 2000ms | < 3000ms |

### Database Monitoring Query

```sql
-- Optional: Create performance view
create or replace view flyr_addr_lookup_p50 as
select
  date_trunc('minute', created_at) as minute,
  percentile_cont(0.5) within group (order by ms) as p50_ms,
  percentile_cont(0.95) within group (order by ms) as p95_ms,
  count(*) as calls
from rpc_logs
where name='fn_addr_nearest_v2'
group by 1 order by 1 desc;
```

---

## 6. Testing Checklist

### Manual Tests

- [ ] **Test 1: Health Probe with ignoreTTL**
  ```swift
  await AddressServiceHealth.shared.probe(lat:43.987854, lon:-78.622448, ignoreTTL:true)
  ```
  Expected: Fresh probe, logs show healthy, TTL reset

- [ ] **Test 2: Health Probe with TTL**
  ```swift
  await AddressServiceHealth.shared.checkHealth(lat:43.987854, lon:-78.622448)
  // Call again immediately
  await AddressServiceHealth.shared.checkHealth(lat:43.987854, lon:-78.622448)
  ```
  Expected: Second call uses cached status

- [ ] **Test 3: Normal DB Fetch**
  ```swift
  let results = try await AddressService.shared.fetchNearest(
      center: CLLocationCoordinate2D(latitude: 43.987854, longitude: -78.622448),
      target: 25
  )
  ```
  Expected: DB path, latency < 300ms, count ≥ 25, source: "oda"

- [ ] **Test 4: Force Timeout**
  Temporarily modify `tryDBOnce` to use `timeoutMs: 1`
  Expected: Instant fallback, Mapbox path, source: "mapbox"

- [ ] **Test 5: Same Street Search**
  ```swift
  let results = try await AddressService.shared.fetchSameStreet(
      seed: CLLocationCoordinate2D(latitude: 43.987854, longitude: -78.622448),
      target: 25
  )
  ```
  Expected: DB path, street detected, count ≥ 25

- [ ] **Test 6: Mapbox Street-Lock Disabled**
  Verify logs show "Street-lock disabled by caller" when used

### Database Tests

- [ ] **DB Function Existence**
  ```sql
  select proname from pg_proc where proname in ('fn_addr_nearest_v2','fn_addr_same_street_v2');
  ```
  Expected: Both functions exist

- [ ] **DB Performance**
  ```sql
  explain analyze select * from public.fn_addr_nearest_v2(43.987854,-78.622448,25,'ON');
  ```
  Expected: Execution time < 300ms, uses KNN index

- [ ] **DB Result Count**
  ```sql
  select count(*) from public.fn_addr_nearest_v2(43.987854,-78.622448,25,'ON');
  ```
  Expected: Returns 25 rows (or all available if less)

---

## 7. Files Modified

### Core Implementation
- ✅ `FLYR/Feautures/Addresses/AddressServiceHealth.swift` (ignoreTTL support)
- ✅ `FLYR/Feautures/Addresses/AddressService.swift` (optimistic fetch)
- ✅ `FLYR/Feautures/Addresses/Providers/ODAProvider.swift` (timeout wrapper)
- ✅ `FLYR/Feautures/Addresses/Providers/MapboxProvider.swift` (street-lock disable)

### Supporting Files (No Changes Required)
- `FLYR/Feautures/Addresses/GeoStreetAdapter.swift` (used as-is)
- `FLYR/Config/SupabaseClientShim.swift` (used as-is)
- `FLYR/Feautures/Campaigns/API/GeoAPI.swift` (no changes needed)

---

## 8. Deployment Readiness

### Pre-Production Checklist

- [ ] All manual tests pass
- [ ] Database performance meets targets (< 300ms)
- [ ] Logs show correct source tracking
- [ ] Health auto-recovery verified (unhealthy → healthy)
- [ ] Mapbox fallback works correctly
- [ ] No street-lock issues on fallback
- [ ] Schema mappings verified
- [ ] No linter errors

### Production Deployment

When all checks pass:

1. **Tag Release:**
   ```bash
   git tag -a flyr-address-recovery-v2.0 -m "DB-first auto-recovery implementation"
   git push origin flyr-address-recovery-v2.0
   ```

2. **Feature Flag (Optional):**
   ```swift
   // Enable in Config.swift or feature flags
   let useODAv2 = true
   ```

3. **Monitor:**
   - Watch logs for latency patterns
   - Track DB vs Mapbox usage ratio
   - Monitor health state transitions
   - Check user-facing performance

---

## 9. Rollback Plan

If issues arise:

1. **Disable Feature Flag:**
   ```swift
   let useODAv2 = false
   ```

2. **Revert Commit:**
   ```bash
   git revert flyr-address-recovery-v2.0
   ```

3. **Check Database:**
   - Verify RPC functions are responding
   - Check for connection pool issues
   - Validate index health

---

## 10. Success Metrics

### Week 1 Targets
- 95% of lookups complete in < 500ms
- DB usage > 90% (vs Mapbox fallback)
- Health state accurate (no stuck unhealthy)
- Zero user-reported "address not found" issues

### Week 4 Targets
- DB p50 < 200ms consistently
- DB p95 < 400ms consistently
- Mapbox fallback < 5% of requests
- Zero DB-related errors

---

## 11. Known Limitations

1. **Timeout Not Configurable at Runtime:** Default 1200ms is hardcoded
2. **No Retry Logic:** Single DB attempt per fetch (by design for speed)
3. **Health TTL Fixed:** 5 minutes cannot be adjusted without code change
4. **No Circuit Breaker:** Doesn't back off after repeated failures (relies on TTL)

---

## 12. Future Enhancements

- Add configurable timeout per environment
- Implement exponential backoff for repeated failures
- Add Prometheus/Grafana metrics export
- Create dashboard for real-time monitoring
- Add A/B testing framework for timeout tuning
- Implement request queueing for rate limiting

---

## Status: ✅ IMPLEMENTATION COMPLETE

**Next Step:** Run verification tests and mark environment PRODUCTION READY

**Contact:** Development Team
**Document Version:** 1.0
**Last Updated:** October 28, 2025
