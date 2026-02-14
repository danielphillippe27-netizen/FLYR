// supabase/functions/tiledecode_buildings/index.ts
// Deno Edge Function: Decode Mapbox Vector Tiles to get real building polygons,
// select best polygon per address, cache in building_polygons, timed logs.
// Uses style-based MVT fetching with fallback to streets-v11.

import { createClient } from "npm:@supabase/supabase-js@2";
import { VectorTile } from "https://esm.sh/@mapbox/vector-tile@1.3.1";
import Pbf from "https://esm.sh/pbf@3.2.1";
import * as turf from "https://esm.sh/@turf/turf@6.5.0";

type AddressIn = {
  id: string;            // Expected to be campaign_addresses.id
  lat: number;
  lon: number;
  formatted?: string;    // Add for fallback resolution
};

type EnsurePayload = {
  addresses: AddressIn[];
  // Optional overrides
  zoom?: number;         // default 16
  searchRadiusM?: number;// default 50
  retryRadiusM?: number; // default 75
  maxTilesPerAddr?: number; // default 5 (center + 4 neighbors)
};

type PerAddressResult = {
  id: string;
  status: "matched" | "proxy";
  reason?: "no-mvt" | "no-building-layer" | "no-polygons" | "decode-error";
};

type MapboxStyle = {
  sources: Record<string, { type: string; url?: string; tiles?: string[] }>;
};

// ------------------------------
// Configuration Constants
// ------------------------------
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const MAPBOX_TOKEN = Deno.env.get("MAPBOX_ACCESS_TOKEN")!;

// REQUIRED: set your style here (Mapbox Studio → Styles → your style)
// Example: mapbox://styles/<username>/<style_id>
// Using custom light style as default
const STYLE_URL = Deno.env.get("MAPBOX_STYLE_URL") ?? "mapbox://styles/fliper27/cml6z0dhg002301qo9xxc08k4";

// Source layer name used for buildings in Streets styles (usually "building")
const BUILDING_LAYER = "building";

// Fallback classic tileset id (vector tiles API v4)
const FALLBACK_TILESET_ID = "mapbox.mapbox-streets-v11";

// Search radii (meters)
const SEARCH_RADIUS_M = 50;
const RETRY_RADIUS_M = 75;

// Neighborhood tiles to fetch around center to avoid edge cutoffs
const NEIGHBOR_OFFSETS = [
  [0, 0],   // center
  [1, 0],   // east
  [-1, 0],  // west
  [0, 1],   // south
  [0, -1],  // north
];

if (!MAPBOX_TOKEN) {
  throw new Error("Missing MAPBOX_ACCESS_TOKEN");
}

if (!SERVICE_ROLE) {
  throw new Error("Missing SUPABASE_SERVICE_ROLE_KEY - required for database writes");
}

const supabase = createClient(
  SUPABASE_URL,
  SERVICE_ROLE,
  { auth: { persistSession: false } },
);

// ------------------------------
// Style Resolution
// ------------------------------
async function resolveStyleTilesTemplate(styleUrl: string, token: string): Promise<string | null> {
  // Accepts "mapbox://styles/user/styleid" or full https; normalize to v1 styles API
  const m = styleUrl.match(/^mapbox:\/\/styles\/([^/]+)\/([^/]+)$/);
  const styleApiUrl = m
    ? `https://api.mapbox.com/styles/v1/${m[1]}/${m[2]}?access_token=${token}`
    : `${styleUrl}${styleUrl.includes("?") ? "&" : "?"}access_token=${token}`;

  try {
    const res = await fetch(styleApiUrl);
    if (!res.ok) {
      console.log(`[STYLE] Fetch failed ${res.status} for ${styleUrl}`);
      return null;
    }
    const style: MapboxStyle = await res.json();

    // Most Mapbox base styles put building in the "composite" source
    // but we'll scan all vector sources to find one that provides a tiles template.
    for (const [name, src] of Object.entries(style.sources)) {
      if (src.type !== "vector") continue;

      // Preferred: explicit tiles array (modern styles often include this)
      if (src.tiles?.length) {
        // Example template:
        // https://api.mapbox.com/v4/mapbox.mapbox-streets-v11/{z}/{x}/{y}.vector.pbf?access_token=...
        const template = src.tiles[0].replace(/\{access_token\}.*$/, "").replace(/\?$/, "");
        console.log(`[STYLE] Using source "${name}" tiles template: ${template.substring(0, 80)}...`);
        return template;
      }

      // Fallback: an embedded URL "mapbox://mapbox.mapbox-streets-v11"
      if (src.url?.startsWith("mapbox://")) {
        const tilesetId = src.url.replace("mapbox://", "");
        const template = `https://api.mapbox.com/v4/${tilesetId}/{z}/{x}/{y}.vector.pbf`;
        console.log(`[STYLE] Using source "${name}" via tileset "${tilesetId}"`);
        return template;
      }
    }

    console.log("[STYLE] No vector source with tiles template found");
    return null;
  } catch (error) {
    console.error(`[STYLE] Error resolving style: ${error}`);
    return null;
  }
}

// ------------------------------
// Tile URL Helpers
// ------------------------------
function tileURLFromTemplate(template: string, z: number, x: number, y: number, token: string): string {
  const base = template
    .replace("{z}", String(z))
    .replace("{x}", String(x))
    .replace("{y}", String(y));
  const url = base.includes("?") ? `${base}&access_token=${token}` : `${base}?access_token=${token}`;
  return url;
}

function fallbackTileURL(tilesetId: string, z: number, x: number, y: number, token: string): string {
  return `https://api.mapbox.com/v4/${tilesetId}/${z}/${x}/${y}.vector.pbf?access_token=${token}`;
}

// ------------------------------
// MVT Decoding
// ------------------------------
async function getBuildingPolygonsFromTile(url: string, z: number, x: number, y: number): Promise<GeoJSON.Feature<GeoJSON.Polygon | GeoJSON.MultiPolygon>[]> {
  const t0 = performance.now();
  const r = await fetch(url, {
    headers: {
      "Accept": "application/x-protobuf",
    },
  });
  const t1 = performance.now();
  
  if (!r.ok) {
    console.log(`[MVT] ${r.status} for ${z}/${x}/${y} in ${(t1 - t0).toFixed(1)}ms`);
    return [];
  }
  
  const buf = new Uint8Array(await r.arrayBuffer());
  const tile = new VectorTile(new Pbf(buf));
  const layer = tile.layers[BUILDING_LAYER];
  
  if (!layer) {
    // Try fallback layer names
    const fallbackLayers = ["buildings", "structure"];
    for (const fallback of fallbackLayers) {
      if (tile.layers[fallback]) {
        console.log(`[MVT] Using fallback layer "${fallback}" for tile ${z}/${x}/${y}`);
        const fallbackLayer = tile.layers[fallback];
        const features: GeoJSON.Feature<GeoJSON.Polygon | GeoJSON.MultiPolygon>[] = [];
        for (let i = 0; i < fallbackLayer.length; i++) {
          const feat = fallbackLayer.feature(i);
          if (feat.type !== 3) continue; // only polygons
          const gj = feat.toGeoJSON(x, y, z) as GeoJSON.Feature<GeoJSON.Geometry>;
          if (gj.geometry?.type === "Polygon" || gj.geometry?.type === "MultiPolygon") {
            features.push(gj as GeoJSON.Feature<GeoJSON.Polygon | GeoJSON.MultiPolygon>);
          }
        }
        return features;
      }
    }
    return [];
  }

  const features: GeoJSON.Feature<GeoJSON.Polygon | GeoJSON.MultiPolygon>[] = [];
  for (let i = 0; i < layer.length; i++) {
    const feat = layer.feature(i);
    if (feat.type !== 3) continue; // only polygons (type 3)
    const gj = feat.toGeoJSON(x, y, z) as GeoJSON.Feature<GeoJSON.Geometry>;
    if (gj.geometry?.type === "Polygon" || gj.geometry?.type === "MultiPolygon") {
      features.push(gj as GeoJSON.Feature<GeoJSON.Polygon | GeoJSON.MultiPolygon>);
    }
  }
  
  if (features.length > 0) {
    console.log(`[MVT] Extracted ${features.length} polygons from tile ${z}/${x}/${y} in ${(t1 - t0).toFixed(1)}ms`);
  }
  return features;
}

// ------------------------------
// Coordinate/Tile Helpers
// ------------------------------
function lngLatToTile(lon: number, lat: number, z: number): { x: number; y: number } {
  const x = Math.floor(((lon + 180) / 360) * Math.pow(2, z));
  const y = Math.floor(
    (1 - Math.log(Math.tan((lat * Math.PI) / 180) + 1 / Math.cos((lat * Math.PI) / 180)) / Math.PI) / 2 * Math.pow(2, z)
  );
  return { x, y };
}

// ------------------------------
// Selection Logic
// ------------------------------
function selectBestPolygon(
  point: turf.helpers.Point,
  polys: GeoJSON.Feature<GeoJSON.Polygon | GeoJSON.MultiPolygon>[],
  searchRadiusM: number,
): GeoJSON.Feature<GeoJSON.Polygon | GeoJSON.MultiPolygon> | null {
  if (polys.length === 0) return null;

  // 1) contains
  for (const f of polys) {
    if (turf.booleanPointInPolygon(point, f)) return f;
  }

  // 2) nearest within radius
  let best: { f: GeoJSON.Feature<GeoJSON.Polygon | GeoJSON.MultiPolygon>, dist: number } | null = null;
  for (const f of polys) {
    const centroid = turf.centroid(f);
    const d = turf.distance(point, centroid, { units: "meters" });
    if (d <= searchRadiusM && (!best || d < best.dist)) best = { f, dist: d };
  }
  if (best) return best.f;

  // 3) largest area
  let largest: { f: GeoJSON.Feature<GeoJSON.Polygon | GeoJSON.MultiPolygon>, area: number } | null = null;
  for (const f of polys) {
    const a = turf.area(f);
    if (!largest || a > largest.area) largest = { f, area: a };
  }
  return largest?.f ?? null;
}

// ------------------------------
// UUID Validation Helper
// ------------------------------
const toUuid = (v: string): string => {
  // basic UUID v4/v1 tolerance; if invalid, throw early
  const ok = /^[0-9a-fA-F-]{36}$/.test(v);
  if (!ok) throw new Error(`Invalid UUID: ${v}`);
  return v.toLowerCase();
};

// ------------------------------
// FK Resolution
// ------------------------------
async function resolveCampaignAddressId(
  supabase: ReturnType<typeof createClient>,
  incoming: AddressIn
): Promise<string | null> {
  // Validate UUID format first
  let validatedId: string;
  try {
    validatedId = toUuid(incoming.id);
  } catch (e) {
    console.error(`[FK_RESOLVE] Invalid UUID format: ${incoming.id}`);
    return null;
  }

  // 1) Exact id lookup
  const { data: exact, error } = await supabase
    .from("campaign_addresses")
    .select("id")
    .eq("id", validatedId)
    .limit(1)
    .maybeSingle();

  if (error && error.code !== "PGRST116") {
    console.error(`[FK_RESOLVE] Error checking exact id: ${error.message}`);
  }
  
  if (exact?.id) {
    console.log(`[FK_RESOLVE] Found exact match for id=${validatedId}`);
    return exact.id;
  }

  // 2) Fallback: formatted address match only (proximity would require PostGIS RPC)
  // Since campaign_addresses uses PostGIS geometry, we'll match by formatted address only
  // This is a best-effort fallback - exact ID match should work in most cases
  if (!incoming.formatted) {
    console.log(`[FK_RESOLVE] No fallback data for id=${validatedId}`);
    return null;
  }

  const { data: fallback, error: fbError } = await supabase
    .from("campaign_addresses")
    .select("id, formatted")
    .eq("formatted", incoming.formatted)
    .limit(1)
    .maybeSingle();

  if (fbError && fbError.code !== "PGRST116") {
    console.error(`[FK_RESOLVE] Error in fallback lookup: ${fbError.message}`);
  }

  if (fallback?.id) {
    console.log(`[FK_RESOLVE] Found fallback match by formatted address: ${validatedId} -> ${fallback.id}`);
    return fallback.id;
  }

  console.log(`[FK_RESOLVE] No match found for id=${validatedId}, formatted=${incoming.formatted}`);
  return null;
}

// ------------------------------
// Database Operations
// ------------------------------
async function upsertPolygon(
  addressId: string,
  polygon: GeoJSON.Feature<GeoJSON.Polygon | GeoJSON.MultiPolygon> | null,
  incomingAddr: AddressIn
): Promise<{ upserted: boolean, area: number, created: boolean }> {
  if (!polygon) return { upserted: false, area: 0, created: false };
  
  // Validate and resolve FK first
  let address_id: string;
  try {
    address_id = toUuid(incomingAddr.id);
  } catch (e: any) {
    console.error(`[UPSERT][ERROR] Invalid UUID addr=${incomingAddr.id}:`, e.message);
    return { upserted: false, area: 0, created: false };
  }

  // Verify FK exists
  const fkId = await resolveCampaignAddressId(supabase, incomingAddr);
  if (!fkId) {
    console.error(`[UPSERT][ERROR] FK addr=${address_id}: address not found in campaign_addresses`);
    return { upserted: false, area: 0, created: false };
  }

  // Ensure resolved ID matches validated UUID
  if (fkId.toLowerCase() !== address_id) {
    console.log(`[UPSERT][INFO] Using resolved FK addr=${fkId} (original: ${address_id})`);
    address_id = fkId;
  }

  const area = turf.area(polygon);

  console.log(`[UPSERT][TRY] addr=${address_id}`);

  // Check if exists to determine created vs updated
  const { data: existing, error: selectError } = await supabase
    .from("building_polygons")
    .select("id")
    .eq("address_id", address_id)
    .maybeSingle();

  if (selectError && selectError.code !== "PGRST116") { // PGRST116 = not found, which is OK
    console.error(`[UPSERT][ERROR] Select check failed for address_id=${address_id}:`, JSON.stringify({
      addressId: address_id,
      error: selectError.message,
      code: selectError.code,
      details: selectError.details,
      hint: selectError.hint
    }));
  }

  const isCreated = existing === null;

  try {
    // Use fn_upsert_building_polygon RPC to populate both geom and geom_geom
    // The RPC expects a JSONB Feature with geometry property
    const { error: rpcError } = await supabase.rpc("fn_upsert_building_polygon", {
      p_address_id: address_id,
      p_geom_json: polygon as any, // GeoJSON Feature as JSONB
    });

    if (rpcError) {
      // Check for FK constraint violation (23503)
      if (rpcError.code === "23503" || rpcError.message?.includes("23503") || rpcError.message?.includes("foreign key")) {
        console.error(`[UPSERT][ERROR] FK addr=${address_id}:`, rpcError);
        return { upserted: false, area: 0, created: false };
      }
      console.error(`[UPSERT][ERROR] addr=${address_id}:`, rpcError);
      return { upserted: false, area: 0, created: false };
    }

    console.log(`[UPSERT][RESULT] addr=${address_id} created_or_updated=true`);
    return { upserted: true, area, created: isCreated };
  } catch (e: any) {
    // Surface FK error clearly
    if (e?.code === "23503" || e?.message?.includes("23503") || e?.message?.includes("foreign key")) {
      console.error(`[UPSERT][ERROR] FK addr=${address_id}:`, e);
    } else {
      console.error(`[UPSERT][ERROR] addr=${address_id}:`, e);
    }
    return { upserted: false, area: 0, created: false };
  }
}

// ------------------------------
// Main Decode Logic
// ------------------------------
async function decodeForAddress(
  addr: AddressIn,
  zoom: number,
  searchRadiusM: number,
  retryRadiusM: number,
  styleTemplate: string | null,
): Promise<GeoJSON.Feature<GeoJSON.Polygon | GeoJSON.MultiPolygon> | null> {
  const t0 = performance.now();
  const point = turf.point([addr.lon, addr.lat]);
  const { x, y } = lngLatToTile(addr.lon, addr.lat, zoom);

  let polys: GeoJSON.Feature<GeoJSON.Polygon | GeoJSON.MultiPolygon>[] = [];
  let usedStyle = false;

  // Try style tiles first
  if (styleTemplate) {
    usedStyle = true;
    console.log(`[STYLE] Fetching tiles for addr=${addr.id} at ${zoom}/${x}/${y}`);
    for (const [dx, dy] of NEIGHBOR_OFFSETS) {
      const url = tileURLFromTemplate(styleTemplate, zoom, x + dx, y + dy, MAPBOX_TOKEN);
      const tilePolys = await getBuildingPolygonsFromTile(url, zoom, x + dx, y + dy);
      polys = polys.concat(tilePolys);
    }
    console.log(`[STYLE] addr=${addr.id} extracted ${polys.length} polygons from style tiles`);
  }

  // Fallback to streets-v11 if no polygons from style
  if (polys.length === 0) {
    console.log(`[FALLBACK] No polygons from style, trying ${FALLBACK_TILESET_ID} for addr=${addr.id}`);
    for (const [dx, dy] of NEIGHBOR_OFFSETS) {
      const url = fallbackTileURL(FALLBACK_TILESET_ID, zoom, x + dx, y + dy, MAPBOX_TOKEN);
      const tilePolys = await getBuildingPolygonsFromTile(url, zoom, x + dx, y + dy);
      polys = polys.concat(tilePolys);
    }
    console.log(`[FALLBACK] addr=${addr.id} extracted ${polys.length} polygons from fallback tiles`);
  }

  // Deduplicate geometries by stringifying coordinates
  const seen = new Set<string>();
  polys = polys.filter((f) => {
    const key = JSON.stringify(f.geometry.coordinates);
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });

  // First pass: searchRadiusM
  let chosen = selectBestPolygon(point, polys, searchRadiusM);

  // Retry pass: retryRadiusM if none found
  if (!chosen && retryRadiusM > searchRadiusM) {
    chosen = selectBestPolygon(point, polys, retryRadiusM);
  }

  const t1 = performance.now();
  const source = usedStyle ? "STYLE" : "FALLBACK";
  console.log(`[SELECT] addr=${addr.id} source=${source} polys=${polys.length} chosen=${!!chosen} time=${(t1 - t0).toFixed(1)}ms`);
  
  return chosen ?? null;
}

// ------------------------------
// HTTP handler
// ------------------------------
Deno.serve(async (req) => {
  // CORS headers
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type"
      }
    });
  }

  if (req.method !== "POST") {
    return new Response("Use POST", { status: 405 });
  }

  const started = performance.now();
  const body = await req.json().catch(() => null) as EnsurePayload | null;
  
  // ---- Payload validation ----
  const MAX_ADDRESSES = 100;
  if (!body || !Array.isArray(body.addresses)) {
    return new Response(JSON.stringify({ error: "addresses must be an array" }), { status: 400 });
  }
  if (body.addresses.length === 0) {
    return new Response(JSON.stringify({ error: "addresses array is empty" }), { status: 400 });
  }
  if (body.addresses.length > MAX_ADDRESSES) {
    return new Response(JSON.stringify({ error: `too many addresses (max ${MAX_ADDRESSES})` }), { status: 413 });
  }

  const zoom = body.zoom ?? 16; // Default to 16 for better building detail
  const searchRadiusM = body.searchRadiusM ?? SEARCH_RADIUS_M;
  const retryRadiusM = body.retryRadiusM ?? RETRY_RADIUS_M;

  // Resolve style template once per request
  console.log(`[STYLE] Resolving style template from ${STYLE_URL}`);
  const styleTemplate = await resolveStyleTilesTemplate(STYLE_URL, MAPBOX_TOKEN);
  if (styleTemplate) {
    console.log(`[STYLE] Style template resolved successfully`);
  } else {
    console.log(`[STYLE] Style template resolution failed, will use fallback only`);
  }

  // Process in parallel with modest concurrency to avoid cold-start spikes / bandwidth issues
  const concurrency = 10;
  const chunks: AddressIn[][] = [];
  for (let i = 0; i < body.addresses.length; i += concurrency) {
    chunks.push(body.addresses.slice(i, i + concurrency));
  }

  let matched = 0, created = 0, updated = 0, proxies = 0;
  const results: PerAddressResult[] = [];
  const features: GeoJSON.Feature<GeoJSON.Polygon | GeoJSON.MultiPolygon>[] = [];
  
  for (let ci = 0; ci < chunks.length; ci++) {
    const chunk = chunks[ci];
    const t0 = performance.now();

    await Promise.all(chunk.map(async (addr) => {
      const poly = await decodeForAddress(addr, zoom, searchRadiusM, retryRadiusM, styleTemplate);

      if (poly) {
        matched++;
        // Resolve FK to get the actual DB ID for the feature properties
        const fkId = await resolveCampaignAddressId(supabase, addr);
        const addressIdForFeature = fkId || addr.id; // Use resolved FK or fallback to incoming ID
        
        // Normalize feature: ensure id is string or undefined, add address_id to properties
        const normalizedFeature: GeoJSON.Feature<GeoJSON.Polygon | GeoJSON.MultiPolygon> = {
          ...poly,
          id: typeof poly.id === 'string' ? poly.id : typeof poly.id === 'number' ? String(poly.id) : undefined,
          properties: {
            ...poly.properties,
            address_id: addressIdForFeature, // Add address_id for iOS to match
          }
        };
        // Add feature to array for immediate rendering
        features.push(normalizedFeature);
        
        const { upserted, created: isCreated } = await upsertPolygon(addr.id, poly, addr);
        if (upserted) {
          if (isCreated) {
            created++;
          } else {
            updated++;
          }
        }
        results.push({ id: addr.id, status: "matched" });
      } else {
        proxies++;
        results.push({ id: addr.id, status: "proxy", reason: "no-polygons" });
      }
    }));

    const t1 = performance.now();
    console.log(`✅ [BATCH] ${ci + 1}/${chunks.length} size=${chunk.length} time=${(t1 - t0).toFixed(0)}ms`);
  }

  // Alert if polygons found but none written
  if (created === 0 && matched > 0) {
    console.error(`[ALERT] Found ${matched} polygons but wrote none – check service key / FK constraint`);
  }

  const done = performance.now();
  const summary = {
    matched, proxies, created, updated,
    addresses: body.addresses.length,
    total_ms: Math.round(done - started),
    per_addr_ms: Math.round((done - started) / body.addresses.length),
    zoom, searchRadiusM, retryRadiusM,
    style_used: styleTemplate !== null,
    results,
    features, // Include features for immediate iOS rendering
  };
  console.log(`🏁 [SUMMARY]`, { ...summary, features: `[${features.length} features]` });

  return new Response(JSON.stringify(summary), {
    headers: { 
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*"
    },
    status: 200,
  });
});
