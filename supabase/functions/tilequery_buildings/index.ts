// Supabase Edge Function: tilequery_buildings
// Fetches building polygons from Mapbox Tilequery API (mapbox-streets-v8 tileset) and caches in building_polygons table
// Uses 50m initial radius, 75m retry for rural parcels
// Only saves Polygon and MultiPolygon geometries

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const MAPBOX_ACCESS_TOKEN = Deno.env.get("MAPBOX_ACCESS_TOKEN");
if (!MAPBOX_ACCESS_TOKEN) {
  throw new Error("Missing MAPBOX_ACCESS_TOKEN");
}
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Helper function to query a single tileset
async function tilequeryOnce(lon: number, lat: number, radius: number, tileset: string, layers?: string): Promise<{ status: number; feats: any[] }> {
  const params = new URLSearchParams({
    radius: String(radius),
    limit: "10",
    access_token: MAPBOX_ACCESS_TOKEN,
  });
  if (layers) params.set("layers", layers); // only for streets-v8

  const url = `https://api.mapbox.com/v4/${tileset}/tilequery/${lon},${lat}.json?${params}`;
  const safeUrlForLog = url.replace(/access_token=[^&]+/, "access_token=***");
  console.log(`[TILEQUERY] GET ${safeUrlForLog}`);
  
  const res = await fetch(url);
  const status = res.status;
  console.log(`[TILEQUERY] status ${status} for ${tileset}`);
  
  if (!res.ok) {
    return { status, feats: [] };
  }
  
  const json = await res.json().catch(() => ({}));
  const feats = Array.isArray(json?.features) ? json.features : [];
  const candidateCount = feats.length;
  const firstGeometryType = feats[0]?.geometry?.type || "none";
  console.log(`[TILEQUERY] candidates ${candidateCount} for ${tileset}, first geometry type: ${firstGeometryType}`);
  
  return { status, feats };
}

// Query building polygons with dual-tileset strategy
async function queryBuildingPolygons(lon: number, lat: number): Promise<any[]> {
  // 1) Primary: buildings-v3 (polygons)
  let { status, feats } = await tilequeryOnce(lon, lat, 50, "mapbox.mapbox-buildings-v3");
  let polys = feats.filter(f => ["Polygon", "MultiPolygon"].includes(f?.geometry?.type));
  console.log(`[TILEQUERY] buildings-v3 (50m)`, { status, total: feats.length, polys: polys.length });

  // 2) Retry buildings-v3 with larger radius if none
  if (polys.length === 0) {
    const retry = await tilequeryOnce(lon, lat, 75, "mapbox.mapbox-buildings-v3");
    const retryPolys = retry.feats.filter(f => ["Polygon", "MultiPolygon"].includes(f?.geometry?.type));
    console.log(`[TILEQUERY] buildings-v3 retry (75m)`, { status: retry.status, total: retry.feats.length, polys: retryPolys.length });
    if (retryPolys.length > 0) polys = retryPolys;
  }

  // 3) Fallback: streets-v8 (often Points; still filter for polygons)
  if (polys.length === 0) {
    const s8 = await tilequeryOnce(lon, lat, 75, "mapbox.mapbox-streets-v8", "building");
    const s8Polys = s8.feats.filter(f => ["Polygon", "MultiPolygon"].includes(f?.geometry?.type));
    console.log(`[TILEQUERY] streets-v8 fallback (75m)`, { status: s8.status, total: s8.feats.length, polys: s8Polys.length });
    if (s8Polys.length > 0) polys = s8Polys;
  }

  return polys;
}

interface AddressInput {
  id: string;
  lat: number;
  lon: number;
}

interface TilequeryResponse {
  features: Array<{
    id?: string;
    geometry: {
      type: string;
      coordinates: any;
    };
    properties: Record<string, any>;
  }>;
}

interface Result {
  address_id: string;
  matched: boolean;
  selection?: "contains" | "nearby" | "largest";
  area_m2?: number;
}

interface Response {
  created: number;
  updated: number;
  proxies: number;
  requested: number;
  matched: number;
  errors: number;
  results: Result[];
}

// Calculate polygon area in m² (rough approximation)
function calculateAreaM2(coordinates: number[][][]): number {
  if (!coordinates || coordinates.length === 0) return 0;
  const ring = coordinates[0];
  if (ring.length < 3) return 0;
  
  let area = 0;
  for (let i = 0; i < ring.length - 1; i++) {
    const p1 = ring[i];
    const p2 = ring[i + 1];
    area += (p1[0] * p2[1] - p2[0] * p1[1]);
  }
  return Math.abs(area / 2) * 111320 * 111320 * Math.cos((ring[0][1] + ring[ring.length - 1][1]) / 2 * Math.PI / 180);
}

// Calculate bounding box
function calculateBbox(coordinates: number[][][]): { minLng: number; minLat: number; maxLng: number; maxLat: number } {
  if (!coordinates || coordinates.length === 0) {
    return { minLng: 0, minLat: 0, maxLng: 0, maxLat: 0 };
  }
  
  let minLng = Infinity, minLat = Infinity, maxLng = -Infinity, maxLat = -Infinity;
  for (const ring of coordinates) {
    for (const coord of ring) {
      minLng = Math.min(minLng, coord[0]);
      minLat = Math.min(minLat, coord[1]);
      maxLng = Math.max(maxLng, coord[0]);
      maxLat = Math.max(maxLat, coord[1]);
    }
  }
  return { minLng, minLat, maxLng, maxLat };
}

// Calculate centroid
function calculateCentroid(coordinates: number[][][]): [number, number] | null {
  if (!coordinates || coordinates.length === 0) return null;
  const ring = coordinates[0];
  if (ring.length === 0) return null;
  
  let sumLng = 0, sumLat = 0;
  for (const coord of ring) {
    sumLng += coord[0];
    sumLat += coord[1];
  }
  return [sumLng / ring.length, sumLat / ring.length];
}

// Check if point is inside polygon (ray casting algorithm)
function pointInPolygon(lon: number, lat: number, coordinates: number[][][]): boolean {
  if (!coordinates || coordinates.length === 0) return false;
  const ring = coordinates[0];
  if (ring.length < 3) return false;
  
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const xi = ring[i][0], yi = ring[i][1];
    const xj = ring[j][0], yj = ring[j][1];
    
    const intersect = ((yi > lat) !== (yj > lat)) && (lon < (xj - xi) * (lat - yi) / (yj - yi) + xi);
    if (intersect) inside = !inside;
  }
  return inside;
}

// Calculate distance between two points in meters (Haversine)
function distanceMeters(lon1: number, lat1: number, lon2: number, lat2: number): number {
  const R = 6371000; // Earth radius in meters
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

// Select best building polygon from candidates
function selectBestPolygon(
  features: TilequeryResponse["features"],
  targetLon: number,
  targetLat: number
): { feature: TilequeryResponse["features"][0]; selection: "contains" | "nearby" | "largest" } | null {
  if (!features || features.length === 0) return null;
  
  // Filter to polygons only
  const polygons = features.filter(f => 
    f.geometry.type === "Polygon" || f.geometry.type === "MultiPolygon"
  );
  
  if (polygons.length === 0) return null;
  
  // Step 1: Check for polygons containing the point
  const containing: Array<{ feature: typeof polygons[0]; area: number }> = [];
  for (const feature of polygons) {
    const coords = feature.geometry.type === "Polygon" 
      ? feature.geometry.coordinates 
      : feature.geometry.coordinates[0]; // Use first polygon of MultiPolygon
    
    if (pointInPolygon(targetLon, targetLat, coords)) {
      const area = calculateAreaM2(coords);
      containing.push({ feature, area });
    }
  }
  
  if (containing.length > 0) {
    // If multiple containing, pick largest
    const best = containing.reduce((a, b) => a.area > b.area ? a : b);
    return { feature: best.feature, selection: "contains" };
  }
  
  // Step 2: Check for polygons with centroid within 15m
  const maxDistance = 15.0; // meters
  const nearby: Array<{ feature: typeof polygons[0]; distance: number; area: number }> = [];
  
  for (const feature of polygons) {
    const coords = feature.geometry.type === "Polygon"
      ? feature.geometry.coordinates
      : feature.geometry.coordinates[0];
    
    const centroid = calculateCentroid(coords);
    if (centroid) {
      const distance = distanceMeters(targetLon, targetLat, centroid[0], centroid[1]);
      if (distance <= maxDistance) {
        const area = calculateAreaM2(coords);
        nearby.push({ feature, distance, area });
      }
    }
  }
  
  if (nearby.length > 0) {
    // Pick nearest centroid
    const best = nearby.reduce((a, b) => a.distance < b.distance ? a : b);
    return { feature: best.feature, selection: "nearby" };
  }
  
  // Step 3: Pick largest area
  const withAreas = polygons.map(f => {
    const coords = f.geometry.type === "Polygon"
      ? f.geometry.coordinates
      : f.geometry.coordinates[0];
    return { feature: f, area: calculateAreaM2(coords) };
  });
  
  const largest = withAreas.reduce((a, b) => a.area > b.area ? a : b);
  return { feature: largest.feature, selection: "largest" };
}

// Process a single address
async function processAddress(
  address: AddressInput,
  supabase: any
): Promise<Result> {
  const { id, lat, lon } = address;
  
  try {
    // Use dual-tileset strategy: buildings-v3 primary, streets-v8 fallback
    const polygonFeatures = await queryBuildingPolygons(lon, lat);
    
    if (polygonFeatures.length === 0) {
      console.log(`[TILEQUERY] ${id}: No polygon geometries found after all tileset attempts`);
      return { address_id: id, matched: false };
    }
    
    // Select best polygon from filtered features (contains → nearby → largest)
    const selected = selectBestPolygon(polygonFeatures, lon, lat);
    
    if (!selected) {
      console.log(`[TILEQUERY] ${id}: No polygon selected from ${polygonFeatures.length} candidates`);
      return { address_id: id, matched: false };
    }
    
    // Process selected polygon
    const coords = selected.feature.geometry.type === "Polygon"
      ? selected.feature.geometry.coordinates
      : selected.feature.geometry.coordinates[0];
    
    const areaM2 = calculateAreaM2(coords);
    const bbox = calculateBbox(coords);
    const centroid = calculateCentroid(coords);
    
    const feature: any = {
      type: "Feature",
      geometry: selected.feature.geometry,
      properties: {
        address_id: id,
        source: "mapbox_tilequery",
        selection: selected.selection,
        ...selected.feature.properties
      }
    };
    
    const geomJson = JSON.stringify(feature);
    
    // Check if exists to determine created vs updated
    const { data: existing } = await supabase
      .from("building_polygons")
      .select("id")
      .eq("address_id", id)
      .single();
    
    const isUpdate = existing !== null;
    
    // Upsert to database
    const upsertData: any = {
      address_id: id,
      source: "mapbox_tilequery",
      geom: JSON.parse(geomJson),
      area_m2: areaM2,
      bbox: bbox,
      properties: selected.feature.properties || {},
      updated_at: new Date().toISOString()
    };
    
    if (centroid) {
      // PostGIS GEOGRAPHY(Point,4326) format: use ST_GeogFromText or WKT
      upsertData.centroid_lnglat = `SRID=4326;POINT(${centroid[0]} ${centroid[1]})`;
    }
    
    const { error } = await supabase
      .from("building_polygons")
      .upsert(upsertData, {
        onConflict: "address_id"
      });
    
    if (error) {
      console.error(`[DB] Upsert error for ${id}:`, error);
      return { address_id: id, matched: false };
    }
    
    console.log(`[TILEQUERY] ${id}: ${selected.selection}, area=${areaM2.toFixed(1)}m², ${isUpdate ? 'updated' : 'created'}`);
    
    return {
      address_id: id,
      matched: true,
      selection: selected.selection,
      area_m2: areaM2
    };
    
  } catch (error) {
    console.error(`[TILEQUERY] Error processing ${id}:`, error);
    return { address_id: id, matched: false };
  }
}

serve(async (req) => {
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
  
  try {
    // Verify authentication
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      );
    }
    
    // Parse request body
    const { addresses }: { addresses: AddressInput[] } = await req.json();
    
    if (!addresses || !Array.isArray(addresses) || addresses.length === 0) {
      return new Response(
        JSON.stringify({ error: "Invalid request: addresses array required" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }
    
    // Initialize Supabase client with service role
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    
    // Process in batches of 10
    const batchSize = 10;
    const delayBetweenBatches = 150; // ms
    
    const results: Result[] = [];
    let created = 0;
    let updated = 0;
    let proxies = 0;
    let errors = 0;
    
    for (let i = 0; i < addresses.length; i += batchSize) {
      const batch = addresses.slice(i, i + batchSize);
      console.log(`[BATCH] Processing batch ${Math.floor(i / batchSize) + 1}, ${batch.length} addresses`);
      
      // Process batch in parallel
      const batchResults = await Promise.all(
        batch.map(addr => processAddress(addr, supabase))
      );
      
      results.push(...batchResults);
      
      // Count stats (created/updated tracking would require returning from processAddress)
      // For now, we'll track in the response but simplified counting
      for (const result of batchResults) {
        if (result.matched) {
          // Simplified: assume created for now (could be enhanced to track from DB)
          created++;
        } else {
          proxies++;
        }
      }
      
      // Delay between batches (except last)
      if (i + batchSize < addresses.length) {
        await new Promise(resolve => setTimeout(resolve, delayBetweenBatches));
      }
    }
    
    const matched = results.filter(r => r.matched).length;
    
    const response: Response = {
      created,
      updated,
      proxies,
      requested: addresses.length,
      matched,
      errors,
      results
    };
    
    return new Response(
      JSON.stringify(response),
      {
        status: 200,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*"
        }
      }
    );
    
  } catch (error) {
    console.error("[ERROR]", error);
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});

