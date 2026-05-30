import * as turf from '@turf/turf';
import { isLinkableBuildingFootprint } from '@/lib/geo/buildingFootprintFilter';

export const PROVISION_TIMINGS_VERSION = 1;
export const DEFAULT_SPATIAL_BUCKET_DEGREES = 0.001;

export type ProvisionTimingSnapshot = {
  version: number;
  total_ms: number;
  stages: Record<string, number>;
  linker: Record<string, number>;
  counts: Record<string, number>;
  source_scan_metrics?: unknown;
  updated_at: string;
};

export class ProvisionTimingRecorder {
  private readonly startedAt = Date.now();
  private readonly stages: Record<string, number> = {};
  private readonly linker: Record<string, number> = {};
  private readonly counts: Record<string, number> = {};
  private sourceScanMetrics: unknown;

  async measure<T>(
    name: string,
    fn: () => Promise<T>,
    bucket: 'stages' | 'linker' = 'stages'
  ): Promise<T> {
    const startedAt = Date.now();
    try {
      return await fn();
    } finally {
      this.record(name, Date.now() - startedAt, bucket);
    }
  }

  measureSync<T>(
    name: string,
    fn: () => T,
    bucket: 'stages' | 'linker' = 'stages'
  ): T {
    const startedAt = Date.now();
    try {
      return fn();
    } finally {
      this.record(name, Date.now() - startedAt, bucket);
    }
  }

  record(name: string, elapsedMs: number, bucket: 'stages' | 'linker' = 'stages'): void {
    const target = bucket === 'linker' ? this.linker : this.stages;
    target[name] = Math.max(0, Math.round(elapsedMs));
  }

  count(name: string, value: number): void {
    if (Number.isFinite(value)) {
      this.counts[name] = Math.round(value);
    }
  }

  sourceMetrics(metrics: unknown): void {
    this.sourceScanMetrics = metrics;
  }

  snapshot(): ProvisionTimingSnapshot {
    return {
      version: PROVISION_TIMINGS_VERSION,
      total_ms: Math.max(0, Math.round(Date.now() - this.startedAt)),
      stages: { ...this.stages },
      linker: { ...this.linker },
      counts: { ...this.counts },
      ...(this.sourceScanMetrics ? { source_scan_metrics: this.sourceScanMetrics } : {}),
      updated_at: new Date().toISOString(),
    };
  }
}

export type LinkerAddressRow = {
  id: string;
  coordinate?: { lon?: unknown; lat?: unknown } | null;
  geom?: GeoJSON.Point | null;
  street_match_score?: unknown;
  house_number_score?: unknown;
  match_score?: unknown;
  score?: unknown;
};

export type LinkerBuildingRow = {
  id: string;
  gers_id?: string | null;
  geom?: GeoJSON.Polygon | GeoJSON.MultiPolygon | null;
  height_m?: number | null;
  units_count?: number | null;
  unit_count?: number | null;
  building_class?: string | null;
  building_type?: string | null;
  subtype?: string | null;
  class?: string | null;
  feature_type?: string | null;
  type?: string | null;
  is_townhome_row?: boolean | null;
  is_multi_unit?: boolean | null;
};

export type LinkerParcelRow = {
  id?: string | null;
  externalId?: string | null;
  geometry?: GeoJSON.Polygon | GeoJSON.MultiPolygon | null;
  geom?: GeoJSON.Polygon | GeoJSON.MultiPolygon | null;
};

export type AutoBuildingLinkRow = {
  campaign_id: string;
  address_id: string;
  building_id: string;
  match_type: string;
  link_source: string;
  confidence: number;
  distance_meters: number;
  building_height: number | null;
  source_version?: string | null;
};

export type AddressOrphanReason =
  | 'no_containment'
  | 'no_parcel'
  | 'proximity_too_far'
  | 'proximity_ambiguous';

export type AddressOrphanLinkerRow = {
  address_id: string;
  campaign_id: string;
  reason: AddressOrphanReason;
  nearest_building_id: string | null;
  nearest_building_distance_m: number | null;
};

export type CanonicalBuildingLinkResult = {
  links: AutoBuildingLinkRow[];
  address_orphans: AddressOrphanLinkerRow[];
};

export type AutoParcelAddressLinkRow = {
  campaign_id: string;
  parcel_id: string;
  address_id: string;
  match_type: string;
  link_source: 'auto' | 'manual';
  confidence: number;
};

type PreparedBuilding = {
  id: string;
  height_m: number | null;
  units_count: number | null;
  is_townhome: boolean;
  is_multi_unit: boolean;
  geom: GeoJSON.Polygon | GeoJSON.MultiPolygon;
  bbox: [number, number, number, number];
};

type PreparedParcel = {
  id: string | null;
  externalId: string | null;
  geom: GeoJSON.Polygon | GeoJSON.MultiPolygon;
  bbox: [number, number, number, number];
  areaSqm: number;
};

function stripGeometryCrs<T extends GeoJSON.Geometry | null | undefined>(geometry: T): T {
  if (!geometry || typeof geometry !== 'object') return geometry;
  const { crs: _crs, ...cleanGeometry } = geometry as T & { crs?: unknown };
  return cleanGeometry as T;
}

export function addressPointCoordinates(address: LinkerAddressRow): [number, number] | null {
  const lon = Number(address.coordinate?.lon);
  const lat = Number(address.coordinate?.lat);
  if (Number.isFinite(lon) && Number.isFinite(lat)) {
    return [lon, lat];
  }

  const geom = stripGeometryCrs(address.geom);
  if (geom?.type !== 'Point' || !Array.isArray(geom.coordinates)) return null;

  const geomLon = Number(geom.coordinates[0]);
  const geomLat = Number(geom.coordinates[1]);
  return Number.isFinite(geomLon) && Number.isFinite(geomLat)
    ? [geomLon, geomLat]
    : null;
}

function bboxMayBeNearPoint(
  point: [number, number],
  bbox: [number, number, number, number],
  padMeters: number
): boolean {
  const [lon, lat] = point;
  const cosLat = Math.max(Math.cos((lat * Math.PI) / 180), 0.000001);
  const lonPad = padMeters / (111_320 * cosLat);
  const latPad = padMeters / 110_540;

  return bbox[0] <= lon + lonPad &&
    bbox[2] >= lon - lonPad &&
    bbox[1] <= lat + latPad &&
    bbox[3] >= lat - latPad;
}

function stringProperty(value: unknown): string | null {
  return typeof value === 'string' && value.trim().length > 0 ? value.trim() : null;
}

export function buildingFeatureIdentity(feature: GeoJSON.Feature): string | null {
  const properties = feature.properties && typeof feature.properties === 'object'
    ? feature.properties as Record<string, unknown>
    : {};

  return stringProperty(properties.gers_id) ??
    stringProperty(properties.building_id) ??
    stringProperty(properties.public_building_id) ??
    stringProperty(properties.canonical_building_id) ??
    stringProperty(properties.id) ??
    stringProperty(feature.id);
}

function numberProperty(value: unknown): number {
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function optionalNumberProperty(value: unknown): number | null {
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function booleanProperty(value: unknown): boolean {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'string') {
    return value.toLowerCase() === 'true' || value === '1';
  }
  return value === 1;
}

function addressContainmentScore(address: LinkerAddressRow): number | null {
  return optionalNumberProperty(address.house_number_score) ??
    optionalNumberProperty(address.street_match_score) ??
    optionalNumberProperty(address.match_score) ??
    optionalNumberProperty(address.score);
}

function buildingUnitsCount(
  row: LinkerBuildingRow | null | undefined,
  properties: Record<string, unknown> = {}
): number | null {
  const parsed = optionalNumberProperty(
    properties.units_count ??
    properties.unit_count ??
    row?.units_count ??
    row?.unit_count
  );
  return parsed && parsed > 0 ? Math.round(parsed) : null;
}

function buildingIsTownhome(
  row: LinkerBuildingRow | null | undefined,
  properties: Record<string, unknown> = {}
): boolean {
  const className = stringProperty(properties.building_class) ?? stringProperty(row?.building_class);
  return Boolean(row?.is_townhome_row) ||
    booleanProperty(properties.is_townhome) ||
    booleanProperty(properties.is_townhome_row) ||
    className === 'townhouse' ||
    className === 'townhome';
}

function buildingIsMultiUnit(
  row: LinkerBuildingRow | null | undefined,
  unitsCount: number | null,
  properties: Record<string, unknown> = {}
): boolean {
  return Boolean(row?.is_multi_unit) ||
    booleanProperty(properties.is_multi_unit) ||
    buildingIsTownhome(row, properties) ||
    (unitsCount ?? 0) > 1;
}

function buildingFilterProperties(
  row: LinkerBuildingRow | null | undefined,
  geometry: GeoJSON.Polygon | GeoJSON.MultiPolygon,
  properties: Record<string, unknown> = {}
): Record<string, unknown> {
  return {
    ...properties,
    area_sqm: properties.area_sqm ?? properties.area ?? turf.area(turf.feature(geometry)),
    building_class: properties.building_class ?? row?.building_class,
    building_type: properties.building_type ?? row?.building_type,
    subtype: properties.subtype ?? row?.subtype,
    class: properties.class ?? row?.class,
    feature_type: properties.feature_type ?? row?.feature_type,
    type: properties.type ?? row?.type,
  };
}

function prepareBuildingsFromMemory(params: {
  materializedBuildings: LinkerBuildingRow[];
  sourceBuildings: GeoJSON.Feature[];
}): PreparedBuilding[] {
  const buildingIdByGersId = new Map<string, LinkerBuildingRow>();
  for (const building of params.materializedBuildings) {
    const gersId = stringProperty(building.gers_id);
    if (gersId) buildingIdByGersId.set(gersId.toLowerCase(), building);
  }

  return params.sourceBuildings.flatMap((feature) => {
    const gersId = buildingFeatureIdentity(feature);
    if (!gersId) return [];

    const materialized = buildingIdByGersId.get(gersId.toLowerCase());
    if (!materialized) return [];

    const geometry = stripGeometryCrs(feature.geometry);
    if (geometry?.type !== 'Polygon' && geometry?.type !== 'MultiPolygon') return [];

    const properties = feature.properties && typeof feature.properties === 'object'
      ? feature.properties as Record<string, unknown>
      : {};
    if (!isLinkableBuildingFootprint({
      geometry,
      properties: buildingFilterProperties(materialized, geometry, properties),
    })) {
      return [];
    }

    const height = numberProperty(properties.height_m ?? properties.height ?? materialized.height_m);

    return [{
      id: materialized.id,
      height_m: Number.isFinite(height) && height > 0 ? height : materialized.height_m ?? null,
      units_count: buildingUnitsCount(materialized, properties),
      is_townhome: buildingIsTownhome(materialized, properties),
      is_multi_unit: buildingIsMultiUnit(materialized, buildingUnitsCount(materialized, properties), properties),
      geom: geometry,
      bbox: turf.bbox(turf.feature(geometry)) as [number, number, number, number],
    }];
  });
}

export function prepareBuildingsFromRows(buildingRows: LinkerBuildingRow[]): PreparedBuilding[] {
  return buildingRows.flatMap((building) => {
    const geometry = stripGeometryCrs(building.geom);
    if (geometry?.type !== 'Polygon' && geometry?.type !== 'MultiPolygon') return [];
    if (!isLinkableBuildingFootprint({
      geometry,
      properties: buildingFilterProperties(building, geometry),
    })) {
      return [];
    }

    const unitsCount = buildingUnitsCount(building);
    return [{
      id: building.id,
      height_m: building.height_m ?? null,
      units_count: unitsCount,
      is_townhome: buildingIsTownhome(building),
      is_multi_unit: buildingIsMultiUnit(building, unitsCount),
      geom: geometry,
      bbox: turf.bbox(turf.feature(geometry)) as [number, number, number, number],
    }];
  });
}

function prepareParcelsFromRows(parcelRows: LinkerParcelRow[]): PreparedParcel[] {
  return parcelRows.flatMap((parcel) => {
    const geometry = stripGeometryCrs(parcel.geometry ?? parcel.geom);
    if (geometry?.type !== 'Polygon' && geometry?.type !== 'MultiPolygon') return [];
    const feature = turf.feature(geometry);
    return [{
      id: stringProperty(parcel.id),
      externalId: stringProperty(parcel.externalId),
      geom: geometry,
      bbox: turf.bbox(feature) as [number, number, number, number],
      areaSqm: Math.max(0, turf.area(feature)),
    }];
  });
}

function bboxIntersects(
  a: [number, number, number, number],
  b: [number, number, number, number]
): boolean {
  return !(a[2] < b[0] || a[0] > b[2] || a[3] < b[1] || a[1] > b[3]);
}

function bucketKey(x: number, y: number): string {
  return `${x},${y}`;
}

function bucketIndex(value: number, bucketDegrees: number): number {
  return Math.floor(value / bucketDegrees);
}

function paddedBbox(
  bbox: [number, number, number, number],
  padMeters: number
): [number, number, number, number] {
  const centerLat = (bbox[1] + bbox[3]) / 2;
  const cosLat = Math.max(Math.cos((centerLat * Math.PI) / 180), 0.000001);
  const lonPad = padMeters / (111_320 * cosLat);
  const latPad = padMeters / 110_540;
  return [bbox[0] - lonPad, bbox[1] - latPad, bbox[2] + lonPad, bbox[3] + latPad];
}

function buildSpatialBuckets(
  buildings: PreparedBuilding[],
  bucketDegrees: number,
  distanceMeters: number
): Map<string, PreparedBuilding[]> {
  const buckets = new Map<string, PreparedBuilding[]>();
  for (const building of buildings) {
    const bbox = paddedBbox(building.bbox, distanceMeters);
    const minX = bucketIndex(bbox[0], bucketDegrees);
    const maxX = bucketIndex(bbox[2], bucketDegrees);
    const minY = bucketIndex(bbox[1], bucketDegrees);
    const maxY = bucketIndex(bbox[3], bucketDegrees);

    for (let x = minX; x <= maxX; x += 1) {
      for (let y = minY; y <= maxY; y += 1) {
        const key = bucketKey(x, y);
        const bucket = buckets.get(key);
        if (bucket) {
          bucket.push(building);
        } else {
          buckets.set(key, [building]);
        }
      }
    }
  }
  return buckets;
}

function nearbyBucketBuildings(
  coordinates: [number, number],
  buckets: Map<string, PreparedBuilding[]>,
  bucketDegrees: number
): PreparedBuilding[] {
  const x = bucketIndex(coordinates[0], bucketDegrees);
  const y = bucketIndex(coordinates[1], bucketDegrees);
  const candidates: PreparedBuilding[] = [];
  const seen = new Set<string>();

  for (let dx = -1; dx <= 1; dx += 1) {
    for (let dy = -1; dy <= 1; dy += 1) {
      for (const building of buckets.get(bucketKey(x + dx, y + dy)) ?? []) {
        if (seen.has(building.id)) continue;
        seen.add(building.id);
        candidates.push(building);
      }
    }
  }

  return candidates;
}

function bucketBuildingsForBbox(
  bbox: [number, number, number, number],
  buckets: Map<string, PreparedBuilding[]>,
  bucketDegrees: number
): PreparedBuilding[] {
  const minX = bucketIndex(bbox[0], bucketDegrees);
  const maxX = bucketIndex(bbox[2], bucketDegrees);
  const minY = bucketIndex(bbox[1], bucketDegrees);
  const maxY = bucketIndex(bbox[3], bucketDegrees);
  const candidates: PreparedBuilding[] = [];
  const seen = new Set<string>();

  for (let x = minX; x <= maxX; x += 1) {
    for (let y = minY; y <= maxY; y += 1) {
      for (const building of buckets.get(bucketKey(x, y)) ?? []) {
        if (seen.has(building.id)) continue;
        seen.add(building.id);
        candidates.push(building);
      }
    }
  }

  return candidates;
}

function findNearestBuilding(
  coordinates: [number, number],
  point: GeoJSON.Feature<GeoJSON.Point>,
  buildings: PreparedBuilding[],
  distanceMeters: number
): { building: PreparedBuilding; distanceMeters: number } | null {
  let best: { building: PreparedBuilding; distanceMeters: number } | null = null;

  for (const building of buildings) {
    if (!bboxMayBeNearPoint(coordinates, building.bbox, distanceMeters + 10)) {
      continue;
    }

    const measuredDistanceMeters = turf.pointToPolygonDistance(
      point,
      turf.feature(building.geom),
      { units: 'kilometers' }
    ) * 1000;

    if (
      measuredDistanceMeters <= distanceMeters &&
      (!best || measuredDistanceMeters < best.distanceMeters)
    ) {
      best = { building, distanceMeters: measuredDistanceMeters };
    }
  }

  return best;
}

function rankNearestBuildings(
  coordinates: [number, number],
  point: GeoJSON.Feature<GeoJSON.Point>,
  buildings: PreparedBuilding[],
  searchMeters: number
): { building: PreparedBuilding; distanceMeters: number }[] {
  const ranked: { building: PreparedBuilding; distanceMeters: number }[] = [];

  for (const building of buildings) {
    if (!bboxMayBeNearPoint(coordinates, building.bbox, searchMeters + 10)) {
      continue;
    }

    const measuredDistanceMeters = turf.pointToPolygonDistance(
      point,
      turf.feature(building.geom),
      { units: 'kilometers' }
    ) * 1000;

    ranked.push({ building, distanceMeters: measuredDistanceMeters });
  }

  ranked.sort((a, b) => a.distanceMeters - b.distanceMeters);
  return ranked;
}

function findSmallestContainingParcel(
  point: GeoJSON.Feature<GeoJSON.Point>,
  parcels: PreparedParcel[]
): PreparedParcel | null {
  let best: PreparedParcel | null = null;
  for (const parcel of parcels) {
    try {
      if (!turf.booleanPointInPolygon(point, turf.feature(parcel.geom))) continue;
    } catch {
      continue;
    }
    if (!best || parcel.areaSqm < best.areaSqm) {
      best = parcel;
    }
  }
  return best;
}

function findContainingBuilding(
  point: GeoJSON.Feature<GeoJSON.Point>,
  buildings: PreparedBuilding[]
): PreparedBuilding | null {
  let best: PreparedBuilding | null = null;
  let bestArea = Number.POSITIVE_INFINITY;

  for (const building of buildings) {
    const coordinates = point.geometry.coordinates as [number, number];
    if (!bboxIntersects(
      [coordinates[0], coordinates[1], coordinates[0], coordinates[1]],
      building.bbox
    )) {
      continue;
    }

    try {
      if (!turf.booleanPointInPolygon(point, turf.feature(building.geom))) {
        continue;
      }
    } catch {
      continue;
    }

    const area = Math.max(0, turf.area(turf.feature(building.geom)));
    if (!best || area < bestArea) {
      best = building;
      bestArea = area;
    }
  }

  return best;
}

function findNearestBuildingOnParcel(
  point: GeoJSON.Feature<GeoJSON.Point>,
  parcel: PreparedParcel,
  buildings: PreparedBuilding[]
): { building: PreparedBuilding; distanceMeters: number } | null {
  let best: { building: PreparedBuilding; distanceMeters: number } | null = null;
  const parcelFeature = turf.feature(parcel.geom);

  for (const building of buildings) {
    if (!bboxIntersects(building.bbox, parcel.bbox)) continue;

    try {
      if (!turf.booleanIntersects(turf.feature(building.geom), parcelFeature)) {
        continue;
      }
    } catch {
      continue;
    }

    const distanceMeters = turf.pointToPolygonDistance(
      point,
      turf.feature(building.geom),
      { units: 'kilometers' }
    ) * 1000;

    if (!best || distanceMeters < best.distanceMeters) {
      best = { building, distanceMeters };
    }
  }

  return best;
}

export function buildParcelAddressLinksFromPreparedRows(params: {
  campaignId: string;
  addresses: LinkerAddressRow[];
  parcels?: LinkerParcelRow[];
}): AutoParcelAddressLinkRow[] {
  const parcels = params.parcels?.length ? prepareParcelsFromRows(params.parcels) : [];
  if (parcels.length === 0) return [];

  const links: AutoParcelAddressLinkRow[] = [];
  for (const address of params.addresses) {
    const coordinates = addressPointCoordinates(address);
    if (!coordinates) continue;

    const parcel = findSmallestContainingParcel(turf.point(coordinates), parcels);
    if (!parcel?.id) continue;

    links.push({
      campaign_id: params.campaignId,
      parcel_id: parcel.id,
      address_id: address.id,
      match_type: 'centroid_in_parcel',
      link_source: 'auto',
      confidence: 0.9,
    });
  }

  return links;
}

export function buildAutoBuildingLinksFromPreparedRows(params: {
  campaignId: string;
  addresses: LinkerAddressRow[];
  buildings: PreparedBuilding[];
  parcels?: LinkerParcelRow[];
  distanceMeters?: number;
  bucketDegrees?: number;
  useSpatialBuckets?: boolean;
  sourceVersion?: string | null;
  claimedSingleUnitBuildingIds?: Set<string>;
}): AutoBuildingLinkRow[] {
  return buildCanonicalBuildingLinksFromPreparedRows(params).links;
}

export function buildCanonicalBuildingLinksFromPreparedRows(params: {
  campaignId: string;
  addresses: LinkerAddressRow[];
  buildings: PreparedBuilding[];
  parcels?: LinkerParcelRow[];
  distanceMeters?: number;
  bucketDegrees?: number;
  useSpatialBuckets?: boolean;
  sourceVersion?: string | null;
  claimedSingleUnitBuildingIds?: Set<string>;
}): CanonicalBuildingLinkResult {
  const distanceMeters = params.distanceMeters ?? 15;
  const disambiguationGapMeters = 3;
  const bucketDegrees = params.bucketDegrees ?? DEFAULT_SPATIAL_BUCKET_DEGREES;
  const buckets = params.useSpatialBuckets === false
    ? null
    : buildSpatialBuckets(params.buildings, bucketDegrees, distanceMeters + disambiguationGapMeters);
  const parcels = params.parcels?.length ? prepareParcelsFromRows(params.parcels) : [];
  const claimedSingleUnitBuildingIds = params.claimedSingleUnitBuildingIds ?? new Set<string>();

  const links: AutoBuildingLinkRow[] = [];
  const addressOrphans: AddressOrphanLinkerRow[] = [];

  const pushLink = (address: LinkerAddressRow, building: PreparedBuilding, values: {
    match_type: string;
    link_source: string;
    confidence: number;
    distance_meters: number;
  }) => {
    links.push({
      campaign_id: params.campaignId,
      address_id: address.id,
      building_id: building.id,
      match_type: values.match_type,
      link_source: values.link_source,
      confidence: values.confidence,
      distance_meters: values.distance_meters,
      building_height: building.height_m ?? null,
      source_version: params.sourceVersion ?? null,
    });

    if (!building.is_multi_unit && !building.is_townhome && (building.units_count ?? 1) <= 1) {
      claimedSingleUnitBuildingIds.add(building.id);
    }
  };

  const pushOrphan = (
    address: LinkerAddressRow,
    reason: AddressOrphanReason,
    nearest: { building: PreparedBuilding; distanceMeters: number } | null
  ) => {
    addressOrphans.push({
      campaign_id: params.campaignId,
      address_id: address.id,
      reason,
      nearest_building_id: nearest?.building.id ?? null,
      nearest_building_distance_m: nearest ? Number(nearest.distanceMeters.toFixed(2)) : null,
    });
  };

  for (const address of params.addresses) {
    const coordinates = addressPointCoordinates(address);
    if (!coordinates) continue;

    const point = turf.point(coordinates);
    const candidateBuildings = buckets
      ? nearbyBucketBuildings(coordinates, buckets, bucketDegrees)
      : params.buildings;
    const containingBuilding = findContainingBuilding(point, candidateBuildings);
    const containmentScore = addressContainmentScore(address);
    const containmentRejectedByScore = Boolean(
      containingBuilding && containmentScore !== null && containmentScore < 0.4
    );
    if (containingBuilding && (containmentScore === null || containmentScore >= 0.4)) {
      pushLink(address, containingBuilding, {
        match_type: 'containment_verified',
        link_source: 'auto',
        confidence: 1,
        distance_meters: 0,
      });
      continue;
    }

    const parcel = parcels.length > 0 ? findSmallestContainingParcel(point, parcels) : null;
    const parcelCandidateBuildings = parcel && buckets
      ? bucketBuildingsForBbox(parcel.bbox, buckets, bucketDegrees)
      : params.buildings;
    const parcelBest = parcel ? findNearestBuildingOnParcel(
      point,
      parcel,
      parcelCandidateBuildings.length > 0 ? parcelCandidateBuildings : params.buildings
    ) : null;
    if (parcelBest) {
      pushLink(address, parcelBest.building, {
        match_type: 'parcel_bridge',
        link_source: 'auto_parcel',
        confidence: 0.9,
        distance_meters: parcelBest.distanceMeters,
      });
      continue;
    }

    const rankedBuildings = rankNearestBuildings(
      coordinates,
      point,
      candidateBuildings,
      Math.max(distanceMeters + disambiguationGapMeters, 60)
    );
    const best = rankedBuildings[0] ?? null;
    const nextBest = rankedBuildings[1] ?? null;
    if (!best) {
      const reason: AddressOrphanReason = containmentRejectedByScore
        ? 'no_containment'
        : (parcels.length === 0 ? 'no_parcel' : 'proximity_too_far');
      pushOrphan(address, reason, null);
      continue;
    }

    if (best.distanceMeters > distanceMeters) {
      pushOrphan(address, 'proximity_too_far', best);
      continue;
    }

    if (nextBest && (nextBest.distanceMeters - best.distanceMeters) < disambiguationGapMeters) {
      pushOrphan(address, 'proximity_ambiguous', best);
      continue;
    }

    const bestCanAcceptMultiple = best.building.is_multi_unit ||
      best.building.is_townhome ||
      (best.building.units_count ?? 1) > 1;
    if (!bestCanAcceptMultiple && claimedSingleUnitBuildingIds.has(best.building.id)) {
      pushOrphan(address, 'proximity_ambiguous', best);
      continue;
    }

    if (best) {
      pushLink(address, best.building, {
        match_type: 'nearest_building_15m',
        link_source: 'auto',
        confidence: Math.max(0, Math.min(1, 1 - best.distanceMeters / distanceMeters)),
        distance_meters: best.distanceMeters,
      });
      continue;
    }
  }

  return {
    links,
    address_orphans: addressOrphans,
  };
}

export function buildAutoBuildingLinksFromMemory(params: {
  campaignId: string;
  addresses: LinkerAddressRow[];
  materializedBuildings: LinkerBuildingRow[];
  sourceBuildings: GeoJSON.Feature[];
  parcels?: LinkerParcelRow[];
  distanceMeters?: number;
  bucketDegrees?: number;
  useSpatialBuckets?: boolean;
  sourceVersion?: string | null;
  claimedSingleUnitBuildingIds?: Set<string>;
}): AutoBuildingLinkRow[] {
  return buildCanonicalBuildingLinksFromMemory(params).links;
}

export function buildCanonicalBuildingLinksFromMemory(params: {
  campaignId: string;
  addresses: LinkerAddressRow[];
  materializedBuildings: LinkerBuildingRow[];
  sourceBuildings: GeoJSON.Feature[];
  parcels?: LinkerParcelRow[];
  distanceMeters?: number;
  bucketDegrees?: number;
  useSpatialBuckets?: boolean;
  sourceVersion?: string | null;
  claimedSingleUnitBuildingIds?: Set<string>;
}): CanonicalBuildingLinkResult {
  return buildCanonicalBuildingLinksFromPreparedRows({
    campaignId: params.campaignId,
    addresses: params.addresses,
    buildings: prepareBuildingsFromMemory({
      materializedBuildings: params.materializedBuildings,
      sourceBuildings: params.sourceBuildings,
    }),
    parcels: params.parcels,
    distanceMeters: params.distanceMeters,
    bucketDegrees: params.bucketDegrees,
    useSpatialBuckets: params.useSpatialBuckets,
    sourceVersion: params.sourceVersion,
    claimedSingleUnitBuildingIds: params.claimedSingleUnitBuildingIds,
  });
}
