import { featureCollection, union } from '@turf/turf';

export type ParcelPolygonGeometry = GeoJSON.Polygon | GeoJSON.MultiPolygon;

export type ParcelFragmentFeature = GeoJSON.Feature<ParcelPolygonGeometry, Record<string, unknown>>;

export type ReconstructedParcelFeature = GeoJSON.Feature<ParcelPolygonGeometry, Record<string, unknown>>;

type ParcelFragmentGroup = {
  id: string;
  fragments: ParcelFragmentFeature[];
  properties: Record<string, unknown>;
  include: boolean;
};

function normalizeWrappedLongitude(lon: number): number {
  if (!Number.isFinite(lon) || (lon >= -180 && lon <= 180)) return lon;
  return ((((lon + 180) % 360) + 360) % 360) - 180;
}

function normalizeWrappedPosition(position: number[]): { position: number[]; changed: boolean } {
  const lon = Number(position[0]);
  const normalizedLon = normalizeWrappedLongitude(lon);
  if (normalizedLon === lon) return { position, changed: false };
  return {
    position: [normalizedLon, ...position.slice(1)],
    changed: true,
  };
}

function normalizeWrappedRing(ring: number[][]): { ring: number[][]; changed: boolean } {
  let changed = false;
  const normalized = ring.map((position) => {
    const result = normalizeWrappedPosition(position);
    changed = changed || result.changed;
    return result.position;
  });
  return { ring: changed ? normalized : ring, changed };
}

function normalizeWrappedPolygonCoordinates(
  coordinates: number[][][]
): { coordinates: number[][][]; changed: boolean } {
  let changed = false;
  const normalized = coordinates.map((ring) => {
    const result = normalizeWrappedRing(ring);
    changed = changed || result.changed;
    return result.ring;
  });
  return { coordinates: changed ? normalized : coordinates, changed };
}

export function normalizeWrappedParcelGeometry(geometry: ParcelPolygonGeometry): ParcelPolygonGeometry {
  if (geometry.type === 'Polygon') {
    const result = normalizeWrappedPolygonCoordinates(geometry.coordinates);
    return result.changed ? { type: 'Polygon', coordinates: result.coordinates } : geometry;
  }

  let changed = false;
  const normalized = geometry.coordinates.map((polygon) => {
    const result = normalizeWrappedPolygonCoordinates(polygon);
    changed = changed || result.changed;
    return result.coordinates;
  });
  return changed ? { type: 'MultiPolygon', coordinates: normalized } : geometry;
}

export function polygonalGeometry(geometry: GeoJSON.Geometry | null | undefined): ParcelPolygonGeometry | null {
  if (geometry?.type === 'Polygon' || geometry?.type === 'MultiPolygon') {
    return normalizeWrappedParcelGeometry(geometry);
  }
  return null;
}

function geometryParts(geometry: ParcelPolygonGeometry): number[][][][] {
  return geometry.type === 'Polygon' ? [geometry.coordinates] : geometry.coordinates;
}

function fallbackMultiPolygon(fragments: ParcelFragmentFeature[]): GeoJSON.MultiPolygon | null {
  const coordinates = fragments.flatMap((fragment) => geometryParts(fragment.geometry));
  return coordinates.length > 0 ? { type: 'MultiPolygon', coordinates } : null;
}

function reconstructGeometry(fragments: ParcelFragmentFeature[]): ParcelPolygonGeometry | null {
  if (fragments.length === 0) return null;
  if (fragments.length === 1) return fragments[0].geometry;

  try {
    const merged = union(featureCollection(fragments));
    const geometry = polygonalGeometry(merged?.geometry);
    if (geometry) return geometry;
  } catch {
    // Fall back below. Tile fragments can occasionally be invalid or have tiny gaps.
  }

  return fallbackMultiPolygon(fragments);
}

export function reconstructParcelFragments(
  fragments: Array<{
    id: string;
    geometry: ParcelPolygonGeometry;
    properties?: Record<string, unknown> | null;
    include?: boolean;
  }>
): ReconstructedParcelFeature[] {
  const groups = new Map<string, ParcelFragmentGroup>();

  for (const fragment of fragments) {
    const id = fragment.id.trim();
    if (!id) continue;

    const existing = groups.get(id);
    const feature: ParcelFragmentFeature = {
      type: 'Feature',
      id,
      geometry: fragment.geometry,
      properties: fragment.properties ?? {},
    };

    if (existing) {
      existing.fragments.push(feature);
      existing.include = existing.include || fragment.include !== false;
      existing.properties = {
        ...existing.properties,
        ...(fragment.properties ?? {}),
      };
    } else {
      groups.set(id, {
        id,
        fragments: [feature],
        properties: fragment.properties ?? {},
        include: fragment.include !== false,
      });
    }
  }

  return Array.from(groups.values()).flatMap((group) => {
    if (!group.include) return [];

    const geometry = reconstructGeometry(group.fragments);
    if (!geometry) return [];

    return [{
      type: 'Feature' as const,
      id: group.id,
      geometry,
      properties: {
        ...group.properties,
        parcel_id: group.id,
      },
    }];
  });
}
