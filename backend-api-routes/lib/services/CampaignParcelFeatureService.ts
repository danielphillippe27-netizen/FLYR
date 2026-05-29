import type { SupabaseClient } from '@supabase/supabase-js';
import { VectorTile } from '@mapbox/vector-tile';
import Pbf from 'pbf';
import {
  getCachedCampaignSnapshot,
  getCachedPmtilesArchive,
} from '@/app/api/campaigns/_utils/tile-cache';
import {
  type CampaignSnapshotRow,
  type ParcelPmtilesResolution,
  resolveArtifactUrl,
  resolvePmtilesKey,
} from '@/lib/diamond/geometry';
import {
  polygonalGeometry,
  reconstructParcelFragments,
} from '@/lib/geo/parcelFragments';
import { isResidentialParcelFeature } from '@/lib/geo/parcelFilters';
import { ParcelEnrichmentService } from '@/lib/services/ParcelEnrichmentService';

const PARCEL_SEAM_SAFE_MAX_ZOOM = 13;
const PARCEL_FAILURE_CACHE_TTL_MS = 5 * 60 * 1000;
const parcelFailureCache = new Map<string, number>();

export type CampaignParcelResponse = {
  id: string;
  campaign_id: string;
  external_id: string;
  geom: string;
  properties: Record<string, unknown>;
  created_at: string;
};

type CampaignScopeRow = {
  bbox: unknown;
  territory_boundary: GeoJSON.Polygon | string | null;
};

type CampaignAddressPoint = {
  id: string;
  lat: number;
  lon: number;
};

type ParcelAddressLinkRow = {
  parcel_id: string;
  address_id: string;
  match_type: string | null;
  link_source: string | null;
  confidence: number | null;
};

type ParcelAddressAnnotation = {
  parcelKey: string;
  parcelId?: string;
  addressId: string;
  matchType?: string | null;
  linkSource?: string | null;
  confidence?: number | null;
};

type PersistedParcelFeatureCollection = {
  features?: Array<{
    id?: string | number | null;
    geometry?: GeoJSON.Polygon | GeoJSON.MultiPolygon | null;
    properties?: Record<string, unknown> | null;
  }>;
};

type AddressFeatureCollection = {
  features?: Array<{
    id?: string | number | null;
    geometry?: GeoJSON.Point | null;
    properties?: Record<string, unknown> | null;
  }>;
};

export type CampaignParcelFeatureCollection = {
  type: 'FeatureCollection';
  features: GeoJSON.Feature[];
};

export type CampaignParcelResolutionSource = 'campaign_parcels' | 'snapshot_pmtiles' | 'empty';
export type CampaignParcelSuppressedReason = 'cached-failure' | 'access-denied' | 'not-found';

export type CampaignParcelResolution = {
  features: CampaignParcelResponse[];
  featureCollection: CampaignParcelFeatureCollection;
  source: CampaignParcelResolutionSource;
  suppressedReason?: CampaignParcelSuppressedReason;
};

export class CampaignParcelNotFoundError extends Error {
  constructor(campaignId: string) {
    super(`Campaign not found: ${campaignId}`);
    this.name = 'CampaignParcelNotFoundError';
  }
}

function emptyResolution(
  source: CampaignParcelResolutionSource = 'empty',
  suppressedReason?: CampaignParcelSuppressedReason
): CampaignParcelResolution {
  return {
    features: [],
    featureCollection: { type: 'FeatureCollection', features: [] },
    source,
    suppressedReason,
  };
}

function getParcelFailureCacheKey(campaignId: string, pmtilesKey: string) {
  return `${campaignId}:${pmtilesKey}`;
}

function hasCachedParcelFailure(cacheKey: string) {
  const expiresAt = parcelFailureCache.get(cacheKey);
  if (!expiresAt) return false;
  if (expiresAt <= Date.now()) {
    parcelFailureCache.delete(cacheKey);
    return false;
  }
  return true;
}

function cacheParcelFailure(cacheKey: string) {
  parcelFailureCache.set(cacheKey, Date.now() + PARCEL_FAILURE_CACHE_TTL_MS);
}

function stringMetric(metrics: Record<string, unknown> | null | undefined, key: string): string | null {
  const value = metrics?.[key];
  return typeof value === 'string' && value.trim().length > 0 ? value.trim() : null;
}

function numberMetric(metrics: Record<string, unknown> | null | undefined, key: string): number | null {
  const value = metrics?.[key];
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

function parcelTilesFromSnapshot(snapshot: CampaignSnapshotRow | null): ParcelPmtilesResolution | null {
  const pmtilesKey = stringMetric(snapshot?.tile_metrics, 'parcels_pmtiles_key');
  if (!snapshot) return null;

  if (!pmtilesKey) {
    const buildingPmtilesKey = resolvePmtilesKey(snapshot);
    const bedrockCountryCode = stringMetric(snapshot.tile_metrics, 'bedrock_country_code');
    const isBedrockCountrySnapshot =
      snapshot.tile_metrics?.bedrock_mode === true &&
      bedrockCountryCode !== 'US' &&
      buildingPmtilesKey?.endsWith('/buildings/buildings.pmtiles');

    if (!isBedrockCountrySnapshot || !buildingPmtilesKey) return null;

    const derivedPmtilesKey = buildingPmtilesKey.replace(/\/buildings\/buildings\.pmtiles$/i, '/parcels/parcels.pmtiles');
    return {
      bucket: snapshot.bucket,
      pmtilesKey: derivedPmtilesKey,
      tilejsonKey: derivedPmtilesKey.replace(/\.pmtiles$/i, '.json'),
      datePart: 'snapshot',
      sourceLayer: 'parcels',
      promoteId: 'parcel_id',
      minzoom: numberMetric(snapshot.tile_metrics, 'parcel_minzoom') ?? 10,
      maxzoom: numberMetric(snapshot.tile_metrics, 'parcel_maxzoom') ?? 16,
    };
  }

  return {
    bucket: snapshot.bucket,
    pmtilesKey,
    tilejsonKey:
      stringMetric(snapshot.tile_metrics, 'parcels_tilejson_key') ??
      pmtilesKey.replace(/\.pmtiles$/i, '.json'),
    datePart: 'snapshot',
    sourceLayer: 'parcels',
    promoteId: 'parcel_id',
    minzoom: numberMetric(snapshot.tile_metrics, 'parcel_minzoom') ?? 10,
    maxzoom: numberMetric(snapshot.tile_metrics, 'parcel_maxzoom') ?? 16,
  };
}

async function fetchPersistedCampaignParcels(
  supabase: SupabaseClient,
  campaignId: string
): Promise<CampaignParcelResponse[]> {
  const { data, error } = await supabase.rpc('rpc_get_campaign_parcels', {
    p_campaign_id: campaignId,
  });

  if (error) {
    console.warn('[CampaignParcels] Failed to read persisted campaign parcels:', {
      campaignId,
      code: error.code,
      message: error.message,
    });
    return [];
  }

  const featureCollection = data as PersistedParcelFeatureCollection | null;
  const features = Array.isArray(featureCollection?.features) ? featureCollection.features : [];
  const now = new Date().toISOString();

  return features
    .filter((feature) => feature.geometry?.type === 'Polygon' || feature.geometry?.type === 'MultiPolygon')
    .map((feature) => {
      const properties = feature.properties ?? {};
      const id = String(feature.id ?? properties.id ?? properties.parcel_id ?? properties.external_id ?? '');
      const externalId = String(properties.external_id ?? properties.parcel_id ?? id);

      return {
        id,
        campaign_id: campaignId,
        external_id: externalId,
        geom: JSON.stringify(feature.geometry),
        properties,
        created_at: now,
      };
    })
    .filter((parcel) => parcel.id.length > 0 && parcel.external_id.length > 0);
}

async function fetchPreparedCampaignParcels(
  supabase: SupabaseClient,
  campaignId: string
): Promise<CampaignParcelResponse[]> {
  try {
    const result = await new ParcelEnrichmentService(supabase).prepareParcelsForProvision(campaignId);
    if (result.status !== 'ready' || result.parcelCount === 0) {
      if (result.status !== 'skipped') {
        console.warn('[CampaignParcels] On-demand parcel enrichment returned no parcels:', {
          campaignId,
          status: result.status,
          parcelCount: result.parcelCount,
          error: result.error,
        });
      }
      return [];
    }

    return fetchPersistedCampaignParcels(supabase, campaignId);
  } catch (error) {
    console.warn('[CampaignParcels] On-demand parcel enrichment failed; falling back to snapshot parcels:', {
      campaignId,
      error: error instanceof Error ? error.message : String(error),
    });
    return [];
  }
}

async function fetchPersistedParcelAddressLinks(
  supabase: SupabaseClient,
  campaignId: string
): Promise<ParcelAddressLinkRow[]> {
  const { data, error } = await supabase
    .from('parcel_address_links')
    .select('parcel_id, address_id, match_type, link_source, confidence')
    .eq('campaign_id', campaignId);

  if (error) {
    const message = error.message ?? '';
    const isMissing =
      error.code === '42P01' ||
      error.code === 'PGRST205' ||
      (message.includes('parcel_address_links') &&
        (message.includes('does not exist') || message.includes('schema cache')));
    if (!isMissing) {
      console.warn('[CampaignParcels] Failed to read parcel-address links:', {
        campaignId,
        code: error.code,
        message: error.message,
      });
    }
    return [];
  }

  return (data ?? []) as ParcelAddressLinkRow[];
}

function validCampaignAddressPoint(address: CampaignAddressPoint): boolean {
  return (
    address.id.length > 0 &&
    Number.isFinite(address.lat) &&
    Number.isFinite(address.lon) &&
    Math.abs(address.lat) <= 90 &&
    Math.abs(address.lon) <= 180
  );
}

function campaignAddressPointsFromRows(rows: unknown[] | null): CampaignAddressPoint[] {
  return (rows ?? [])
    .map((row) => ({
      id: String((row as { id?: unknown }).id ?? ''),
      lat: Number((row as { lat?: unknown }).lat),
      lon: Number((row as { lon?: unknown }).lon),
    }))
    .filter(validCampaignAddressPoint);
}

function campaignAddressPointsFromFeatureCollection(data: unknown): CampaignAddressPoint[] {
  const featureCollection = data as AddressFeatureCollection | null;
  const features = Array.isArray(featureCollection?.features) ? featureCollection.features : [];
  return features
    .map((feature) => {
      const coordinates = feature.geometry?.coordinates;
      const id = String(feature.properties?.id ?? feature.id ?? '');
      return {
        id,
        lon: Number(coordinates?.[0]),
        lat: Number(coordinates?.[1]),
      };
    })
    .filter(validCampaignAddressPoint);
}

async function fetchCampaignAddressPoints(
  supabase: SupabaseClient,
  campaignId: string
): Promise<CampaignAddressPoint[]> {
  const { data: addressRows } = await supabase
    .from('campaign_addresses')
    .select('id, lat, lon')
    .eq('campaign_id', campaignId);
  const rowPoints = campaignAddressPointsFromRows(addressRows ?? []);
  if (rowPoints.length > 0) return rowPoints;

  const { data, error } = await supabase.rpc('rpc_get_campaign_addresses', {
    p_campaign_id: campaignId,
  });
  if (error) {
    console.warn('[CampaignParcels] Failed to read address points for parcel annotations:', {
      campaignId,
      code: error.code,
      message: error.message,
    });
    return [];
  }

  return campaignAddressPointsFromFeatureCollection(data);
}

function normalizedParcelIdentifier(value: unknown): string | null {
  if (typeof value !== 'string' && typeof value !== 'number') return null;
  const normalized = String(value).trim();
  return normalized.length > 0 ? normalized : null;
}

function parcelIdentityKeys(parcel: CampaignParcelResponse): string[] {
  const properties = parcel.properties ?? {};
  const candidates = [
    parcel.external_id,
    properties.external_id,
    properties.parcel_id,
    properties.parcel_link_id,
    parcel.id,
    properties.id,
  ];
  return Array.from(
    new Set(
      candidates
        .map(normalizedParcelIdentifier)
        .filter((value): value is string => Boolean(value))
    )
  );
}

function canonicalParcelKey(parcel: CampaignParcelResponse): string {
  return parcelIdentityKeys(parcel)[0] ?? parcel.external_id ?? parcel.id;
}

function parcelLookupByIdentity(parcels: CampaignParcelResponse[]): Map<string, CampaignParcelResponse> {
  const lookup = new Map<string, CampaignParcelResponse>();
  for (const parcel of parcels) {
    for (const key of parcelIdentityKeys(parcel)) {
      lookup.set(key, parcel);
    }
  }
  return lookup;
}

function uniqueStrings(values: Array<string | null | undefined>): string[] {
  return Array.from(
    new Set(
      values
        .map((value) => value?.trim())
        .filter((value): value is string => Boolean(value))
    )
  );
}

function parcelAnnotationsFromEvidence(
  parcels: CampaignParcelResponse[],
  links: ParcelAddressLinkRow[]
): ParcelAddressAnnotation[] {
  if (parcels.length === 0 || links.length === 0) return [];

  const parcelsById = parcelLookupByIdentity(parcels);
  return links.flatMap((link) => {
    const parcel = parcelsById.get(link.parcel_id);
    if (!parcel) return [];

    return [{
      parcelKey: canonicalParcelKey(parcel),
      parcelId: link.parcel_id,
      addressId: link.address_id,
      matchType: link.match_type ?? 'centroid_in_parcel',
      linkSource: link.link_source ?? 'auto',
      confidence: link.confidence,
    }];
  });
}

function parseBbox(value: unknown): [number, number, number, number] | null {
  if (!Array.isArray(value) || value.length !== 4) return null;
  const bbox = value.map((entry) => Number(entry));
  if (!bbox.every((entry) => Number.isFinite(entry))) return null;
  return bbox as [number, number, number, number];
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

function bboxFromPositions(positions: Array<[number, number]>): [number, number, number, number] | null {
  const validPositions = positions.filter(
    (position) => Number.isFinite(position[0]) && Number.isFinite(position[1])
  );
  if (validPositions.length === 0) return null;

  let minLon = Infinity;
  let minLat = Infinity;
  let maxLon = -Infinity;
  let maxLat = -Infinity;
  for (const [lon, lat] of validPositions) {
    minLon = Math.min(minLon, lon);
    minLat = Math.min(minLat, lat);
    maxLon = Math.max(maxLon, lon);
    maxLat = Math.max(maxLat, lat);
  }

  return [minLon, minLat, maxLon, maxLat];
}

function normalizeGeoJsonPolygon(value: GeoJSON.Polygon | string | null | undefined): GeoJSON.Polygon | null {
  if (!value) return null;
  if (typeof value === 'string') {
    try {
      return normalizeGeoJsonPolygon(JSON.parse(value) as GeoJSON.Polygon);
    } catch {
      return null;
    }
  }
  return value.type === 'Polygon' && Array.isArray(value.coordinates) ? value : null;
}

function geometryIntersectsBbox(
  geometry: GeoJSON.Geometry | null | undefined,
  bbox: [number, number, number, number]
): boolean {
  const geometryBbox = bboxFromPositions(flattenPositions(geometry));
  if (!geometryBbox) return false;

  return !(
    geometryBbox[2] < bbox[0] ||
    geometryBbox[0] > bbox[2] ||
    geometryBbox[3] < bbox[1] ||
    geometryBbox[1] > bbox[3]
  );
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

function geometryPolygons(geometry: GeoJSON.Geometry | null | undefined): GeoJSON.Polygon[] {
  if (!geometry) return [];
  if (geometry.type === 'Polygon') return [geometry];
  if (geometry.type === 'MultiPolygon') {
    return geometry.coordinates.map((coordinates) => ({
      type: 'Polygon',
      coordinates,
    }));
  }
  return [];
}

function bboxArea(geometry: GeoJSON.Geometry | null | undefined): number {
  const bbox = bboxFromPositions(flattenPositions(geometry));
  if (!bbox) return Number.POSITIVE_INFINITY;
  return Math.abs((bbox[2] - bbox[0]) * (bbox[3] - bbox[1]));
}

function inferParcelAddressAnnotations(
  parcels: CampaignParcelResponse[],
  addresses: CampaignAddressPoint[]
): ParcelAddressAnnotation[] {
  if (parcels.length === 0 || addresses.length === 0) return [];

  const parsedParcels = parcels
    .map((parcel) => {
      try {
        const geometry = JSON.parse(parcel.geom) as GeoJSON.Geometry;
        return { parcel, geometry, area: bboxArea(geometry) };
      } catch {
        return null;
      }
    })
    .filter((entry): entry is { parcel: CampaignParcelResponse; geometry: GeoJSON.Geometry; area: number } =>
      Boolean(entry)
    );

  const annotations: ParcelAddressAnnotation[] = [];
  for (const address of addresses) {
    const match = parsedParcels
      .filter((entry) =>
        geometryPolygons(entry.geometry).some((polygon) => pointInPolygon([address.lon, address.lat], polygon))
      )
      .sort((a, b) => a.area - b.area)[0];

    if (!match) continue;
    annotations.push({
      parcelKey: canonicalParcelKey(match.parcel),
      parcelId: match.parcel.external_id,
      addressId: address.id,
      matchType: 'centroid_in_parcel',
      linkSource: 'inferred',
    });
  }

  return annotations;
}

function annotateParcelsWithAddressLinks(
  parcels: CampaignParcelResponse[],
  annotations: ParcelAddressAnnotation[]
): CampaignParcelResponse[] {
  if (parcels.length === 0 || annotations.length === 0) return parcels;

  const annotationsByParcel = new Map<string, ParcelAddressAnnotation[]>();
  for (const annotation of annotations) {
    const addressId = annotation.addressId.trim();
    if (!annotation.parcelKey || !addressId) continue;
    const existing = annotationsByParcel.get(annotation.parcelKey) ?? [];
    existing.push({ ...annotation, addressId });
    annotationsByParcel.set(annotation.parcelKey, existing);
  }

  return parcels.map((parcel) => {
    const parcelAnnotations = annotationsByParcel.get(canonicalParcelKey(parcel));
    if (!parcelAnnotations || parcelAnnotations.length === 0) return parcel;

    const addressIds = uniqueStrings(parcelAnnotations.map((annotation) => annotation.addressId));
    if (addressIds.length === 0) return parcel;

    const parcelLinkIds = uniqueStrings(parcelAnnotations.map((annotation) => annotation.parcelId));
    const first = parcelAnnotations[0];
    return {
      ...parcel,
      properties: {
        ...parcel.properties,
        address_id: addressIds[0],
        address_ids: addressIds,
        parcel_address_count: addressIds.length,
        ...(parcelLinkIds.length > 0 ? { parcel_link_ids: parcelLinkIds } : {}),
        parcel_match_type: first.matchType ?? 'centroid_in_parcel',
        parcel_link_source: first.linkSource ?? 'auto',
        ...(first.confidence != null ? { parcel_confidence: first.confidence } : {}),
      },
    };
  });
}

function validRingPositions(ring: number[][] | undefined): Array<[number, number]> {
  if (!Array.isArray(ring)) return [];
  return ring
    .map((position) => [Number(position?.[0]), Number(position?.[1])] as [number, number])
    .filter((position) => Number.isFinite(position[0]) && Number.isFinite(position[1]));
}

function orientation(a: [number, number], b: [number, number], c: [number, number]): number {
  const value = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);
  if (Math.abs(value) < 1e-12) return 0;
  return value > 0 ? 1 : 2;
}

function segmentsIntersect(
  a: [number, number],
  b: [number, number],
  c: [number, number],
  d: [number, number]
): boolean {
  const o1 = orientation(a, b, c);
  const o2 = orientation(a, b, d);
  const o3 = orientation(c, d, a);
  const o4 = orientation(c, d, b);

  if (o1 === 0 && pointOnSegment(c, a, b)) return true;
  if (o2 === 0 && pointOnSegment(d, a, b)) return true;
  if (o3 === 0 && pointOnSegment(a, c, d)) return true;
  if (o4 === 0 && pointOnSegment(b, c, d)) return true;

  return o1 !== o2 && o3 !== o4;
}

function ringsHaveIntersectingSegments(
  firstRing: number[][] | undefined,
  secondRing: number[][] | undefined
): boolean {
  const first = validRingPositions(firstRing);
  const second = validRingPositions(secondRing);
  if (first.length < 2 || second.length < 2) return false;

  for (let firstIndex = 0; firstIndex < first.length; firstIndex += 1) {
    const firstStart = first[firstIndex];
    const firstEnd = first[(firstIndex + 1) % first.length];

    for (let secondIndex = 0; secondIndex < second.length; secondIndex += 1) {
      const secondStart = second[secondIndex];
      const secondEnd = second[(secondIndex + 1) % second.length];

      if (segmentsIntersect(firstStart, firstEnd, secondStart, secondEnd)) {
        return true;
      }
    }
  }

  return false;
}

function polygonIntersectsPolygon(featurePolygon: GeoJSON.Polygon, boundary: GeoJSON.Polygon): boolean {
  const featureOuterRing = featurePolygon.coordinates[0];
  const boundaryOuterRing = boundary.coordinates[0];

  if (validRingPositions(featureOuterRing).some((position) => pointInPolygon(position, boundary))) {
    return true;
  }

  if (validRingPositions(boundaryOuterRing).some((position) => pointInPolygon(position, featurePolygon))) {
    return true;
  }

  return ringsHaveIntersectingSegments(featureOuterRing, boundaryOuterRing);
}

function geometryIntersectsPolygon(
  geometry: GeoJSON.Geometry | null | undefined,
  boundary: GeoJSON.Polygon
): boolean {
  return geometryPolygons(geometry).some((polygon) => polygonIntersectsPolygon(polygon, boundary));
}

function lonLatToTile(lon: number, lat: number, z: number) {
  const n = 2 ** z;
  const x = Math.floor(((lon + 180) / 360) * n);
  const latRad = (lat * Math.PI) / 180;
  const y = Math.floor(((1 - Math.log(Math.tan(latRad) + 1 / Math.cos(latRad)) / Math.PI) / 2) * n);
  return {
    x: Math.max(0, Math.min(n - 1, x)),
    y: Math.max(0, Math.min(n - 1, y)),
  };
}

function tileRangesForBbox(bbox: [number, number, number, number], maxZoom: number, padding = 1) {
  const [minLon, minLat, maxLon, maxLat] = bbox;
  for (let z = Math.min(maxZoom, PARCEL_SEAM_SAFE_MAX_ZOOM); z >= 10; z -= 1) {
    const nw = lonLatToTile(minLon, maxLat, z);
    const se = lonLatToTile(maxLon, minLat, z);
    const maxTile = 2 ** z - 1;
    const minX = Math.max(0, Math.min(nw.x, se.x) - padding);
    const maxX = Math.min(maxTile, Math.max(nw.x, se.x) + padding);
    const minY = Math.max(0, Math.min(nw.y, se.y) - padding);
    const maxY = Math.min(maxTile, Math.max(nw.y, se.y) + padding);
    const tileCount = (maxX - minX + 1) * (maxY - minY + 1);
    if (tileCount <= 96 || z === 10) {
      return { z, minX, maxX, minY, maxY };
    }
  }
  return null;
}

function getFeatureExternalId(feature: GeoJSON.Feature): string | null {
  const properties = (feature.properties ?? {}) as Record<string, unknown>;
  const candidates = [
    properties.parcel_id,
    properties.external_id,
    properties.PARCELID,
    properties.gisid,
    properties.roll_number,
    properties.id,
    feature.id,
  ];

  for (const candidate of candidates) {
    if (typeof candidate === 'string' || typeof candidate === 'number') {
      const normalized = String(candidate).trim();
      if (normalized) return normalized;
    }
  }

  return null;
}

function parcelResponseToFeature(parcel: CampaignParcelResponse): GeoJSON.Feature | null {
  try {
    const geometry = JSON.parse(parcel.geom) as GeoJSON.Geometry;
    if (geometry.type !== 'Polygon' && geometry.type !== 'MultiPolygon') return null;
    return {
      type: 'Feature',
      id: parcel.id,
      geometry,
      properties: parcel.properties,
    };
  } catch {
    return null;
  }
}

function filterResidentialParcelResponses(parcels: CampaignParcelResponse[]): CampaignParcelResponse[] {
  return parcels.filter((parcel) => {
    const feature = parcelResponseToFeature(parcel);
    return feature ? isResidentialParcelFeature(feature) : false;
  });
}

function filterCampaignScopedParcelResponses(
  parcels: CampaignParcelResponse[],
  bbox: [number, number, number, number],
  boundary: GeoJSON.Polygon | null
): CampaignParcelResponse[] {
  return parcels.filter((parcel) => {
    const feature = parcelResponseToFeature(parcel);
    return feature ? featureWithinCampaignScope(feature, bbox, boundary) : false;
  });
}

function featureWithinCampaignScope(
  feature: GeoJSON.Feature,
  bbox: [number, number, number, number],
  boundary: GeoJSON.Polygon | null
): boolean {
  if (!geometryIntersectsBbox(feature.geometry, bbox)) return false;
  if (!boundary) return true;

  return geometryIntersectsPolygon(feature.geometry, boundary);
}

async function fetchScopedPmtilesParcels(
  campaignId: string,
  snapshot: CampaignSnapshotRow,
  parcelTiles: ParcelPmtilesResolution,
  bbox: [number, number, number, number],
  boundary: GeoJSON.Polygon | null
): Promise<CampaignParcelResponse[]> {
  const pmtilesUrl = await resolveArtifactUrl(snapshot, parcelTiles.pmtilesKey);
  const archive = getCachedPmtilesArchive(pmtilesUrl);
  const header = await archive.getHeader();
  const range = tileRangesForBbox(bbox, Math.min(header.maxZoom, parcelTiles.maxzoom));
  if (!range) return [];

  const now = new Date().toISOString();
  const fragments: Array<{
    id: string;
    geometry: GeoJSON.Polygon | GeoJSON.MultiPolygon;
    properties: Record<string, unknown>;
    include: boolean;
  }> = [];

  for (let x = range.minX; x <= range.maxX; x += 1) {
    for (let y = range.minY; y <= range.maxY; y += 1) {
      const tile = await archive.getZxy(range.z, x, y);
      if (!tile) continue;

      const vectorTile = new VectorTile(new Pbf(Buffer.from(tile.data)));
      const layer = vectorTile.layers[parcelTiles.sourceLayer];
      if (!layer) continue;

      for (let index = 0; index < layer.length; index += 1) {
        const vectorFeature = layer.feature(index);
        const feature = vectorFeature.toGeoJSON(x, y, range.z) as GeoJSON.Feature;
        const geometry = polygonalGeometry(feature.geometry);
        if (!geometry) continue;
        if (!isResidentialParcelFeature(feature)) continue;

        const externalId = getFeatureExternalId(feature);
        if (!externalId) continue;

        fragments.push({
          id: externalId,
          geometry,
          properties: {
            ...((feature.properties ?? {}) as Record<string, unknown>),
            parcel_id: externalId,
            source: 'bedrock_pmtiles',
          },
          include: featureWithinCampaignScope({ ...feature, geometry }, bbox, boundary),
        });
      }
    }
  }

  return reconstructParcelFragments(fragments).map((feature) => {
    const externalId = String(feature.id ?? feature.properties?.parcel_id ?? '');
    return {
      id: externalId,
      campaign_id: campaignId,
      external_id: externalId,
      geom: JSON.stringify(feature.geometry),
      properties: feature.properties ?? {},
      created_at: now,
    };
  }).filter((parcel) => parcel.id.length > 0 && parcel.external_id.length > 0);
}

function parcelResponsesToFeatureCollection(parcels: CampaignParcelResponse[]): CampaignParcelFeatureCollection {
  return {
    type: 'FeatureCollection',
    features: parcels.flatMap((parcel) => {
      const feature = parcelResponseToFeature(parcel);
      return feature ? [feature] : [];
    }),
  };
}

function responseFromParcels(
  features: CampaignParcelResponse[],
  source: CampaignParcelResolutionSource,
  suppressedReason?: CampaignParcelSuppressedReason
): CampaignParcelResolution {
  return {
    features,
    featureCollection: parcelResponsesToFeatureCollection(features),
    source,
    suppressedReason,
  };
}

export async function resolveCampaignParcels(
  supabase: SupabaseClient,
  campaignId: string
): Promise<CampaignParcelResolution> {
  const [{ data: campaign, error: campaignError }, snapshot] = await Promise.all([
    supabase
      .from('campaigns')
      .select('bbox, territory_boundary')
      .eq('id', campaignId)
      .maybeSingle(),
    getCachedCampaignSnapshot(supabase, campaignId),
  ]);

  if (campaignError || !campaign) {
    throw new CampaignParcelNotFoundError(campaignId);
  }

  const campaignScope = campaign as CampaignScopeRow;
  const boundary = normalizeGeoJsonPolygon(campaignScope.territory_boundary);
  const bbox = parseBbox(campaignScope.bbox) ?? (boundary ? bboxFromPositions(flattenPositions(boundary)) : null);
  if (!bbox) return emptyResolution();

  const addressPoints = await fetchCampaignAddressPoints(supabase, campaignId);

  const persistedParcels = await fetchPersistedCampaignParcels(supabase, campaignId);
  const residentialPersistedParcels = filterCampaignScopedParcelResponses(
    filterResidentialParcelResponses(persistedParcels),
    bbox,
    boundary
  );
  if (residentialPersistedParcels.length > 0) {
    const parcelAddressLinks = await fetchPersistedParcelAddressLinks(supabase, campaignId);
    const evidenceAnnotations = parcelAnnotationsFromEvidence(residentialPersistedParcels, parcelAddressLinks);
    const annotations = evidenceAnnotations.length > 0
      ? evidenceAnnotations
      : inferParcelAddressAnnotations(residentialPersistedParcels, addressPoints);
    return responseFromParcels(
      annotateParcelsWithAddressLinks(residentialPersistedParcels, annotations),
      'campaign_parcels'
    );
  }

  if (snapshot) {
    const parcelTiles = parcelTilesFromSnapshot(snapshot);
    if (parcelTiles) {
      const failureCacheKey = getParcelFailureCacheKey(campaignId, parcelTiles.pmtilesKey);
      if (hasCachedParcelFailure(failureCacheKey)) {
        return emptyResolution('empty', 'cached-failure');
      }

      try {
        const parcels = await fetchScopedPmtilesParcels(campaignId, snapshot, parcelTiles, bbox, boundary);
        const annotations = inferParcelAddressAnnotations(parcels, addressPoints);
        return responseFromParcels(annotateParcelsWithAddressLinks(parcels, annotations), 'snapshot_pmtiles');
      } catch (error) {
        const errorMessage = error instanceof Error ? error.message : String(error);
        if (errorMessage.includes('403')) {
          cacheParcelFailure(failureCacheKey);
          console.warn('[CampaignParcels] Parcel PMTiles access denied; suppressing retries temporarily:', {
            campaignId,
            error: errorMessage,
          });
          return emptyResolution('empty', 'access-denied');
        }

        if (errorMessage.includes('404') || errorMessage.includes('Bad response code: 404')) {
          cacheParcelFailure(failureCacheKey);
          console.warn('[CampaignParcels] Parcel PMTiles unavailable; returning empty parcel set:', {
            campaignId,
            error: errorMessage,
          });
          return emptyResolution('empty', 'not-found');
        }

        throw error;
      }
    }
  }

  const preparedParcels = await fetchPreparedCampaignParcels(supabase, campaignId);
  const residentialPreparedParcels = filterCampaignScopedParcelResponses(
    filterResidentialParcelResponses(preparedParcels),
    bbox,
    boundary
  );
  if (residentialPreparedParcels.length > 0) {
    const parcelAddressLinks = await fetchPersistedParcelAddressLinks(supabase, campaignId);
    const evidenceAnnotations = parcelAnnotationsFromEvidence(residentialPreparedParcels, parcelAddressLinks);
    const annotations = evidenceAnnotations.length > 0
      ? evidenceAnnotations
      : inferParcelAddressAnnotations(residentialPreparedParcels, addressPoints);
    return responseFromParcels(
      annotateParcelsWithAddressLinks(residentialPreparedParcels, annotations),
      'campaign_parcels'
    );
  }

  return emptyResolution();
}
