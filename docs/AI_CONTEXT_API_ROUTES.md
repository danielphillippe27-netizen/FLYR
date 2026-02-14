# FLYR API Routes

Reference for backend API routes (Next.js) and Supabase Edge Functions.

## Backend API (Next.js)

Base URL: `https://flyrpro.app`

All routes require authentication via Supabase auth token in `Authorization` header.

---

### Campaign Provisioning

**`POST /api/campaigns/provision`**

Provisions a campaign with addresses, buildings, and roads from external sources.

**Request**:
```json
{
  "campaign_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

**Response**:
```json
{
  "success": true,
  "addresses": 245,
  "buildings": 238,
  "roads": 42,
  "message": "Campaign provisioned successfully"
}
```

**Process**:
1. Loads polygon from `campaigns.territory_boundary` in Supabase
2. Calls Tile Lambda with polygon; Lambda reads S3 parquet (DuckDB/ST_Intersects), writes snapshot GeoJSON to S3
3. Backend downloads addresses from snapshot, inserts into `campaign_addresses`, writes `campaign_snapshots`
4. Runs StableLinker and TownhouseSplitter → `building_address_links`, `building_units`
5. Building geometry stays in S3; map fetches via GET `/api/campaigns/[id]/buildings`

**Error Responses**:
- `400` - Missing or invalid campaign_id
- `404` - Campaign not found
- `500` - Server error (check logs)

---

### Address List Generation

**`POST /api/campaigns/generate-address-list`**

Generates address list from backend (Lambda + S3 / Overture) based on campaign parameters.

**Request**:
```json
{
  "campaign_id": "550e8400-e29b-41d4-a716-446655440000",
  "params": {
    "source": "closest_home",
    "center": {
      "lat": 35.9940,
      "lon": -78.8986
    },
    "radius_meters": 1000,
    "limit": 100
  }
}
```

**Alternative Request (Same Street)**:
```json
{
  "campaign_id": "550e8400-e29b-41d4-a716-446655440000",
  "params": {
    "source": "same_street",
    "street": "Main St",
    "city": "Durham",
    "ref_lat": 35.9940,
    "ref_lon": -78.8986
  }
}
```

**Response**:
```json
{
  "addresses": [
    {
      "formatted": "123 Main St",
      "latitude": 35.9940,
      "longitude": -78.8986,
      "postal_code": "27701",
      "city": "Durham",
      "province": "NC"
    }
  ],
  "count": 100
}
```

**Address Sources**:
- `closest_home` - Radial search from center point
- `same_street` - Addresses on same street
- `import_list` - User-provided CSV import
- `map` - User-drawn polygon on map

---

## Supabase Edge Functions

Base URL: `https://<project-ref>.supabase.co/functions/v1`

All functions require `Authorization: Bearer <anon-key>` header.

---

### Tile Decode (Building Polygons)

**`POST /functions/v1/tiledecode_buildings`**

Decodes Mapbox Vector Tiles (MVT) to extract building polygons for addresses.

**Request**:
```json
{
  "addresses": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "lat": 35.9940,
      "lon": -78.8986,
      "formatted": "123 Main St"
    }
  ],
  "zoom": 16,
  "searchRadiusM": 15,
  "retryRadiusM": 30
}
```

**Response**:
```json
{
  "matched": 85,
  "proxies": 10,
  "created": 90,
  "updated": 5,
  "features": [...],
  "results": [
    {
      "address_id": "550e8400-e29b-41d4-a716-446655440000",
      "method": "contains",
      "building_id": "770e8400-e29b-41d4-a716-446655440000",
      "area_m2": 145.3
    }
  ]
}
```

**Process**:
1. Fetches MVT tiles from Mapbox for each address location
2. Decodes tile to extract building polygons
3. Finds closest building to address point (contains > nearby > largest)
4. Inserts/updates `building_polygons` table
5. Returns GeoJSON features and metadata

**Matching Methods**:
- `contains` - Address point inside building polygon (best)
- `nearby` - Building centroid within radius (fallback)
- `largest` - Largest building by area (last resort)

---

### Tile Query (Building Polygons)

**`POST /functions/v1/tilequery_buildings`**

Uses Mapbox Tilequery API to fetch building polygons (simpler alternative to tile decode).

**Request**:
```json
{
  "addresses": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "lat": 35.9940,
      "lon": -78.8986
    }
  ]
}
```

**Response**: Same structure as `tiledecode_buildings`

**Tileset Strategy**:
1. Primary: `mapbox.buildings-v3` (building footprints)
2. Fallback: `mapbox.mapbox-streets-v8` (building layer)

**Use when**: Need simpler API, don't need fine-grained control

---

### QR Code Redirect

**`GET /functions/v1/qr_redirect/q/<slug>`**

Redirects QR code scans to landing pages or custom URLs with analytics tracking.

**URL**: `https://<project-ref>.supabase.co/functions/v1/qr_redirect/q/abc123`

**Process**:
1. Looks up QR code by slug in `qr_codes` table
2. Logs scan in `qr_code_scans` table (IP, user agent, timestamp)
3. Increments analytics counters
4. Updates `building_stats.scans_total` via trigger
5. Redirects to landing page or custom URL

**Query Parameters** (optional):
- `?preview=true` - Preview mode (no analytics)
- `?debug=true` - Debug mode (JSON response)

**Response (normal)**:
- `302` redirect to destination URL

**Response (debug mode)**:
```json
{
  "qr_code_id": "550e8400-e29b-41d4-a716-446655440000",
  "destination": "https://example.com/landing",
  "scans_total": 42
}
```

**Error Responses**:
- `404` - QR code not found
- `410` - QR code expired/disabled

---

### OAuth Exchange

**`POST /functions/v1/oauth_exchange`**

Exchanges OAuth authorization codes for access tokens (CRM integrations).

**Request**:
```json
{
  "provider": "hubspot",
  "code": "auth_code_from_oauth_callback",
  "user_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

**Supported Providers**:
- `hubspot` - HubSpot CRM
- `monday` - Monday.com
- `fub` - Follow Up Boss
- `kvcore` - KVCore

**Response**:
```json
{
  "success": true,
  "provider": "hubspot",
  "expires_at": "2024-12-31T23:59:59Z"
}
```

**Process**:
1. Exchanges code for access/refresh tokens via provider OAuth API
2. Stores tokens in `user_integrations` table (encrypted)
3. Returns success status

**Error Responses**:
- `400` - Invalid code or provider
- `401` - OAuth exchange failed

---

### CRM Sync

**`POST /functions/v1/crm_sync`**

Syncs lead to connected CRM integrations.

**Request**:
```json
{
  "lead": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "name": "John Doe",
    "phone": "+1-555-0123",
    "email": "john@example.com",
    "address": "123 Main St, Durham, NC",
    "source": "door_knock",
    "campaign_id": "660e8400-e29b-41d4-a716-446655440000",
    "notes": "Interested in selling next year"
  },
  "user_id": "770e8400-e29b-41d4-a716-446655440000"
}
```

**Response**:
```json
{
  "success": true,
  "synced_to": ["hubspot", "monday"],
  "results": {
    "hubspot": {
      "contact_id": "12345",
      "url": "https://app.hubspot.com/contacts/12345"
    },
    "monday": {
      "item_id": "67890",
      "url": "https://monday.com/boards/123/pulses/67890"
    }
  }
}
```

**Process**:
1. Looks up user's active integrations in `user_integrations`
2. For each integration, creates/updates contact via provider API
3. Returns sync results for each provider

**Supported Providers**:
- HubSpot - Creates contact + deal
- Monday.com - Creates item in leads board
- Follow Up Boss - Creates lead
- KVCore - Creates contact
- Zapier - Triggers webhook

---

## Authentication

### iOS Client Pattern

```swift
// Get Supabase auth token
let session = try await supabase.auth.session
let token = session.accessToken

// Call backend API
var request = URLRequest(url: URL(string: "\(apiURL)/api/campaigns/provision")!)
request.httpMethod = "POST"
request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
request.httpBody = try JSONEncoder().encode(payload)

let (data, response) = try await URLSession.shared.data(for: request)
```

### Edge Function Pattern

```swift
// Edge functions use Supabase anon key
let response = try await supabase.functions.invoke(
  "tiledecode_buildings",
  options: FunctionInvokeOptions(
    body: payload
  )
)
```

---

## Rate Limiting

### Backend API
- **Rate limit**: 100 requests/minute per user
- **Burst**: 10 concurrent requests
- **Header**: `X-RateLimit-Remaining` shows remaining requests

### Edge Functions
- **Rate limit**: 60 requests/minute per IP
- **Burst**: 5 concurrent requests
- **Retry-After**: Header shows seconds to wait if rate limited

---

## Error Handling

### Standard Error Response

```json
{
  "error": "Error message here",
  "code": "ERROR_CODE",
  "details": {...}
}
```

### Common Error Codes

- `INVALID_REQUEST` - Missing or invalid parameters
- `UNAUTHORIZED` - Invalid or missing auth token
- `FORBIDDEN` - User lacks permission
- `NOT_FOUND` - Resource not found
- `RATE_LIMIT_EXCEEDED` - Too many requests
- `SERVER_ERROR` - Internal server error

### iOS Error Handling

```swift
do {
  let result = try await api.provision(campaignId: id)
  // Handle success
} catch let error as APIError {
  switch error.code {
  case "RATE_LIMIT_EXCEEDED":
    // Show rate limit message, retry later
  case "NOT_FOUND":
    // Show not found message
  default:
    // Show generic error
  }
}
```

---

## Environment Configuration

### iOS App (Info.plist)

```xml
<key>FLYR_PRO_API_URL</key>
<string>https://flyrpro.app</string>

<key>SUPABASE_URL</key>
<string>https://xxx.supabase.co</string>

<key>SUPABASE_ANON_KEY</key>
<string>eyJhbGciOi...</string>
```

### Backend (.env)

```bash
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_SERVICE_KEY=eyJhbGciOi...
MAPBOX_ACCESS_TOKEN=pk.your_public_token_here
# Backend uses Lambda + S3 for provision; no MotherDuck token in this repo.
```

---

## Best Practices

1. **Always include auth token** in `Authorization` header
2. **Handle rate limits** with exponential backoff retry
3. **Validate responses** for expected structure
4. **Log errors** with request IDs for debugging
5. **Use edge functions** for Supabase operations (avoid backend when possible)
6. **Cache responses** when appropriate (addresses, buildings)
7. **Handle timeouts** gracefully (provision can take 30+ seconds)
