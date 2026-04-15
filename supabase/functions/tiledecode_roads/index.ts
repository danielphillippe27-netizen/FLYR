// supabase/functions/tiledecode_roads/index.ts
// Fetch Mapbox Vector Tiles for a campaign area, decode "road" layer, return LineString GeoJSON.
// Uses the drawn campaign polygon as the single source of truth: tile selection and road clipping
// are both derived from the polygon (no bbox). Includes all walkable road types.

import { VectorTile } from "https://esm.sh/@mapbox/vector-tile@1.3.1";
import Pbf from "https://esm.sh/pbf@3.2.1";
import * as turf from "https://esm.sh/@turf/turf@6.5.0";

type Payload = {
  zoom?: number;
  // Campaign polygon from drawn coordinates [[lon, lat], ...]. Required; bbox is derived from this.
  polygon: [number, number][];
};

const MAPBOX_TOKEN = Deno.env.get("MAPBOX_ACCESS_TOKEN")!;
const TILESET_ID = "mapbox.mapbox-streets-v8";
const ROAD_LAYER = "road";

// MVT feature type 2 = LineString
const LINESTRING_TYPE = 2;

// Road classes considered walkable / relevant to door-knocking routes.
// Excludes motorways and high-speed links that have no sidewalk access.
const EXCLUDED_CLASSES = new Set(["motorway", "motorway_link", "trunk", "trunk_link"]);

if (!MAPBOX_TOKEN) {
  throw new Error("Missing MAPBOX_ACCESS_TOKEN");
}

function tileURL(z: number, x: number, y: number, token: string): string {
  return `https://api.mapbox.com/v4/${TILESET_ID}/${z}/${x}/${y}.vector.pbf?access_token=${token}`;
}

function lngLatToTile(lon: number, lat: number, z: number): { x: number; y: number } {
  const x = Math.floor(((lon + 180) / 360) * Math.pow(2, z));
  const y = Math.floor(
    (1 - Math.log(Math.tan((lat * Math.PI) / 180) + 1 / Math.cos((lat * Math.PI) / 180)) / Math.PI) /
      2 *
      Math.pow(2, z),
  );
  return { x, y };
}

function bboxToTiles(
  minLat: number,
  minLon: number,
  maxLat: number,
  maxLon: number,
  z: number,
): { x: number; y: number }[] {
  const sw = lngLatToTile(minLon, minLat, z);
  const ne = lngLatToTile(maxLon, maxLat, z);
  const tiles: { x: number; y: number }[] = [];
  for (let x = sw.x; x <= ne.x; x++) {
    for (let y = ne.y; y <= sw.y; y++) {
      tiles.push({ x, y });
    }
  }
  return tiles;
}

/** Geographic bbox [minLon, minLat, maxLon, maxLat] for a tile at z,x,y (Web Mercator). */
function tileToBbox(z: number, x: number, y: number): [number, number, number, number] {
  const n = Math.pow(2, z);
  const minLon = (x / n) * 360 - 180;
  const maxLon = ((x + 1) / n) * 360 - 180;
  const maxLat = (180 / Math.PI) * Math.atan(Math.sinh(Math.PI * (1 - (2 * y) / n)));
  const minLat = (180 / Math.PI) * Math.atan(Math.sinh(Math.PI * (1 - (2 * (y + 1)) / n)));
  return [minLon, minLat, maxLon, maxLat];
}

type RoadFeatureOut = {
  type: "Feature";
  geometry: { type: "LineString"; coordinates: [number, number][] };
  properties: { id?: string; name?: string; class?: string };
};

function isFiniteCoordinate(value: unknown): value is [number, number] {
  return Array.isArray(value) &&
    value.length >= 2 &&
    typeof value[0] === "number" &&
    Number.isFinite(value[0]) &&
    typeof value[1] === "number" &&
    Number.isFinite(value[1]);
}

function sanitizeLineCoordinates(value: unknown): [number, number][] {
  if (!Array.isArray(value)) return [];
  const out: [number, number][] = [];
  for (const item of value) {
    if (!isFiniteCoordinate(item)) continue;
    const coord: [number, number] = [item[0], item[1]];
    const prev = out[out.length - 1];
    if (!prev || prev[0] !== coord[0] || prev[1] !== coord[1]) {
      out.push(coord);
    }
  }
  return out;
}

function sanitizePolygonRing(value: unknown): [number, number][] {
  const ring = sanitizeLineCoordinates(value);
  if (ring.length < 3) return [];

  const first = ring[0];
  const last = ring[ring.length - 1];
  if (first[0] !== last[0] || first[1] !== last[1]) {
    ring.push([first[0], first[1]]);
  }

  return ring.length >= 4 ? ring : [];
}

// Tile-seam merge: snap and tolerance so segment endpoints from different tiles match.
const ENDPOINT_DECIMALS = 6;
const ENDPOINT_TOLERANCE_DEG = 2e-5; // ~1.5–2 m at mid-latitudes

function roundCoord(c: [number, number]): [number, number] {
  const scale = Math.pow(10, ENDPOINT_DECIMALS);
  return [Math.round(c[0] * scale) / scale, Math.round(c[1] * scale) / scale];
}

/** Snap first and last point of a LineString so tile-split endpoints compare equal. */
function snapLineStringEndpoints(coords: [number, number][]): [number, number][] {
  if (coords.length === 0) return coords;
  const out = coords.map((c) => [c[0], c[1]] as [number, number]);
  out[0] = roundCoord(out[0]);
  if (out.length > 1) out[out.length - 1] = roundCoord(out[out.length - 1]);
  return out;
}

function endpointMatch(a: [number, number], b: [number, number]): boolean {
  return (
    Math.abs(a[0] - b[0]) <= ENDPOINT_TOLERANCE_DEG &&
    Math.abs(a[1] - b[1]) <= ENDPOINT_TOLERANCE_DEG
  );
}

/**
 * Merge tile-split segments into continuous LineStrings by grouping by road name+class
 * and chaining segments whose endpoints match (with optional reversal). Removes visible
 * seams and improves GPS normalization quality.
 */
function mergeConnectedSegments(features: RoadFeatureOut[]): RoadFeatureOut[] {
  if (features.length === 0) return [];

  // Snap endpoints on all segments so boundaries from different tiles compare equal.
  const snapped = features.map((f) => ({
    ...f,
    geometry: {
      type: "LineString" as const,
      coordinates: snapLineStringEndpoints(f.geometry.coordinates),
    },
  }));

  // Group by same road (name + class); use sentinel for missing so unnamed roads still merge by class.
  const groupKey = (f: RoadFeatureOut) =>
    `${f.properties?.name ?? "__"}\t${f.properties?.class ?? "__"}`;
  const groups = new Map<string, RoadFeatureOut[]>();
  for (const f of snapped) {
    const key = groupKey(f);
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key)!.push(f);
  }

  const merged: RoadFeatureOut[] = [];

  for (const [, segs] of groups) {
    const remaining = segs.map((s) => ({ ...s, coords: s.geometry.coordinates.slice() }));
    while (remaining.length > 0) {
      const first = remaining.pop()!;
      let coords = first.coords;
      let id = first.properties?.id;
      const name = first.properties?.name;
      const roadClass = first.properties?.class;

      // Extend backward and forward until no segment connects.
      let changed = true;
      while (changed) {
        changed = false;
        const head = coords[0];
        const tail = coords[coords.length - 1];

        for (let i = remaining.length - 1; i >= 0; i--) {
          const s = remaining[i];
          const sStart = s.coords[0];
          const sEnd = s.coords[s.coords.length - 1];

          // Append at tail: tail ≈ sStart -> append s[1..]; tail ≈ sEnd -> append reverse s[0..-1]
          if (endpointMatch(tail, sStart)) {
            coords = coords.concat(s.coords.slice(1));
            remaining.splice(i, 1);
            changed = true;
            break;
          }
          if (endpointMatch(tail, sEnd)) {
            coords = coords.concat(s.coords.slice(0, -1).reverse());
            remaining.splice(i, 1);
            changed = true;
            break;
          }
          // Prepend at head: head ≈ sEnd -> prepend s[0..-1]; head ≈ sStart -> prepend reverse s[1..]
          if (endpointMatch(head, sEnd)) {
            coords = s.coords.slice(0, -1).concat(coords);
            remaining.splice(i, 1);
            changed = true;
            break;
          }
          if (endpointMatch(head, sStart)) {
            coords = s.coords.slice(1).reverse().concat(coords);
            remaining.splice(i, 1);
            changed = true;
            break;
          }
        }
      }

      if (coords.length >= 2) {
        merged.push({
          type: "Feature",
          geometry: { type: "LineString", coordinates: coords },
          properties: { id, name, class: roadClass },
        });
      }
    }
  }

  return merged;
}

/** Optional: light Douglas-Peucker simplification after merge (tolerance in degrees, ~0.5–1 m). */
const SIMPLIFY_TOLERANCE_DEG = 1e-6;

function simplifyMergedFeatures(features: RoadFeatureOut[]): RoadFeatureOut[] {
  return features.map((f) => {
    try {
      const coords = sanitizeLineCoordinates(f.geometry.coordinates);
      if (coords.length < 2) return f;

      const line = turf.lineString(coords);
      const simplified = turf.simplify(line, { tolerance: SIMPLIFY_TOLERANCE_DEG, highQuality: true });
      const simplifiedCoords = sanitizeLineCoordinates(simplified.geometry.coordinates);

      // Keep original geometry if simplification collapses a very short segment.
      if (simplifiedCoords.length < 2) return f;
      return {
        ...f,
        geometry: { type: "LineString" as const, coordinates: simplifiedCoords },
      };
    } catch (error) {
      console.warn(`[ROADS] simplify skipped for feature ${f.properties?.id ?? "unknown"}: ${error}`);
      return f;
    }
  });
}

const TILE_FETCH_RETRIES = 3;
const TILE_FETCH_RETRY_DELAY_MS = 600;

async function getRoadsFromTile(
  z: number,
  x: number,
  y: number,
  token: string,
): Promise<RoadFeatureOut[]> {
  const url = tileURL(z, x, y, token);
  let r: Response | null = null;
  for (let attempt = 0; attempt < TILE_FETCH_RETRIES; attempt++) {
    r = await fetch(url, { headers: { Accept: "application/x-protobuf" } });
    if (r.ok) break;
    if ((r.status === 429 || r.status >= 500) && attempt < TILE_FETCH_RETRIES - 1) {
      console.log(`[MVT] ${r.status} for ${z}/${x}/${y}, retry ${attempt + 1}/${TILE_FETCH_RETRIES}`);
      await new Promise((resolve) => setTimeout(resolve, TILE_FETCH_RETRY_DELAY_MS));
      continue;
    }
    break;
  }
  if (!r || !r.ok) {
    console.log(`[MVT] ${r?.status ?? "error"} for ${z}/${x}/${y} (final)`);
    return [];
  }
  const buf = new Uint8Array(await r.arrayBuffer());
  const tile = new VectorTile(new Pbf(buf));
  const layer = tile.layers[ROAD_LAYER];
  if (!layer) return [];

  const features: RoadFeatureOut[] = [];
  for (let i = 0; i < layer.length; i++) {
    const feat = layer.feature(i);
    if (feat.type !== LINESTRING_TYPE) continue;

    const props = feat.properties || {};
    const roadClass: string = props.class ?? props.type ?? "";

    // Skip high-speed roads with no pedestrian access
    if (EXCLUDED_CLASSES.has(roadClass)) continue;

    const gj = feat.toGeoJSON(x, y, z) as {
      id?: string | number;
      properties?: Record<string, unknown>;
      geometry?: {
        type: string;
        coordinates: unknown;
      };
    };
    if (!gj.geometry) continue;

    const baseId = gj.id != null
      ? String(gj.id)
      : props.osm_id != null
      ? `osm-${props.osm_id}`
      : undefined;
    const baseName = props.name ?? gj.properties?.name;
    const baseClass = roadClass || "street";

    if (gj.geometry.type === "LineString") {
      const coords = sanitizeLineCoordinates(gj.geometry.coordinates);
      if (coords.length < 2) continue;
      features.push({
        type: "Feature",
        geometry: { type: "LineString", coordinates: coords },
        properties: {
          id: baseId,
          name: typeof baseName === "string" ? baseName : undefined,
          class: baseClass,
        },
      });
      continue;
    }

    if (gj.geometry.type === "MultiLineString") {
      const parts = gj.geometry.coordinates as unknown[];
      for (let partIndex = 0; partIndex < parts.length; partIndex++) {
        const part = sanitizeLineCoordinates(parts[partIndex]);
        if (part.length < 2) continue;
        features.push({
          type: "Feature",
          geometry: { type: "LineString", coordinates: part },
          properties: {
            id: baseId ? `${baseId}-mls-${partIndex}` : undefined,
            name: typeof baseName === "string" ? baseName : undefined,
            class: baseClass,
          },
        });
      }
    }
  }

  if (features.length > 0) {
    console.log(`[MVT] ${z}/${x}/${y} roads=${features.length}`);
  }
  return features;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }
  if (req.method !== "POST") {
    return new Response("Use POST", { status: 405 });
  }

  let body: Payload;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), { status: 400 });
  }

  if (!Array.isArray(body.polygon) || body.polygon.length < 3) {
    return new Response(
      JSON.stringify({ error: "Body must include polygon: [[lon, lat], ...] with at least 3 points (drawn campaign boundary)" }),
      { status: 400 },
    );
  }

  try {
    // Zoom 17 gives maximum road detail (service roads, inner loops, cul-de-sacs).
    const zoom = Math.min(17, Math.max(12, body.zoom ?? 16));

    // Build polygon from drawn coordinates; close ring if needed.
    const ring = sanitizePolygonRing(body.polygon);
    if (ring.length < 4) {
      return new Response(
        JSON.stringify({ error: "Polygon became invalid after sanitizing coordinates" }),
        { status: 400 },
      );
    }

    const rawPolygon = turf.polygon([ring]);
    let clipPolygon: turf.AllGeoJSON = rawPolygon;
    try {
      // Buffer 150 m so boundary and inner roads are included.
      clipPolygon = turf.buffer(rawPolygon, 0.15, { units: "kilometers" });
      console.log(`[ROADS] Polygon from drawn coordinates: ${ring.length} points, buffered 150 m`);
    } catch (error) {
      console.warn(`[ROADS] Buffer failed, using raw polygon: ${error}`);
    }

    // Derive bbox from the buffered polygon (no separate bbox param).
    const [minLon, minLat, maxLon, maxLat] = turf.bbox(clipPolygon);
    const latSpan = maxLat - minLat;
    const lonSpan = maxLon - minLon;
    const pad = 0.005;
    const paddedMinLat = minLat - latSpan * pad;
    const paddedMaxLat = maxLat + latSpan * pad;
    const paddedMinLon = minLon - lonSpan * pad;
    const paddedMaxLon = maxLon + lonSpan * pad;

    const candidateTiles = bboxToTiles(paddedMinLat, paddedMinLon, paddedMaxLat, paddedMaxLon, zoom);
    // Only fetch tiles that actually intersect the polygon (use polygon, not just bbox).
    const tileBboxPolygon = (x: number, y: number) =>
      turf.bboxPolygon(tileToBbox(zoom, x, y)) as turf.helpers.Feature<turf.helpers.Polygon>;
    const tiles = candidateTiles.filter(({ x, y }) => {
      try {
        return turf.booleanIntersects(tileBboxPolygon(x, y), clipPolygon);
      } catch {
        return true;
      }
    });
    console.log(`[ROADS] zoom=${zoom} tiles=${tiles.length} (polygon-intersecting, from drawn boundary)`);

    const allFeatures: RoadFeatureOut[] = [];
    const seen = new Set<string>();

    for (const { x, y } of tiles) {
      const tileFeatures = await getRoadsFromTile(zoom, x, y, MAPBOX_TOKEN);
      for (const f of tileFeatures) {
        // Deduplicate by geometry
        const coords = sanitizeLineCoordinates(f.geometry.coordinates);
        if (coords.length < 2) continue;
        const key = JSON.stringify(coords);
        if (seen.has(key)) continue;
        seen.add(key);

        // Clip to polygon (drawn campaign boundary)
        try {
          const line = turf.lineString(coords);
          if (!turf.booleanIntersects(line, clipPolygon)) continue;
        } catch (error) {
          console.warn(`[ROADS] Clip test skipped for feature ${f.properties?.id ?? "unknown"}: ${error}`);
        }

        allFeatures.push({
          ...f,
          geometry: { type: "LineString", coordinates: coords },
        });
      }
    }

    console.log(`[ROADS] total after clip=${allFeatures.length}`);

    // Merge tile-split segments into continuous LineStrings (removes seams, improves normalization).
    const mergedFeatures = mergeConnectedSegments(allFeatures);
    console.log(`[ROADS] after merge=${mergedFeatures.length}`);
    const simplifiedFeatures = simplifyMergedFeatures(mergedFeatures);

    return new Response(
      JSON.stringify({ features: simplifiedFeatures }),
      {
        headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
        status: 200,
      },
    );
  } catch (error) {
    console.error("[ROADS] Unhandled error:", error);
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : String(error) }),
      {
        headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
        status: 500,
      },
    );
  }
});
