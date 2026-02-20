import zlib from "zlib";

const TILE_LAMBDA_URL = process.env.TILE_LAMBDA_URL ?? "";

export interface SnapshotUrls {
  addresses?: string;
  buildings?: string;
  roads?: string;
}

export interface SnapshotKeys {
  addresses_key?: string;
  buildings_key?: string;
  roads_key?: string;
}

export interface SnapshotResult {
  urls:   SnapshotUrls;
  keys:   SnapshotKeys;
  bucket: string;
  addresses_count?: number;
  buildings_count?: number;
}

export interface LambdaParams {
  campaign_id:     string;
  polygon_geojson: string;
  province?:       string;
  address_limit?:  number;
  building_limit?: number;
}

/**
 * Calls the Tile Lambda to generate snapshot GeoJSON files for a polygon.
 * Lambda reads Overture/ODA parquet from the extract bucket, writes
 * gzipped GeoJSON to the snapshot bucket, and returns presigned URLs + S3 keys.
 */
export async function generateSnapshots(
  params: LambdaParams
): Promise<SnapshotResult> {
  if (!TILE_LAMBDA_URL) {
    throw new Error("TILE_LAMBDA_URL env var is not set");
  }

  const response = await fetch(TILE_LAMBDA_URL, {
    method:  "POST",
    headers: { "Content-Type": "application/json" },
    body:    JSON.stringify(params),
  });

  if (!response.ok) {
    const body = await response.text().catch(() => "");
    throw new Error(
      `[TileLambdaService] Lambda returned ${response.status}: ${body}`
    );
  }

  const result: SnapshotResult = await response.json();
  console.log(
    `[TileLambdaService] Snapshot ready: addresses=${result.addresses_count ?? "?"} ` +
    `buildings=${result.buildings_count ?? "?"} bucket=${result.bucket}`
  );
  return result;
}

/**
 * Downloads a presigned S3 URL, gunzips if gzipped, and parses as GeoJSON.
 * Works for both .geojson and .geojson.gz URLs.
 */
export async function fetchGeoJSONFromUrl(url: string): Promise<GeoJSONFeatureCollection> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(
      `[TileLambdaService] Failed to fetch GeoJSON from URL (${response.status}): ${url}`
    );
  }

  const buffer = Buffer.from(await response.arrayBuffer());

  let text: string;
  if (url.includes(".gz") || response.headers.get("content-encoding") === "gzip") {
    text = zlib.gunzipSync(buffer).toString("utf8");
  } else {
    text = buffer.toString("utf8");
  }

  return JSON.parse(text) as GeoJSONFeatureCollection;
}

export interface GeoJSONFeature {
  type:       "Feature";
  id?:        string | number;
  geometry:   { type: string; coordinates: unknown };
  properties: Record<string, unknown> | null;
}

export interface GeoJSONFeatureCollection {
  type:     "FeatureCollection";
  features: GeoJSONFeature[];
}
