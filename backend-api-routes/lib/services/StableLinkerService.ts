import { createClient } from "@supabase/supabase-js";
import type { GeoJSONFeatureCollection } from "./TileLambdaService";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

// Valid match_type values (matches building_address_links CHECK constraint)
export type MatchType =
  | "containment_verified"
  | "containment_suspect"
  | "point_on_surface"
  | "proximity_verified"
  | "proximity_fallback"
  | "manual"
  | "orphan";

export type UnitArrangement = "single" | "horizontal" | "vertical";

export interface BuildingMatch {
  campaign_id:         string;
  building_id:         string;  // GERS ID text (NOT uuid)
  address_id:          string;  // campaign_addresses.id UUID
  match_type:          MatchType;
  confidence:          number;  // 0.0–1.0
  distance_meters:     number | null;
  street_match_score:  number | null;
  building_area_sqm:   number | null;
  building_class:      string | null;
  building_height:     number | null;
  is_multi_unit:       boolean;
  unit_count:          number;
  unit_arrangement:    UnitArrangement | null;
  overture_release:    string | null;
}

interface CampaignAddressRow {
  id:           string;
  house_number: string | null;
  street_name:  string | null;
  // [lng, lat]
  longitude:    number;
  latitude:     number;
}

interface BuildingFeatureNormalized {
  id:           string;  // GERS ID
  height:       number | null;
  area_sqm:     number | null;
  building_type:string | null;
  polygon:      Array<[number, number]>; // exterior ring [lng, lat]
  centroid:     [number, number];
}

// ---- Geometry helpers (pure JS, no PostGIS) --------------------------------

function toRad(deg: number) { return deg * (Math.PI / 180); }

/** Haversine distance in metres between two [lng, lat] points. */
function haversine(a: [number, number], b: [number, number]): number {
  const R = 6_371_000;
  const dLat = toRad(b[1] - a[1]);
  const dLng = toRad(b[0] - a[0]);
  const sinLat = Math.sin(dLat / 2);
  const sinLng = Math.sin(dLng / 2);
  const c =
    sinLat * sinLat +
    Math.cos(toRad(a[1])) * Math.cos(toRad(b[1])) * sinLng * sinLng;
  return R * 2 * Math.atan2(Math.sqrt(c), Math.sqrt(1 - c));
}

/** Ray-casting point-in-polygon for [lng, lat] point. */
function pointInPolygon(
  point: [number, number],
  ring: Array<[number, number]>
): boolean {
  let inside = false;
  const [px, py] = point;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i];
    const [xj, yj] = ring[j];
    const intersect =
      yi > py !== yj > py &&
      px < ((xj - xi) * (py - yi)) / (yj - yi) + xi;
    if (intersect) inside = !inside;
  }
  return inside;
}

/** Centroid of a polygon ring. */
function ringCentroid(ring: Array<[number, number]>): [number, number] {
  let x = 0; let y = 0;
  ring.forEach(([lx, ly]) => { x += lx; y += ly; });
  return [x / ring.length, y / ring.length];
}

/** Jaro-Winkler similarity, simplified. Returns 0–1. */
function jaroWinkler(s1: string, s2: string): number {
  if (s1 === s2) return 1;
  const len1 = s1.length; const len2 = s2.length;
  const matchDist = Math.max(Math.floor(Math.max(len1, len2) / 2) - 1, 0);
  const s1Matches = new Array(len1).fill(false);
  const s2Matches = new Array(len2).fill(false);
  let matches = 0; let transpositions = 0;
  for (let i = 0; i < len1; i++) {
    const lo = Math.max(0, i - matchDist);
    const hi = Math.min(i + matchDist + 1, len2);
    for (let j = lo; j < hi; j++) {
      if (s2Matches[j] || s1[i] !== s2[j]) continue;
      s1Matches[i] = true; s2Matches[j] = true; matches++; break;
    }
  }
  if (!matches) return 0;
  let k = 0;
  for (let i = 0; i < len1; i++) {
    if (!s1Matches[i]) continue;
    while (!s2Matches[k]) k++;
    if (s1[i] !== s2[k]) transpositions++;
    k++;
  }
  const jaro =
    (matches / len1 + matches / len2 + (matches - transpositions / 2) / matches) / 3;
  let prefix = 0;
  for (let i = 0; i < Math.min(4, Math.min(len1, len2)); i++) {
    if (s1[i] !== s2[i]) break;
    prefix++;
  }
  return jaro + prefix * 0.1 * (1 - jaro);
}

// ---- Feature parsing -------------------------------------------------------

function parseBuildings(
  geojson: GeoJSONFeatureCollection
): BuildingFeatureNormalized[] {
  const results: BuildingFeatureNormalized[] = [];
  for (const f of geojson.features) {
    const props = f.properties ?? {};
    const id =
      (props.gers_id as string | null) ??
      (props.id as string | null) ??
      (f.id?.toString() ?? "");
    if (!id) continue;

    const geomType = f.geometry?.type;
    let ring: Array<[number, number]> | null = null;

    if (geomType === "Polygon") {
      const coords = f.geometry.coordinates as Array<Array<[number, number]>>;
      ring = coords[0] ?? null;
    } else if (geomType === "MultiPolygon") {
      const coords = f.geometry.coordinates as Array<Array<Array<[number, number]>>>;
      // Use largest ring
      let best: Array<[number, number]> = [];
      for (const poly of coords) {
        const outer = poly[0] ?? [];
        if (outer.length > best.length) best = outer;
      }
      ring = best.length > 0 ? best : null;
    }

    if (!ring || ring.length < 3) continue;

    results.push({
      id,
      height:        (props.height_m as number | null) ?? (props.height as number | null) ?? null,
      area_sqm:      (props.area_sqm as number | null) ?? (props.building_area_sqm as number | null) ?? null,
      building_type: (props.building_type as string | null) ?? (props.building_class as string | null) ?? null,
      polygon: ring,
      centroid: ringCentroid(ring),
    });
  }
  return results;
}

// ---- Main spatial join -----------------------------------------------------

/**
 * Runs a 4-tier spatial match between campaign_addresses and building polygons.
 * Saves matches to building_address_links (upsert on campaign_id, address_id).
 */
export async function runSpatialJoin(
  campaignId: string,
  buildingsGeoJSON: GeoJSONFeatureCollection,
  overtureRelease?: string
): Promise<{ linked: number; orphans: number }> {
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // Load addresses for the campaign
  const { data: addrRows, error: addrErr } = await supabase
    .from("campaign_addresses")
    .select("id, house_number, street_name, geom")
    .eq("campaign_id", campaignId);

  if (addrErr || !addrRows) {
    throw new Error(`[StableLinkerService] Failed to load addresses: ${addrErr?.message}`);
  }

  // Parse geom column (Supabase returns WKT or GeoJSON string)
  const addresses: CampaignAddressRow[] = addrRows
    .filter((r) => r.geom != null)
    .map((r) => {
      let lng = 0; let lat = 0;
      try {
        const g = typeof r.geom === "string" ? JSON.parse(r.geom) : r.geom;
        if (g?.coordinates) { [lng, lat] = g.coordinates as [number, number]; }
      } catch { /* skip unparseable */ }
      return { id: r.id, house_number: r.house_number, street_name: r.street_name, longitude: lng, latitude: lat };
    })
    .filter((a) => a.longitude !== 0 || a.latitude !== 0);

  const buildings = parseBuildings(buildingsGeoJSON);
  console.log(
    `[StableLinkerService] Matching ${addresses.length} addresses vs ${buildings.length} buildings`
  );

  const matches: BuildingMatch[] = [];
  const PROXIMITY_VERIFIED_DIST = 15;
  const PROXIMITY_FALLBACK_DIST = 30;
  const STREET_MATCH_THRESHOLD = 0.85;

  for (const addr of addresses) {
    const pt: [number, number] = [addr.longitude, addr.latitude];
    let matched: BuildingMatch | null = null;

    // Tier 1: containment_verified — point inside polygon
    for (const b of buildings) {
      if (pointInPolygon(pt, b.polygon)) {
        matched = {
          campaign_id:        campaignId,
          building_id:        b.id,
          address_id:         addr.id,
          match_type:         "containment_verified",
          confidence:         1.0,
          distance_meters:    0,
          street_match_score: null,
          building_area_sqm:  b.area_sqm,
          building_class:     b.building_type,
          building_height:    b.height,
          is_multi_unit:      false,
          unit_count:         1,
          unit_arrangement:   null,
          overture_release:   overtureRelease ?? null,
        };
        break;
      }
    }
    if (matched) { matches.push(matched); continue; }

    // Tier 2: point_on_surface — address is very close to a building centroid
    let minDist = Infinity;
    let closest: BuildingFeatureNormalized | null = null;
    for (const b of buildings) {
      const d = haversine(pt, b.centroid);
      if (d < minDist) { minDist = d; closest = b; }
    }

    if (closest && minDist <= 5) {
      matched = {
        campaign_id: campaignId, building_id: closest.id, address_id: addr.id,
        match_type: "point_on_surface", confidence: 0.95,
        distance_meters: minDist, street_match_score: null,
        building_area_sqm: closest.area_sqm, building_class: closest.building_type,
        building_height: closest.height, is_multi_unit: false, unit_count: 1,
        unit_arrangement: null, overture_release: overtureRelease ?? null,
      };
      matches.push(matched); continue;
    }

    // Tier 3: proximity_verified — within 15 m AND street name matches
    if (closest && minDist <= PROXIMITY_VERIFIED_DIST) {
      const bStreet = (closest.building_type ?? "").toLowerCase(); // buildings don't have street; use address
      const aStreet = (addr.street_name ?? "").toLowerCase();
      const score = aStreet && bStreet ? jaroWinkler(aStreet, bStreet) : 0;
      if (score >= STREET_MATCH_THRESHOLD) {
        matched = {
          campaign_id: campaignId, building_id: closest.id, address_id: addr.id,
          match_type: "proximity_verified",
          confidence: Math.max(0, 1 - minDist / PROXIMITY_VERIFIED_DIST),
          distance_meters: minDist, street_match_score: score,
          building_area_sqm: closest.area_sqm, building_class: closest.building_type,
          building_height: closest.height, is_multi_unit: false, unit_count: 1,
          unit_arrangement: null, overture_release: overtureRelease ?? null,
        };
        matches.push(matched); continue;
      }
    }

    // Tier 4: proximity_fallback — nearest within 30 m
    if (closest && minDist <= PROXIMITY_FALLBACK_DIST) {
      matched = {
        campaign_id: campaignId, building_id: closest.id, address_id: addr.id,
        match_type: "proximity_fallback",
        confidence: Math.max(0, 1 - minDist / PROXIMITY_FALLBACK_DIST),
        distance_meters: minDist, street_match_score: null,
        building_area_sqm: closest.area_sqm, building_class: closest.building_type,
        building_height: closest.height, is_multi_unit: false, unit_count: 1,
        unit_arrangement: null, overture_release: overtureRelease ?? null,
      };
      matches.push(matched);
    }
  }

  const orphans = addresses.length - matches.length;
  console.log(`[StableLinkerService] Matched: ${matches.length}, Orphans: ${orphans}`);

  if (matches.length > 0) {
    await saveMatches(matches);
  }

  return { linked: matches.length, orphans };
}

/**
 * Batch upserts matches into building_address_links.
 * Unique constraint: (campaign_id, address_id). Re-provision overwrites stale links.
 */
export async function saveMatches(matches: BuildingMatch[]): Promise<void> {
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const BATCH = 500;

  for (let i = 0; i < matches.length; i += BATCH) {
    const batch = matches.slice(i, i + BATCH);
    const { error } = await supabase
      .from("building_address_links")
      .upsert(batch, { onConflict: "campaign_id,address_id" });

    if (error) {
      console.error(`[StableLinkerService] Upsert batch ${i} error:`, error);
      throw error;
    }
  }
}
