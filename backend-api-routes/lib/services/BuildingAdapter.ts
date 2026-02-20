import {
  type GeoJSONFeatureCollection,
  type GeoJSONFeature,
  type SnapshotResult,
  fetchGeoJSONFromUrl,
} from "./TileLambdaService";

export interface GoldBuildingRow {
  id:                    string;
  source_id?:            string | null;
  external_id?:          string | null;
  area_sqm?:             number | null;
  height_m?:             number | null;
  floors?:               number | null;
  year_built?:           number | null;
  building_type?:        string | null;
  subtype?:              string | null;
  primary_address?:      string | null;
  primary_street_number?:string | null;
  primary_street_name?:  string | null;
  // geometry as parsed GeoJSON (from get_gold_buildings_in_polygon_geojson)
  geometry?:             { type: string; coordinates: unknown } | null;
}

export interface NormalizedBuildingCollection extends GeoJSONFeatureCollection {
  buildingSource: "gold" | "lambda";
  count: number;
}

/**
 * Converts rows from get_gold_buildings_in_polygon_geojson (already a FeatureCollection)
 * into a normalized collection tagged with source: 'gold'.
 * The RPC already returns GeoJSON, so we just parse and re-tag if needed.
 */
export function fromGoldFeatureCollection(
  raw: GeoJSONFeatureCollection
): NormalizedBuildingCollection {
  const features = raw.features.map((f) => ({
    ...f,
    properties: {
      ...f.properties,
      source: "gold",
      height: (f.properties?.height_m as number | null) ?? 10,
      height_m: (f.properties?.height_m as number | null) ?? 10,
      min_height: 0,
    },
  }));

  return {
    type: "FeatureCollection",
    features,
    buildingSource: "gold",
    count: features.length,
  };
}

/**
 * Converts rows (from GoldBuildingRow array, when using manual parsing).
 */
export function fromGoldRows(rows: GoldBuildingRow[]): NormalizedBuildingCollection {
  const features: GeoJSONFeature[] = rows.map((b) => ({
    type: "Feature",
    id: b.id,
    geometry: b.geometry ?? { type: "Point", coordinates: [0, 0] },
    properties: {
      id:             b.id,
      building_id:    b.id,
      source:         "gold",
      area_sqm:       b.area_sqm ?? 0,
      height:         b.height_m ?? 10,
      height_m:       b.height_m ?? 10,
      min_height:     0,
      building_type:  b.building_type ?? null,
      primary_address:b.primary_address ?? null,
    },
  }));

  return {
    type: "FeatureCollection",
    features,
    buildingSource: "gold",
    count: features.length,
  };
}

/**
 * Normalizes Lambda building GeoJSON features, tagging them source: 'lambda'.
 */
export function fromLambdaGeoJSON(
  geojson: GeoJSONFeatureCollection
): NormalizedBuildingCollection {
  const features = geojson.features.map((f) => ({
    ...f,
    id: f.id?.toString() ?? (f.properties?.id as string | undefined),
    properties: {
      ...f.properties,
      source:     "lambda",
      building_id: f.id?.toString() ?? f.properties?.id ?? f.properties?.gers_id,
      height:     (f.properties?.height as number | null) ??
                  (f.properties?.height_m as number | null) ?? 10,
      height_m:   (f.properties?.height_m as number | null) ??
                  (f.properties?.height as number | null) ?? 10,
      min_height: 0,
    },
  }));

  return {
    type: "FeatureCollection",
    features,
    buildingSource: "lambda",
    count: features.length,
  };
}

/**
 * Decides which building source to use and returns normalized collection.
 *
 * @param goldBuildings  Pre-fetched Gold FeatureCollection (from RPC), or null.
 * @param snapshot       Lambda snapshot result with presigned URLs, or null.
 * @param preFetchedLambda Already-downloaded Lambda building GeoJSON, or null.
 */
export async function fetchAndNormalize(
  goldBuildings:    GeoJSONFeatureCollection | null,
  snapshot:         SnapshotResult | null,
  preFetchedLambda: GeoJSONFeatureCollection | null = null
): Promise<NormalizedBuildingCollection> {
  if (goldBuildings && goldBuildings.features.length > 0) {
    return fromGoldFeatureCollection(goldBuildings);
  }

  if (preFetchedLambda) {
    return fromLambdaGeoJSON(preFetchedLambda);
  }

  if (snapshot?.urls.buildings) {
    const lambdaGeo = await fetchGeoJSONFromUrl(snapshot.urls.buildings);
    return fromLambdaGeoJSON(lambdaGeo);
  }

  return {
    type: "FeatureCollection",
    features: [],
    buildingSource: "lambda",
    count: 0,
  };
}
