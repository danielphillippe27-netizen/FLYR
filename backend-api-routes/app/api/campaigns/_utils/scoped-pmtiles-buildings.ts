import { VectorTile } from '@mapbox/vector-tile';
import Pbf from 'pbf';
import * as turf from '@turf/turf';
import { getCachedPmtilesArchive } from '@/app/api/campaigns/_utils/tile-cache';
import {
  type CampaignSnapshotRow,
  resolveArtifactUrl,
  resolvePmtilesKey,
} from '@/lib/diamond/geometry';

export type ScopedBuildingFeatureCollection = {
  type: 'FeatureCollection';
  features: Array<GeoJSON.Feature<GeoJSON.Polygon | GeoJSON.MultiPolygon>>;
};

function envInt(name: string, fallback: number, min: number, max: number) {
  const raw = process.env[name];
  const parsed = raw ? Number.parseInt(raw, 10) : NaN;
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function finiteNumber(value: unknown, fallback: number) {
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function finiteNumberOrNull(value: unknown) {
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

const DEFAULT_RENDER_HEIGHT_METERS = 8;
const MIN_RENDER_HEIGHT_METERS = 4;
const MAX_RENDER_HEIGHT_METERS = 14;

function renderableBuildingHeight(properties: Record<string, unknown>) {
  const rawHeight =
    finiteNumberOrNull(properties.height_m) ??
    finiteNumberOrNull(properties.height) ??
    finiteNumberOrNull(properties.render_height);
  const normalized = rawHeight && rawHeight > 0 ? rawHeight : DEFAULT_RENDER_HEIGHT_METERS;
  return Math.min(
    Math.max(normalized, MIN_RENDER_HEIGHT_METERS),
    MAX_RENDER_HEIGHT_METERS
  );
}

function scopedMaxZoom(headerMaxZoom: number) {
  const configured = envInt('SCOPED_PMTILES_BUILDINGS_MAX_ZOOM', 17, 10, 18);
  return Math.min(headerMaxZoom, configured);
}

function scopedMaxTiles() {
  return envInt('SCOPED_PMTILES_BUILDINGS_MAX_TILES', 512, 1, 4096);
}

function scopedTileConcurrency() {
  return envInt('SCOPED_PMTILES_BUILDINGS_TILE_CONCURRENCY', 8, 1, 32);
}

function scopedTilePadding() {
  return envInt('SCOPED_PMTILES_BUILDINGS_TILE_PADDING', 1, 0, 2);
}

function lonLatToTile(lon: number, lat: number, z: number) {
  const n = 2 ** z;
  const x = Math.max(0, Math.min(n - 1, Math.floor(((lon + 180) / 360) * n)));
  const latRad = (lat * Math.PI) / 180;
  const y = Math.max(
    0,
    Math.min(n - 1, Math.floor(((1 - Math.log(Math.tan(latRad) + 1 / Math.cos(latRad)) / Math.PI) / 2) * n))
  );
  return { x, y };
}

type TileRange = {
  z: number;
  minX: number;
  maxX: number;
  minY: number;
  maxY: number;
  tileCount: number;
};

function tileRangesForBbox(
  bbox: [number, number, number, number],
  minZoom: number,
  maxZoom: number,
  maxTiles: number
) {
  const [minLon, minLat, maxLon, maxLat] = bbox;
  const minCandidateZoom = Math.max(0, Math.min(minZoom, maxZoom, 18));
  const ranges: TileRange[] = [];

  for (let z = Math.min(maxZoom, 18); z >= minCandidateZoom; z -= 1) {
    const nw = lonLatToTile(minLon, maxLat, z);
    const se = lonLatToTile(maxLon, minLat, z);
    const maxTile = (1 << z) - 1;
    const padding = scopedTilePadding();
    const minX = Math.max(0, Math.min(nw.x, se.x) - padding);
    const maxX = Math.min(maxTile, Math.max(nw.x, se.x) + padding);
    const minY = Math.max(0, Math.min(nw.y, se.y) - padding);
    const maxY = Math.min(maxTile, Math.max(nw.y, se.y) + padding);
    const tileCount = (maxX - minX + 1) * (maxY - minY + 1);
    if (tileCount <= maxTiles) {
      ranges.push({ z, minX, maxX, minY, maxY, tileCount });
    }
  }

  return ranges;
}

function tileCoords(range: TileRange) {
  const coords: Array<{ x: number; y: number }> = [];
  for (let x = range.minX; x <= range.maxX; x += 1) {
    for (let y = range.minY; y <= range.maxY; y += 1) {
      coords.push({ x, y });
    }
  }
  return coords;
}

async function mapWithConcurrency<T, R>(
  items: T[],
  concurrency: number,
  worker: (item: T) => Promise<R>
): Promise<R[]> {
  const results = new Array<R>(items.length);
  let nextIndex = 0;

  async function runWorker() {
    while (nextIndex < items.length) {
      const currentIndex = nextIndex;
      nextIndex += 1;
      results[currentIndex] = await worker(items[currentIndex]);
    }
  }

  const workers = Array.from({ length: Math.min(concurrency, items.length) }, runWorker);
  await Promise.all(workers);
  return results;
}

function flattenPositions(geometry: GeoJSON.Geometry | null | undefined): Array<[number, number]> {
  if (!geometry) return [];
  if (geometry.type === 'Point') return [geometry.coordinates as [number, number]];
  if (geometry.type === 'MultiPoint' || geometry.type === 'LineString') {
    return geometry.coordinates as Array<[number, number]>;
  }
  if (geometry.type === 'MultiLineString' || geometry.type === 'Polygon') {
    return geometry.coordinates.flat() as Array<[number, number]>;
  }
  if (geometry.type === 'MultiPolygon') {
    return geometry.coordinates.flat(2) as Array<[number, number]>;
  }
  return [];
}

function geometryCenter(geometry: GeoJSON.Geometry | null | undefined): [number, number] | null {
  const positions = flattenPositions(geometry).filter(
    (position) => Number.isFinite(position[0]) && Number.isFinite(position[1])
  );
  if (positions.length === 0) return null;
  let minLon = Infinity;
  let minLat = Infinity;
  let maxLon = -Infinity;
  let maxLat = -Infinity;
  for (const [lon, lat] of positions) {
    minLon = Math.min(minLon, lon);
    minLat = Math.min(minLat, lat);
    maxLon = Math.max(maxLon, lon);
    maxLat = Math.max(maxLat, lat);
  }
  return [(minLon + maxLon) / 2, (minLat + maxLat) / 2];
}

function geometryBbox(geometry: GeoJSON.Geometry | null | undefined): [number, number, number, number] | null {
  const positions = flattenPositions(geometry).filter(
    (position) => Number.isFinite(position[0]) && Number.isFinite(position[1])
  );
  if (positions.length === 0) return null;

  let minLon = Infinity;
  let minLat = Infinity;
  let maxLon = -Infinity;
  let maxLat = -Infinity;
  for (const [lon, lat] of positions) {
    minLon = Math.min(minLon, lon);
    minLat = Math.min(minLat, lat);
    maxLon = Math.max(maxLon, lon);
    maxLat = Math.max(maxLat, lat);
  }
  return [minLon, minLat, maxLon, maxLat];
}

function pointInBbox(point: [number, number], bbox: [number, number, number, number]) {
  const [lon, lat] = point;
  const [minLon, minLat, maxLon, maxLat] = bbox;
  return lon >= minLon && lon <= maxLon && lat >= minLat && lat <= maxLat;
}

function geometryIntersectsBbox(
  geometry: GeoJSON.Geometry | null | undefined,
  bbox: [number, number, number, number]
): boolean {
  const bounds = geometryBbox(geometry);
  if (!bounds) return false;
  const [featureMinLon, featureMinLat, featureMaxLon, featureMaxLat] = bounds;
  const [minLon, minLat, maxLon, maxLat] = bbox;
  if (
    featureMaxLon < minLon ||
    featureMinLon > maxLon ||
    featureMaxLat < minLat ||
    featureMinLat > maxLat
  ) {
    return false;
  }

  return true;
}

function pointOnSegment(
  point: [number, number],
  start: [number, number],
  end: [number, number]
): boolean {
  const [px, py] = point;
  const [x1, y1] = start;
  const [x2, y2] = end;
  const cross = (px - x1) * (y2 - y1) - (py - y1) * (x2 - x1);
  if (Math.abs(cross) > 1e-12) return false;

  return (
    px >= Math.min(x1, x2) - 1e-12 &&
    px <= Math.max(x1, x2) + 1e-12 &&
    py >= Math.min(y1, y2) - 1e-12 &&
    py <= Math.max(y1, y2) + 1e-12
  );
}

function pointInRing(point: [number, number], ring: number[][]): boolean {
  if (!Array.isArray(ring) || ring.length < 4) return false;
  const [x, y] = point;
  let inside = false;

  for (let i = 0, j = ring.length - 1; i < ring.length; j = i, i += 1) {
    const current = ring[i];
    const previous = ring[j];
    if (!Array.isArray(current) || !Array.isArray(previous)) continue;

    const xi = Number(current[0]);
    const yi = Number(current[1]);
    const xj = Number(previous[0]);
    const yj = Number(previous[1]);
    if (![xi, yi, xj, yj].every(Number.isFinite)) continue;

    if (pointOnSegment(point, [xi, yi], [xj, yj])) return true;
    const intersects = yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi;
    if (intersects) inside = !inside;
  }

  return inside;
}

function pointInPolygon(point: [number, number], polygon: GeoJSON.Polygon): boolean {
  const [outerRing, ...holes] = polygon.coordinates;
  if (!pointInRing(point, outerRing)) return false;
  return !holes.some((hole) => pointInRing(point, hole));
}

function featureInCampaignBoundary(feature: GeoJSON.Feature, boundary: GeoJSON.Polygon): boolean {
  const center = geometryCenter(feature.geometry);
  if (center && pointInPolygon(center, boundary)) return true;
  return flattenPositions(feature.geometry).some((position) => pointInPolygon(position, boundary));
}

function candidateLayerNames(vectorTile: VectorTile, preferredLayer: string) {
  const availableLayers = Object.keys(vectorTile.layers);
  const names: string[] = [];
  for (const candidate of [preferredLayer, 'buildings', 'building']) {
    if (candidate && vectorTile.layers[candidate] && !names.includes(candidate)) {
      names.push(candidate);
    }
  }
  for (const layerName of availableLayers) {
    if (!names.includes(layerName)) {
      names.push(layerName);
    }
  }
  return { names, availableLayers };
}

function geometryArea(feature: GeoJSON.Feature<GeoJSON.Polygon | GeoJSON.MultiPolygon>): number {
  try {
    return turf.area(feature);
  } catch {
    return 0;
  }
}

function stringIdentifier(value: unknown): string | null {
  if (typeof value === 'string') {
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
  }
  if (typeof value === 'number' && Number.isFinite(value)) {
    return String(value);
  }
  if (typeof value === 'bigint') {
    return value.toString();
  }
  return null;
}

function buildingIdentifier(
  properties: Record<string, unknown>,
  featureId?: unknown,
  vectorFeatureId?: unknown
): string | null {
  return (
    stringIdentifier(properties.building_id) ??
    stringIdentifier(properties.gers_id) ??
    stringIdentifier(properties.id) ??
    stringIdentifier(properties.id_str) ??
    stringIdentifier(properties.fid) ??
    stringIdentifier(properties.source_id) ??
    stringIdentifier(properties.external_id) ??
    stringIdentifier(properties.global_id) ??
    stringIdentifier(featureId) ??
    stringIdentifier(vectorFeatureId)
  );
}

function mergeBuildingFeatureFragments(
  existing: GeoJSON.Feature<GeoJSON.Polygon | GeoJSON.MultiPolygon>,
  next: GeoJSON.Feature<GeoJSON.Polygon | GeoJSON.MultiPolygon>
): GeoJSON.Feature<GeoJSON.Polygon | GeoJSON.MultiPolygon> {
  try {
    const unioned = turf.union(turf.featureCollection([existing, next]));
    if (
      unioned?.geometry &&
      (unioned.geometry.type === 'Polygon' || unioned.geometry.type === 'MultiPolygon')
    ) {
      return {
        ...existing,
        geometry: unioned.geometry,
        properties: {
          ...(existing.properties ?? {}),
          ...(next.properties ?? {}),
          tile_fragments_merged:
            finiteNumber(existing.properties?.tile_fragments_merged, 1) +
            finiteNumber(next.properties?.tile_fragments_merged, 1),
        },
      };
    }
  } catch (error) {
    console.warn(
      '[ScopedPMTilesBuildings] Fragment union failed; keeping largest tile fragment',
      error instanceof Error ? error.message : error
    );
  }

  return geometryArea(next) > geometryArea(existing) ? next : existing;
}

export async function fetchScopedPmtilesBuildingFeatures(
  snapshot: CampaignSnapshotRow,
  bbox: [number, number, number, number],
  hiddenBuildingIds: Set<string> = new Set(),
  boundary: GeoJSON.Polygon | null = null
): Promise<ScopedBuildingFeatureCollection | null> {
  const pmtilesKey = resolvePmtilesKey(snapshot);
  if (!pmtilesKey) return null;
  const sourceLayers = snapshot.tile_metrics?.source_layers;
  const sourceLayer =
    sourceLayers && typeof sourceLayers === 'object' && 'buildings' in sourceLayers
      ? String((sourceLayers as Record<string, unknown>).buildings || 'buildings')
      : 'buildings';

  const pmtilesUrl = await resolveArtifactUrl(snapshot, pmtilesKey);
  const archive = getCachedPmtilesArchive(pmtilesUrl);
  const header = await archive.getHeader();
  const ranges = tileRangesForBbox(
    bbox,
    Math.max(Number(header.minZoom ?? 0), 10),
    scopedMaxZoom(Number(header.maxZoom ?? 14)),
    scopedMaxTiles()
  );
  if (ranges.length === 0) return null;

  const startedAt = Date.now();
  const byBuildingId = new Map<string, GeoJSON.Feature<GeoJSON.Polygon | GeoJSON.MultiPolygon>>();
  let selectedRange: TileRange | null = null;
  let selectedTiles = 0;
  let selectedLayer = sourceLayer;
  const attemptedRanges: Array<{ z: number; tiles: number; decodedTiles: number; layers: string[]; features: number }> = [];

  for (const range of ranges) {
    const coords = tileCoords(range);
    const rangeLayerNames = new Set<string>();
    let decodedTiles = 0;
    const rangeFeatures = new Map<string, GeoJSON.Feature<GeoJSON.Polygon | GeoJSON.MultiPolygon>>();

    const tileFeatureBatches = await mapWithConcurrency(
      coords,
      scopedTileConcurrency(),
      async ({ x, y }) => {
        const tile = await archive.getZxy(range.z, x, y);
        if (!tile) return { features: [] as Array<GeoJSON.Feature<GeoJSON.Polygon | GeoJSON.MultiPolygon>>, layers: [] as string[] };

        const vectorTile = new VectorTile(new Pbf(Buffer.from(tile.data)));
        const { names, availableLayers } = candidateLayerNames(vectorTile, sourceLayer);
        if (availableLayers.length > 0) decodedTiles += 1;
        for (const layerName of availableLayers) rangeLayerNames.add(layerName);

        const features: Array<GeoJSON.Feature<GeoJSON.Polygon | GeoJSON.MultiPolygon>> = [];
        for (const layerName of names) {
          const layer = vectorTile.layers[layerName];
          if (!layer) continue;

          for (let index = 0; index < layer.length; index += 1) {
            const vectorFeature = layer.feature(index);
            const feature = vectorFeature.toGeoJSON(x, y, range.z) as GeoJSON.Feature;
            if (feature.geometry?.type !== 'Polygon' && feature.geometry?.type !== 'MultiPolygon') continue;

            const properties = (feature.properties ?? {}) as Record<string, unknown>;
            const rawHeight =
              finiteNumberOrNull(properties.height_m) ??
              finiteNumberOrNull(properties.height) ??
              null;
            const height = renderableBuildingHeight(properties);
            const minHeight = Math.max(
              Math.min(finiteNumber(properties.min_height, 0), height - 0.1),
              0
            );
            const buildingId = buildingIdentifier(properties, feature.id, vectorFeature.id);
            if (!buildingId) continue;
            const buildingIdKey = buildingId.toLowerCase();
            if (hiddenBuildingIds.has(buildingIdKey)) continue;

            if (!geometryIntersectsBbox(feature.geometry, bbox)) continue;
            if (boundary && !featureInCampaignBoundary(feature, boundary)) continue;

            selectedLayer = layerName;
            features.push({
              ...feature,
              id: buildingId,
              geometry: feature.geometry,
              properties: {
                ...properties,
                id: buildingId,
                building_id: buildingId,
                gers_id: buildingId,
                source_height_m: rawHeight,
                render_height: height,
                height,
                height_m: height,
                min_height: minHeight,
                source: properties.source ?? 'bedrock_pmtiles',
                feature_type: 'matched_house',
                feature_status: 'matched',
                status: 'not_visited',
                scans_total: 0,
                qr_scanned: false,
              },
            });
          }

          if (features.length > 0) break;
        }

        return { features, layers: availableLayers };
      }
    );

    for (const batch of tileFeatureBatches) {
      for (const layerName of batch.layers) rangeLayerNames.add(layerName);
      for (const feature of batch.features) {
        const properties = (feature.properties ?? {}) as Record<string, unknown>;
        const buildingId = buildingIdentifier(properties, feature.id);
        if (!buildingId) continue;
        const buildingIdKey = buildingId.toLowerCase();
        const existing = rangeFeatures.get(buildingIdKey);
        rangeFeatures.set(
          buildingIdKey,
          existing ? mergeBuildingFeatureFragments(existing, feature) : feature
        );
      }
    }

    attemptedRanges.push({
      z: range.z,
      tiles: coords.length,
      decodedTiles,
      layers: Array.from(rangeLayerNames).slice(0, 8),
      features: rangeFeatures.size,
    });

    if (rangeFeatures.size > 0) {
      for (const [buildingIdKey, feature] of rangeFeatures) {
        if (!byBuildingId.has(buildingIdKey)) {
          byBuildingId.set(buildingIdKey, feature);
        }
      }
      selectedRange = range;
      selectedTiles = coords.length;
      break;
    }
  }

  const features = Array.from(byBuildingId.values());
  console.log('[ScopedPMTilesBuildings] materialized campaign GeoJSON', {
    pmtilesKey,
    sourceLayer: selectedLayer,
    headerMinZoom: header.minZoom,
    headerMaxZoom: header.maxZoom,
    zoom: selectedRange?.z ?? null,
    tiles: selectedTiles,
    attemptedRanges,
    features: features.length,
    ms: Date.now() - startedAt,
  });
  if (features.length === 0) return null;
  return {
    type: 'FeatureCollection',
    features,
  };
}
