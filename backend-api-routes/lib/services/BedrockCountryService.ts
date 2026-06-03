import { GetObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { defaultProvider } from '@aws-sdk/credential-provider-node';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { VectorTile } from '@mapbox/vector-tile';
import * as turf from '@turf/turf';
import { PMTiles } from 'pmtiles';
import Pbf from 'pbf';
import {
  polygonalGeometry,
  reconstructParcelFragments,
} from '@/lib/geo/parcelFragments';
import { isResidentialParcelFeature } from '@/lib/geo/parcelFilters';
import type { LambdaSnapshotResponse } from '@/lib/services/TileLambdaService';
import type { StandardCampaignAddress } from '@/lib/services/AddressAdapter';
import {
  canonicalBedrockAddressExternalId,
  isStreetOnlyOrdinalAddressLabel,
  isUsableHouseNumberAddressLabel,
  normalizedAddressDisplayIdentity,
  normalizedAddressPart,
} from '@/lib/services/AddressDisplayIdentity';

type Bounds = [number, number, number, number];
type SnapshotTileMetrics = NonNullable<NonNullable<LambdaSnapshotResponse['metadata']>['tile_metrics']>;
type BedrockLayer = 'addresses' | 'buildings' | 'parcels';

export type BedrockProvisionSource =
  | 'bedrock_nz'
  | 'bedrock_au'
  | 'bedrock_ca'
  | 'bedrock_us'
  | 'bedrock_za'
  | 'bedrock_uk';

type BedrockCountryConfig = {
  country: 'new-zealand' | 'australia' | 'canada' | 'usa' | 'south-africa' | 'uk';
  countryCode: 'NZ' | 'AU' | 'CA' | 'US' | 'ZA' | 'GB';
  provisionSource: BedrockProvisionSource;
  envPrefix: 'BEDROCK_NZ' | 'BEDROCK_AU' | 'BEDROCK_CA' | 'BEDROCK_US' | 'BEDROCK_ZA' | 'BEDROCK_UK';
  defaultSource: string;
  overtureRelease: string;
  buildingPrefix?: string;
  coordinateColumns?: {
    longitude: string;
    latitude: string;
  };
  singleFileSpatialParquetLayers?: BedrockLayer[];
  geojsonExtension?: 'ndjson.gz' | 'geojson.gz';
  metadataFilename?: string;
};

type ParquetManifest = {
  feature_count?: number;
  partitioning?: { scheme?: string; tile_z?: number };
  tile_seam_awareness?: { enabled?: boolean; tile_padding?: number; tile_z?: number; reason?: string };
  tile_counts?: Array<{ tile_z: number; tile_x: number; tile_y: number; feature_count: number }>;
  state_counts?: Array<{ state: string; feature_count?: number; path: string }>;
  single_file_key?: string;
};

type BedrockParquetRow = Record<string, unknown> & {
  address_id?: string;
  gers_id?: string;
  source_id?: string;
  address_detail_pid?: string;
  uprn?: string;
  full_address?: string;
  formatted?: string;
  house_number?: string;
  house_number_label?: string;
  number_first?: string;
  street_number?: string;
  street_name?: string;
  street_type?: string;
  locality?: string;
  locality_name?: string;
  city?: string;
  region?: string;
  state?: string;
  postal_code?: string;
  postcode?: string;
  longitude?: number;
  latitude?: number;
  lon?: number;
  lat?: number;
  geometry_json?: string;
  geometry_geojson?: string;
  properties_json?: string;
};

type BedrockScanResult = {
  hits: number;
  scanned: number;
  bboxCandidates: number;
  seconds: number;
  queryEngine: 'duckdb_parquet' | 'pmtiles_vector';
  touchedTiles: number;
  partitioning?: string;
  tilePadding?: number;
  timings: {
    manifestMs: number;
    partitionMs: number;
    queryMs: number;
    filterMs: number;
    totalMs: number;
    duckdb_setup_ms?: number;
    duckdb_extension_ms?: number;
    duckdb_credentials_ms?: number;
    duckdb_query_ms?: number;
    manifest_cache_hit?: boolean;
  };
};

type ManifestReadResult = {
  manifest: ParquetManifest;
  manifestMs: number;
  cacheHit: boolean;
};

type DuckDbTimings = {
  duckdb_setup_ms: number;
  duckdb_extension_ms: number;
  duckdb_credentials_ms: number;
  duckdb_query_ms: number;
};

type PmtilesAddressFeature = {
  type: 'Feature';
  geometry?: {
    type: 'Point';
    coordinates?: [number, number];
  };
  properties?: Record<string, unknown>;
  id?: string | number;
};

type BedrockScopedBuildingFeature = GeoJSON.Feature<
  GeoJSON.Polygon | GeoJSON.MultiPolygon,
  {
    gers_id: string;
    building_id: string;
    name: string | null;
    height: number | null;
    layer: 'building';
    source?: string | null;
    [key: string]: unknown;
  }
>;

type PmtilesParcelFeature = GeoJSON.Feature<GeoJSON.Geometry, Record<string, unknown>>;

type BedrockScopedParcelFeature = {
  externalId: string;
  geometry: GeoJSON.MultiPolygon;
  properties?: Record<string, unknown>;
};

const DEFAULT_BUCKET = 'flyr-pro-addresses-2025';
const REGION = process.env.AWS_REGION || process.env.AWS_S3_BUCKET_REGION || 'us-east-2';
const WEB_MERCATOR_MAX_LAT = 85.05112878;
const USA_FULL_PMTILES_REGIONS = new Set([
  'AK',
  'AL',
  'AR',
  'AZ',
  'CA',
  'CO',
  'CT',
  'DC',
  'DE',
  'FL',
  'GA',
  'HI',
  'IA',
  'ID',
  'IL',
  'IN',
  'KS',
  'KY',
  'LA',
  'MA',
  'MD',
  'ME',
  'MI',
  'MN',
  'MO',
  'MS',
  'MT',
  'NC',
  'ND',
  'NE',
  'NH',
  'NJ',
  'NM',
  'NV',
  'NY',
  'OH',
  'OK',
  'OR',
  'PA',
  'RI',
  'SC',
  'SD',
  'TN',
  'TX',
  'UT',
  'VA',
  'VT',
  'WA',
  'WI',
  'WV',
  'WY',
]);
const USA_ADDRESS_REGIONS = new Set([...USA_FULL_PMTILES_REGIONS, 'PR', 'VI']);
const USA_BUILDING_REGIONS = USA_FULL_PMTILES_REGIONS;
const USA_PARCEL_REGIONS = USA_FULL_PMTILES_REGIONS;

export function isBedrockUsFullPmtilesRegion(regionCode: string | null | undefined): boolean {
  const normalized = regionCode?.trim().toUpperCase();
  return Boolean(normalized && USA_FULL_PMTILES_REGIONS.has(normalized));
}

let s3Client: S3Client | null = null;
let resolvedAwsCredentials:
  | { accessKeyId: string; secretAccessKey: string; sessionToken?: string; expiresAt?: number }
  | null = null;
let awsCredentialsPromise:
  | Promise<{ accessKeyId: string; secretAccessKey: string; sessionToken?: string; expiresAt?: number }>
  | null = null;
let duckdbModulePromise: Promise<typeof import('duckdb')> | null = null;
let httpfsInstallPromise: Promise<void> | null = null;
let httpfsInstalled = false;

const AWS_CREDENTIAL_CACHE_TTL_MS = 5 * 60 * 1000;
const AWS_CREDENTIAL_EXPIRY_SKEW_MS = 60 * 1000;
const MANIFEST_CACHE_TTL_MS = 5 * 60 * 1000;
const manifestCache = new Map<string, { expiresAt: number; manifest: ParquetManifest }>();

function getS3Client() {
  if (!s3Client) {
    s3Client = new S3Client({
      region: REGION,
      credentials:
        process.env.AWS_ACCESS_KEY_ID && process.env.AWS_SECRET_ACCESS_KEY
          ? {
              accessKeyId: process.env.AWS_ACCESS_KEY_ID,
              secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
              sessionToken: process.env.AWS_SESSION_TOKEN,
            }
          : undefined,
    });
  }
  return s3Client;
}

async function getAwsCredentials() {
  if (process.env.AWS_ACCESS_KEY_ID && process.env.AWS_SECRET_ACCESS_KEY) {
    return {
      accessKeyId: process.env.AWS_ACCESS_KEY_ID,
      secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
      sessionToken: process.env.AWS_SESSION_TOKEN,
      expiresAt: Date.now() + AWS_CREDENTIAL_CACHE_TTL_MS,
    };
  }
  const now = Date.now();
  if (resolvedAwsCredentials && (resolvedAwsCredentials.expiresAt ?? 0) > now + AWS_CREDENTIAL_EXPIRY_SKEW_MS) {
    return resolvedAwsCredentials;
  }
  if (!awsCredentialsPromise) {
    awsCredentialsPromise = defaultProvider()()
      .then((credentials) => {
        const expiration = credentials.expiration instanceof Date
          ? credentials.expiration.getTime()
          : Date.now() + AWS_CREDENTIAL_CACHE_TTL_MS;
        resolvedAwsCredentials = {
          accessKeyId: credentials.accessKeyId,
          secretAccessKey: credentials.secretAccessKey,
          sessionToken: credentials.sessionToken,
          expiresAt: expiration,
        };
        return resolvedAwsCredentials;
      })
      .finally(() => {
        awsCredentialsPromise = null;
      });
  }
  return awsCredentialsPromise;
}

function env(config: BedrockCountryConfig, suffix: string) {
  return process.env[`${config.envPrefix}_${suffix}`];
}

function bucket(config: BedrockCountryConfig) {
  return env(config, 'BUCKET') || process.env.DIAMOND_GEOMETRY_BUCKET || DEFAULT_BUCKET;
}

function prefix(config: BedrockCountryConfig) {
  return (env(config, 'PREFIX') || `bedrock/${config.country}/current`).replace(/^\/+|\/+$/g, '');
}

function layerKey(config: BedrockCountryConfig, layer: 'addresses' | 'buildings' | 'parcels', filename: string) {
  const layerPrefix =
    layer === 'addresses'
      ? env(config, 'ADDRESS_PREFIX')
      : layer === 'buildings'
        ? env(config, 'BUILDING_PREFIX') || config.buildingPrefix
        : env(config, 'PARCEL_PREFIX');

  const base = (layerPrefix || `${prefix(config)}/${layer}`).replace(/^\/+|\/+$/g, '');
  return `${base}/${filename}`;
}

function cdnBase(config: BedrockCountryConfig) {
  return (
    env(config, 'CDN_BASE_URL') ||
    process.env.CLOUDFRONT_GEOMETRY_BASE_URL ||
    process.env.NEXT_PUBLIC_GEOMETRY_CDN_BASE_URL ||
    ''
  ).trim();
}

function cdnUrl(config: BedrockCountryConfig, key: string): string | null {
  const base = cdnBase(config);
  return base ? `${base.replace(/\/+$/, '')}/${key.replace(/^\/+/, '')}` : null;
}

async function pmtilesArchiveUrl(config: BedrockCountryConfig, key: string): Promise<string> {
  return (
    cdnUrl(config, key) ??
    getSignedUrl(getS3Client(), new GetObjectCommand({ Bucket: bucket(config), Key: key }), { expiresIn: 3600 })
  );
}

function layerUrl(config: BedrockCountryConfig, layer: 'addresses' | 'buildings' | 'parcels', filename: string) {
  const cdn = cdnUrl(config, layerKey(config, layer, filename));
  if (cdn) {
    return cdn;
  }
  return `s3://${bucket(config)}/${layerKey(config, layer, filename)}`;
}

function usaParcelPmtilesKey(config: BedrockCountryConfig, regionCode?: string | null) {
  if (config.country !== 'usa') return layerKey(config, 'parcels', 'parcels.pmtiles');
  const state = regionCode?.trim().toUpperCase();
  if (!state || !USA_PARCEL_REGIONS.has(state)) return null;
  return `${prefix(config)}/parcels/pmtiles_by_state/state=${state}/parcels.pmtiles`;
}

function usaAddressPmtilesKey(config: BedrockCountryConfig, regionCode?: string | null) {
  if (config.country !== 'usa') return layerKey(config, 'addresses', 'addresses.pmtiles');
  const state = regionCode?.trim().toUpperCase();
  if (!state || !USA_ADDRESS_REGIONS.has(state)) return null;
  return `${prefix(config)}/addresses/pmtiles_by_state/state=${state}/addresses.pmtiles`;
}

function usaBuildingPmtilesKey(config: BedrockCountryConfig, regionCode?: string | null) {
  if (config.country !== 'usa') return layerKey(config, 'buildings', 'buildings.pmtiles');
  const state = regionCode?.trim().toUpperCase();
  if (!state || !USA_BUILDING_REGIONS.has(state)) return null;
  return `${prefix(config)}/buildings/pmtiles_by_state/state=${state}/buildings.pmtiles`;
}

function sqlString(value: string) {
  return `'${value.replace(/'/g, "''")}'`;
}

function sqlNumber(value: number) {
  if (!Number.isFinite(value)) throw new Error(`Invalid SQL number: ${value}`);
  return value.toString();
}

function sqlIdentifier(value: string) {
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(value)) {
    throw new Error(`Invalid SQL identifier: ${value}`);
  }
  return value;
}

function coordinateColumns(config: BedrockCountryConfig) {
  return {
    longitude: env(config, 'LONGITUDE_COLUMN') || config.coordinateColumns?.longitude || 'longitude',
    latitude: env(config, 'LATITUDE_COLUMN') || config.coordinateColumns?.latitude || 'latitude',
  };
}

function numericValue(value: unknown): number | null {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function slippyTile(lon: number, lat: number, zoom: number): [number, number] {
  const n = 1 << zoom;
  const clampedLat = Math.max(Math.min(lat, WEB_MERCATOR_MAX_LAT), -WEB_MERCATOR_MAX_LAT);
  const x = Math.floor(((lon + 180) / 360) * n);
  const latRad = (clampedLat * Math.PI) / 180;
  const y = Math.floor(((1 - Math.log(Math.tan(latRad) + 1 / Math.cos(latRad)) / Math.PI) / 2) * n);
  return [Math.max(0, Math.min(n - 1, x)), Math.max(0, Math.min(n - 1, y))];
}

function tileSeamPadding(manifest: ParquetManifest, tileZ: number) {
  const configured = manifest.tile_seam_awareness;
  if (configured?.enabled === false) return 0;
  const padding = Number(configured?.tile_padding ?? 1);
  const manifestTileZ = Number(configured?.tile_z ?? tileZ);
  if (!Number.isFinite(padding) || padding < 0 || manifestTileZ !== tileZ) return 0;
  return Math.min(2, Math.floor(padding));
}

async function s3Text(config: BedrockCountryConfig, s3Key: string) {
  const cdn = cdnUrl(config, s3Key);
  if (cdn) {
    const response = await fetch(cdn, { cache: 'no-store' });
    if (response.ok) {
      return response.text();
    }
    console.warn('[BedrockCountryService] CDN manifest fetch failed; falling back to S3', {
      key: s3Key,
      status: response.status,
    });
  }

  const response = await getS3Client().send(new GetObjectCommand({ Bucket: bucket(config), Key: s3Key }));
  const body = response.Body;
  if (!body || typeof body !== 'object' || !('transformToString' in body)) {
    throw new Error(`Unable to read S3 object: ${s3Key}`);
  }
  return (body as { transformToString: () => Promise<string> }).transformToString();
}

function manifestCacheKey(config: BedrockCountryConfig, layer: BedrockLayer, s3Key: string) {
  return `${config.country}:${layer}:${s3Key}`;
}

function cachedManifest(config: BedrockCountryConfig, layer: BedrockLayer, s3Key: string): ParquetManifest | null {
  const cached = manifestCache.get(manifestCacheKey(config, layer, s3Key));
  if (!cached) return null;
  if (cached.expiresAt <= Date.now()) {
    manifestCache.delete(manifestCacheKey(config, layer, s3Key));
    return null;
  }
  return cached.manifest;
}

function setCachedManifest(
  config: BedrockCountryConfig,
  layer: BedrockLayer,
  s3Key: string,
  manifest: ParquetManifest
) {
  manifestCache.set(manifestCacheKey(config, layer, s3Key), {
    expiresAt: Date.now() + MANIFEST_CACHE_TTL_MS,
    manifest,
  });
}

async function readManifest(
  config: BedrockCountryConfig,
  layer: BedrockLayer = 'addresses'
): Promise<ManifestReadResult> {
  const startedAt = Date.now();
  const primaryManifestKey = layerKey(config, layer, 'parquet-manifest.json');
  const primaryCached = cachedManifest(config, layer, primaryManifestKey);
  if (primaryCached) {
    return { manifest: primaryCached, manifestMs: Date.now() - startedAt, cacheHit: true };
  }

  try {
    const manifest = JSON.parse(await s3Text(config, primaryManifestKey)) as ParquetManifest;
    setCachedManifest(config, layer, primaryManifestKey, manifest);
    return { manifest, manifestMs: Date.now() - startedAt, cacheHit: false };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    const manifestMissing =
      errorMessage.includes('NoSuchKey') ||
      errorMessage.includes('The specified key does not exist') ||
      errorMessage.includes('404');
    const canUseSingleFileSpatialParquet =
      manifestMissing &&
      (
        Boolean(config.singleFileSpatialParquetLayers?.includes(layer)) ||
        (layer === 'buildings' && config.country === 'canada')
      );

    if (!canUseSingleFileSpatialParquet) {
      throw error;
    }

    const spatialManifestKey = layerKey(config, layer, `parquet/${layer}.spatial.json`);
    const spatialCached = cachedManifest(config, layer, spatialManifestKey);
    let spatialManifest = spatialCached as ({ tile_z?: number; features?: number; feature_count?: number } | null);
    let spatialManifestCacheHit = Boolean(spatialCached);

    if (!spatialManifest) {
      try {
        spatialManifest = JSON.parse(await s3Text(config, spatialManifestKey)) as {
          tile_z?: number;
          features?: number;
          feature_count?: number;
        };
        setCachedManifest(config, layer, spatialManifestKey, spatialManifest as ParquetManifest);
      } catch {
        spatialManifest = null;
        spatialManifestCacheHit = false;
      }
    }

    const manifest = {
      feature_count: spatialManifest?.features ?? spatialManifest?.feature_count,
      single_file_key: layerKey(config, layer, `parquet/${layer}.spatial.parquet`),
      partitioning: {
        scheme: 'single_file_spatial',
        tile_z: spatialManifest?.tile_z ?? 12,
      },
      tile_seam_awareness: {
        enabled: false,
      },
    };
    setCachedManifest(config, layer, primaryManifestKey, manifest);
    return {
      manifest,
      manifestMs: Date.now() - startedAt,
      cacheHit: spatialManifestCacheHit,
    };
  }
}

function parquetPathsForTiles(
  config: BedrockCountryConfig,
  manifest: ParquetManifest,
  bbox: Bounds,
  regionCode?: string | null,
  layer: BedrockLayer = 'addresses'
) {
  const parquetPathFor = (relative: string) => {
    const key = layerKey(config, layer, relative);
    return `s3://${bucket(config)}/${key}`;
  };

  if (manifest.partitioning?.scheme === 'single_file_spatial' && manifest.single_file_key) {
    return {
      paths: [`s3://${bucket(config)}/${manifest.single_file_key}`],
      tileZ: manifest.partitioning.tile_z ?? 0,
      partitioning: 'single_file_spatial',
      tilePadding: 0,
    };
  }

  if (manifest.partitioning?.scheme === 'state') {
    const normalizedRegion = regionCode?.trim().toUpperCase();
    const available = new Set((manifest.state_counts ?? []).map((entry) => entry.state.toUpperCase()));
    const candidates = [
      normalizedRegion,
      config.country === 'south-africa' && normalizedRegion !== config.countryCode ? config.countryCode : null,
    ].filter((candidate): candidate is string => Boolean(candidate));
    const stateEntry = available.size > 0
      ? (manifest.state_counts ?? []).find((entry) => candidates.includes(entry.state.toUpperCase()))
      : null;
    const state = stateEntry?.state.toUpperCase() ?? candidates[0];

    if (!state) {
      return { paths: [], tileZ: 0, partitioning: 'state' };
    }

    if (normalizedRegion && state !== normalizedRegion) {
      console.warn('[BedrockCountryService] Falling back to country-level state partition', {
        country: config.country,
        requestedRegion: normalizedRegion,
        partition: state,
      });
    }

    const relative = stateEntry?.path ?? `parquet/state=${state}/*.parquet`;
    return {
      paths: [parquetPathFor(relative)],
      tileZ: 0,
      partitioning: 'state',
    };
  }

  const tileZ = manifest.partitioning?.tile_z ?? 12;
  const corners = [
    slippyTile(bbox[0], bbox[1], tileZ),
    slippyTile(bbox[0], bbox[3], tileZ),
    slippyTile(bbox[2], bbox[1], tileZ),
    slippyTile(bbox[2], bbox[3], tileZ),
  ];
  const padding = tileSeamPadding(manifest, tileZ);
  const maxTile = (1 << tileZ) - 1;
  const minX = Math.max(0, Math.min(...corners.map(([x]) => x)) - padding);
  const maxX = Math.min(maxTile, Math.max(...corners.map(([x]) => x)) + padding);
  const minY = Math.max(0, Math.min(...corners.map(([, y]) => y)) - padding);
  const maxY = Math.min(maxTile, Math.max(...corners.map(([, y]) => y)) + padding);
  const available = new Set((manifest.tile_counts ?? []).map((tile) => `${tile.tile_z}/${tile.tile_x}/${tile.tile_y}`));
  const paths: string[] = [];

  for (let x = minX; x <= maxX; x += 1) {
    for (let y = minY; y <= maxY; y += 1) {
      if (available.size > 0 && !available.has(`${tileZ}/${x}/${y}`)) continue;
      const relative = `parquet/tile_z=${tileZ}/tile_x=${x}/tile_y=${y}/*.parquet`;
      paths.push(parquetPathFor(relative));
    }
  }

  return { paths, tileZ, partitioning: 'web_mercator_xyz', tilePadding: padding };
}

function pmtilesTileRangeForBbox(
  bbox: Bounds,
  maxZoom: number,
  minZoom: number,
  maxTiles: number = 128,
  padding: number = 1
) {
  const [minLon, minLat, maxLon, maxLat] = bbox;
  for (let z = Math.min(maxZoom, 16); z >= Math.max(8, minZoom); z -= 1) {
    const nw = slippyTile(minLon, maxLat, z);
    const se = slippyTile(maxLon, minLat, z);
    const maxTile = (1 << z) - 1;
    const minX = Math.max(0, Math.min(nw[0], se[0]) - padding);
    const maxX = Math.min(maxTile, Math.max(nw[0], se[0]) + padding);
    const minY = Math.max(0, Math.min(nw[1], se[1]) - padding);
    const maxY = Math.min(maxTile, Math.max(nw[1], se[1]) + padding);
    const tileCount = (maxX - minX + 1) * (maxY - minY + 1);
    if (tileCount <= maxTiles || z === Math.max(8, minZoom)) {
      return { z, minX, maxX, minY, maxY, tileCount };
    }
  }
  return null;
}

async function loadDuckDbModule() {
  if (!duckdbModulePromise) {
    duckdbModulePromise = import('duckdb');
  }
  return duckdbModulePromise;
}

async function duckDbQuery(
  sql: string,
  usesRemoteFiles: boolean
): Promise<{ rows: BedrockParquetRow[]; timings: DuckDbTimings }> {
  const setupStartedAt = Date.now();
  const duckdbModule = await loadDuckDbModule();
  const duckdb = ((duckdbModule as { default?: typeof duckdbModule }).default ?? duckdbModule) as typeof duckdbModule;
  const db = new duckdb.Database(':memory:');
  const all = (statement: string) =>
    new Promise<BedrockParquetRow[]>((resolve, reject) => {
      db.all(statement, (error: Error | null, rows: BedrockParquetRow[]) => {
        if (error) reject(error);
        else resolve(rows);
      });
    });
  const duckdbSetupMs = Date.now() - setupStartedAt;
  let duckdbExtensionMs = 0;
  let duckdbCredentialsMs = 0;

  try {
    if (usesRemoteFiles) {
      const extensionStartedAt = Date.now();
      await all("SET home_directory='/tmp'");
      await all("SET extension_directory='/tmp/duckdb_extensions'");
      if (!httpfsInstalled) {
        if (!httpfsInstallPromise) {
          httpfsInstallPromise = all('INSTALL httpfs')
            .then(() => {
              httpfsInstalled = true;
            })
            .catch((error) => {
              httpfsInstallPromise = null;
              throw error;
            });
        }
        await httpfsInstallPromise;
      }
      await all('LOAD httpfs');
      duckdbExtensionMs = Date.now() - extensionStartedAt;

      if (sql.includes('s3://')) {
        const credentialsStartedAt = Date.now();
        await all(`SET s3_region=${sqlString(REGION)}`);
        const credentials = await getAwsCredentials();
        if (credentials?.accessKeyId && credentials.secretAccessKey) {
          await all(`SET s3_access_key_id=${sqlString(credentials.accessKeyId)}`);
          await all(`SET s3_secret_access_key=${sqlString(credentials.secretAccessKey)}`);
          if (credentials.sessionToken) {
            await all(`SET s3_session_token=${sqlString(credentials.sessionToken)}`);
          }
        }
        duckdbCredentialsMs = Date.now() - credentialsStartedAt;
      }
    }

    const queryStartedAt = Date.now();
    const rows = await all(sql);
    return {
      rows,
      timings: {
        duckdb_setup_ms: duckdbSetupMs,
        duckdb_extension_ms: duckdbExtensionMs,
        duckdb_credentials_ms: duckdbCredentialsMs,
        duckdb_query_ms: Date.now() - queryStartedAt,
      },
    };
  } finally {
    db.close();
  }
}

function parseProperties(row: BedrockParquetRow) {
  if (typeof row.properties_json !== 'string' || !row.properties_json.trim()) return {};
  try {
    return JSON.parse(row.properties_json) as Record<string, unknown>;
  } catch {
    return {};
  }
}

function rowProperties(row: BedrockParquetRow) {
  return {
    ...parseProperties(row),
    ...Object.fromEntries(
      Object.entries(row).filter(([key, value]) => {
        return (
          value != null &&
          ![
            'geometry_geojson',
            'properties_json',
            'tile_z',
            'tile_x',
            'tile_y',
            'tile_key',
            'minx',
            'miny',
            'maxx',
            'maxy',
            'lon',
            'lat',
          ].includes(key)
        );
      })
    ),
  };
}

function parseRowGeometry(row: BedrockParquetRow): GeoJSON.Geometry | null {
  if (typeof row.geometry_geojson === 'string' && row.geometry_geojson.trim()) {
    try {
      return JSON.parse(row.geometry_geojson) as GeoJSON.Geometry;
    } catch {
      return null;
    }
  }

  const lon = Number(row.lon ?? row.longitude);
  const lat = Number(row.lat ?? row.latitude);
  if (Number.isFinite(lon) && Number.isFinite(lat)) {
    return { type: 'Point', coordinates: [lon, lat] };
  }

  return null;
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

function geometryBbox(geometry: GeoJSON.Geometry | null | undefined): Bounds | null {
  const positions = flattenPositions(geometry).filter(
    (position) => Number.isFinite(position[0]) && Number.isFinite(position[1])
  );
  if (positions.length === 0) return null;

  return [
    Math.min(...positions.map((position) => position[0])),
    Math.min(...positions.map((position) => position[1])),
    Math.max(...positions.map((position) => position[0])),
    Math.max(...positions.map((position) => position[1])),
  ];
}

function bboxIntersects(a: Bounds, b: Bounds) {
  return !(a[2] < b[0] || a[0] > b[2] || a[3] < b[1] || a[1] > b[3]);
}

function featureIntersectsPolygon(feature: GeoJSON.Feature, polygon: GeoJSON.Polygon, bbox: Bounds) {
  const geometry = feature.geometry;
  if (geometry?.type === 'Point') {
    const coordinates = geometry.coordinates as [number, number];
    return bboxIntersects([coordinates[0], coordinates[1], coordinates[0], coordinates[1]], bbox) &&
      turf.booleanPointInPolygon(turf.point(coordinates), polygon);
  }

  const featureBbox = geometryBbox(geometry);
  if (!featureBbox || !bboxIntersects(featureBbox, bbox)) return false;
  try {
    return turf.booleanIntersects(feature, polygon);
  } catch {
    return true;
  }
}

function text(value: unknown) {
  if (typeof value === 'string') {
    const trimmed = value.trim();
    return trimmed ? trimmed : undefined;
  }
  if (typeof value === 'number' && Number.isFinite(value)) {
    return Number.isInteger(value) ? String(value) : String(value);
  }
  if (typeof value === 'bigint') {
    return value.toString();
  }
  return undefined;
}

function firstText(...values: unknown[]) {
  for (const value of values) {
    const normalized = text(value);
    if (normalized) return normalized;
  }
  return undefined;
}

function streetText(value: unknown) {
  const normalized = text(value);
  if (!normalized) return undefined;
  if (/^[\d\s#./-]+$/.test(normalized)) return undefined;
  return normalized;
}

function fallbackAddressLabel(config: BedrockCountryConfig, row: BedrockParquetRow, props: Record<string, unknown>, addressId?: string) {
  const sourceId = text(row.source_id) ?? text(props.source_id);
  const uprn = text(row.uprn) ?? text(props.uprn);
  const stableId = sourceId ?? uprn ?? addressId ?? text(row.gers_id);

  if (config.country === 'uk') {
    return 'Address point';
  }

  if (stableId) {
    return `${config.defaultSource} ${stableId}`;
  }

  return 'Address point';
}

function streetLabel(name: unknown, type: unknown): string | undefined {
  const streetName = streetText(name);
  const streetType = streetText(type);
  if (!streetName) return undefined;
  if (!streetType) return streetName;

  const normalizedName = streetName.toUpperCase();
  const normalizedType = streetType.toUpperCase();
  if (normalizedName === normalizedType || normalizedName.endsWith(` ${normalizedType}`)) {
    return streetName;
  }
  return `${streetName} ${streetType}`;
}

function streetLabelFrom(primary: Record<string, unknown>, secondary: Record<string, unknown> = {}): string | undefined {
  const streetName =
    streetText(primary.street_name) ??
    streetText(primary.street) ??
    streetText(primary.road_name) ??
    streetText(primary.road) ??
    streetText(primary.str_name) ??
    streetText(primary.street_full) ??
    streetText(primary.street_label) ??
    streetText(primary.full_street) ??
    streetText(primary.primary_street) ??
    streetText(primary['addr:street']) ??
    streetText(primary.name) ??
    streetText(secondary.street_name) ??
    streetText(secondary.street) ??
    streetText(secondary.road_name) ??
    streetText(secondary.road) ??
    streetText(secondary.str_name) ??
    streetText(secondary.street_full) ??
    streetText(secondary.street_label) ??
    streetText(secondary.full_street) ??
    streetText(secondary.primary_street) ??
    streetText(secondary['addr:street']) ??
    streetText(secondary.name);
  const streetType =
    streetText(primary.street_type) ??
    streetText(primary.road_type) ??
    streetText(primary.str_type) ??
    streetText(primary.street_suffix) ??
    streetText(primary.suffix) ??
    streetText(secondary.street_type) ??
    streetText(secondary.road_type) ??
    streetText(secondary.str_type) ??
    streetText(secondary.street_suffix) ??
    streetText(secondary.suffix);
  return streetLabel(streetName, streetType);
}

function houseNumberFrom(primary: Record<string, unknown>, secondary: Record<string, unknown> = {}): string | undefined {
  const candidate = firstText(
    primary.house_number,
    primary.house_number_label,
    primary.street_number,
    primary.number_first,
    primary.address_number,
    primary.street_no,
    primary.civic_number,
    primary.housenumber,
    primary['addr:housenumber'],
    secondary.house_number,
    secondary.house_number_label,
    secondary.street_number,
    secondary.number_first,
    secondary.address_number,
    secondary.street_no,
    secondary.civic_number,
    secondary.housenumber,
    secondary['addr:housenumber']
  );
  return isUsableHouseNumberAddressLabel(candidate) ? candidate : undefined;
}

function explicitAddressText(primary: Record<string, unknown>, secondary: Record<string, unknown> = {}): string | undefined {
  return firstText(
    primary.full_address,
    primary.formatted,
    primary.display_address,
    primary.address,
    primary.label,
    primary.full_addr,
    secondary.full_address,
    secondary.formatted,
    secondary.display_address,
    secondary.address,
    secondary.label,
    secondary.full_addr
  );
}

function looksLikeNumericOnlyAddress(value: string): boolean {
  return /^[\d\s#./-]+$/.test(value.trim());
}

function looksLikeUnusableAddressLabel(value: string): boolean {
  return looksLikeNumericOnlyAddress(value) || isStreetOnlyOrdinalAddressLabel(value);
}

function chooseFormattedAddress(
  explicit: string | undefined,
  houseNumber: string | undefined,
  streetName: string | undefined,
  locality: string | undefined,
  fallback: string
) {
  const composed = [houseNumber, streetName, locality].filter(Boolean).join(' ').trim();
  if (composed && (!explicit || looksLikeUnusableAddressLabel(explicit))) {
    return composed;
  }
  if (explicit && !looksLikeUnusableAddressLabel(explicit)) {
    return explicit;
  }
  return composed || explicit || fallback;
}

function normalizeAddress(config: BedrockCountryConfig, campaignId: string, row: BedrockParquetRow): StandardCampaignAddress | null {
  const columns = coordinateColumns(config);
  const lon = numericValue(row[columns.longitude]) ?? numericValue(row.longitude) ?? numericValue(row.lon);
  const lat = numericValue(row[columns.latitude]) ?? numericValue(row.latitude) ?? numericValue(row.lat);
  if (lon == null || lat == null) return null;

  const props = parseProperties(row);
  const geometry =
    typeof row.geometry_json === 'string' && row.geometry_json.trim()
      ? row.geometry_json
      : typeof row.geometry_geojson === 'string' && row.geometry_geojson.trim()
        ? row.geometry_geojson
      : JSON.stringify({ type: 'Point', coordinates: [lon, lat] });
  const addressId = canonicalBedrockAddressExternalId(
    text(row.address_id) ??
    text(props.address_id) ??
    text(row.address_detail_pid) ??
    text(props.address_detail_pid) ??
    text(row.source_id) ??
    text(props.source_id) ??
    text(row.uprn) ??
    text(props.uprn) ??
    text(row.gers_id)
  );
  const houseNumber = houseNumberFrom(row, props);
  const streetName = streetLabelFrom(row, props);
  const unit = text(row.unit) ?? text(props.unit) ?? text(props.unit_number) ?? text(props.suite);
  const locality =
    text(row.locality) ??
    text(props.locality) ??
    text(row.locality_name) ??
    text(props.locality_name) ??
    text(row.city);
  const formatted = chooseFormattedAddress(
    explicitAddressText(row, props),
    houseNumber,
    streetName,
    locality,
    fallbackAddressLabel(config, row, props, addressId)
  );

  return {
    campaign_id: campaignId,
    formatted,
    house_number: houseNumber,
    street_name: streetName,
    unit,
    locality,
    region: (text(row.region) ?? text(props.region) ?? text(row.state) ?? config.countryCode).toUpperCase(),
    postal_code: text(row.postal_code) ?? text(props.postal_code) ?? text(row.postcode) ?? text(props.postcode),
    coordinate: { lat, lon },
    lat,
    lon,
    geom: geometry,
    source: config.provisionSource,
    gers_id: addressId ? `${config.provisionSource}:${addressId}` : null,
  };
}

function normalizeBuildingFeature(row: BedrockParquetRow): BedrockScopedBuildingFeature | null {
  const geometry = parseRowGeometry(row);
  if (geometry?.type !== 'Polygon' && geometry?.type !== 'MultiPolygon') return null;

  const properties = rowProperties(row);
  const buildingId =
    text(row.building_id) ??
    text(properties.building_id) ??
    text(row.gers_id) ??
    text(properties.gers_id) ??
    text(row.source_id) ??
    text(properties.source_id) ??
    text(row.feature_id) ??
    text(properties.feature_id);

  if (!buildingId) return null;

  const height = Number(row.height ?? properties.height ?? properties.height_m);
  return {
    type: 'Feature',
    id: buildingId,
    geometry,
    properties: {
      ...properties,
      id: buildingId,
      gers_id: buildingId,
      building_id: buildingId,
      source_id: text(row.source_id) ?? text(properties.source_id) ?? buildingId,
      name: text(row.name) ?? text(properties.name) ?? null,
      height: Number.isFinite(height) && height > 0 ? height : 10,
      height_m: Number.isFinite(height) && height > 0 ? height : 10,
      min_height: 0,
      layer: 'building',
      source: text(row.source) ?? text(properties.source) ?? 'Overture Maps Buildings',
      feature_type: 'matched_house',
      feature_status: 'matched',
      status: 'not_visited',
      scans_total: 0,
      qr_scanned: false,
    },
  };
}

function normalizePmtilesParcel(feature: PmtilesParcelFeature, fallbackId: string): BedrockScopedParcelFeature | null {
  if (feature.geometry?.type !== 'Polygon' && feature.geometry?.type !== 'MultiPolygon') return null;

  const properties = feature.properties ?? {};
  const externalId =
    text(properties.parcel_id) ??
    text(properties.id) ??
    text(properties.external_id) ??
    text(properties.source_id) ??
    text(properties.objectid) ??
    text(properties.apn) ??
    text(properties.pin) ??
    (typeof feature.id === 'string' || typeof feature.id === 'number' ? String(feature.id) : null) ??
    fallbackId;

  return {
    externalId,
    geometry:
      feature.geometry.type === 'MultiPolygon'
        ? feature.geometry
        : {
            type: 'MultiPolygon',
            coordinates: [feature.geometry.coordinates],
          },
    properties: {
      ...properties,
      parcel_id: externalId,
    },
  };
}

function normalizePmtilesAddress(
  config: BedrockCountryConfig,
  campaignId: string,
  feature: PmtilesAddressFeature
): StandardCampaignAddress | null {
  const coordinates = feature.geometry?.coordinates;
  if (!Array.isArray(coordinates) || coordinates.length < 2) return null;

  const lon = Number(coordinates[0]);
  const lat = Number(coordinates[1]);
  if (!Number.isFinite(lon) || !Number.isFinite(lat)) return null;

  const props = feature.properties ?? {};
  const addressId = canonicalBedrockAddressExternalId(
    text(props.address_id) ??
    text(props.address_detail_pid) ??
    text(props.source_id) ??
    text(props.uprn) ??
    text(props.gers_id)
  );
  const houseNumber = houseNumberFrom(props);
  const streetName = streetLabelFrom(props);
  const unit = text(props.unit) ?? text(props.unit_number) ?? text(props.suite);
  const locality = text(props.locality) ?? text(props.locality_name) ?? text(props.city);
  const formatted = chooseFormattedAddress(
    explicitAddressText(props),
    houseNumber,
    streetName,
    locality,
    fallbackAddressLabel(config, {}, props, addressId)
  );

  return {
    campaign_id: campaignId,
    formatted,
    house_number: houseNumber,
    street_name: streetName,
    unit,
    locality,
    region: (text(props.region) ?? text(props.state) ?? config.countryCode).toUpperCase(),
    postal_code: text(props.postal_code) ?? text(props.postcode),
    coordinate: { lat, lon },
    lat,
    lon,
    geom: JSON.stringify({ type: 'Point', coordinates: [lon, lat] }),
    source: config.provisionSource,
    gers_id: addressId ? `${config.provisionSource}:${addressId}` : null,
  };
}

function normalizedAddressFragment(value: string | null | undefined): string {
  return normalizedAddressPart(value) ?? '';
}

function normalizedAddressIdentity(address: StandardCampaignAddress): string | null {
  return normalizedAddressDisplayIdentity(address);
}

async function loadAddressesFromPmtiles(options: {
  config: BedrockCountryConfig;
  campaignId: string;
  polygon: GeoJSON.Polygon;
  bbox: Bounds;
  addressLimit?: number;
  regionCode?: string | null;
}): Promise<{
  addresses: StandardCampaignAddress[];
  scanned: number;
  bboxCandidates: number;
  touchedTiles: number;
} | null> {
  const pmtilesKey =
    options.config.country === 'usa'
      ? usaAddressPmtilesKey(options.config, options.regionCode)
      : layerKey(options.config, 'addresses', 'addresses.pmtiles');
  if (!pmtilesKey) return null;

  const resolvedUrl = await pmtilesArchiveUrl(options.config, pmtilesKey);
  const archive = new PMTiles(resolvedUrl);
  const header = await archive.getHeader();
  const range = pmtilesTileRangeForBbox(options.bbox, header.maxZoom, header.minZoom);
  if (!range) return null;

  const addresses: StandardCampaignAddress[] = [];
  const byIdentity = new Set<string>();
  let scanned = 0;
  let bboxCandidates = 0;
  let touchedTiles = 0;

  for (let x = range.minX; x <= range.maxX; x += 1) {
    for (let y = range.minY; y <= range.maxY; y += 1) {
      const tile = await archive.getZxy(range.z, x, y);
      if (!tile) continue;
      touchedTiles += 1;

      const vectorTile = new VectorTile(new Pbf(Buffer.from(tile.data)));
      const layer = vectorTile.layers.addresses ?? vectorTile.layers.address_points;
      if (!layer) continue;

      for (let index = 0; index < layer.length; index += 1) {
        scanned += 1;
        const feature = layer.feature(index).toGeoJSON(x, y, range.z) as PmtilesAddressFeature;
        const coordinates = feature.geometry?.coordinates;
        if (!Array.isArray(coordinates) || coordinates.length < 2) continue;

        const lon = Number(coordinates[0]);
        const lat = Number(coordinates[1]);
        if (!Number.isFinite(lon) || !Number.isFinite(lat)) continue;
        if (
          lon < options.bbox[0] ||
          lon > options.bbox[2] ||
          lat < options.bbox[1] ||
          lat > options.bbox[3]
        ) {
          continue;
        }

        bboxCandidates += 1;
        if (!turf.booleanPointInPolygon(turf.point([lon, lat]), options.polygon)) continue;

        const address = normalizePmtilesAddress(options.config, options.campaignId, feature);
        if (!address) continue;

        const dedupeKey = normalizedAddressIdentity(address) ?? address.gers_id ?? `${address.formatted}:${lon}:${lat}`;
        if (byIdentity.has(dedupeKey)) continue;
        byIdentity.add(dedupeKey);
        addresses.push(address);

        if (options.addressLimit && addresses.length >= options.addressLimit) {
          return { addresses, scanned, bboxCandidates, touchedTiles };
        }
      }
    }
  }

  return { addresses, scanned, bboxCandidates, touchedTiles };
}

async function loadParcelsFromPmtiles(options: {
  config: BedrockCountryConfig;
  polygon: GeoJSON.Polygon;
  bbox: Bounds;
  regionCode?: string | null;
}): Promise<{ features: BedrockScopedParcelFeature[]; metric: BedrockScanResult } | null> {
  const startedAt = Date.now();
  const pmtilesKey = usaParcelPmtilesKey(options.config, options.regionCode);
  if (!pmtilesKey) return null;

  const queryStartedAt = Date.now();
  const archive = new PMTiles(await pmtilesArchiveUrl(options.config, pmtilesKey));
  const header = await archive.getHeader();
  const range = pmtilesTileRangeForBbox(options.bbox, header.maxZoom, header.minZoom, 256);
  if (!range) return null;

  const fragments: Array<{
    id: string;
    geometry: GeoJSON.Polygon | GeoJSON.MultiPolygon;
    properties: Record<string, unknown>;
    include: boolean;
  }> = [];
  let scanned = 0;
  let bboxCandidates = 0;
  let touchedTiles = 0;

  for (let x = range.minX; x <= range.maxX; x += 1) {
    for (let y = range.minY; y <= range.maxY; y += 1) {
      const tile = await archive.getZxy(range.z, x, y);
      if (!tile) continue;
      touchedTiles += 1;

      const vectorTile = new VectorTile(new Pbf(Buffer.from(tile.data)));
      const layer =
        vectorTile.layers.parcels ??
        vectorTile.layers.parcel ??
        vectorTile.layers.property ??
        vectorTile.layers.land_parcels;
      if (!layer) continue;

      for (let index = 0; index < layer.length; index += 1) {
        scanned += 1;
        const rawFeature = layer.feature(index).toGeoJSON(x, y, range.z) as PmtilesParcelFeature;
        const geometry = polygonalGeometry(rawFeature.geometry);
        if (!geometry) continue;
        const feature = { ...rawFeature, geometry };
        if (!isResidentialParcelFeature(feature)) continue;

        const featureBbox = geometryBbox(rawFeature.geometry);
        const intersectsBbox = Boolean(featureBbox && bboxIntersects(featureBbox, options.bbox));
        if (intersectsBbox) bboxCandidates += 1;

        const parcel = normalizePmtilesParcel(
          feature,
          `${range.z}/${x}/${y}/${index}`
        );
        if (!parcel) continue;

        fragments.push({
          id: parcel.externalId,
          geometry,
          properties: parcel.properties ?? {},
          include: featureIntersectsPolygon(feature, options.polygon, options.bbox),
        });
      }
    }
  }

  const features = reconstructParcelFragments(fragments).map((feature): BedrockScopedParcelFeature => ({
    externalId: String(feature.id ?? feature.properties?.parcel_id),
    geometry:
      feature.geometry.type === 'MultiPolygon'
        ? feature.geometry
        : {
            type: 'MultiPolygon',
            coordinates: [feature.geometry.coordinates],
          },
    properties: feature.properties ?? {},
  })).filter((feature) => feature.externalId.trim().length > 0);

  const totalMs = Date.now() - startedAt;
  return {
    features,
    metric: {
      hits: features.length,
      scanned,
      bboxCandidates,
      seconds: Number((totalMs / 1000).toFixed(2)),
      queryEngine: 'pmtiles_vector',
      touchedTiles,
      partitioning: 'pmtiles_vector_state',
      timings: {
        manifestMs: 0,
        partitionMs: 0,
        queryMs: Date.now() - queryStartedAt,
        filterMs: 0,
        totalMs,
      },
    },
  };
}

async function loadBuildingsFromParquet(options: {
  config: BedrockCountryConfig;
  polygon: GeoJSON.Polygon;
  bbox: Bounds;
  regionCode?: string | null;
}): Promise<{ features: BedrockScopedBuildingFeature[]; metric: BedrockScanResult } | null> {
  const startedAt = Date.now();
  const { manifest, manifestMs, cacheHit } = await readManifest(options.config, 'buildings');
  const partitionStartedAt = Date.now();
  const { paths, partitioning, tilePadding } = parquetPathsForTiles(
    options.config,
    manifest,
    options.bbox,
    options.regionCode,
    'buildings'
  );
  const partitionMs = Date.now() - partitionStartedAt;
  if (paths.length === 0) return null;

  const queryStartedAt = Date.now();
  const { rows, timings: duckDbTimings } = await duckDbQuery(
    `
      SELECT *
      FROM read_parquet([${paths.map(sqlString).join(',')}], hive_partitioning=1, union_by_name=true)
      WHERE maxx >= ${sqlNumber(options.bbox[0])}
        AND minx <= ${sqlNumber(options.bbox[2])}
        AND maxy >= ${sqlNumber(options.bbox[1])}
        AND miny <= ${sqlNumber(options.bbox[3])}
    `,
    paths.some((path) => path.startsWith('s3://') || /^https?:\/\//i.test(path))
  );
  const queryMs = Date.now() - queryStartedAt;

  const filterStartedAt = Date.now();
  const features: BedrockScopedBuildingFeature[] = [];
  const seen = new Set<string>();
  for (const row of rows) {
    const feature = normalizeBuildingFeature(row);
    if (!feature) continue;
    if (!featureIntersectsPolygon(feature, options.polygon, options.bbox)) continue;

    const key = feature.properties.building_id.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    features.push(feature);
  }
  const filterMs = Date.now() - filterStartedAt;
  const totalMs = Date.now() - startedAt;

  return {
    features,
    metric: {
      hits: features.length,
      scanned: rows.length,
      bboxCandidates: rows.length,
      seconds: Number((totalMs / 1000).toFixed(2)),
      queryEngine: 'duckdb_parquet',
      touchedTiles: paths.length,
      partitioning,
      tilePadding,
      timings: {
        manifestMs,
        partitionMs,
        queryMs,
        filterMs,
        totalMs,
        ...duckDbTimings,
        manifest_cache_hit: cacheHit,
      },
    },
  };
}

export class BedrockCountryService {
  constructor(private readonly config: BedrockCountryConfig) {}

  async provisionCampaign(options: {
    campaignId: string;
    polygon: GeoJSON.Polygon;
    addressLimit?: number;
    regionCode?: string | null;
  }): Promise<{
    addresses: StandardCampaignAddress[];
    snapshot: LambdaSnapshotResponse;
    metrics: { addresses: BedrockScanResult; buildings?: BedrockScanResult; parcels?: BedrockScanResult };
    linkGeometry?: { buildings: BedrockScopedBuildingFeature[]; parcels: BedrockScopedParcelFeature[] } | null;
  }> {
    const startedAt = Date.now();
    const bbox = turf.bbox(options.polygon) as Bounds;

    const addressScanPromise = (async () => {
      const { manifest, manifestMs, cacheHit } = await readManifest(this.config);
      const partitionStartedAt = Date.now();
      const { paths, partitioning, tilePadding } = parquetPathsForTiles(this.config, manifest, bbox, options.regionCode);
      const partitionMs = Date.now() - partitionStartedAt;
      if (paths.length === 0) {
        throw new Error(`BEDROCK ${this.config.country} has no Parquet partitions for this territory`);
      }

      console.log(`[BedrockCountryService] ${this.config.country} address scan starting`, {
        campaignId: options.campaignId,
        regionCode: options.regionCode ?? null,
        partitioning,
        touchedTiles: paths.length,
        tilePadding,
        manifestMs,
        manifestCacheHit: cacheHit,
        partitionMs,
        bbox,
      });

      const queryStartedAt = Date.now();
      let addresses: StandardCampaignAddress[] = [];
      let metric: BedrockScanResult;
      let duckDbTimings: DuckDbTimings | undefined;
      const columns = coordinateColumns(this.config);
      const longitudeColumn = sqlIdentifier(columns.longitude);
      const latitudeColumn = sqlIdentifier(columns.latitude);

      try {
        const query = await duckDbQuery(
          `
            SELECT *
            FROM read_parquet([${paths.map(sqlString).join(',')}], hive_partitioning=1, union_by_name=true)
            WHERE ${longitudeColumn} BETWEEN ${sqlNumber(bbox[0])} AND ${sqlNumber(bbox[2])}
              AND ${latitudeColumn} BETWEEN ${sqlNumber(bbox[1])} AND ${sqlNumber(bbox[3])}
          `,
          paths.some((path) => path.startsWith('s3://') || /^https?:\/\//i.test(path))
        );
        const rows = query.rows;
        duckDbTimings = query.timings;
        const queryMs = Date.now() - queryStartedAt;

        const filterStartedAt = Date.now();
        const byIdentity = new Set<string>();
        for (const row of rows) {
          const lon = numericValue(row[columns.longitude]) ?? numericValue(row.longitude) ?? numericValue(row.lon);
          const lat = numericValue(row[columns.latitude]) ?? numericValue(row.latitude) ?? numericValue(row.lat);
          if (lon == null || lat == null) continue;
          if (!turf.booleanPointInPolygon(turf.point([lon, lat]), options.polygon)) continue;
          const address = normalizeAddress(this.config, options.campaignId, row);
          if (!address) continue;
          const dedupeKey = normalizedAddressIdentity(address) ?? address.gers_id ?? `${address.formatted}:${lon}:${lat}`;
          if (byIdentity.has(dedupeKey)) continue;
          byIdentity.add(dedupeKey);
          addresses.push(address);
          if (options.addressLimit && addresses.length >= options.addressLimit) break;
        }
        const filterMs = Date.now() - filterStartedAt;
        const totalMs = Date.now() - startedAt;

        metric = {
          hits: addresses.length,
          scanned: rows.length,
          bboxCandidates: rows.length,
          seconds: Number((totalMs / 1000).toFixed(2)),
          queryEngine: 'duckdb_parquet',
          touchedTiles: paths.length,
          partitioning,
          tilePadding,
          timings: {
            manifestMs,
            partitionMs,
            queryMs,
            filterMs,
            totalMs,
            ...duckDbTimings,
            manifest_cache_hit: cacheHit,
          },
        };
      } catch (duckDbError) {
        console.warn(
          `[BedrockCountryService] ${this.config.country} DuckDB Parquet scan failed; trying PMTiles address fallback`,
          duckDbError instanceof Error ? duckDbError.message : duckDbError
        );

        const fallbackStartedAt = Date.now();
        const pmtilesResult = await loadAddressesFromPmtiles({
          config: this.config,
          campaignId: options.campaignId,
          polygon: options.polygon,
          bbox,
          addressLimit: options.addressLimit,
          regionCode: options.regionCode,
        });
        if (!pmtilesResult) {
          throw duckDbError;
        }

        addresses = pmtilesResult.addresses;
        const totalMs = Date.now() - startedAt;
        metric = {
          hits: addresses.length,
          scanned: pmtilesResult.scanned,
          bboxCandidates: pmtilesResult.bboxCandidates,
          seconds: Number((totalMs / 1000).toFixed(2)),
          queryEngine: 'pmtiles_vector',
          touchedTiles: pmtilesResult.touchedTiles,
          partitioning: 'pmtiles_vector',
          timings: {
            manifestMs,
            partitionMs,
            queryMs: Date.now() - fallbackStartedAt,
            filterMs: 0,
            totalMs,
            ...(duckDbTimings ?? {}),
            manifest_cache_hit: cacheHit,
          },
        };
      }

      console.log(`[BedrockCountryService] ${this.config.country} address scan complete`, {
        campaignId: options.campaignId,
        hits: metric.hits,
        scanned: metric.scanned,
        touchedTiles: metric.touchedTiles,
        timings: metric.timings,
      });

      return { addresses, metric, manifest };
    })();

    const buildingScanPromise = (async () => {
      try {
        const buildingResult = await loadBuildingsFromParquet({
          config: this.config,
          polygon: options.polygon,
          bbox,
          regionCode: options.regionCode,
        });
        const buildingFeatures = buildingResult?.features ?? [];
        const buildingMetric = buildingResult?.metric;
        console.log(`[BedrockCountryService] ${this.config.country} building scan complete`, {
          campaignId: options.campaignId,
          hits: buildingMetric?.hits ?? 0,
          scanned: buildingMetric?.scanned ?? 0,
          touchedTiles: buildingMetric?.touchedTiles ?? 0,
          timings: buildingMetric?.timings ?? null,
        });
        return { buildingFeatures, buildingMetric };
      } catch (buildingError) {
        console.warn(
          `[BedrockCountryService] ${this.config.country} building Parquet scan failed; PMTiles display fallback remains available`,
          buildingError instanceof Error ? buildingError.message : buildingError
        );
        return { buildingFeatures: [] as BedrockScopedBuildingFeature[], buildingMetric: undefined };
      }
    })();

    const parcelScanPromise = (async () => {
      try {
        const parcelResult = await loadParcelsFromPmtiles({
          config: this.config,
          polygon: options.polygon,
          bbox,
          regionCode: options.regionCode,
        });
        const parcelFeatures = parcelResult?.features ?? [];
        const parcelMetric = parcelResult?.metric;
        console.log(`[BedrockCountryService] ${this.config.country} parcel scan complete`, {
          campaignId: options.campaignId,
          hits: parcelMetric?.hits ?? 0,
          scanned: parcelMetric?.scanned ?? 0,
          touchedTiles: parcelMetric?.touchedTiles ?? 0,
          timings: parcelMetric?.timings ?? null,
        });
        return { parcelFeatures, parcelMetric };
      } catch (parcelError) {
        console.warn(
          `[BedrockCountryService] ${this.config.country} parcel PMTiles scan failed; parcel tile rendering metadata remains available`,
          parcelError instanceof Error ? parcelError.message : parcelError
        );
        return { parcelFeatures: [] as BedrockScopedParcelFeature[], parcelMetric: undefined };
      }
    })();

    const [addressScan, buildingScan, parcelScan] = await Promise.allSettled([
      addressScanPromise,
      buildingScanPromise,
      parcelScanPromise,
    ]);

    if (addressScan.status === 'rejected') {
      throw addressScan.reason;
    }

    const { addresses, metric, manifest } = addressScan.value;
    const { buildingFeatures, buildingMetric } = buildingScan.status === 'fulfilled'
      ? buildingScan.value
      : { buildingFeatures: [] as BedrockScopedBuildingFeature[], buildingMetric: undefined };
    const { parcelFeatures, parcelMetric } = parcelScan.status === 'fulfilled'
      ? parcelScan.value
      : { parcelFeatures: [] as BedrockScopedParcelFeature[], parcelMetric: undefined };

    return {
      addresses,
      metrics: {
        addresses: metric,
        ...(buildingMetric ? { buildings: buildingMetric } : {}),
        ...(parcelMetric ? { parcels: parcelMetric } : {}),
      },
      linkGeometry: buildingFeatures.length > 0 || parcelFeatures.length > 0
        ? { buildings: buildingFeatures, parcels: parcelFeatures }
        : null,
      snapshot: this.snapshotForCampaign(
        options.campaignId,
        addresses.length,
        metric,
        manifest,
        options.regionCode,
        buildingFeatures.length,
        buildingMetric,
        parcelFeatures.length,
        parcelMetric
      ),
    };
  }

  snapshotForCampaign(
    campaignId: string,
    addressCount: number,
    scanMetric: BedrockScanResult,
    manifest: ParquetManifest,
    regionCode?: string | null,
    buildingCount: number = 0,
    buildingScanMetric?: BedrockScanResult,
    parcelCount: number = 0,
    parcelScanMetric?: BedrockScanResult
  ): LambdaSnapshotResponse {
    const buildingPmtilesKey = usaBuildingPmtilesKey(this.config, regionCode);
    const snapshotBuildingKey = buildingPmtilesKey ?? layerKey(this.config, 'buildings', 'buildings.pmtiles');
    const addressPmtilesKey = usaAddressPmtilesKey(this.config, regionCode);
    const snapshotAddressKey = addressPmtilesKey ?? layerKey(this.config, 'addresses', 'addresses.pmtiles');
    const parcelPmtilesKey = usaParcelPmtilesKey(this.config, regionCode);
    const geojsonExtension = this.config.geojsonExtension ?? null;
    const metadataKey = `${prefix(this.config)}/${this.config.metadataFilename ?? `bedrock-${this.config.country}.json`}`;
    const tileMetrics = {
      artifact_type: 'diamond',
      diamond_mode: true,
      bedrock_mode: true,
      bedrock_country: this.config.country,
      bedrock_country_code: this.config.countryCode,
      bedrock_version: env(this.config, 'VERSION') || 'current',
      geometry_provider: 'pmtiles',
      pmtiles_key: buildingPmtilesKey,
      tilejson_key: layerKey(this.config, 'buildings', 'buildings.json'),
      buildings_pmtiles_index_key: layerKey(this.config, 'buildings', 'pmtiles-index.json'),
      buildings_geojson_key: geojsonExtension ? layerKey(this.config, 'buildings', `buildings.${geojsonExtension}`) : null,
      addresses_pmtiles_key: addressPmtilesKey,
      addresses_tilejson_key: layerKey(this.config, 'addresses', 'addresses.json'),
      addresses_geojson_key: geojsonExtension ? layerKey(this.config, 'addresses', `addresses.${geojsonExtension}`) : null,
      addresses_parquet_prefix: layerKey(this.config, 'addresses', 'parquet'),
      addresses_parquet_manifest_key: layerKey(this.config, 'addresses', 'parquet-manifest.json'),
      addresses_pmtiles_index_key: layerKey(this.config, 'addresses', 'pmtiles-index.json'),
      parcels_pmtiles_key: parcelPmtilesKey,
      parcels_tilejson_key: parcelPmtilesKey?.replace(/\.pmtiles$/i, '.json') ?? null,
      parcels_geojson_key: null,
      parcels_pmtiles_index_key: layerKey(this.config, 'parcels', 'pmtiles-index.json'),
      addresses_parquet_partitioning: {
        scheme: manifest.partitioning?.scheme ?? 'web_mercator_xyz',
        tile_z: manifest.partitioning?.tile_z ?? 12,
        columns: manifest.partitioning?.scheme === 'state' ? ['state'] : ['tile_z', 'tile_x', 'tile_y'],
        path_template:
          manifest.partitioning?.scheme === 'state'
            ? 'state={state}/*.parquet'
            : 'tile_z={tile_z}/tile_x={tile_x}/tile_y={tile_y}/*.parquet',
      },
      addresses_tile_seam_awareness: manifest.tile_seam_awareness ?? {
        enabled: true,
        tile_padding: 1,
        tile_z: manifest.partitioning?.tile_z ?? 12,
      },
      source_layers: {
        buildings: 'buildings',
        addresses: 'addresses',
        parcels: 'parcels',
      },
      promote_ids: {
        buildings: 'building_id',
        addresses: 'address_id',
        parcels: 'parcel_id',
      },
      join_key: 'address_id',
      sources: {
        addresses: this.config.defaultSource,
      },
      minzoom: 12,
      maxzoom: 18,
      address_minzoom: 10,
      address_maxzoom: 16,
      parcel_minzoom: 10,
      parcel_maxzoom: 16,
      addresses_count: addressCount,
      parcels_count: parcelCount,
      scan_metrics: {
        addresses: scanMetric,
        ...(buildingScanMetric ? { buildings: buildingScanMetric } : {}),
        ...(parcelScanMetric ? { parcels: parcelScanMetric } : {}),
      },
    };

    return {
      campaign_id: campaignId,
      bucket: bucket(this.config),
      prefix: prefix(this.config),
      counts: {
        buildings: buildingCount,
        addresses: addressCount,
        parcels: parcelCount,
        roads: 0,
      },
      s3_keys: {
        buildings: snapshotBuildingKey,
        addresses: snapshotAddressKey,
        ...(parcelPmtilesKey ? { parcels: parcelPmtilesKey } : {}),
        metadata: metadataKey,
      },
      urls: {
        buildings: cdnUrl(this.config, snapshotBuildingKey) ?? `s3://${bucket(this.config)}/${snapshotBuildingKey}`,
        addresses: cdnUrl(this.config, snapshotAddressKey) ?? `s3://${bucket(this.config)}/${snapshotAddressKey}`,
        ...(parcelPmtilesKey
          ? { parcels: cdnUrl(this.config, parcelPmtilesKey) ?? `s3://${bucket(this.config)}/${parcelPmtilesKey}` }
          : {}),
        metadata: `s3://${bucket(this.config)}/${metadataKey}`,
      },
      metadata: {
        elapsed_ms: Math.round(scanMetric.seconds * 1000),
        snapshot_size_bytes: 0,
        overture_release: this.config.overtureRelease,
        tile_metrics: tileMetrics as unknown as SnapshotTileMetrics,
      },
    };
  }
}

export const BEDROCK_CANADA_CONFIG: BedrockCountryConfig = {
  country: 'canada',
  countryCode: 'CA',
  provisionSource: 'bedrock_ca',
  envPrefix: 'BEDROCK_CA',
  defaultSource: 'Statistics Canada National Address Register',
  overtureRelease: 'bedrock-ca-statcan-nar',
};

export const BEDROCK_NZ_CONFIG: BedrockCountryConfig = {
  country: 'new-zealand',
  countryCode: 'NZ',
  provisionSource: 'bedrock_nz',
  envPrefix: 'BEDROCK_NZ',
  defaultSource: 'LINZ NZ Addresses',
  overtureRelease: 'bedrock-nz-linz',
  coordinateColumns: {
    longitude: 'lon',
    latitude: 'lat',
  },
  singleFileSpatialParquetLayers: ['addresses', 'buildings'],
  geojsonExtension: 'geojson.gz',
  metadataFilename: 'bedrock-new-zealand-manifest.json',
};

export const BEDROCK_AUSTRALIA_CONFIG: BedrockCountryConfig = {
  country: 'australia',
  countryCode: 'AU',
  provisionSource: 'bedrock_au',
  envPrefix: 'BEDROCK_AU',
  defaultSource: 'G-NAF',
  overtureRelease: 'bedrock-au-gnaf',
  buildingPrefix: 'bedrock/australia/buildings/national',
};

export const BEDROCK_US_CONFIG: BedrockCountryConfig = {
  country: 'usa',
  countryCode: 'US',
  provisionSource: 'bedrock_us',
  envPrefix: 'BEDROCK_US',
  defaultSource: 'Overture Maps Addresses',
  overtureRelease: 'bedrock-us-overture',
};

export const BEDROCK_SOUTH_AFRICA_CONFIG: BedrockCountryConfig = {
  country: 'south-africa',
  countryCode: 'ZA',
  provisionSource: 'bedrock_za',
  envPrefix: 'BEDROCK_ZA',
  defaultSource: 'OpenStreetMap Addresses',
  overtureRelease: 'bedrock-za-osm',
};

export const BEDROCK_UK_CONFIG: BedrockCountryConfig = {
  country: 'uk',
  countryCode: 'GB',
  provisionSource: 'bedrock_uk',
  envPrefix: 'BEDROCK_UK',
  defaultSource: 'OS Open UPRN',
  overtureRelease: 'bedrock-uk-os-open-uprn-overture',
};
