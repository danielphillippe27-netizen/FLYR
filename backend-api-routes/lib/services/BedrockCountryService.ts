import { GetObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { defaultProvider } from '@aws-sdk/credential-provider-node';
import { VectorTile } from '@mapbox/vector-tile';
import * as turf from '@turf/turf';
import { PMTiles } from 'pmtiles';
import Pbf from 'pbf';
import type { LambdaSnapshotResponse } from '@/lib/services/TileLambdaService';
import type { StandardCampaignAddress } from '@/lib/services/AddressAdapter';

type Bounds = [number, number, number, number];
type SnapshotTileMetrics = NonNullable<NonNullable<LambdaSnapshotResponse['metadata']>['tile_metrics']>;

export type BedrockProvisionSource = 'bedrock_au' | 'bedrock_ca' | 'bedrock_us' | 'bedrock_za' | 'bedrock_uk';

type BedrockCountryConfig = {
  country: 'australia' | 'canada' | 'usa' | 'south-africa' | 'uk';
  countryCode: 'AU' | 'CA' | 'US' | 'ZA' | 'GB';
  provisionSource: BedrockProvisionSource;
  envPrefix: 'BEDROCK_AU' | 'BEDROCK_CA' | 'BEDROCK_US' | 'BEDROCK_ZA' | 'BEDROCK_UK';
  defaultSource: string;
  overtureRelease: string;
  buildingPrefix?: string;
};

type ParquetManifest = {
  feature_count?: number;
  partitioning?: { scheme?: string; tile_z?: number };
  tile_seam_awareness?: { enabled?: boolean; tile_padding?: number; tile_z?: number; reason?: string };
  tile_counts?: Array<{ tile_z: number; tile_x: number; tile_y: number; feature_count: number }>;
  state_counts?: Array<{ state: string; feature_count?: number; path: string }>;
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
  geometry_json?: string;
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
  };
};

type PmtilesAddressFeature = {
  type: 'Feature';
  geometry?: {
    type: 'Point';
    coordinates?: [number, number];
  };
  properties?: Record<string, unknown>;
};

const DEFAULT_BUCKET = 'flyr-pro-addresses-2025';
const REGION = process.env.AWS_REGION || process.env.AWS_S3_BUCKET_REGION || 'us-east-2';
const WEB_MERCATOR_MAX_LAT = 85.05112878;
const USA_ADDRESS_REGIONS = new Set([
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
  'PR',
  'RI',
  'SC',
  'SD',
  'TN',
  'TX',
  'UT',
  'VA',
  'VI',
  'VT',
  'WA',
  'WI',
  'WV',
  'WY',
]);
const USA_BUILDING_REGIONS = new Set([
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
const USA_PARCEL_REGIONS = new Set([
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

let s3Client: S3Client | null = null;
let resolvedAwsCredentials:
  | { accessKeyId: string; secretAccessKey: string; sessionToken?: string }
  | null = null;

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
    };
  }
  if (!resolvedAwsCredentials) {
    const credentials = await defaultProvider()();
    resolvedAwsCredentials = {
      accessKeyId: credentials.accessKeyId,
      secretAccessKey: credentials.secretAccessKey,
      sessionToken: credentials.sessionToken,
    };
  }
  return resolvedAwsCredentials;
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

async function readManifest(config: BedrockCountryConfig): Promise<ParquetManifest> {
  return JSON.parse(await s3Text(config, layerKey(config, 'addresses', 'parquet-manifest.json'))) as ParquetManifest;
}

function parquetPathsForTiles(config: BedrockCountryConfig, manifest: ParquetManifest, bbox: Bounds, regionCode?: string | null) {
  const parquetPathFor = (relative: string) => {
    const key = layerKey(config, 'addresses', relative);
    return `s3://${bucket(config)}/${key}`;
  };

  if (manifest.partitioning?.scheme === 'state') {
    const normalizedRegion = regionCode?.trim().toUpperCase();
    const available = new Set((manifest.state_counts ?? []).map((entry) => entry.state.toUpperCase()));
    const candidates = [
      normalizedRegion,
      config.country === 'south-africa' && normalizedRegion !== config.countryCode ? config.countryCode : null,
    ].filter((candidate): candidate is string => Boolean(candidate));
    const state = available.size > 0
      ? candidates.find((candidate) => available.has(candidate))
      : candidates[0];

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

    const relative = `parquet/state=${state}/*.parquet`;
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

async function duckDbAll(sql: string, usesRemoteFiles: boolean): Promise<BedrockParquetRow[]> {
  const duckdbModule = await import('duckdb');
  const duckdb = (duckdbModule.default ?? duckdbModule) as typeof duckdbModule;
  const db = new duckdb.Database(':memory:');
  const all = (statement: string) =>
    new Promise<BedrockParquetRow[]>((resolve, reject) => {
      db.all(statement, (error: Error | null, rows: BedrockParquetRow[]) => {
        if (error) reject(error);
        else resolve(rows);
      });
    });

  try {
    if (usesRemoteFiles) {
      await all("SET home_directory='/tmp'");
      await all("SET extension_directory='/tmp/duckdb_extensions'");
      await all('INSTALL httpfs');
      await all('LOAD httpfs');
      if (sql.includes('s3://')) {
        await all(`SET s3_region=${sqlString(REGION)}`);
        const credentials = await getAwsCredentials();
        if (credentials?.accessKeyId && credentials.secretAccessKey) {
          await all(`SET s3_access_key_id=${sqlString(credentials.accessKeyId)}`);
          await all(`SET s3_secret_access_key=${sqlString(credentials.secretAccessKey)}`);
          if (credentials.sessionToken) {
            await all(`SET s3_session_token=${sqlString(credentials.sessionToken)}`);
          }
        }
      }
    }
    return await all(sql);
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

function text(value: unknown) {
  return typeof value === 'string' && value.trim() ? value.trim() : undefined;
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
  const streetName = text(name);
  const streetType = text(type);
  if (!streetName) return undefined;
  if (!streetType) return streetName;

  const normalizedName = streetName.toUpperCase();
  const normalizedType = streetType.toUpperCase();
  if (normalizedName === normalizedType || normalizedName.endsWith(` ${normalizedType}`)) {
    return streetName;
  }
  return `${streetName} ${streetType}`;
}

function normalizeAddress(config: BedrockCountryConfig, campaignId: string, row: BedrockParquetRow): StandardCampaignAddress | null {
  const lon = Number(row.longitude);
  const lat = Number(row.latitude);
  if (!Number.isFinite(lon) || !Number.isFinite(lat)) return null;

  const props = parseProperties(row);
  const geometry =
    typeof row.geometry_json === 'string' && row.geometry_json.trim()
      ? row.geometry_json
      : JSON.stringify({ type: 'Point', coordinates: [lon, lat] });
  const addressId =
    text(row.address_id) ??
    text(props.address_id) ??
    text(row.address_detail_pid) ??
    text(props.address_detail_pid) ??
    text(row.source_id) ??
    text(props.source_id) ??
    text(row.uprn) ??
    text(props.uprn) ??
    text(row.gers_id);
  const houseNumber =
    text(row.house_number) ??
    text(row.house_number_label) ??
    text(row.number_first) ??
    text(row.street_number) ??
    text(props.house_number) ??
    text(props.house_number_label) ??
    text(props.number_first) ??
    text(props.street_number) ??
    text(props.address_number);
  const streetName =
    streetLabel(row.street_name, row.street_type) ??
    streetLabel(props.street_name, props.street_type);
  const unit = text(row.unit) ?? text(props.unit) ?? text(props.unit_number) ?? text(props.suite);
  const locality =
    text(row.locality) ??
    text(props.locality) ??
    text(row.locality_name) ??
    text(props.locality_name) ??
    text(row.city);
  const formatted =
    text(row.full_address) ??
    text(row.formatted) ??
    text(props.full_address) ??
    ([houseNumber, streetName, locality].filter(Boolean).join(' ') ||
      fallbackAddressLabel(config, row, props, addressId));

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
  const addressId =
    text(props.address_id) ??
    text(props.address_detail_pid) ??
    text(props.source_id) ??
    text(props.uprn) ??
    text(props.gers_id);
  const houseNumber =
    text(props.house_number) ??
    text(props.house_number_label) ??
    text(props.street_number) ??
    text(props.number_first) ??
    text(props.address_number);
  const streetName = streetLabel(props.street_name, props.street_type);
  const unit = text(props.unit) ?? text(props.unit_number) ?? text(props.suite);
  const locality = text(props.locality) ?? text(props.locality_name) ?? text(props.city);
  const formatted =
    text(props.full_address) ??
    text(props.formatted) ??
    ([houseNumber, streetName, locality].filter(Boolean).join(' ') ||
      fallbackAddressLabel(config, {}, props, addressId));

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
  return typeof value === 'string' ? value.trim().toLowerCase() : '';
}

function normalizedAddressIdentity(address: StandardCampaignAddress): string | null {
  const unit = normalizedAddressFragment(address.unit);
  const houseNumber = normalizedAddressFragment(address.house_number);
  const streetName = normalizedAddressFragment(address.street_name);
  const locality = normalizedAddressFragment(address.locality);
  const postalCode = normalizedAddressFragment(address.postal_code);

  if (houseNumber || streetName || locality) {
    return [unit, houseNumber, streetName, locality, postalCode].join('|');
  }

  const formatted = normalizedAddressFragment(address.formatted);
  return formatted || postalCode ? [formatted, postalCode].join('|') : null;
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

  const url = layerUrl(options.config, 'addresses', pmtilesKey.split('/').pop() ?? 'addresses.pmtiles');
  const resolvedUrl = cdnUrl(options.config, pmtilesKey) ?? url;
  if (!/^https?:\/\//i.test(resolvedUrl)) {
    return null;
  }

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
    metrics: { addresses: BedrockScanResult };
  }> {
    const startedAt = Date.now();
    const bbox = turf.bbox(options.polygon) as Bounds;

    const manifestStartedAt = Date.now();
    const manifest = await readManifest(this.config);
    const manifestMs = Date.now() - manifestStartedAt;

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
      partitionMs,
      bbox,
    });

    const queryStartedAt = Date.now();
    let addresses: StandardCampaignAddress[] = [];
    let metric: BedrockScanResult;

    try {
      const rows = await duckDbAll(
        `
          SELECT *
          FROM read_parquet([${paths.map(sqlString).join(',')}], hive_partitioning=1, union_by_name=true)
          WHERE longitude BETWEEN ${sqlNumber(bbox[0])} AND ${sqlNumber(bbox[2])}
            AND latitude BETWEEN ${sqlNumber(bbox[1])} AND ${sqlNumber(bbox[3])}
        `,
        paths.some((path) => path.startsWith('s3://') || /^https?:\/\//i.test(path))
      );
      const queryMs = Date.now() - queryStartedAt;

      const filterStartedAt = Date.now();
      for (const row of rows) {
        const lon = Number(row.longitude);
        const lat = Number(row.latitude);
        if (!Number.isFinite(lon) || !Number.isFinite(lat)) continue;
        if (!turf.booleanPointInPolygon(turf.point([lon, lat]), options.polygon)) continue;
        const address = normalizeAddress(this.config, options.campaignId, row);
        if (!address) continue;
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

    return {
      addresses,
      metrics: { addresses: metric },
      snapshot: this.snapshotForCampaign(options.campaignId, addresses.length, metric, manifest, options.regionCode),
    };
  }

  snapshotForCampaign(
    campaignId: string,
    addressCount: number,
    scanMetric: BedrockScanResult,
    manifest: ParquetManifest,
    regionCode?: string | null
  ): LambdaSnapshotResponse {
    const buildingPmtilesKey = usaBuildingPmtilesKey(this.config, regionCode);
    const snapshotBuildingKey = buildingPmtilesKey ?? layerKey(this.config, 'buildings', 'buildings.pmtiles');
    const addressPmtilesKey = usaAddressPmtilesKey(this.config, regionCode);
    const snapshotAddressKey = addressPmtilesKey ?? layerKey(this.config, 'addresses', 'addresses.pmtiles');
    const parcelPmtilesKey = usaParcelPmtilesKey(this.config, regionCode);
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
      buildings_geojson_key: layerKey(this.config, 'buildings', 'buildings.ndjson.gz'),
      addresses_pmtiles_key: addressPmtilesKey,
      addresses_tilejson_key: layerKey(this.config, 'addresses', 'addresses.json'),
      addresses_geojson_key: layerKey(this.config, 'addresses', 'addresses.ndjson.gz'),
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
      scan_metrics: {
        addresses: scanMetric,
      },
    };

    return {
      campaign_id: campaignId,
      bucket: bucket(this.config),
      prefix: prefix(this.config),
      counts: {
        buildings: 0,
        addresses: addressCount,
        roads: 0,
      },
      s3_keys: {
        buildings: snapshotBuildingKey,
        addresses: snapshotAddressKey,
        metadata: `${prefix(this.config)}/bedrock-${this.config.country}.json`,
      },
      urls: {
        buildings: cdnUrl(this.config, snapshotBuildingKey) ?? `s3://${bucket(this.config)}/${snapshotBuildingKey}`,
        addresses: cdnUrl(this.config, snapshotAddressKey) ?? `s3://${bucket(this.config)}/${snapshotAddressKey}`,
        metadata: `s3://${bucket(this.config)}/${prefix(this.config)}/bedrock-${this.config.country}.json`,
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
