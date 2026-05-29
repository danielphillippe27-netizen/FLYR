import type { SupabaseClient } from '@supabase/supabase-js';
import { createHash } from 'crypto';
import { fetchScopedPmtilesBuildingFeatures } from '@/app/api/campaigns/_utils/scoped-pmtiles-buildings';
import { filterLinkableBuildingFootprints } from '@/lib/geo/buildingFootprintFilter';
import { resolvePmtilesKey, type CampaignSnapshotRow } from '@/lib/diamond/geometry';
import { resolveCampaignParcels } from '@/lib/services/CampaignParcelFeatureService';

type GeoJSONFeature = {
  id?: unknown;
  type?: string;
  geometry?: { type?: string; coordinates?: unknown } | null;
  properties?: Record<string, unknown> | null;
};

type FeatureCollection = {
  type: 'FeatureCollection';
  features: GeoJSONFeature[];
};

type CurrentBundleRow = {
  campaign_id: string;
  asset_signature: string;
  source_version: string;
  buildings_geojson: FeatureCollection;
  addresses_geojson: FeatureCollection;
  parcels_geojson: FeatureCollection;
  roads_geojson: FeatureCollection;
  links: CampaignMapBundleLink[];
  address_orphans?: AddressOrphan[];
  building_orphans?: BuildingOrphan[];
  display_mode_hint: DisplayModeHint;
  counts: Record<string, unknown>;
  layer_fetched_at: Record<string, string | null>;
  links_status: LinksStatus;
  built_at: string;
  expires_at: string;
  updated_at: string;
};

type SourceVersionResult = {
  source_version?: string;
  link_source_version?: string;
  counts?: Record<string, unknown>;
  updated_at?: string;
};

export type CampaignMapBundleLink = {
  id?: string;
  building_id: string;
  address_id: string;
  match_type: string;
  link_source?: string | null;
  confidence: number;
  distance_meters: number;
  source_version?: string | null;
  is_multi_unit?: boolean | null;
  unit_count?: number | null;
  building_class?: string | null;
};

export type AddressOrphan = {
  address_id: string;
  campaign_id: string;
  reason: 'no_containment' | 'no_parcel' | 'proximity_too_far' | 'proximity_ambiguous';
  nearest_building_id: string | null;
  nearest_building_distance_m: number | null;
};

export type BuildingOrphan = {
  building_id: string;
  campaign_id: string;
};

type BuildingIdentityRow = {
  id: string;
  gers_id: string | null;
};
type MaterializedCampaignBuildingRow = {
  id: string;
  gers_id: string | null;
  geom?: unknown;
  height_m: number | string | null;
  height: number | string | null;
  latest_status: string | null;
  is_hidden: boolean | null;
  units_count: number | string | null;
  addr_housenumber: string | null;
  addr_street: string | null;
};

type DisplayModeHint = 'buildings' | 'addresses';
type LinksStatus = 'ok' | 'stale_reused' | 'pending_provision' | 'client_fallback_required' | 'fresh';
type Bbox = [number, number, number, number];
type ParcelBundleResult = {
  collection: FeatureCollection;
  source: string;
};
type PolishedBuildingCacheMeta = {
  featureCount: number;
  updatedAt: string | null;
};
export type CampaignMapBundleTimingRecorder = (name: string, durationMs: number) => void;

export type CampaignMapBundleServiceResult =
  | { status: 'not_modified'; assetSignature: string; sourceVersion: string }
  | { status: 'ok'; bundle: CanonicalCampaignMapBundleResponse };

export type CanonicalCampaignMapBundleResponse = {
  campaign_id: string;
  asset_signature: string;
  source_version: string;
  display_mode_hint: DisplayModeHint;
  links_status: LinksStatus;
  addresses: FeatureCollection;
  buildings: FeatureCollection;
  parcels: FeatureCollection;
  roads: FeatureCollection;
  links: CampaignMapBundleLink[];
  address_orphans: AddressOrphan[];
  building_orphans: BuildingOrphan[];
  counts: {
    addresses: number;
    buildings: number;
    parcels: number;
    roads: number;
    links: number;
  };
  layer_fetched_at: Record<string, string | null>;
  built_at: string;
  expires_at: string;
  updated_at?: string;
};

const EMPTY_FEATURE_COLLECTION: FeatureCollection = { type: 'FeatureCollection', features: [] };
const ADDRESS_TTL_MS = 15 * 60 * 1000;
const STATIC_GEOMETRY_TTL_MS = 24 * 60 * 60 * 1000;
const MAP_BUNDLE_CACHE_VERSION = 'canonical-map-bundle-v5';
const PARCEL_RESOLUTION_VERSION = 'pmtiles-v2';
const STRICT_NEAREST_LINK_MAX_DISTANCE_METERS = 15;
const STRICT_PROXIMITY_LINK_MAX_DISTANCE_METERS = 25;
const STRICT_PROXIMITY_LINK_MIN_CONFIDENCE = 0.75;
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function asFeatureCollection(raw: unknown): FeatureCollection {
  if (!raw) return { ...EMPTY_FEATURE_COLLECTION };
  if (typeof raw === 'string') {
    try {
      return asFeatureCollection(JSON.parse(raw));
    } catch {
      return { ...EMPTY_FEATURE_COLLECTION };
    }
  }
  if (typeof raw === 'object') {
    const value = raw as { type?: unknown; features?: unknown };
    if (value.type === 'FeatureCollection' && Array.isArray(value.features)) {
      return { type: 'FeatureCollection', features: value.features as GeoJSONFeature[] };
    }
  }
  return { ...EMPTY_FEATURE_COLLECTION };
}

function normalizedString(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function normalizeLinksStatus(value: unknown): LinksStatus {
  const status = normalizedString(value);
  if (status === 'fresh') return 'ok';
  if (status === 'ok' || status === 'stale_reused' || status === 'pending_provision') return status;
  if (status === 'client_fallback_required') return 'client_fallback_required';
  return 'pending_provision';
}

function numericValue(value: unknown, fallback = 0): number {
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : fallback;
}

function isAddressProxyFeature(feature: GeoJSONFeature): boolean {
  const props = feature.properties ?? {};
  const source = normalizedString(props.source)?.toLowerCase();
  const featureType = normalizedString(props.feature_type)?.toLowerCase();
  const featureStatus = normalizedString(props.feature_status)?.toLowerCase();
  const identifierSource = normalizedString(props.building_identifier_source)?.toLowerCase();
  const ids = [
    normalizedString(feature.id),
    normalizedString(props.id),
    normalizedString(props.gers_id),
    normalizedString(props.building_id),
    normalizedString(props.public_building_id),
    normalizedString(props.canonical_building_id),
  ].flatMap((value) => {
    const normalized = value?.toLowerCase();
    return normalized ? [normalized] : [];
  });

  return source === 'address_proxy' ||
    featureType === 'address_proxy' ||
    featureStatus === 'missing_footprint_proxy' ||
    identifierSource === 'address_proxy' ||
    ids.some((id) => id.startsWith('address-proxy-'));
}

function withoutAddressProxyBuildings(collection: FeatureCollection): FeatureCollection {
  return {
    type: collection.type,
    features: collection.features.filter((feature) => !isAddressProxyFeature(feature)),
  };
}

function finiteNumber(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value.trim().length > 0) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function isUuid(value: string): boolean {
  return UUID_RE.test(value);
}

function linkRank(link: CampaignMapBundleLink): number {
  const matchType = link.match_type.toLowerCase();
  const matchScore =
    matchType === 'manual' ? 5 :
    matchType === 'containment_verified' ? 4 :
    matchType === 'point_on_surface' ? 3 :
    matchType === 'parcel_verified' || matchType === 'parcel_bridge' ? 2 :
    matchType === 'proximity_fallback' || matchType === 'nearest_building_15m' ? 1 :
    0;
  return matchScore * 10 + link.confidence;
}

export function isStrictCampaignMapBundleLink(link: CampaignMapBundleLink): boolean {
  const matchType = normalizedString(link.match_type)?.toLowerCase() ?? '';
  const linkSource = normalizedString(link.link_source)?.toLowerCase() ?? '';
  const confidence = numericValue(link.confidence, 0);
  const distanceMeters = numericValue(link.distance_meters, Number.POSITIVE_INFINITY);

  if (matchType === 'manual' || linkSource === 'manual' || linkSource === 'client_auto') return true;
  if (matchType === 'semantic_verified') return confidence >= 0.9;
  if (matchType === 'containment_verified' || matchType === 'point_on_surface') return confidence >= 0.85;
  if (matchType === 'parcel_verified' || matchType === 'parcel_bridge') return confidence >= 0.9;
  if (matchType === 'proximity_verified') {
    return confidence >= STRICT_PROXIMITY_LINK_MIN_CONFIDENCE &&
      distanceMeters <= STRICT_PROXIMITY_LINK_MAX_DISTANCE_METERS;
  }
  if (matchType === 'nearest_building_15m') {
    return distanceMeters <= STRICT_NEAREST_LINK_MAX_DISTANCE_METERS;
  }
  return false;
}

function strictCampaignMapBundleLinks(links: CampaignMapBundleLink[]): CampaignMapBundleLink[] {
  return links.filter(isStrictCampaignMapBundleLink);
}

function deduplicateLinksByAddress(links: CampaignMapBundleLink[]): CampaignMapBundleLink[] {
  if (links.length <= 1) return links;

  const orderedAddressIds: string[] = [];
  const bestByAddressId = new Map<string, CampaignMapBundleLink>();
  for (const link of links) {
    const addressKey = link.address_id.trim().toLowerCase();
    if (!addressKey) continue;

    const existing = bestByAddressId.get(addressKey);
    if (!existing) {
      orderedAddressIds.push(addressKey);
      bestByAddressId.set(addressKey, link);
      continue;
    }

    if (linkRank(link) > linkRank(existing)) {
      bestByAddressId.set(addressKey, link);
    }
  }

  return orderedAddressIds.flatMap((addressId) => {
    const link = bestByAddressId.get(addressId);
    return link ? [link] : [];
  });
}

function lookupNormalizedString(lookup: Map<string, string>, value: string): string | null {
  return normalizedString(lookup.get(value.trim().toLowerCase()));
}

export function normalizeCampaignMapBundleLinksForClient(
  rawLinks: CampaignMapBundleLink[],
  publicIdsByBuildingRowId: Map<string, string>
): CampaignMapBundleLink[] {
  return deduplicateLinksByAddress(strictCampaignMapBundleLinks(rawLinks)).map((link) => {
    const publicBuildingId =
      lookupNormalizedString(publicIdsByBuildingRowId, link.building_id) ??
      link.building_id;

    return {
      ...link,
      building_id: publicBuildingId,
    };
  });
}

function featureIdentity(feature: GeoJSONFeature, keys: string[]): string | null {
  const props = feature.properties ?? {};
  for (const key of keys) {
    const value = normalizedString(props[key]);
    if (value) return value.toLowerCase();
  }
  const rootId = normalizedString(feature.id);
  return rootId?.toLowerCase() ?? null;
}

function featureIdentityCandidates(feature: GeoJSONFeature, keys: string[]): string[] {
  const props = feature.properties ?? {};
  const seen = new Set<string>();
  const values: string[] = [];
  for (const key of keys) {
    const value = normalizedString(props[key])?.toLowerCase();
    if (value && !seen.has(value)) {
      seen.add(value);
      values.push(value);
    }
  }
  const rootId = normalizedString(feature.id)?.toLowerCase();
  if (rootId && !seen.has(rootId)) values.push(rootId);
  return values;
}

function dedupeStrings(values: string[]): string[] {
  const seen = new Set<string>();
  return values.filter((value) => {
    const normalized = value.trim().toLowerCase();
    if (!normalized || seen.has(normalized)) return false;
    seen.add(normalized);
    return true;
  });
}

function applyLinksToFeatureCollections(
  buildings: FeatureCollection,
  addresses: FeatureCollection,
  links: CampaignMapBundleLink[]
): { buildings: FeatureCollection; addresses: FeatureCollection } {
  const linksByBuildingId = new Map<string, CampaignMapBundleLink[]>();
  const linkByAddressId = new Map<string, CampaignMapBundleLink>();
  for (const link of links) {
    const buildingId = link.building_id.trim().toLowerCase();
    const addressId = link.address_id.trim().toLowerCase();
    if (!buildingId || !addressId) continue;
    linksByBuildingId.set(buildingId, [...(linksByBuildingId.get(buildingId) ?? []), link]);
    linkByAddressId.set(addressId, link);
  }

  const linkedBuildings: FeatureCollection = {
    type: 'FeatureCollection',
    features: buildings.features.map((feature) => {
      const identifiers = featureIdentityCandidates(feature, [
        'canonical_building_id',
        'canonicalBuildingId',
        'public_building_id',
        'building_id',
        'gers_id',
        'id',
      ]);
      const rawFeatureLinks = identifiers.flatMap((identifier) => linksByBuildingId.get(identifier) ?? []);
      const featureLinks = dedupeStrings(rawFeatureLinks.map((link) => link.address_id));
      const splitterUnitsCount = rawFeatureLinks.reduce((max, link) => {
        const unitCount = numericValue(link.unit_count, 0);
        return unitCount > max ? unitCount : max;
      }, 0);
      const isTownhouse = rawFeatureLinks.some((link) => normalizedString(link.building_class)?.toLowerCase() === 'townhouse');
      const properties = { ...(feature.properties ?? {}) };
      properties.address_ids = featureLinks;
      properties.is_linked = featureLinks.length > 0;
      properties.is_townhouse = isTownhouse;
      if (featureLinks.length === 1) {
        properties.address_id = featureLinks[0];
      } else {
        delete properties.address_id;
      }
      properties.address_count = featureLinks.length;
      properties.units_count = Math.max(
        numericValue(properties.units_count, 1),
        featureLinks.length,
        splitterUnitsCount || 0
      );
      if (featureLinks.length > 0) {
        properties.feature_type = 'linked_building';
        properties.feature_status = 'linked';
      }
      return { ...feature, properties };
    }),
  };

  const linkedAddresses: FeatureCollection = {
    type: 'FeatureCollection',
    features: addresses.features.map((feature) => {
      const addressId = featureIdentity(feature, ['id', 'address_id', 'campaign_address_id']);
      const link = addressId ? linkByAddressId.get(addressId) : undefined;
      const properties = { ...(feature.properties ?? {}) };
      if (link) {
        properties.building_gers_id = link.building_id;
      } else {
        delete properties.building_gers_id;
      }
      return { ...feature, properties };
    }),
  };

  return { buildings: linkedBuildings, addresses: linkedAddresses };
}

function collectBuildingOrphans(
  campaignId: string,
  buildings: FeatureCollection,
  links: CampaignMapBundleLink[]
): BuildingOrphan[] {
  const linkedBuildingIds = new Set(
    links
      .map((link) => normalizedString(link.building_id)?.toLowerCase())
      .filter((id): id is string => Boolean(id))
  );
  return buildings.features.flatMap((feature) => {
    const identifiers = featureIdentityCandidates(feature, [
      'canonical_building_id',
      'canonicalBuildingId',
      'public_building_id',
      'building_id',
      'gers_id',
      'id',
    ]);
    if (identifiers.length === 0) return [];
    if (identifiers.some((identifier) => linkedBuildingIds.has(identifier))) return [];
    return [{
      campaign_id: campaignId,
      building_id: identifiers[0],
    }];
  });
}

function collectCoordinatePairs(value: unknown, output: Array<[number, number]>) {
  if (!Array.isArray(value)) return;
  if (
    value.length >= 2 &&
    typeof value[0] === 'number' &&
    typeof value[1] === 'number' &&
    Number.isFinite(value[0]) &&
    Number.isFinite(value[1])
  ) {
    output.push([value[0], value[1]]);
    return;
  }
  for (const child of value) {
    collectCoordinatePairs(child, output);
  }
}

function bboxFromGeometry(value: unknown): Bbox | null {
  if (!value || typeof value !== 'object') return null;
  const coordinates = (value as { coordinates?: unknown }).coordinates;
  const positions: Array<[number, number]> = [];
  collectCoordinatePairs(coordinates, positions);
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

function polygonBoundary(value: unknown): GeoJSON.Polygon | null {
  if (!value || typeof value !== 'object') return null;
  const geometry = value as { type?: unknown; coordinates?: unknown };
  if (geometry.type !== 'Polygon' || !Array.isArray(geometry.coordinates)) return null;
  return geometry as GeoJSON.Polygon;
}

function polygonGeometryFromValue(value: unknown): GeoJSONFeature['geometry'] | null {
  if (!value) return null;
  if (typeof value === 'object') {
    const geometry = value as GeoJSONFeature['geometry'];
    if (geometry?.type === 'Polygon' || geometry?.type === 'MultiPolygon') return geometry;
    return null;
  }
  if (typeof value !== 'string') return null;

  const trimmed = value.trim();
  if (!trimmed) return null;
  try {
    return polygonGeometryFromValue(JSON.parse(trimmed));
  } catch {
    return null;
  }
}

function materializedBuildingFeature(row: MaterializedCampaignBuildingRow): GeoJSONFeature | null {
  if (row.is_hidden === true) return null;
  const geometry = polygonGeometryFromValue(row.geom);
  if (!geometry) return null;

  const publicId = normalizedString(row.gers_id) ?? row.id;
  const height = finiteNumber(row.height_m) ?? finiteNumber(row.height) ?? 9;
  const unitsCount = Math.max(1, Math.round(finiteNumber(row.units_count) ?? 1));

  return {
    type: 'Feature',
    id: publicId,
    geometry,
    properties: {
      id: row.id,
      building_id: row.id,
      gers_id: publicId,
      public_building_id: publicId,
      canonical_building_id: publicId,
      building_identifier_source: normalizedString(row.gers_id) ? 'gers' : 'materialized',
      source: 'silver',
      height,
      height_m: height,
      min_height: 0,
      units_count: unitsCount,
      address_count: 0,
      address_id: null,
      address_ids: [],
      address_text: null,
      house_number: normalizedString(row.addr_housenumber),
      street_name: normalizedString(row.addr_street),
      feature_type: 'orphan',
      feature_status: 'orphan_building',
      is_linked: false,
      status: normalizedString(row.latest_status) ?? 'not_visited',
      scans_today: 0,
      scans_total: 0,
      qr_scanned: false,
    },
  };
}

function filterRenderableBuildingFeatures(features: GeoJSONFeature[], context: string): GeoJSONFeature[] {
  const filtered = filterLinkableBuildingFootprints(features, { allowManual: true });
  const removed = features.length - filtered.length;
  if (removed > 0) {
    console.log(`[CampaignMapBundle] Filtered ${removed} building feature(s) under minimum area from ${context}`);
  }
  return filtered;
}

function stableHash(values: string[]): string {
  const hash = createHash('sha256');
  for (const value of values) {
    hash.update(value);
    hash.update('\0');
  }
  return hash.digest('hex').slice(0, 16);
}

function assetSignature(
  campaignId: string,
  buildings: FeatureCollection,
  addresses: FeatureCollection,
  parcels: FeatureCollection
): string {
  const buildingIds = buildings.features
    .map((feature) => featureIdentity(feature, [
      'canonical_building_id',
      'canonicalBuildingId',
      'public_building_id',
      'building_id',
      'gers_id',
      'id',
    ]))
    .filter((value): value is string => Boolean(value))
    .sort();
  const addressIds = addresses.features
    .map((feature) => featureIdentity(feature, ['id', 'address_id', 'campaign_address_id', 'gers_id']))
    .filter((value): value is string => Boolean(value))
    .sort();
  const parcelIds = parcels.features
    .map((feature) => featureIdentity(feature, ['parcel_id', 'external_id', 'id']))
    .filter((value): value is string => Boolean(value))
    .sort();

  return [
    campaignId.toLowerCase(),
    `b${buildings.features.length}:${stableHash(buildingIds)}`,
    `a${addresses.features.length}:${stableHash(addressIds)}`,
    `p${parcels.features.length}:${stableHash(parcelIds)}`,
  ].join(':');
}

function parseTime(value: string | null | undefined): number | null {
  if (!value) return null;
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp) ? timestamp : null;
}

function isFresh(value: string | null | undefined, ttlMs: number, nowMs = Date.now()): boolean {
  const timestamp = parseTime(value);
  return timestamp !== null && nowMs - timestamp < ttlMs;
}

function currentBundleIsFresh(row: CurrentBundleRow, nowMs = Date.now()): boolean {
  return parseTime(row.expires_at) !== null &&
    parseTime(row.expires_at)! > nowMs &&
    isFresh(row.layer_fetched_at?.addresses, ADDRESS_TTL_MS, nowMs) &&
    isFresh(row.layer_fetched_at?.buildings, STATIC_GEOMETRY_TTL_MS, nowMs) &&
    isFresh(row.layer_fetched_at?.parcels, STATIC_GEOMETRY_TTL_MS, nowMs);
}

function currentBundleNeedsParcelBackfill(row: CurrentBundleRow): boolean {
  if (normalizedString(row.counts?.parcel_resolution_version) !== PARCEL_RESOLUTION_VERSION) return true;
  if (asFeatureCollection(row.parcels_geojson).features.length > 0) return false;
  return !normalizedString(row.counts?.parcel_source) &&
    !normalizedString(row.counts?.parcel_source_checked_at);
}

export function shouldRefreshBundleForCacheVersion(currentVersion?: string | null): boolean {
  return normalizedString(currentVersion) !== MAP_BUNDLE_CACHE_VERSION;
}

function currentBundleNeedsCacheVersionRefresh(row: CurrentBundleRow): boolean {
  return shouldRefreshBundleForCacheVersion(row.counts?.bundle_cache_version as string | null | undefined);
}

export function shouldRefreshBundleFromPolishedCache(params: {
  currentBuildingFeatures: number;
  currentBuildingsFetchedAt?: string | null;
  polishedFeatureCount?: number | null;
  polishedUpdatedAt?: string | null;
}): boolean {
  const polishedFeatureCount = numericValue(params.polishedFeatureCount, 0);
  if (polishedFeatureCount <= 0) return false;

  if (polishedFeatureCount > Math.max(params.currentBuildingFeatures, 0)) {
    return true;
  }

  const currentFetchedAt = parseTime(params.currentBuildingsFetchedAt);
  const polishedUpdatedAt = parseTime(params.polishedUpdatedAt);
  return (
    currentFetchedAt !== null &&
    polishedUpdatedAt !== null &&
    polishedUpdatedAt > currentFetchedAt &&
    polishedFeatureCount !== params.currentBuildingFeatures
  );
}

function currentBundleNeedsPolishedCacheRefresh(
  row: CurrentBundleRow,
  polishedCacheMeta: PolishedBuildingCacheMeta | null
): boolean {
  return shouldRefreshBundleFromPolishedCache({
    currentBuildingFeatures: asFeatureCollection(row.buildings_geojson).features.length,
    currentBuildingsFetchedAt: normalizedString(row.layer_fetched_at?.buildings),
    polishedFeatureCount: polishedCacheMeta?.featureCount,
    polishedUpdatedAt: polishedCacheMeta?.updatedAt,
  });
}

export function shouldRefreshBundleFromPersistedParcels(params: {
  currentParcelFeatures: number;
  currentParcelSource?: string | null;
  persistedParcelCount?: number | null;
}): boolean {
  const persistedParcelCount = numericValue(params.persistedParcelCount, 0);
  if (persistedParcelCount <= 0) return false;

  const currentParcelFeatures = Math.max(params.currentParcelFeatures, 0);
  if (persistedParcelCount > currentParcelFeatures) return true;

  return normalizedString(params.currentParcelSource) !== 'campaign_parcels';
}

function currentBundleNeedsPersistedParcelRefresh(
  row: CurrentBundleRow,
  source: SourceVersionResult
): boolean {
  return shouldRefreshBundleFromPersistedParcels({
    currentParcelFeatures: numericValue(
      row.counts?.parcels,
      asFeatureCollection(row.parcels_geojson).features.length
    ),
    currentParcelSource: row.counts?.parcel_source as string | null | undefined,
    persistedParcelCount: source.counts?.parcels as number | null | undefined,
  });
}

function displayModeHint(buildings: FeatureCollection, addresses: FeatureCollection, links: CampaignMapBundleLink[]): DisplayModeHint {
  const buildingCount = buildings.features.length;
  const addressCount = addresses.features.length;
  if (addressCount >= 20 && buildingCount <= 1) return 'addresses';
  if (addressCount > 0 && links.length / addressCount < 0.15) return 'addresses';
  return 'buildings';
}

function linksStatusForStoredLinks(
  links: CampaignMapBundleLink[],
  linkSourceVersion: string | null
): Exclude<LinksStatus, 'fresh' | 'client_fallback_required'> {
  if (links.length === 0) return 'pending_provision';

  const autoLinks = links.filter((link) => {
    const source = normalizedString(link.link_source)?.toLowerCase() ?? 'auto';
    return source === 'auto' || source === 'auto_parcel' || source === 'client_auto_expired';
  });
  if (autoLinks.length === 0) return 'ok';
  if (!linkSourceVersion) return 'stale_reused';
  return autoLinks.every((link) => normalizedString(link.source_version) === linkSourceVersion)
    ? 'ok'
    : 'stale_reused';
}

function responseFromRow(row: CurrentBundleRow): CanonicalCampaignMapBundleResponse {
  const addressOrphans = Array.isArray(row.address_orphans) ? row.address_orphans : [];
  const buildingOrphans = Array.isArray(row.building_orphans) ? row.building_orphans : [];
  return {
    campaign_id: row.campaign_id,
    asset_signature: row.asset_signature,
    source_version: row.source_version,
    display_mode_hint: row.display_mode_hint === 'addresses' ? 'addresses' : 'buildings',
    links_status: normalizeLinksStatus(row.links_status),
    addresses: asFeatureCollection(row.addresses_geojson),
    buildings: asFeatureCollection(row.buildings_geojson),
    parcels: asFeatureCollection(row.parcels_geojson),
    roads: asFeatureCollection(row.roads_geojson),
    links: Array.isArray(row.links) ? row.links : [],
    address_orphans: addressOrphans,
    building_orphans: buildingOrphans,
    counts: {
      addresses: numericValue(row.counts?.addresses, asFeatureCollection(row.addresses_geojson).features.length),
      buildings: numericValue(row.counts?.buildings, asFeatureCollection(row.buildings_geojson).features.length),
      parcels: numericValue(row.counts?.parcels, asFeatureCollection(row.parcels_geojson).features.length),
      roads: numericValue(row.counts?.roads, asFeatureCollection(row.roads_geojson).features.length),
      links: numericValue(row.counts?.links, Array.isArray(row.links) ? row.links.length : 0),
    },
    layer_fetched_at: row.layer_fetched_at ?? {},
    built_at: row.built_at,
    expires_at: row.expires_at,
    updated_at: row.updated_at,
  };
}

export class CampaignMapBundleService {
  constructor(
    private readonly supabase: SupabaseClient,
    private readonly recordTiming: CampaignMapBundleTimingRecorder = () => {}
  ) {}

  private async measure<T>(name: string, operation: () => Promise<T>): Promise<T> {
    const startedAt = performance.now();
    try {
      return await operation();
    } finally {
      this.recordTiming(name, performance.now() - startedAt);
    }
  }

  async resolve(campaignId: string, localSignature?: string | null): Promise<CampaignMapBundleServiceResult> {
    const source = await this.measure('source', () => this.fetchSourceVersion(campaignId));
    const current = await this.measure('current', () => this.fetchCurrentBundle(campaignId));
    const polishedCacheMeta = await this.measure('polished_cache_meta', () =>
      this.fetchPolishedBuildingCacheMeta(campaignId)
    );
    const needsCacheVersionRefresh = current ? currentBundleNeedsCacheVersionRefresh(current) : false;
    const needsParcelBackfill = current ? currentBundleNeedsParcelBackfill(current) : false;
    const needsPersistedParcelRefresh = current
      ? currentBundleNeedsPersistedParcelRefresh(current, source.raw)
      : false;
    const needsPolishedCacheRefresh = current
      ? currentBundleNeedsPolishedCacheRefresh(current, polishedCacheMeta)
      : false;

    if (
      current &&
      !needsCacheVersionRefresh &&
      !needsParcelBackfill &&
      !needsPersistedParcelRefresh &&
      !needsPolishedCacheRefresh &&
      current.asset_signature === localSignature &&
      current.source_version === source.sourceVersion &&
      currentBundleIsFresh(current)
    ) {
      return {
        status: 'not_modified',
        assetSignature: current.asset_signature,
        sourceVersion: current.source_version,
      };
    }

    const shouldRebuild =
      !current ||
      current.source_version !== source.sourceVersion ||
      !currentBundleIsFresh(current) ||
      needsCacheVersionRefresh ||
      needsParcelBackfill ||
      needsPersistedParcelRefresh ||
      needsPolishedCacheRefresh;

    if (!shouldRebuild && current) {
      return { status: 'ok', bundle: responseFromRow(current) };
    }

    const bundle = await this.rebuildBundle(campaignId, source.sourceVersion, source.linkSourceVersion, current, {
      forceRefreshAllLayers: needsCacheVersionRefresh,
      forceRefreshBuildings: needsPolishedCacheRefresh,
      forceRefreshParcels: needsParcelBackfill || needsPersistedParcelRefresh,
    });
    return { status: 'ok', bundle };
  }

  // Manual repair tool only. Not part of the normal map load path.
  // See: flyr-linking-restructure task 2
  async refreshLinksForRepair(campaignId: string): Promise<void> {
    const { error } = await this.supabase.rpc('rpc_refresh_campaign_map_links', {
      p_campaign_id: campaignId,
    });
    if (error) {
      throw new Error(`Failed to repair campaign map links: ${error.message}`);
    }
  }

  private async fetchSourceVersion(campaignId: string): Promise<{
    sourceVersion: string;
    linkSourceVersion: string | null;
    raw: SourceVersionResult;
  }> {
    const { data, error } = await this.supabase.rpc('rpc_get_campaign_map_source_version', {
      p_campaign_id: campaignId,
    });
    if (error) {
      throw new Error(`Failed to compute map source version: ${error.message}`);
    }
    const raw = (data ?? {}) as SourceVersionResult;
    const sourceVersion = normalizedString(raw.source_version) ?? `fallback:${campaignId}`;
    const linkSourceVersion = normalizedString(raw.link_source_version) ?? sourceVersion;
    return { sourceVersion, linkSourceVersion, raw };
  }

  private async fetchCurrentBundle(campaignId: string): Promise<CurrentBundleRow | null> {
    const { data, error } = await this.supabase
      .from('campaign_map_bundles')
      .select('*')
      .eq('campaign_id', campaignId)
      .eq('is_current', true)
      .maybeSingle();
    if (error) {
      throw new Error(`Failed to read campaign map bundle cache: ${error.message}`);
    }
    return (data as CurrentBundleRow | null) ?? null;
  }

  private async rebuildBundle(
    campaignId: string,
    sourceVersion: string,
    linkSourceVersion: string | null,
    current: CurrentBundleRow | null,
    options: {
      forceRefreshAllLayers?: boolean;
      forceRefreshBuildings?: boolean;
      forceRefreshParcels?: boolean;
    } = {}
  ): Promise<CanonicalCampaignMapBundleResponse> {
    const now = new Date();
    const nowIso = now.toISOString();
    const sameSource = current?.source_version === sourceVersion;
    const currentFetchedAt = current?.layer_fetched_at ?? {};

    const shouldReuseAddresses =
      !options.forceRefreshAllLayers &&
      sameSource &&
      current &&
      isFresh(currentFetchedAt.addresses, ADDRESS_TTL_MS);
    const shouldReuseBuildings =
      !options.forceRefreshAllLayers &&
      !options.forceRefreshBuildings &&
      sameSource &&
      current &&
      isFresh(currentFetchedAt.buildings, STATIC_GEOMETRY_TTL_MS);
    const shouldReuseParcels =
      !options.forceRefreshAllLayers &&
      !options.forceRefreshParcels &&
      sameSource &&
      current &&
      isFresh(currentFetchedAt.parcels, STATIC_GEOMETRY_TTL_MS) &&
      !currentBundleNeedsParcelBackfill(current);
    const shouldReuseRoads =
      !options.forceRefreshAllLayers &&
      sameSource &&
      current &&
      isFresh(currentFetchedAt.roads, STATIC_GEOMETRY_TTL_MS);

    const [addresses, buildings, parcelBundle, roads, linkBundle] = await Promise.all([
      this.measure('addresses', () =>
        shouldReuseAddresses
          ? Promise.resolve(asFeatureCollection(current!.addresses_geojson))
          : this.fetchFeatureCollection('rpc_get_campaign_addresses', campaignId)
      ),
      this.measure('buildings', () =>
        shouldReuseBuildings
          ? Promise.resolve(asFeatureCollection(current!.buildings_geojson))
          : this.fetchBuildingsFeatureCollection(campaignId)
      ),
      this.measure('parcels', () =>
        shouldReuseParcels
          ? Promise.resolve({
              collection: asFeatureCollection(current!.parcels_geojson),
              source: normalizedString(current!.counts?.parcel_source) ?? 'current_bundle',
            })
          : this.fetchParcelsFeatureCollection(campaignId)
      ),
      this.measure('roads', () =>
        shouldReuseRoads
          ? Promise.resolve(asFeatureCollection(current!.roads_geojson))
          : this.fetchFeatureCollection('rpc_get_campaign_roads_v2', campaignId)
      ),
      this.measure('links', async () => {
        const links = await this.fetchLinks(campaignId);
        return {
          linksStatus: linksStatusForStoredLinks(links, linkSourceVersion),
          links,
        };
      }),
    ]);

    const { linksStatus, links } = linkBundle;
    const parcels = parcelBundle.collection;
    const linkedFeatures = applyLinksToFeatureCollections(buildings, addresses, links);
    const [addressOrphans, buildingOrphans] = await Promise.all([
      this.measure('address_orphans', () => this.fetchAddressOrphans(campaignId)),
      Promise.resolve(collectBuildingOrphans(campaignId, linkedFeatures.buildings, links)),
    ]);
    const signature = assetSignature(campaignId, linkedFeatures.buildings, linkedFeatures.addresses, parcels);
    const layerFetchedAt = {
      addresses: shouldReuseAddresses ? currentFetchedAt.addresses ?? nowIso : nowIso,
      buildings: shouldReuseBuildings ? currentFetchedAt.buildings ?? nowIso : nowIso,
      parcels: shouldReuseParcels ? currentFetchedAt.parcels ?? nowIso : nowIso,
      roads: shouldReuseRoads ? currentFetchedAt.roads ?? nowIso : nowIso,
    };
    const expiresAt = new Date(Math.min(
      parseTime(layerFetchedAt.addresses)! + ADDRESS_TTL_MS,
      parseTime(layerFetchedAt.buildings)! + STATIC_GEOMETRY_TTL_MS,
      parseTime(layerFetchedAt.parcels)! + STATIC_GEOMETRY_TTL_MS
    )).toISOString();
    const counts = {
      addresses: addresses.features.length,
      buildings: buildings.features.length,
      parcels: parcels.features.length,
      roads: roads.features.length,
      links: links.length,
      address_orphans: addressOrphans.length,
      building_orphans: buildingOrphans.length,
    };
    const persistedCounts = {
      ...counts,
      bundle_cache_version: MAP_BUNDLE_CACHE_VERSION,
      parcel_source: parcelBundle.source,
      parcel_resolution_version: PARCEL_RESOLUTION_VERSION,
      parcel_source_checked_at: nowIso,
    };
    const hint = displayModeHint(buildings, addresses, links);

    const { data, error } = await this.measure('persist', async () => await this.supabase.rpc('rpc_upsert_campaign_map_bundle', {
      p_campaign_id: campaignId,
      p_asset_signature: signature,
      p_source_version: sourceVersion,
      p_buildings_geojson: linkedFeatures.buildings,
      p_addresses_geojson: linkedFeatures.addresses,
      p_parcels_geojson: parcels,
      p_roads_geojson: roads,
      p_links: links,
      p_address_orphans: addressOrphans,
      p_building_orphans: buildingOrphans,
      p_display_mode_hint: hint,
      p_counts: persistedCounts,
      p_layer_fetched_at: layerFetchedAt,
      p_links_status: linksStatus,
      p_built_at: nowIso,
      p_expires_at: expiresAt,
    }));
    if (error) {
      throw new Error(`Failed to persist campaign map bundle: ${error.message}`);
    }

    const persisted = data as Partial<CanonicalCampaignMapBundleResponse> | null;
    return {
      campaign_id: campaignId,
      asset_signature: signature,
      source_version: sourceVersion,
      display_mode_hint: hint,
      links_status: linksStatus,
      addresses: linkedFeatures.addresses,
      buildings: linkedFeatures.buildings,
      parcels,
      roads,
      links,
      address_orphans: addressOrphans,
      building_orphans: buildingOrphans,
      counts,
      layer_fetched_at: layerFetchedAt,
      built_at: normalizedString(persisted?.built_at) ?? nowIso,
      expires_at: normalizedString(persisted?.expires_at) ?? expiresAt,
      updated_at: normalizedString(persisted?.updated_at),
    };
  }

  private async fetchFeatureCollection(rpcName: string, campaignId: string): Promise<FeatureCollection> {
    const { data, error } = await this.supabase.rpc(rpcName, { p_campaign_id: campaignId });
    if (error) {
      console.warn(`[CampaignMapBundle] ${rpcName} failed:`, error.message);
      return { ...EMPTY_FEATURE_COLLECTION };
    }
    return asFeatureCollection(data);
  }

  private async fetchParcelsFeatureCollection(campaignId: string): Promise<ParcelBundleResult> {
    try {
      const resolved = await resolveCampaignParcels(this.supabase, campaignId);
      const suffix = resolved.suppressedReason ? `:${resolved.suppressedReason}` : '';
      return {
        collection: asFeatureCollection(resolved.featureCollection),
        source: `${resolved.source}${suffix}`,
      };
    } catch (error) {
      console.warn(
        '[CampaignMapBundle] Parcel bundle resolution failed:',
        error instanceof Error ? error.message : error
      );
      return {
        collection: { ...EMPTY_FEATURE_COLLECTION },
        source: 'error',
      };
    }
  }

  private async fetchPolishedBuildingCacheMeta(campaignId: string): Promise<PolishedBuildingCacheMeta | null> {
    const { data, error } = await this.supabase
      .from('campaign_polished_building_features')
      .select('feature_count, updated_at')
      .eq('campaign_id', campaignId)
      .maybeSingle();
    if (error) {
      console.warn('[CampaignMapBundle] Polished building cache meta read failed:', error.message);
      return null;
    }

    const row = data as { feature_count?: number | null; updated_at?: string | null } | null;
    const featureCount = numericValue(row?.feature_count, 0);
    if (!row || featureCount <= 0) return null;
    return {
      featureCount,
      updatedAt: normalizedString(row.updated_at),
    };
  }

  private async fetchBuildingsFeatureCollection(campaignId: string): Promise<FeatureCollection> {
    const cached = await this.fetchPolishedBuildingCache(campaignId);
    if (cached.features.length > 0) return cached;

    const materialized = await this.fetchMaterializedCampaignBuildingFeatures(campaignId);
    if (materialized.features.length > 0) return materialized;

    const scopedPmtiles = await this.fetchSnapshotBuildingsGeoJSON(campaignId);
    if (scopedPmtiles.features.length > 0) return scopedPmtiles;

    return this.fetchFeatureCollection('rpc_get_campaign_renderable_buildings', campaignId);
  }

  private async fetchMaterializedCampaignBuildingFeatures(campaignId: string): Promise<FeatureCollection> {
    try {
      const [{ data: rows, error: rowsError }, { data: hiddenRows, error: hiddenError }] = await Promise.all([
        this.supabase
          .from('buildings')
          .select('id, gers_id, geom, height_m, height, latest_status, is_hidden, units_count, addr_housenumber, addr_street')
          .eq('campaign_id', campaignId),
        this.supabase
          .from('campaign_hidden_buildings')
          .select('public_building_id')
          .eq('campaign_id', campaignId),
      ]);

      if (rowsError) {
        console.warn('[CampaignMapBundle] Materialized building read failed:', rowsError.message);
        return { ...EMPTY_FEATURE_COLLECTION };
      }
      if (hiddenError) {
        console.warn('[CampaignMapBundle] Hidden building read failed:', hiddenError.message);
      }

      const hiddenBuildingIds = new Set(
        ((hiddenRows ?? []) as Array<{ public_building_id?: string | null }>)
          .map((row) => normalizedString(row.public_building_id)?.toLowerCase() ?? '')
          .filter((value) => value.length > 0)
      );
      const features = ((rows ?? []) as MaterializedCampaignBuildingRow[])
        .map(materializedBuildingFeature)
        .filter((feature): feature is GeoJSONFeature => {
          if (!feature) return false;
          const identifiers = featureIdentityCandidates(feature, [
            'canonical_building_id',
            'public_building_id',
            'building_id',
            'gers_id',
            'id',
          ]);
          return !identifiers.some((identifier) => hiddenBuildingIds.has(identifier));
        });
      const renderableFeatures = filterRenderableBuildingFeatures(features, 'materialized-buildings');
      if (renderableFeatures.length > 0) {
        console.log(
          `[CampaignMapBundle] Materialized buildings selected for ${campaignId}; features=${renderableFeatures.length}`
        );
      }
      return {
        type: 'FeatureCollection',
        features: renderableFeatures,
      };
    } catch (error) {
      console.warn(
        '[CampaignMapBundle] Materialized building fallback failed:',
        error instanceof Error ? error.message : error
      );
      return { ...EMPTY_FEATURE_COLLECTION };
    }
  }

  private async fetchPolishedBuildingCache(campaignId: string): Promise<FeatureCollection> {
    const { data, error } = await this.supabase
      .from('campaign_polished_building_features')
      .select('feature_collection, feature_count')
      .eq('campaign_id', campaignId)
      .maybeSingle();
    if (error) {
      console.warn('[CampaignMapBundle] Polished building cache read failed:', error.message);
      return { ...EMPTY_FEATURE_COLLECTION };
    }

    const row = data as { feature_collection?: unknown; feature_count?: number | null } | null;
    if (!row || (row.feature_count ?? 0) <= 0) return { ...EMPTY_FEATURE_COLLECTION };
    return withoutAddressProxyBuildings(asFeatureCollection(row.feature_collection));
  }

  private async fetchSnapshotBuildingsGeoJSON(campaignId: string): Promise<FeatureCollection> {
    try {
      const [{ data: campaign, error: campaignError }, { data: snapshot, error: snapshotError }, { data: hiddenRows }] = await Promise.all([
        this.supabase
          .from('campaigns')
          .select('territory_boundary')
          .eq('id', campaignId)
          .maybeSingle(),
        this.supabase
          .from('campaign_snapshots')
          .select('bucket, prefix, buildings_key, addresses_key, buildings_url, metadata_key, buildings_count, created_at, tile_metrics')
          .eq('campaign_id', campaignId)
          .maybeSingle(),
        this.supabase
          .from('campaign_hidden_buildings')
          .select('public_building_id')
          .eq('campaign_id', campaignId),
      ]);

      if (campaignError) {
        console.warn('[CampaignMapBundle] Campaign boundary read failed:', campaignError.message);
        return { ...EMPTY_FEATURE_COLLECTION };
      }
      if (snapshotError) {
        console.warn('[CampaignMapBundle] Campaign snapshot read failed:', snapshotError.message);
        return { ...EMPTY_FEATURE_COLLECTION };
      }

      const snap = snapshot as CampaignSnapshotRow | null;
      if (!snap || !resolvePmtilesKey(snap)) return { ...EMPTY_FEATURE_COLLECTION };

      const boundaryValue = (campaign as { territory_boundary?: unknown } | null)?.territory_boundary ?? null;
      const bbox = bboxFromGeometry(boundaryValue);
      if (!bbox) return { ...EMPTY_FEATURE_COLLECTION };

      const hiddenBuildingIds = new Set(
        ((hiddenRows ?? []) as Array<{ public_building_id?: string | null }>)
          .map((row) => normalizedString(row.public_building_id)?.toLowerCase() ?? '')
          .filter((value) => value.length > 0)
      );

      const featureCollection = await fetchScopedPmtilesBuildingFeatures(
        snap,
        bbox,
        hiddenBuildingIds,
        polygonBoundary(boundaryValue)
      );
      return asFeatureCollection(featureCollection);
    } catch (error) {
      console.warn(
        '[CampaignMapBundle] Scoped PMTiles building GeoJSON failed:',
        error instanceof Error ? error.message : error
      );
      return { ...EMPTY_FEATURE_COLLECTION };
    }
  }

  private async fetchAddressOrphans(campaignId: string): Promise<AddressOrphan[]> {
    const { data, error } = await this.supabase
      .from('address_orphans')
      .select('campaign_id, address_id, reason, nearest_building_id, nearest_distance')
      .eq('campaign_id', campaignId);
    if (error) {
      console.warn('[CampaignMapBundle] Failed to fetch address orphans:', error.message);
      return [];
    }

    return ((data ?? []) as Array<{
      campaign_id?: string | null;
      address_id?: string | null;
      reason?: string | null;
      nearest_building_id?: string | null;
      nearest_distance?: number | string | null;
    }>).flatMap((row) => {
      const addressId = normalizedString(row.address_id);
      const rowCampaignId = normalizedString(row.campaign_id) ?? campaignId;
      const reason = normalizedString(row.reason) as AddressOrphan['reason'] | null;
      if (!addressId || !reason) return [];
      return [{
        campaign_id: rowCampaignId,
        address_id: addressId,
        reason,
        nearest_building_id: normalizedString(row.nearest_building_id),
        nearest_building_distance_m: finiteNumber(row.nearest_distance),
      }];
    });
  }

  private async fetchLinks(campaignId: string): Promise<CampaignMapBundleLink[]> {
    const { data, error } = await this.supabase
      .from('building_address_links')
      .select('id, building_id, address_id, match_type, link_source, confidence, distance_meters, source_version, is_multi_unit, unit_count, building_class')
      .eq('campaign_id', campaignId);
    if (error) {
      console.warn('[CampaignMapBundle] Failed to fetch links:', error.message);
      return [];
    }
    const rawLinks = ((data ?? []) as Array<{
      id: string;
      building_id: string | null;
      address_id: string | null;
      match_type: string | null;
      link_source: string | null;
      confidence: number | null;
      distance_meters: number | null;
      source_version: string | null;
      is_multi_unit: boolean | null;
      unit_count: number | null;
      building_class: string | null;
    }>).flatMap((row) => {
      const buildingId = normalizedString(row.building_id);
      const addressId = normalizedString(row.address_id);
      if (!buildingId || !addressId) return [];
      return [{
        id: normalizedString(row.id) ?? `${buildingId.toLowerCase()}:${addressId.toLowerCase()}`,
        building_id: buildingId,
        address_id: addressId,
        match_type: row.match_type ?? 'auto',
        link_source: row.link_source ?? null,
        confidence: row.confidence ?? 0.5,
        distance_meters: row.distance_meters ?? 0,
        source_version: row.source_version ?? null,
        is_multi_unit: row.is_multi_unit ?? null,
        unit_count: row.unit_count ?? null,
        building_class: row.building_class ?? null,
      }];
    });
    if (rawLinks.length === 0) return [];

    const publicIdsByBuildingRowId = await this.fetchPublicBuildingIdsByRowId(
      campaignId,
      rawLinks.map((link) => link.building_id)
    );
    return normalizeCampaignMapBundleLinksForClient(
      rawLinks,
      publicIdsByBuildingRowId
    );
  }

  private async fetchPublicBuildingIdsByRowId(
    campaignId: string,
    buildingIds: string[]
  ): Promise<Map<string, string>> {
    const rowIds = Array.from(
      new Set(
        buildingIds
          .map((value) => value.trim())
          .filter((value) => value.length > 0 && isUuid(value))
      )
    );
    if (rowIds.length === 0) return new Map();

    const { data, error } = await this.supabase
      .from('buildings')
      .select('id, gers_id')
      .eq('campaign_id', campaignId)
      .in('id', rowIds);
    if (error) {
      console.warn('[CampaignMapBundle] Failed to fetch building public ids:', error.message);
      return new Map();
    }

    return new Map(
      ((data ?? []) as BuildingIdentityRow[]).map((row) => [
        row.id.toLowerCase(),
        normalizedString(row.gers_id) ?? row.id,
      ])
    );
  }
}
