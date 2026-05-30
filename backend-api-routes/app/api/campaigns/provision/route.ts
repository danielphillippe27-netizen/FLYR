import { after, NextRequest, NextResponse } from 'next/server';
import { createHash } from 'node:crypto';
import { createAdminClient } from '@/lib/supabase/server';
import type { LambdaSnapshotResponse } from '@/lib/services/TileLambdaService';
import type { StandardCampaignAddress } from '@/lib/services/AddressAdapter';
import { BedrockProvisionService, type BedrockLinkGeometry } from '@/lib/services/BedrockProvisionService';
import { DiamondMunicipalService } from '@/lib/services/DiamondMunicipalService';
import { resolveCampaignRegion } from '@/lib/geo/regionResolver';
import { resolveUserFromRequest } from '@/app/api/_utils/request-user';
import { fetchScopedPmtilesBuildingFeatures } from '@/app/api/campaigns/_utils/scoped-pmtiles-buildings';
import type { CampaignSnapshotRow } from '@/lib/diamond/geometry';
import {
  ParcelEnrichmentService,
  type ParcelEnrichmentStatus,
} from '@/lib/services/ParcelEnrichmentService';
import { CampaignMapBundleService } from '@/lib/services/CampaignMapBundleService';
import { isParcelRegionSupported } from '@/lib/geo/parcelRegions';
import { sendCampaignReadyNotificationOnce } from '@/lib/notifications/campaign-ready';
import {
  ProvisionTimingRecorder,
  buildCanonicalBuildingLinksFromMemory,
  buildCanonicalBuildingLinksFromPreparedRows,
  buildParcelAddressLinksFromPreparedRows,
  prepareBuildingsFromRows,
  type AddressOrphanLinkerRow,
  type AutoBuildingLinkRow,
  type AutoParcelAddressLinkRow,
  type LinkerParcelRow,
  type ProvisionTimingSnapshot,
} from '@/lib/services/ProvisionPerformance';
import { TownhouseSplitterService, type SplitterResult } from '@/lib/services/TownhouseSplitterService';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export const maxDuration = 300;

interface ProvisionRequest {
  campaign_id: string;
  wait_for_linker?: boolean;
  wait_for_postprocess?: boolean;
  require_linked_homes?: boolean;
}

type ProvisionSource = 'diamond' | 'bedrock';

type AutoLinkCampaignAddressesResult = {
  linked?: unknown;
  skipped_manual?: unknown;
  unlinked?: unknown;
  parcel_linked?: unknown;
  address_orphans?: AddressOrphanLinkerRow[];
  links?: AutoLinkRow[];
};

type CampaignPostProcessingResult = {
  optimized: boolean;
  postprocessDeferred: boolean;
  linkedAddressCount: number;
  skippedManualCount: number;
  unlinkedAddressCount: number;
  unitsCreated: number;
  townhousesIdentified: number;
  linkerPath: 'in_memory' | 'in_process' | 'postgis_rpc' | 'deferred' | 'failed';
  message: string;
};

type ResolvedProvisionResult = {
  addressSource: ProvisionSource;
  snapshot: LambdaSnapshotResponse;
  addressesToInsert: StandardCampaignAddress[];
  bedrockLinkGeometry: BedrockLinkGeometry | null;
  sourceMetrics?: unknown;
};

type ExistingCampaignAddressSignatureRow = {
  formatted: string | null;
  house_number: string | null;
  street_name: string | null;
  locality: string | null;
  postal_code: string | null;
  source: string | null;
  source_id: string | null;
  gers_id: string | null;
};

type CampaignAddressLinkerRow = {
  id: string;
  source_id?: string | null;
  coordinate?: { lon?: unknown; lat?: unknown } | null;
  geom?: GeoJSON.Point | null;
  street_match_score?: unknown;
  house_number_score?: unknown;
  match_score?: unknown;
  score?: unknown;
};

type CampaignBuildingLinkerRow = {
  id: string;
  gers_id?: string | null;
  geom?: GeoJSON.Polygon | GeoJSON.MultiPolygon | null;
  height_m?: number | null;
  units_count?: number | null;
  unit_count?: number | null;
  building_class?: string | null;
  is_townhome_row?: boolean | null;
  is_multi_unit?: boolean | null;
};

type CampaignParcelLinkerRow = LinkerParcelRow;

type AutoLinkRow = AutoBuildingLinkRow;
type AutoParcelLinkRow = AutoParcelAddressLinkRow;

type MaterializedBuildingResult = {
  count: number;
  buildings: CampaignBuildingLinkerRow[];
};

type CampaignAddressInsertResult = {
  count: number;
  addresses: CampaignAddressLinkerRow[];
};

const DEFAULT_STATIC_GEOMETRY_ADDRESS_HYDRATION_LIMIT = 5000;
const FALLBACK_INSERT_BATCH_SIZE = 500;
const BULK_ADDRESS_RPC = 'add_campaign_addresses';
const POLISHED_BUILDING_GEOMETRY_VERSION = 8;
const MAX_PROVISION_ERROR_LENGTH = 2000;
const DEFAULT_SOURCE_RESOLUTION_TIMEOUT_MS = 240_000;
const AUTO_LINK_DISTANCE_METERS = 15;
const MIN_HYBRID_LINK_RATIO = 0.8;

class ProvisionError extends Error {
  constructor(message: string, readonly status: number = 500) {
    super(message);
    this.name = 'ProvisionError';
  }
}

function dbProvisionSource(source: ProvisionSource): ProvisionSource {
  return source;
}

function sourceDisplayName(source: ProvisionSource): string {
  return source === 'diamond' ? 'Diamond' : 'Bedrock';
}

function jsonNumber(value: unknown): number {
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function provisionFailureMessage(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  return (message || 'Provisioning failed').slice(0, MAX_PROVISION_ERROR_LENGTH);
}

function sourceResolutionTimeoutMs() {
  const raw = process.env.PROVISION_SOURCE_RESOLUTION_TIMEOUT_MS;
  const parsed = raw ? Number(raw) : NaN;
  return Number.isFinite(parsed) && parsed > 0
    ? Math.floor(parsed)
    : DEFAULT_SOURCE_RESOLUTION_TIMEOUT_MS;
}

function territoryHash(polygon: unknown): string {
  return createHash('sha1').update(JSON.stringify(polygon)).digest('hex');
}

async function persistProvisionTimings(
  supabase: ReturnType<typeof createAdminClient>,
  campaignId: string,
  timings: ProvisionTimingSnapshot
): Promise<void> {
  const { error } = await supabase
    .from('campaigns')
    .update({ provision_timings: timings })
    .eq('id', campaignId);

  if (error) {
    console.warn('[Provision] Failed to persist provision timings:', error.message);
  }
}

async function withTimeout<T>(
  promise: Promise<T>,
  timeoutMs: number,
  message: string
): Promise<T> {
  let timeout: ReturnType<typeof setTimeout> | null = null;
  try {
    return await Promise.race([
      promise,
      new Promise<never>((_, reject) => {
        timeout = setTimeout(() => reject(new Error(message)), timeoutMs);
      }),
    ]);
  } finally {
    if (timeout) {
      clearTimeout(timeout);
    }
  }
}

async function markCampaignProvisionFailed(
  supabase: ReturnType<typeof createAdminClient>,
  campaignId: string,
  error: unknown
): Promise<void> {
  const message = provisionFailureMessage(error);
  const failedPatch = {
    provision_status: 'failed',
    provision_phase: 'failed',
    provision_error: message,
    provision_message: message,
  };
  const { error: updateError } = await supabase
    .from('campaigns')
    .update(failedPatch)
    .eq('id', campaignId);

  if (updateError) {
    const missingErrorColumns =
      updateError.code === '42703' ||
      updateError.message.includes('provision_error') ||
      updateError.message.includes('provision_message');

    if (missingErrorColumns) {
      const { error: fallbackError } = await supabase
        .from('campaigns')
        .update({
          provision_status: 'failed',
          provision_phase: 'failed',
        })
        .eq('id', campaignId);

      if (!fallbackError) {
        console.warn('[Provision] Failed state persisted without provision error text; apply provision error column migration.', {
          campaignId,
          message,
        });
        return;
      }

      throw new Error(`Failed to update failed provision state: ${fallbackError.message}`);
    }

    throw new Error(`Failed to update failed provision state: ${updateError.message}`);
  }
}

function staticGeometryAddressHydrationLimit() {
  const raw =
    process.env.STATIC_GEOMETRY_ADDRESS_HYDRATION_LIMIT ??
    process.env.BEDROCK_ADDRESS_HYDRATION_LIMIT;
  const parsed = raw ? Number(raw) : NaN;
  return Number.isFinite(parsed) && parsed >= 0
    ? Math.floor(parsed)
    : DEFAULT_STATIC_GEOMETRY_ADDRESS_HYDRATION_LIMIT;
}

function isConnectionError(error: Error): boolean {
  return (
    error.message.includes('closed') ||
    error.message.includes('Connection Error') ||
    error.message.includes('established') ||
    error.message.includes('timeout')
  );
}

async function retryWithBackoff<T>(
  fn: () => Promise<T>,
  maxAttempts: number = 3,
  baseDelay: number = 200
): Promise<T> {
  let lastError: Error | null = null;

  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    try {
      return await fn();
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error));
      if (!isConnectionError(lastError) || attempt === maxAttempts) {
        throw lastError;
      }

      const delay = baseDelay * Math.pow(2, attempt - 1);
      console.warn(`[Provision] Retry attempt ${attempt}/${maxAttempts} after ${delay}ms...`);
      await new Promise((resolve) => setTimeout(resolve, delay));
    }
  }

  throw lastError ?? new Error('Retry failed');
}

function deduplicateAddresses(addresses: StandardCampaignAddress[]): StandardCampaignAddress[] {
  return Array.from(
    new Map(
      addresses.map((address) => {
        return [buildAddressIdentity(address), address] as const;
      })
    ).values()
  );
}

function normalizeAddressFragment(value: string | null | undefined): string {
  return typeof value === 'string' ? value.trim().toLowerCase() : '';
}

function normalizeSource(value: string | null | undefined): string {
  const normalized = normalizeAddressFragment(value);
  return normalized || 'unknown';
}

function normalizeExternalAddressId(value: string | null | undefined): string {
  return typeof value === 'string' ? value.trim() : '';
}

function normalizedFeatureString(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function normalizeCachedBuildingIdentity(feature: Record<string, unknown>): Record<string, unknown> {
  const existingProperties =
    feature.properties && typeof feature.properties === 'object'
      ? (feature.properties as Record<string, unknown>)
      : {};
  const publicId =
    normalizedFeatureString(existingProperties.public_building_id) ??
    normalizedFeatureString(existingProperties.canonical_building_id) ??
    normalizedFeatureString(existingProperties.gers_id) ??
    normalizedFeatureString(existingProperties.building_id) ??
    normalizedFeatureString(existingProperties.id) ??
    normalizedFeatureString(feature.id);

  if (!publicId) return feature;

  const source = normalizedFeatureString(existingProperties.source)?.toLowerCase() ?? '';
  const identifierSource =
    normalizedFeatureString(existingProperties.building_identifier_source) ??
    (source.includes('diamond') || source.startsWith('bedrock') ? 'diamond' : null) ??
    (normalizedFeatureString(existingProperties.gers_id) ? 'gers' : 'feature');

  return {
    ...feature,
    id: normalizedFeatureString(feature.id) ?? publicId,
    properties: {
      ...existingProperties,
      id: normalizedFeatureString(existingProperties.id) ?? publicId,
      building_id: normalizedFeatureString(existingProperties.building_id) ?? publicId,
      gers_id: normalizedFeatureString(existingProperties.gers_id) ?? publicId,
      public_building_id: normalizedFeatureString(existingProperties.public_building_id) ?? publicId,
      canonical_building_id: normalizedFeatureString(existingProperties.canonical_building_id) ?? publicId,
      building_identifier_source: identifierSource,
    },
  };
}

function externalAddressId(address: { gers_id?: string | null; source_id?: string | null }): string {
  return normalizeExternalAddressId(address.gers_id ?? address.source_id);
}

function buildAddressSignature(address: {
  formatted?: string | null;
  house_number?: string | null;
  street_name?: string | null;
  unit?: string | null;
  locality?: string | null;
  postal_code?: string | null;
}): string {
  const unit = normalizeAddressFragment(address.unit);
  const houseNumber = normalizeAddressFragment(address.house_number);
  const streetName = normalizeAddressFragment(address.street_name);
  const locality = normalizeAddressFragment(address.locality);
  const postalCode = normalizeAddressFragment(address.postal_code);

  if (houseNumber || streetName || locality) {
    return `${unit}|${houseNumber}|${streetName}|${locality}|${postalCode}`;
  }

  const formatted = normalizeAddressFragment(address.formatted);
  return `${formatted}|${postalCode}`;
}

function hasAddressSignature(address: {
  formatted?: string | null;
  house_number?: string | null;
  street_name?: string | null;
  locality?: string | null;
  postal_code?: string | null;
}): boolean {
  return Boolean(
    normalizeAddressFragment(address.house_number) ||
      normalizeAddressFragment(address.street_name) ||
      normalizeAddressFragment(address.locality) ||
      normalizeAddressFragment(address.formatted) ||
      normalizeAddressFragment(address.postal_code)
  );
}

function buildAddressIdentity(address: {
  campaign_id: string;
  formatted?: string | null;
  house_number?: string | null;
  street_name?: string | null;
  unit?: string | null;
  locality?: string | null;
  postal_code?: string | null;
  source?: string | null;
  source_id?: string | null;
  gers_id?: string | null;
}): string {
  const source = normalizeSource(address.source);
  if (hasAddressSignature(address)) {
    return `${address.campaign_id}|${source}|address|${buildAddressSignature(address)}`;
  }

  const externalId = externalAddressId(address);
  if (externalId) {
    return `${address.campaign_id}|${source}|external|${externalId}`;
  }

  return `${address.campaign_id}|${source}|address|`;
}

function deduplicateAddressesByProvisionKey(
  addresses: StandardCampaignAddress[]
): StandardCampaignAddress[] {
  const deduped = new Map<string, StandardCampaignAddress>();

  for (const address of addresses) {
    const externalId = externalAddressId(address);
    deduped.set(buildAddressIdentity(address), {
      ...address,
      gers_id: externalId || null,
    });
  }

  return [...deduped.values()];
}

async function fetchCampaignAddressSignatures(
  supabase: ReturnType<typeof createAdminClient>,
  campaignId: string
): Promise<Set<string>> {
  const { data, error } = await supabase
    .from('campaign_addresses')
    .select('formatted, house_number, street_name, locality, postal_code, source, source_id, gers_id')
    .eq('campaign_id', campaignId);

  if (error) {
    throw new Error(`Failed to fetch campaign address signatures: ${error.message}`);
  }

  return new Set(
    ((data ?? []) as ExistingCampaignAddressSignatureRow[]).map((row) =>
      buildAddressIdentity({
        campaign_id: campaignId,
        formatted: row.formatted,
        house_number: row.house_number,
        street_name: row.street_name,
        locality: row.locality,
        postal_code: row.postal_code,
        source: row.source,
        source_id: row.source_id,
        gers_id: row.gers_id,
      })
    )
  );
}

function filterAddressesAgainstExisting(
  addresses: StandardCampaignAddress[],
  existingSignatures: Set<string>
): StandardCampaignAddress[] {
  const accepted: StandardCampaignAddress[] = [];
  const seenThisBatch = new Set<string>();

  for (const address of addresses) {
    const signature = buildAddressIdentity(address);
    if (existingSignatures.has(signature) || seenThisBatch.has(signature)) {
      continue;
    }
    seenThisBatch.add(signature);
    accepted.push(address);
  }

  return accepted;
}

function isUniqueConstraintError(error: { message?: string; code?: string; details?: string } | null): boolean {
  if (!error) {
    return false;
  }

  const text = `${error.message ?? ''} ${error.details ?? ''}`.toLowerCase();
  return error.code === '23505' || text.includes('unique') || text.includes('constraint') || text.includes('conflict');
}

function stringTileMetric(
  metrics: Record<string, unknown> | null | undefined,
  key: string
): string | null {
  const value = metrics?.[key];
  return typeof value === 'string' && value.trim().length > 0 ? value.trim() : null;
}

function snapshotHasStaticPmtilesGeometry(
  snapshot: LambdaSnapshotResponse | null | undefined
): boolean {
  if (!snapshot) return false;

  const metrics = snapshot.metadata?.tile_metrics;
  const buildingsKey = snapshot.s3_keys.buildings;
  const addressesKey = snapshot.s3_keys.addresses;

  return [
    buildingsKey,
    addressesKey,
    stringTileMetric(metrics, 'pmtiles_key'),
    stringTileMetric(metrics, 'addresses_pmtiles_key'),
    stringTileMetric(metrics, 'parcels_pmtiles_key'),
  ].some((key) => typeof key === 'string' && key.toLowerCase().endsWith('.pmtiles'));
}

function snapshotHasStaticBuildingPmtiles(
  snapshot: LambdaSnapshotResponse | null | undefined
): boolean {
  if (!snapshot) return false;

  const metrics = snapshot.metadata?.tile_metrics;
  return [
    snapshot.s3_keys.buildings,
    stringTileMetric(metrics, 'pmtiles_key'),
  ].some((key) => typeof key === 'string' && key.toLowerCase().endsWith('.pmtiles'));
}

function bboxFromPolygon(polygon: GeoJSON.Polygon): [number, number, number, number] | null {
  const positions = polygon.coordinates.flat().filter(
    (position): position is [number, number] =>
      Array.isArray(position) &&
      typeof position[0] === 'number' &&
      typeof position[1] === 'number' &&
      Number.isFinite(position[0]) &&
      Number.isFinite(position[1])
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

function lambdaSnapshotToCampaignSnapshotRow(snapshot: LambdaSnapshotResponse): CampaignSnapshotRow {
  return {
    bucket: snapshot.bucket,
    prefix: snapshot.prefix,
    buildings_key: snapshot.s3_keys.buildings,
    addresses_key: snapshot.s3_keys.addresses,
    buildings_url: snapshot.urls.buildings,
    metadata_key: snapshot.s3_keys.metadata,
    buildings_count: snapshot.counts.buildings,
    created_at: null,
    tile_metrics: (snapshot.metadata?.tile_metrics ?? null) as Record<string, unknown> | null,
  };
}

function isMissingPolishedCacheTable(error: unknown): boolean {
  const message = String((error as { message?: unknown })?.message ?? '').toLowerCase();
  return message.includes('campaign_polished_building_features') ||
    message.includes('schema cache') ||
    message.includes('does not exist');
}

async function fetchCampaignLinkerBuildings(
  supabase: ReturnType<typeof createAdminClient>,
  campaignId: string
): Promise<CampaignBuildingLinkerRow[]> {
  return fetchAllCampaignRows<CampaignBuildingLinkerRow>(
    supabase,
    'buildings',
    'id, gers_id, geom, height_m, units_count, is_townhome_row',
    campaignId
  );
}

async function fetchCampaignLinkerParcels(
  supabase: ReturnType<typeof createAdminClient>,
  campaignId: string
): Promise<CampaignParcelLinkerRow[]> {
  const rows = await fetchAllCampaignRows<{
    id: string | null;
    external_id: string | null;
    geom: GeoJSON.Polygon | GeoJSON.MultiPolygon | string | null;
  }>(
    supabase,
    'campaign_parcels',
    'id, external_id, geom',
    campaignId
  );

  return rows.flatMap((row) => {
    const rawGeometry = row.geom;
    const geometry = typeof rawGeometry === 'string'
      ? (() => {
        try {
          return JSON.parse(rawGeometry) as GeoJSON.Polygon | GeoJSON.MultiPolygon;
        } catch {
          return null;
        }
      })()
      : rawGeometry;
    if (geometry?.type !== 'Polygon' && geometry?.type !== 'MultiPolygon') return [];
    return [{
      id: row.id,
      externalId: row.external_id,
      geometry,
    }];
  });
}

async function persistPreparedParcels(
  supabase: ReturnType<typeof createAdminClient>,
  campaignId: string,
  parcels: NonNullable<BedrockLinkGeometry['parcels']>
): Promise<number> {
  const normalizedParcels = parcels.flatMap((parcel) => {
    const geometry = parcel.geometry as GeoJSON.Polygon | GeoJSON.MultiPolygon | null | undefined;
    if (geometry?.type !== 'Polygon' && geometry?.type !== 'MultiPolygon') return [];
    return [{
      externalId: parcel.externalId,
      geometry,
      properties: parcel.properties ?? {},
    }];
  });

  await supabase
    .from('campaign_parcels')
    .delete()
    .eq('campaign_id', campaignId);

  if (normalizedParcels.length === 0) {
    return 0;
  }

  for (let index = 0; index < normalizedParcels.length; index += FALLBACK_INSERT_BATCH_SIZE) {
    const chunk = normalizedParcels.slice(index, index + FALLBACK_INSERT_BATCH_SIZE);
    const { error } = await supabase
      .from('campaign_parcels')
      .insert(chunk.map((parcel) => ({
        campaign_id: campaignId,
        external_id: parcel.externalId,
        geom: JSON.stringify(parcel.geometry),
        properties: {
          ...parcel.properties,
          parcel_id: parcel.externalId,
          source: 'bedrock_link_geometry',
        },
      })));

    if (error) {
      throw new Error(`Prepared parcel insert failed: ${error.message}`);
    }
  }

  await updateCampaignProvision(supabase, campaignId, {
    has_parcels: true,
    parcel_enrichment_status: 'ready',
    parcel_source_id: 'bedrock_link_geometry',
    parcel_count: normalizedParcels.length,
    parcel_enriched_at: new Date().toISOString(),
    parcel_enrichment_error: null,
    parcel_enrichment_debug: {
      source_id: 'bedrock_link_geometry',
      inserted_count: normalizedParcels.length,
      completed_at: new Date().toISOString(),
    },
  });

  return normalizedParcels.length;
}

type ProvisionParcelPreparationResult = {
  count: number;
  status: ParcelEnrichmentStatus;
  sourceId: string | null;
  error: string | null;
  shouldRunDeferred: boolean;
};

async function prepareProvisionParcels(params: {
  supabase: ReturnType<typeof createAdminClient>;
  campaignId: string;
  regionCode: string;
  bedrockLinkGeometry?: BedrockLinkGeometry | null;
}): Promise<ProvisionParcelPreparationResult> {
  const preparedLinkGeometryParcels = params.bedrockLinkGeometry?.parcels ?? [];
  if (preparedLinkGeometryParcels.length > 0) {
    const count = await persistPreparedParcels(
      params.supabase,
      params.campaignId,
      preparedLinkGeometryParcels
    );
    return {
      count,
      status: count > 0 ? 'ready' : 'skipped',
      sourceId: count > 0 ? 'bedrock_link_geometry' : null,
      error: null,
      shouldRunDeferred: false,
    };
  }

  if (!isParcelRegionSupported(params.regionCode)) {
    return {
      count: 0,
      status: 'skipped',
      sourceId: null,
      error: null,
      shouldRunDeferred: false,
    };
  }

  try {
    const result = await new ParcelEnrichmentService(params.supabase)
      .prepareParcelsForProvision(params.campaignId);
    return {
      count: result.status === 'ready' ? result.parcelCount : 0,
      status: result.status,
      sourceId: result.sourceId,
      error: result.error,
      shouldRunDeferred: false,
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.warn('[Provision] Gold parcel preparation failed; deferring parcel enrichment retry:', {
      campaignId: params.campaignId,
      message,
    });
    await new ParcelEnrichmentService(params.supabase).markQueued(params.campaignId);
    return {
      count: 0,
      status: 'queued',
      sourceId: null,
      error: message,
      shouldRunDeferred: true,
    };
  }
}

async function runDeferredParcelEnrichment(campaignId: string) {
  try {
    const supabase = createAdminClient();
    await new ParcelEnrichmentService(supabase).runForCampaign(campaignId);
  } catch (error) {
    console.error('[Provision] Deferred parcel enrichment failed:', {
      campaignId,
      error: error instanceof Error ? error.message : error,
    });
  }
}

function scheduleDeferredParcelEnrichment(campaignId: string) {
  try {
    after(() => runDeferredParcelEnrichment(campaignId));
  } catch (error) {
    console.warn('[Provision] Next after() unavailable for parcel enrichment; running best-effort fallback.', {
      campaignId,
      error: error instanceof Error ? error.message : error,
    });
    void runDeferredParcelEnrichment(campaignId);
  }
}

async function cachePolishedBuildingGeoJSON(
  supabase: ReturnType<typeof createAdminClient>,
  campaignId: string,
  source: 'gold' | 'silver',
  featureCollection: unknown
): Promise<MaterializedBuildingResult> {
  const features =
    featureCollection &&
    typeof featureCollection === 'object' &&
    Array.isArray((featureCollection as { features?: unknown }).features)
      ? (featureCollection as { features: unknown[] }).features
      : [];

  const renderableFeatures = features.filter((feature) => {
    if (!feature || typeof feature !== 'object') return false;
    const geometry = (feature as { geometry?: { type?: unknown } }).geometry;
    return geometry?.type === 'Polygon' || geometry?.type === 'MultiPolygon';
  });

  if (renderableFeatures.length === 0) return { count: 0, buildings: [] };

  const versionedFeatures = renderableFeatures.map((feature) => {
    const record = normalizeCachedBuildingIdentity(feature as Record<string, unknown>);
    const existingProperties =
      record.properties && typeof record.properties === 'object'
        ? (record.properties as Record<string, unknown>)
        : {};

    return {
      ...record,
      properties: {
        ...existingProperties,
        polished_geometry_version: POLISHED_BUILDING_GEOMETRY_VERSION,
      },
    };
  });

  const { data: materializedCount, error: materializeError } = await supabase.rpc(
    'materialize_campaign_buildings_from_geojson',
    {
      p_campaign_id: campaignId,
      p_features: {
        type: 'FeatureCollection',
        features: versionedFeatures,
      },
      p_source: source,
    }
  );

  if (materializeError) {
    console.warn('[Provision] Campaign building materialization failed:', {
      campaignId,
      source,
      message: materializeError.message,
      code: materializeError.code,
      details: materializeError.details,
    });
  } else {
    console.log('[Provision] Materialized campaign buildings into PostGIS', {
      campaignId,
      source,
      buildings: jsonNumber(materializedCount),
    });
  }

  const materializedBuildings = materializeError
    ? []
    : await fetchCampaignLinkerBuildings(supabase, campaignId);

  const { error } = await supabase
    .from('campaign_polished_building_features')
    .upsert(
      {
        campaign_id: campaignId,
        source,
        feature_count: renderableFeatures.length,
        feature_collection: {
          type: 'FeatureCollection',
          features: versionedFeatures,
        },
        updated_at: new Date().toISOString(),
      },
      { onConflict: 'campaign_id' }
    );

  if (error) {
    if (!isMissingPolishedCacheTable(error)) {
      console.warn('[Provision] Polished building cache write failed:', error.message);
    }
    return { count: materializedBuildings.length, buildings: materializedBuildings };
  }

  console.log('[Provision] Cached polished building GeoJSON', {
    campaignId,
    source,
    features: renderableFeatures.length,
  });
  return { count: renderableFeatures.length, buildings: materializedBuildings };
}

async function materializeBuildingGeoJSONForMapReady(params: {
  supabase: ReturnType<typeof createAdminClient>;
  campaignId: string;
  polygon: GeoJSON.Polygon;
  source: ProvisionSource;
  snapshot: LambdaSnapshotResponse | null;
  bedrockLinkGeometry?: BedrockLinkGeometry | null;
}): Promise<MaterializedBuildingResult> {
  const { supabase, campaignId, polygon, source, snapshot, bedrockLinkGeometry } = params;

  if (bedrockLinkGeometry?.buildings?.length) {
    return cachePolishedBuildingGeoJSON(
      supabase,
      campaignId,
      source === 'diamond' ? 'gold' : 'silver',
      {
        type: 'FeatureCollection',
        features: bedrockLinkGeometry.buildings,
      }
    );
  }

  if (!snapshot || !snapshotHasStaticBuildingPmtiles(snapshot)) {
    return { count: 0, buildings: [] };
  }

  const bbox = bboxFromPolygon(polygon);
  if (!bbox) return { count: 0, buildings: [] };

  try {
    const scopedBuildings = await fetchScopedPmtilesBuildingFeatures(
      lambdaSnapshotToCampaignSnapshotRow(snapshot),
      bbox,
      new Set(),
      polygon
    );
    return cachePolishedBuildingGeoJSON(
      supabase,
      campaignId,
      source === 'diamond' ? 'gold' : 'silver',
      scopedBuildings
    );
  } catch (error) {
    console.warn(
      '[Provision] Failed to materialize building GeoJSON for map-ready cache:',
      error instanceof Error ? error.message : error
    );
    return { count: 0, buildings: [] };
  }
}

async function countCampaignAddresses(
  supabase: ReturnType<typeof createAdminClient>,
  campaignId: string
): Promise<number> {
  const { count, error } = await supabase
    .from('campaign_addresses')
    .select('id', { count: 'exact', head: true })
    .eq('campaign_id', campaignId);

  if (error) {
    throw new Error(`Failed to count campaign addresses: ${error.message}`);
  }

  return count ?? 0;
}

async function fetchCampaignLinkerAddresses(
  supabase: ReturnType<typeof createAdminClient>,
  campaignId: string
): Promise<CampaignAddressLinkerRow[]> {
  return fetchAllCampaignRows<CampaignAddressLinkerRow>(
    supabase,
    'campaign_addresses',
    'id, source_id, coordinate, geom',
    campaignId
  );
}

async function bulkInsertAddresses(
  supabase: ReturnType<typeof createAdminClient>,
  campaignId: string,
  addresses: StandardCampaignAddress[]
): Promise<CampaignAddressInsertResult> {
  const uniqueAddresses = deduplicateAddressesByProvisionKey(addresses).filter((address) => {
    const hasPoint =
      Number.isFinite(Number(address.lat)) &&
      Number.isFinite(Number(address.lon));
    if (!hasPoint) {
      console.warn('[Provision] Skipping address without usable coordinates:', {
        formatted: address.formatted,
        gers_id: address.gers_id,
      });
    }
    return hasPoint;
  });

  if (uniqueAddresses.length === 0) {
    const existingAddresses = await fetchCampaignLinkerAddresses(supabase, campaignId);
    return { count: existingAddresses.length, addresses: existingAddresses };
  }

  const existingSignatures = await fetchCampaignAddressSignatures(supabase, campaignId);
  const addressesToWrite = filterAddressesAgainstExisting(uniqueAddresses, existingSignatures);

  if (addressesToWrite.length === 0) {
    const existingAddresses = await fetchCampaignLinkerAddresses(supabase, campaignId);
    return { count: existingAddresses.length, addresses: existingAddresses };
  }

  const countBeforeRpc = await countCampaignAddresses(supabase, campaignId);
  const { error: rpcError } = await supabase.rpc(BULK_ADDRESS_RPC, {
    p_campaign_id: campaignId,
    p_addresses: addressesToWrite,
  });

  if (!rpcError) {
    const countAfterRpc = await countCampaignAddresses(supabase, campaignId);
    if (countAfterRpc > countBeforeRpc) {
      const insertedAddresses = await fetchCampaignLinkerAddresses(supabase, campaignId);
      return { count: insertedAddresses.length, addresses: insertedAddresses };
    }

    console.warn(
      '[Provision] add_campaign_addresses RPC completed without inserting rows; falling back to batched upserts'
    );
  } else {
    console.warn('[Provision] add_campaign_addresses RPC failed, falling back to batched inserts:', rpcError.message);
  }

  for (let from = 0; from < addressesToWrite.length; from += FALLBACK_INSERT_BATCH_SIZE) {
    const batch = addressesToWrite.slice(from, from + FALLBACK_INSERT_BATCH_SIZE).map((address) => ({
      campaign_id: address.campaign_id,
      address: address.formatted,
      formatted: address.formatted,
      house_number: address.house_number ?? null,
      street_name: address.street_name ?? null,
      locality: address.locality ?? null,
      region: address.region ?? null,
      postal_code: address.postal_code ?? null,
      source: address.source,
      gers_id: address.gers_id ?? null,
      source_id: address.gers_id ?? null,
      coordinate: address.coordinate ?? { lat: address.lat, lon: address.lon },
      geom: address.geom,
      visited: false,
    }));
    const { error: insertError } = await upsertCampaignAddressBatch(supabase, batch);

    if (insertError) {
      throw new Error(`Fallback address insert failed: ${insertError.message}`);
    }
  }

  const insertedAddresses = await fetchCampaignLinkerAddresses(supabase, campaignId);
  return { count: insertedAddresses.length, addresses: insertedAddresses };
}

async function upsertCampaignAddressBatch(
  supabase: ReturnType<typeof createAdminClient>,
  batch: Array<Record<string, unknown>>
) {
  const gersResult = await supabase
    .from('campaign_addresses')
    .upsert(batch, {
      onConflict: 'campaign_id,gers_id',
      ignoreDuplicates: false,
    });

  if (!isUniqueConstraintError(gersResult.error)) {
    return gersResult;
  }

  console.warn(
    '[Provision] campaign/gers upsert hit a unique constraint; retrying campaign/source_id:',
    gersResult.error?.message ?? 'unknown unique constraint'
  );

  const sourceIdResult = await supabase
    .from('campaign_addresses')
    .upsert(batch, {
      onConflict: 'campaign_id,source_id',
      ignoreDuplicates: false,
    });

  if (!isUniqueConstraintError(sourceIdResult.error)) {
    return sourceIdResult;
  }

  console.warn(
    '[Provision] campaign/source_id upsert still hit a unique constraint; falling back to duplicate-tolerant row inserts:',
    sourceIdResult.error?.message ?? 'unknown unique constraint'
  );

  for (const address of batch) {
    const { error } = await supabase
      .from('campaign_addresses')
      .insert(address);

    if (!error || isUniqueConstraintError(error)) {
      continue;
    }

    return { error };
  }

  return { error: null };
}

async function updateCampaignProvision(
  supabase: ReturnType<typeof createAdminClient>,
  campaignId: string,
  patch: Record<string, unknown>
): Promise<void> {
  const { error } = await supabase
    .from('campaigns')
    .update(patch)
    .eq('id', campaignId);

  if (error) {
    const source = patch.provision_source;
    const message = error.message ?? '';
    const isProvisionSourceCheck =
      error.code === '23514' ||
      message.includes('campaigns_provision_source_check') ||
      message.includes('provision_source');

    if (source === 'bedrock' && isProvisionSourceCheck) {
      console.warn(
        '[Provision] Database rejected bedrock provision_source; retrying state update without provision_source. Apply the two-path provision_source migration to preserve the source value.',
        message
      );
      const { provision_source: _provisionSource, ...fallbackPatch } = patch;
      const { error: fallbackError } = await supabase
        .from('campaigns')
        .update({
          ...fallbackPatch,
          provision_source: null,
        })
        .eq('id', campaignId);

      if (!fallbackError) {
        return;
      }

      throw new Error(`Failed to update campaign provisioning state: ${fallbackError.message}`);
    }

    throw new Error(`Failed to update campaign provisioning state: ${error.message}`);
  }
}

async function fetchAllCampaignRows<T>(
  supabase: ReturnType<typeof createAdminClient>,
  table: string,
  select: string,
  campaignId: string
): Promise<T[]> {
  const rows: T[] = [];
  const pageSize = 1000;

  for (let from = 0; ; from += pageSize) {
    const { data, error } = await supabase
      .from(table)
      .select(select)
      .eq('campaign_id', campaignId)
      .range(from, from + pageSize - 1);

    if (error) {
      throw new Error(`Failed to fetch ${table}: ${error.message}`);
    }

    rows.push(...((data ?? []) as T[]));
    if (!data || data.length < pageSize) break;
  }

  return rows;
}

async function upsertAutoBuildingLinks(
  supabase: ReturnType<typeof createAdminClient>,
  links: AutoLinkRow[]
): Promise<void> {
  if (links.length === 0) return;

  for (let index = 0; index < links.length; index += FALLBACK_INSERT_BATCH_SIZE) {
    const chunk = links.slice(index, index + FALLBACK_INSERT_BATCH_SIZE);
    const addressIds = chunk.map((link) => link.address_id);
    const { data: protectedRows, error: protectedError } = await supabase
      .from('building_address_links')
      .select('address_id, link_source')
      .eq('campaign_id', chunk[0].campaign_id)
      .in('link_source', ['manual', 'client_auto'])
      .in('address_id', addressIds);

    if (protectedError) {
      throw new Error(`Failed to protect manual/client building links before auto upsert: ${protectedError.message}`);
    }

    const protectedAddressIds = new Set((protectedRows ?? []).map((row) => String(row.address_id).toLowerCase()));
    const autoLinks = chunk.filter((link) => !protectedAddressIds.has(link.address_id.toLowerCase()));

    const fallbackUpsert = async (reason: string) => {
      if (autoLinks.length === 0) return;
      console.warn('[Provision] Falling back to Supabase building-link upsert:', {
        campaignId: chunk[0].campaign_id,
        reason,
        chunkSize: chunk.length,
        autoLinkCount: autoLinks.length,
        protectedLinkCount: protectedAddressIds.size,
      });
      const { error } = await supabase
        .from('building_address_links')
        .upsert(autoLinks, {
          onConflict: 'campaign_id,address_id',
        });

      if (error) {
        throw new Error(`Failed to write building links: ${error.message}`);
      }
    };

    const { data: rpcData, error: rpcError } = await supabase.rpc('bulk_upsert_auto_building_links', {
      p_campaign_id: chunk[0].campaign_id,
      p_links: chunk,
    });

    if (rpcError) {
      await fallbackUpsert(`bulk_upsert_auto_building_links RPC failed: ${rpcError.message}`);
    } else {
      const upserted = Number((rpcData as { upserted?: unknown } | null)?.upserted);
      if (!Number.isFinite(upserted) || upserted < autoLinks.length) {
        await fallbackUpsert(
          `bulk_upsert_auto_building_links persisted ${Number.isFinite(upserted) ? upserted : 'unknown'} of ${autoLinks.length} writable links`
        );
      }
    }

    const { count: persistedCount, error: persistedError } = await supabase
      .from('building_address_links')
      .select('id', { count: 'exact', head: true })
      .eq('campaign_id', chunk[0].campaign_id)
      .in('address_id', addressIds);

    if (persistedError) {
      throw new Error(`Failed to verify persisted building links: ${persistedError.message}`);
    }

    if ((persistedCount ?? 0) < chunk.length) {
      throw new Error(
        `Canonical building-link write verification failed: expected ${chunk.length} rows, found ${persistedCount ?? 0}`
      );
    }
  }
}

async function upsertAutoParcelAddressLinks(
  supabase: ReturnType<typeof createAdminClient>,
  links: AutoParcelLinkRow[]
): Promise<void> {
  if (links.length === 0) return;

  for (let index = 0; index < links.length; index += FALLBACK_INSERT_BATCH_SIZE) {
    const chunk = links.slice(index, index + FALLBACK_INSERT_BATCH_SIZE);
    const { data: manualRows, error: manualError } = await supabase
      .from('parcel_address_links')
      .select('address_id')
      .eq('campaign_id', chunk[0].campaign_id)
      .eq('link_source', 'manual')
      .in('address_id', chunk.map((link) => link.address_id));

    if (manualError) {
      if (isMissingParcelAddressLinksTable(manualError)) {
        console.warn('[Provision] parcel_address_links table unavailable; skipping parcel evidence persistence:', {
          code: manualError.code,
          message: manualError.message,
        });
        return;
      }
      throw new Error(`Failed to protect manual parcel links before upsert: ${manualError.message}`);
    }

    const manualAddressIds = new Set((manualRows ?? []).map((row) => String(row.address_id)));
    const autoLinks = chunk.filter((link) => !manualAddressIds.has(link.address_id));
    if (autoLinks.length === 0) {
      continue;
    }

    const { error } = await supabase
      .from('parcel_address_links')
      .upsert(autoLinks, {
        onConflict: 'campaign_id,address_id',
      });

    if (error) {
      if (isMissingParcelAddressLinksTable(error)) {
        console.warn('[Provision] parcel_address_links table unavailable; skipping parcel evidence persistence:', {
          code: error.code,
          message: error.message,
        });
        return;
      }
      throw new Error(`Failed to write parcel-address links: ${error.message}`);
    }
  }
}

function isMissingParcelAddressLinksTable(error: { code?: string; message?: string }) {
  const message = error.message ?? '';
  return error.code === '42P01' ||
    error.code === 'PGRST205' ||
    message.includes('parcel_address_links') && (
      message.includes('does not exist') ||
      message.includes('schema cache')
    );
}

function optionalString(value: unknown): string | null {
  return typeof value === 'string' && value.trim().length > 0 ? value.trim() : null;
}

async function fetchCanonicalLinkSourceVersion(
  supabase: ReturnType<typeof createAdminClient>,
  campaignId: string
): Promise<string | null> {
  const { data, error } = await supabase.rpc('rpc_get_campaign_map_source_version', {
    p_campaign_id: campaignId,
  });

  if (error) {
    console.warn('[Provision] Failed to compute canonical link source_version; links will be written without one:', {
      campaignId,
      code: error.code,
      message: error.message,
    });
    return null;
  }

  const raw = (data ?? {}) as { link_source_version?: unknown; source_version?: unknown };
  return optionalString(raw.link_source_version) ?? optionalString(raw.source_version);
}

async function expireStaleClientAutoLinks(
  supabase: ReturnType<typeof createAdminClient>,
  campaignId: string
): Promise<number> {
  const now = new Date().toISOString();
  const { data: expiredRows, error } = await supabase
    .from('campaign_addresses')
    .update({ match_source: 'client_auto_expired' })
    .eq('campaign_id', campaignId)
    .eq('match_source', 'client_auto')
    .lt('client_link_expires_at', now)
    .select('id');

  if (error) {
    throw new Error(`Failed to expire stale client-auto address links: ${error.message}`);
  }

  const expiredAddressIds = (expiredRows ?? [])
    .map((row) => optionalString((row as { id?: unknown }).id))
    .filter((id): id is string => Boolean(id));
  if (expiredAddressIds.length === 0) return 0;

  const { error: linkError } = await supabase
    .from('building_address_links')
    .update({ link_source: 'client_auto_expired' })
    .eq('campaign_id', campaignId)
    .eq('link_source', 'client_auto')
    .in('address_id', expiredAddressIds);

  if (linkError) {
    throw new Error(`Failed to expire stale client-auto building links: ${linkError.message}`);
  }

  return expiredAddressIds.length;
}

async function clearRefreshableAutoBuildingLinks(
  supabase: ReturnType<typeof createAdminClient>,
  campaignId: string
): Promise<void> {
  const { error } = await supabase
    .from('building_address_links')
    .delete()
    .eq('campaign_id', campaignId)
    .in('link_source', ['auto', 'auto_parcel', 'client_auto_expired']);

  if (error) {
    throw new Error(`Failed to clear refreshable automatic building links: ${error.message}`);
  }
}

async function replaceAddressOrphans(
  supabase: ReturnType<typeof createAdminClient>,
  campaignId: string,
  orphans: AddressOrphanLinkerRow[]
): Promise<void> {
  const { error: deleteError } = await supabase
    .from('address_orphans')
    .delete()
    .eq('campaign_id', campaignId);

  if (deleteError) {
    throw new Error(`Failed to clear address orphans: ${deleteError.message}`);
  }

  if (orphans.length === 0) return;

  const { error } = await supabase.rpc('insert_address_orphans_batch', {
    p_campaign_id: campaignId,
    p_rows: orphans,
  });

  if (error) {
    throw new Error(`Failed to persist address orphans: ${error.message}`);
  }
}

async function replaceAddressOrphansAfterLinking(
  supabase: ReturnType<typeof createAdminClient>,
  campaignId: string,
  candidateOrphans: AddressOrphanLinkerRow[]
): Promise<AddressOrphanLinkerRow[]> {
  if (candidateOrphans.length === 0) {
    await replaceAddressOrphans(supabase, campaignId, []);
    return [];
  }

  const linkedRows = await fetchAllCampaignRows<{ address_id: string | null }>(
    supabase,
    'building_address_links',
    'address_id',
    campaignId
  );
  const linkedAddressIds = new Set(
    linkedRows
      .map((row) => optionalString(row.address_id))
      .filter((id): id is string => Boolean(id))
  );
  const persistedOrphans = candidateOrphans.filter((orphan) => !linkedAddressIds.has(orphan.address_id));
  await replaceAddressOrphans(supabase, campaignId, persistedOrphans);
  return persistedOrphans;
}

async function refreshGroupedBuildingLinkClassifications(
  supabase: ReturnType<typeof createAdminClient>,
  campaignId: string
): Promise<void> {
  const linkRows = await fetchAllCampaignRows<{
    building_id: string | null;
    address_id: string | null;
  }>(
    supabase,
    'building_address_links',
    'building_id, address_id',
    campaignId
  );

  const addressIdsByBuilding = new Map<string, Set<string>>();
  for (const row of linkRows) {
    const buildingId = optionalString(row.building_id);
    const addressId = optionalString(row.address_id);
    if (!buildingId || !addressId) continue;
    const existing = addressIdsByBuilding.get(buildingId) ?? new Set<string>();
    existing.add(addressId);
    addressIdsByBuilding.set(buildingId, existing);
  }

  for (const [buildingId, addressIds] of addressIdsByBuilding) {
    const unitCount = Math.max(addressIds.size, 1);
    const isMultiUnit = unitCount > 1;
    const { error } = await supabase
      .from('building_address_links')
      .update({
        is_multi_unit: isMultiUnit,
        unit_count: unitCount,
        unit_arrangement: isMultiUnit ? 'horizontal' : 'single',
        building_class: isMultiUnit ? 'multi_unit' : null,
      })
      .eq('campaign_id', campaignId)
      .eq('building_id', buildingId);

    if (error) {
      throw new Error(`Failed to classify building links for ${buildingId}: ${error.message}`);
    }
  }
}

async function prewarmCanonicalMapBundle(
  supabase: ReturnType<typeof createAdminClient>,
  campaignId: string
): Promise<void> {
  try {
    await new CampaignMapBundleService(supabase).resolve(campaignId, null);
  } catch (error) {
    console.warn('[Provision] Canonical map-bundle prewarm failed; map-bundle GET will rebuild on demand:', {
      campaignId,
      message: error instanceof Error ? error.message : String(error),
    });
  }
}

function parsePolygonGeometry(
  geometry: CampaignBuildingLinkerRow['geom'] | string | null | undefined
): GeoJSON.Polygon | null {
  const parsed = typeof geometry === 'string'
    ? (() => {
      try {
        return JSON.parse(geometry) as GeoJSON.Geometry;
      } catch {
        return null;
      }
    })()
    : geometry;
  return parsed?.type === 'Polygon' ? parsed : null;
}

function townhouseSplitterFeatures(buildings: CampaignBuildingLinkerRow[]) {
  return buildings.flatMap((building) => {
    const geometry = parsePolygonGeometry(building.geom);
    if (!geometry) return [];
    return [{
      type: 'Feature' as const,
      geometry,
      properties: {
        gers_id: building.id,
        height: building.height_m ?? null,
      },
    }];
  });
}

async function runProvisionTownhouseSplitter(params: {
  supabase: ReturnType<typeof createAdminClient>;
  campaignId: string;
  buildings: CampaignBuildingLinkerRow[];
}): Promise<SplitterResult[]> {
  const buildings = params.buildings.length > 0
    ? params.buildings
    : await fetchCampaignLinkerBuildings(params.supabase, params.campaignId);
  const features = townhouseSplitterFeatures(buildings);
  if (features.length === 0) return [];

  const splitter = new TownhouseSplitterService(params.supabase);
  const summary = await splitter.processCampaignTownhouses(params.campaignId, { features });
  const splitterResults = summary.results ?? [];

  for (const result of splitterResults) {
    const { error } = await params.supabase
      .from('building_address_links')
      .update({
        is_multi_unit: result.units_count > 1,
        unit_count: Math.max(result.units_count, 1),
        unit_arrangement: result.units_count > 1 ? 'horizontal' : 'single',
        building_class: result.is_townhouse ? 'townhouse' : (result.units_count > 1 ? 'multi_unit' : null),
      })
      .eq('campaign_id', params.campaignId)
      .eq('building_id', result.building_id);

    if (error) {
      throw new Error(`Failed to persist townhouse classification for ${result.building_id}: ${error.message}`);
    }
  }

  return splitterResults;
}

async function autoLinkCampaignAddressesFromMemory(params: {
  supabase: ReturnType<typeof createAdminClient>;
  campaignId: string;
  totalAddresses: number;
  addresses: CampaignAddressLinkerRow[];
  materializedBuildings: CampaignBuildingLinkerRow[];
  bedrockLinkGeometry: BedrockLinkGeometry;
  sourceVersion?: string | null;
  timings?: ProvisionTimingRecorder;
}): Promise<AutoLinkCampaignAddressesResult> {
  await clearRefreshableAutoBuildingLinks(params.supabase, params.campaignId);
  const persistedParcels = await fetchCampaignLinkerParcels(params.supabase, params.campaignId).catch((error) => {
    console.warn('[Provision] Persisted parcel evidence unavailable for in-memory linker:', {
      campaignId: params.campaignId,
      message: error instanceof Error ? error.message : String(error),
    });
    return [] as CampaignParcelLinkerRow[];
  });
  const parcelsForLinking = persistedParcels.length > 0
    ? persistedParcels
    : params.bedrockLinkGeometry.parcels ?? [];
  const parcelAddressLinks = persistedParcels.length > 0
    ? buildParcelAddressLinksFromPreparedRows({
      campaignId: params.campaignId,
      addresses: params.addresses,
      parcels: persistedParcels,
    })
    : [];
  const canonicalLinkResult = buildCanonicalBuildingLinksFromMemory({
    campaignId: params.campaignId,
    addresses: params.addresses,
    materializedBuildings: params.materializedBuildings,
    sourceBuildings: params.bedrockLinkGeometry.buildings ?? [],
    parcels: parcelsForLinking,
    distanceMeters: AUTO_LINK_DISTANCE_METERS,
    sourceVersion: params.sourceVersion,
  });
  const links = canonicalLinkResult.links;

  await Promise.all([
    params.timings
      ? params.timings.measure('bulk_link_insert_ms', () => upsertAutoBuildingLinks(params.supabase, links), 'linker')
      : upsertAutoBuildingLinks(params.supabase, links),
    params.timings
      ? params.timings.measure('bulk_parcel_link_insert_ms', () => upsertAutoParcelAddressLinks(params.supabase, parcelAddressLinks), 'linker')
      : upsertAutoParcelAddressLinks(params.supabase, parcelAddressLinks),
  ]);
  const addressOrphans = await (params.timings
    ? params.timings.measure(
      'address_orphan_persist_ms',
      () => replaceAddressOrphansAfterLinking(params.supabase, params.campaignId, canonicalLinkResult.address_orphans),
      'linker'
    )
    : replaceAddressOrphansAfterLinking(params.supabase, params.campaignId, canonicalLinkResult.address_orphans));

  return {
    linked: links.length,
    parcel_linked: parcelAddressLinks.length,
    skipped_manual: 0,
    unlinked: Math.max(params.totalAddresses - links.length, 0),
    address_orphans: addressOrphans,
    links,
  };
}

async function autoLinkCampaignAddressesInProcess(params: {
  supabase: ReturnType<typeof createAdminClient>;
  campaignId: string;
  totalAddresses: number;
  sourceVersion?: string | null;
  timings?: ProvisionTimingRecorder;
}): Promise<AutoLinkCampaignAddressesResult> {
  await clearRefreshableAutoBuildingLinks(params.supabase, params.campaignId);
  const [addresses, buildingRows, parcelRows] = await Promise.all([
    fetchAllCampaignRows<CampaignAddressLinkerRow>(
      params.supabase,
      'campaign_addresses',
      'id, coordinate, geom',
      params.campaignId
    ),
    fetchAllCampaignRows<CampaignBuildingLinkerRow>(
      params.supabase,
      'buildings',
      'id, gers_id, geom, height_m, units_count, is_townhome_row',
      params.campaignId
    ),
    fetchCampaignLinkerParcels(params.supabase, params.campaignId).catch((error) => {
      console.warn('[Provision] Parcel linker enrichment unavailable:', {
        campaignId: params.campaignId,
        message: error instanceof Error ? error.message : String(error),
      });
      return [] as CampaignParcelLinkerRow[];
    }),
  ]);

  const canonicalLinkResult = buildCanonicalBuildingLinksFromPreparedRows({
    campaignId: params.campaignId,
    addresses,
    buildings: prepareBuildingsFromRows(buildingRows),
    parcels: parcelRows,
    distanceMeters: AUTO_LINK_DISTANCE_METERS,
    sourceVersion: params.sourceVersion,
  });
  const links = canonicalLinkResult.links;
  const parcelAddressLinks = buildParcelAddressLinksFromPreparedRows({
    campaignId: params.campaignId,
    addresses,
    parcels: parcelRows,
  });

  await Promise.all([
    params.timings
      ? params.timings.measure('bulk_link_insert_ms', () => upsertAutoBuildingLinks(params.supabase, links), 'linker')
      : upsertAutoBuildingLinks(params.supabase, links),
    params.timings
      ? params.timings.measure('bulk_parcel_link_insert_ms', () => upsertAutoParcelAddressLinks(params.supabase, parcelAddressLinks), 'linker')
      : upsertAutoParcelAddressLinks(params.supabase, parcelAddressLinks),
  ]);
  const addressOrphans = await (params.timings
    ? params.timings.measure(
      'address_orphan_persist_ms',
      () => replaceAddressOrphansAfterLinking(params.supabase, params.campaignId, canonicalLinkResult.address_orphans),
      'linker'
    )
    : replaceAddressOrphansAfterLinking(params.supabase, params.campaignId, canonicalLinkResult.address_orphans));

  return {
    linked: links.length,
    parcel_linked: parcelAddressLinks.length,
    skipped_manual: 0,
    unlinked: Math.max(params.totalAddresses - links.length, 0),
    address_orphans: addressOrphans,
    links,
  };
}

async function updateCampaignLinkSummary(params: {
  supabase: ReturnType<typeof createAdminClient>;
  campaignId: string;
  readyAt: string;
  linkedAddressCount: number;
  totalAddressCount: number;
}): Promise<void> {
  const confidence = params.totalAddressCount > 0
    ? Number(((params.linkedAddressCount / params.totalAddressCount) * 100).toFixed(2))
    : 0;

  await updateCampaignProvision(params.supabase, params.campaignId, {
    provision_status: 'ready',
    provision_phase: 'linked',
    provision_error: null,
    provision_message: null,
    optimized_at: params.readyAt,
    building_link_confidence: confidence,
    map_mode: confidence >= 80 ? 'hybrid' : 'standard_pins',
    standard_mode_recommended: confidence < 80,
    link_quality_reason: `${params.linkedAddressCount}/${params.totalAddressCount} addresses linked to S3 building footprints`,
  });
}

async function upsertSnapshotMetadata(
  supabase: ReturnType<typeof createAdminClient>,
  campaignId: string,
  snapshot: LambdaSnapshotResponse | null
): Promise<void> {
  if (!snapshot || !snapshot.bucket) {
    return;
  }

  const { error } = await supabase
    .from('campaign_snapshots')
    .upsert(
      {
        campaign_id: campaignId,
        bucket: snapshot.bucket,
        prefix: snapshot.prefix,
        buildings_key: snapshot.s3_keys.buildings,
        addresses_key: snapshot.s3_keys.addresses,
        metadata_key: snapshot.s3_keys.metadata,
        buildings_url: snapshot.urls.buildings,
        addresses_url: snapshot.urls.addresses,
        metadata_url: snapshot.urls.metadata,
        buildings_count: snapshot.counts.buildings,
        addresses_count: snapshot.counts.addresses,
        overture_release: snapshot.metadata?.overture_release,
        tile_metrics: snapshot.metadata?.tile_metrics ?? null,
        expires_at: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
      },
      {
        onConflict: 'campaign_id',
      }
    );

  if (error) {
    throw new Error(`Failed to store snapshot metadata: ${error.message}`);
  }
}

function addressesForInitialHydration(
  addresses: StandardCampaignAddress[]
): StandardCampaignAddress[] {
  if (addresses.length === 0) {
    return [];
  }

  return addresses.length <= staticGeometryAddressHydrationLimit() ? addresses : [];
}

function isNumericOnlyAddressLabel(value: string | null | undefined): boolean {
  return typeof value === 'string' && /^[\d\s#./-]+$/.test(value.trim());
}

function addressLabelQuality(addresses: StandardCampaignAddress[]) {
  if (addresses.length === 0) {
    return { usable: 0, numericOnly: 0, usableRatio: 0, acceptable: false };
  }

  let usable = 0;
  let numericOnly = 0;

  for (const address of addresses) {
    const streetName = address.street_name?.trim();
    const formatted = address.formatted?.trim();
    const hasNamedStreet = Boolean(streetName && !isNumericOnlyAddressLabel(streetName));
    const hasReadableFormatted = Boolean(formatted && !isNumericOnlyAddressLabel(formatted));
    if (hasNamedStreet || hasReadableFormatted) {
      usable += 1;
    }
    if (
      isNumericOnlyAddressLabel(streetName) ||
      (formatted && isNumericOnlyAddressLabel(formatted))
    ) {
      numericOnly += 1;
    }
  }

  const usableRatio = usable / addresses.length;
  return {
    usable,
    numericOnly,
    usableRatio,
    acceptable: usableRatio >= 0.6,
  };
}

async function resolveDiamondThenBedrock(options: {
  campaignId: string;
  polygon: GeoJSON.Polygon;
  regionCode: string;
}): Promise<ResolvedProvisionResult> {
  const { campaignId, polygon, regionCode } = options;

  if (DiamondMunicipalService.isSupportedRegion(regionCode)) {
    console.log('[Provision] Source probe: checking Diamond municipal S3...', {
      campaignId,
      regionCode,
    });
    const diamondResult = await DiamondMunicipalService.provisionCampaign({
      campaignId,
      polygon,
      addressLimit: 10000,
      regionCode,
    }).catch((error) => {
      console.warn(
        '[Provision] Diamond S3 probe failed; trying Bedrock S3 next:',
        error instanceof Error ? error.message : String(error)
      );
      return null;
    });

    if (diamondResult) {
      const quality = addressLabelQuality(diamondResult.addresses);
      if (!quality.acceptable) {
        console.warn('[Provision] Diamond municipal address labels failed quality gate; trying Bedrock S3 next:', {
          campaignId,
          addresses: diamondResult.addresses.length,
          usable: quality.usable,
          numericOnly: quality.numericOnly,
          usableRatio: Number(quality.usableRatio.toFixed(3)),
        });
      } else {
        console.log('[Provision] DIAMOND municipal S3 polygon scan complete:', {
          campaignId,
          country: diamondResult.country,
          municipality: diamondResult.municipality,
          addresses: diamondResult.addresses.length,
          bboxCandidates: diamondResult.metrics.addresses.bboxCandidates,
          timings: {
            addresses: diamondResult.metrics.addresses.seconds,
          },
        });

        return {
          addressSource: 'diamond',
          snapshot: diamondResult.snapshot,
          addressesToInsert: addressesForInitialHydration(diamondResult.addresses),
          bedrockLinkGeometry: null,
          sourceMetrics: diamondResult.metrics,
        };
      }
    }

    console.log('[Provision] No matching Diamond S3 folder found; trying Bedrock S3.');
  }

  if (BedrockProvisionService.isSupportedRegion(regionCode)) {
    console.log('[Provision] Source probe: checking Bedrock S3...', {
      campaignId,
      regionCode,
    });
    const bedrockResult = await BedrockProvisionService.provisionCampaign({
      campaignId,
      polygon,
      addressLimit: 10000,
      regionCode,
    });
    console.log('[Provision] BEDROCK S3 polygon scan complete:', {
      campaignId,
      provider: bedrockResult.providerSource,
      country: bedrockResult.providerLabel,
      addresses: bedrockResult.addresses.length,
      buildings: bedrockResult.snapshot.counts.buildings,
      linkerBuildings: bedrockResult.linkGeometry?.buildings.length ?? 0,
      linkerParcels: bedrockResult.linkGeometry?.parcels.length ?? 0,
      metrics: bedrockResult.metrics,
    });
    return {
      addressSource: 'bedrock',
      snapshot: bedrockResult.snapshot,
      addressesToInsert: addressesForInitialHydration(bedrockResult.addresses),
      bedrockLinkGeometry: bedrockResult.linkGeometry,
      sourceMetrics: bedrockResult.metrics,
    };
  }

  throw new ProvisionError(
    `Provisioning only supports the Diamond or Bedrock paths for region "${regionCode}".`,
    422
  );
}

async function runCampaignPostProcessing(params: {
  supabase: ReturnType<typeof createAdminClient>;
  campaignId: string;
  source: ProvisionSource;
  insertedCount: number;
  readyAt: string;
  expectedBuildingCount: number;
  materializedBuildings: CampaignBuildingLinkerRow[];
  campaignAddresses: CampaignAddressLinkerRow[];
  bedrockLinkGeometry?: BedrockLinkGeometry | null;
  timings?: ProvisionTimingRecorder;
}): Promise<CampaignPostProcessingResult> {
  const label = sourceDisplayName(params.source);

  const completeWithLinkResult = async (
    linkResult: AutoLinkCampaignAddressesResult | null,
    linkerPath: CampaignPostProcessingResult['linkerPath']
  ): Promise<CampaignPostProcessingResult> => {
    const result = (linkResult ?? {}) as AutoLinkCampaignAddressesResult;
    const linkedAddressCount = jsonNumber(result.linked);
    const skippedManualCount = jsonNumber(result.skipped_manual);
    const unlinkedAddressCount = jsonNumber(result.unlinked);
    const parcelLinkedAddressCount = jsonNumber(result.parcel_linked);

    if (linkedAddressCount === 0 && params.insertedCount > 0) {
      await updateCampaignProvision(params.supabase, params.campaignId, {
        provision_status: 'ready',
        provision_phase: 'linking_failed',
        provision_error: null,
        provision_message: null,
        optimized_at: params.readyAt,
        building_link_confidence: 0,
        map_mode: 'standard_pins',
        standard_mode_recommended: true,
        link_quality_reason: `0/${params.insertedCount} addresses linked to S3 building footprints`,
      });

      return {
        optimized: false,
        postprocessDeferred: false,
        linkedAddressCount: 0,
        skippedManualCount,
        unlinkedAddressCount: params.insertedCount,
        unitsCreated: 0,
        townhousesIdentified: 0,
        linkerPath,
        message: `${label} campaign is map-ready, but building linking failed.`,
      };
    }

    await (params.timings
      ? params.timings.measure('grouped_link_classification_ms', () => refreshGroupedBuildingLinkClassifications(
        params.supabase,
        params.campaignId
      ), 'linker')
      : refreshGroupedBuildingLinkClassifications(params.supabase, params.campaignId));

    const splitterResults = await (params.timings
      ? params.timings.measure('townhouse_splitter_ms', () => runProvisionTownhouseSplitter({
        supabase: params.supabase,
        campaignId: params.campaignId,
        buildings: params.materializedBuildings,
      }), 'linker')
      : runProvisionTownhouseSplitter({
        supabase: params.supabase,
        campaignId: params.campaignId,
        buildings: params.materializedBuildings,
      }));
    const unitsCreated = splitterResults.reduce((sum, row) => sum + Math.max(row.units_count, 0), 0);
    const townhousesIdentified = splitterResults.filter((row) => row.is_townhouse).length;

    await (params.timings
      ? params.timings.measure('map_bundle_prewarm_ms', () => prewarmCanonicalMapBundle(
        params.supabase,
        params.campaignId
      ), 'linker')
      : prewarmCanonicalMapBundle(params.supabase, params.campaignId));

    await updateCampaignLinkSummary({
      supabase: params.supabase,
      campaignId: params.campaignId,
      readyAt: params.readyAt,
      linkedAddressCount,
      totalAddressCount: params.insertedCount,
    });

    console.log('[Provision] Backend auto-link completed.', {
      campaignId: params.campaignId,
      linkerPath,
      linkedAddressCount,
      parcelLinkedAddressCount,
      skippedManualCount,
      unlinkedAddressCount,
    });

    return {
      optimized: true,
      postprocessDeferred: false,
      linkedAddressCount,
      skippedManualCount,
      unlinkedAddressCount,
      unitsCreated,
      townhousesIdentified,
      linkerPath,
      message: `${label} campaign is map-ready. ${linkedAddressCount} addresses auto-linked.`,
    };
  };

  const expiredClientLinkCount = await expireStaleClientAutoLinks(params.supabase, params.campaignId);
  if (expiredClientLinkCount > 0) {
    console.log('[Provision] Expired stale client-auto links before canonical linking.', {
      campaignId: params.campaignId,
      expiredClientLinkCount,
    });
  }
  await clearRefreshableAutoBuildingLinks(params.supabase, params.campaignId);

  const linkSourceVersion = await fetchCanonicalLinkSourceVersion(params.supabase, params.campaignId);

  const { count: materializedBuildingCount, error: buildingCountError } = await params.supabase
    .from('buildings')
    .select('id', { count: 'exact', head: true })
    .eq('campaign_id', params.campaignId);

  if (buildingCountError || (params.expectedBuildingCount > 0 && (materializedBuildingCount ?? 0) === 0)) {
    console.error('[Provision] Backend auto-link skipped; campaign buildings are not materialized.', {
      campaignId: params.campaignId,
      expectedBuildingCount: params.expectedBuildingCount,
      materializedBuildingCount: materializedBuildingCount ?? 0,
      error: buildingCountError?.message,
    });

    return {
      optimized: false,
      postprocessDeferred: true,
      linkedAddressCount: 0,
      skippedManualCount: 0,
      unlinkedAddressCount: params.insertedCount,
      unitsCreated: 0,
      townhousesIdentified: 0,
      linkerPath: 'deferred',
      // TODO: remove after linking-restructure cleanup
      message: `${label} campaign is map-ready. Linking deferred to device.`,
    };
  }

  let inMemoryResult: AutoLinkCampaignAddressesResult | null = null;
  let inProcessError: unknown = null;

  if (
    params.bedrockLinkGeometry?.buildings?.length &&
    params.materializedBuildings.length > 0 &&
    params.campaignAddresses.length > 0
  ) {
    inMemoryResult = await (params.timings
      ? params.timings.measure('in_memory_ms', () => autoLinkCampaignAddressesFromMemory({
        supabase: params.supabase,
        campaignId: params.campaignId,
        totalAddresses: params.insertedCount,
        addresses: params.campaignAddresses,
        materializedBuildings: params.materializedBuildings,
        bedrockLinkGeometry: params.bedrockLinkGeometry!,
        sourceVersion: linkSourceVersion,
        timings: params.timings,
      }), 'linker')
      : autoLinkCampaignAddressesFromMemory({
        supabase: params.supabase,
        campaignId: params.campaignId,
        totalAddresses: params.insertedCount,
        addresses: params.campaignAddresses,
        materializedBuildings: params.materializedBuildings,
        bedrockLinkGeometry: params.bedrockLinkGeometry,
        sourceVersion: linkSourceVersion,
      }));

    const linkedAddressCount = jsonNumber(inMemoryResult.linked);
    const linkRatio = params.insertedCount > 0 ? linkedAddressCount / params.insertedCount : 0;
    console.log('[Provision] In-memory S3 footprint linker completed.', {
      campaignId: params.campaignId,
      linkedAddressCount,
      unlinkedAddressCount: jsonNumber(inMemoryResult.unlinked),
      linkRatio: Number(linkRatio.toFixed(4)),
    });

    if (linkRatio >= MIN_HYBRID_LINK_RATIO) {
      return completeWithLinkResult(inMemoryResult, 'in_memory');
    }

    console.warn('[Provision] In-memory S3 footprint linker below quality gate; running in-process DB-row reconciliation.', {
      campaignId: params.campaignId,
      linkedAddressCount,
      totalAddressCount: params.insertedCount,
      minimumRatio: MIN_HYBRID_LINK_RATIO,
    });
  }

  try {
    const inProcessResult = await (params.timings
      ? params.timings.measure('in_process_ms', () => autoLinkCampaignAddressesInProcess({
        supabase: params.supabase,
        campaignId: params.campaignId,
        totalAddresses: params.insertedCount,
        sourceVersion: linkSourceVersion,
        timings: params.timings,
      }), 'linker')
      : autoLinkCampaignAddressesInProcess({
        supabase: params.supabase,
        campaignId: params.campaignId,
        totalAddresses: params.insertedCount,
        sourceVersion: linkSourceVersion,
      }));

    console.log('[Provision] In-process S3 footprint linker completed as primary path.', {
      campaignId: params.campaignId,
      linkedAddressCount: jsonNumber(inProcessResult.linked),
      unlinkedAddressCount: jsonNumber(inProcessResult.unlinked),
    });

    return completeWithLinkResult(inProcessResult, 'in_process');
  } catch (fallbackError) {
    inProcessError = fallbackError;
    console.error('[Provision] Primary in-process linker failed; falling back to PostGIS RPC.', {
      campaignId: params.campaignId,
      message: fallbackError instanceof Error ? fallbackError.message : String(fallbackError),
    });
  }

  const { data, error } = await (params.timings
    ? params.timings.measure('postgis_rpc_ms', async () => await params.supabase.rpc('auto_link_campaign_addresses', {
      p_campaign_id: params.campaignId,
    }), 'linker')
    : params.supabase.rpc('auto_link_campaign_addresses', {
      p_campaign_id: params.campaignId,
    }));

  if (!error) {
    console.log('[Provision] PostGIS auto-link RPC completed as fallback.', {
      campaignId: params.campaignId,
    });
    return completeWithLinkResult(data as AutoLinkCampaignAddressesResult | null, 'postgis_rpc');
  }

  console.error('[Provision] PostGIS auto-link RPC fallback failed; leaving iOS fallback enabled.', {
    campaignId: params.campaignId,
    inProcessError: inProcessError instanceof Error ? inProcessError.message : String(inProcessError),
    code: error.code,
    message: error.message,
    details: error.details,
    hint: error.hint,
  });

  return {
    optimized: false,
    postprocessDeferred: true,
    linkedAddressCount: jsonNumber(inMemoryResult?.linked),
    skippedManualCount: 0,
    unlinkedAddressCount: params.insertedCount,
    unitsCreated: 0,
    townhousesIdentified: 0,
    linkerPath: 'failed',
    // TODO: remove after linking-restructure cleanup
    message: `${label} campaign is map-ready. Linking deferred to device.`,
  };
}

export async function POST(request: NextRequest) {
  console.log('[Provision] Starting Diamond/Bedrock S3 map-ready provisioning...');

  let campaignId: string | null = null;
  const timings = new ProvisionTimingRecorder();

  try {
    const requestUser = await resolveUserFromRequest(request);
    if (!requestUser) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

	    const body: ProvisionRequest = await request.json();
	    campaignId = body.campaign_id;
	    const waitForLinker =
	      body.wait_for_linker === true ||
	      body.wait_for_postprocess === true ||
	      body.require_linked_homes === true;
      if (waitForLinker) {
        console.log('[Provision] wait_for_linker requested; backend auto-linking will run after map-ready hydration.');
      }

    if (!campaignId) {
      return NextResponse.json({ error: 'Campaign ID required' }, { status: 400 });
    }

    const supabase = createAdminClient();

    const { data: campaign, error: campaignError } = await supabase
      .from('campaigns')
      .select('owner_id, workspace_id, territory_boundary, region, bbox')
      .eq('id', campaignId)
      .single();

    if (campaignError || !campaign) {
      return NextResponse.json({ error: 'Campaign not found' }, { status: 404 });
    }

    const isOwner = campaign.owner_id === requestUser.id;
    let canProvision = isOwner;
    if (!canProvision && campaign.workspace_id) {
      const { data: membership } = await supabase
        .from('workspace_members')
        .select('role')
        .eq('workspace_id', campaign.workspace_id)
        .eq('user_id', requestUser.id)
        .maybeSingle();
      const role = membership?.role ?? null;
      canProvision = role === 'owner' || role === 'admin';
    }

    if (!canProvision) {
      return NextResponse.json({ error: 'Access denied' }, { status: 403 });
    }

    const polygon = campaign.territory_boundary;
    if (!polygon) {
      throw new ProvisionError(
        'No territory boundary defined. Please draw a polygon on the map when creating the campaign.',
        400
      );
    }

    const regionResolution = await timings.measure('region_resolution_ms', () => resolveCampaignRegion({
      currentRegion: campaign.region,
      polygon,
      bbox: campaign.bbox,
    }));
    const regionCode = regionResolution.regionCode;
    const sourceCacheKey = `${campaignId}:${regionCode}:${territoryHash(polygon)}`;
    let cachedSourceResult: ResolvedProvisionResult | null = null;
    let cachedSourceKey: string | null = null;

    if (regionResolution.shouldPersist) {
      const { error: regionUpdateError } = await supabase
        .from('campaigns')
        .update({ region: regionCode })
        .eq('id', campaignId);
      if (regionUpdateError) {
        console.warn('[Provision] Failed to persist inferred region:', regionUpdateError.message);
      }
    }

    const readyAt = new Date().toISOString();
    await updateCampaignProvision(supabase, campaignId, {
      provision_status: 'pending',
      provision_phase: 'created',
      provision_error: null,
      provision_message: null,
      provision_source: null,
      provisioned_at: null,
      addresses_ready_at: null,
      map_ready_at: null,
      optimized_at: null,
      has_parcels: false,
      building_link_confidence: 0,
      map_mode: 'standard_pins',
      parcel_enrichment_status: 'not_started',
      link_quality_status: 'unknown',
      link_quality_score: 0,
      link_quality_reason: null,
      link_quality_checked_at: null,
      link_quality_metrics: {},
      provision_timings: timings.snapshot(),
    });

	    const runProvisionWorker = async () => {
	      try {
	        return await retryWithBackoff(async () => {
          const sourceTimeoutMs = sourceResolutionTimeoutMs();
          console.log('[Provision] Background provision worker started.', {
            campaignId,
            regionCode,
            sourceTimeoutMs,
          });
          await updateCampaignProvision(supabase, campaignId!, {
            provision_phase: 'source_probed',
          });

          const [existingAddressCount, resolvedProvision] = await Promise.all([
            timings.measure('existing_address_count_ms', () => countCampaignAddresses(supabase, campaignId!)),
            timings.measure('source_resolution_ms', async () => {
              if (cachedSourceKey === sourceCacheKey && cachedSourceResult) {
                console.log('[Provision] Reusing retry-local S3 source scan cache.', {
                  campaignId,
                  regionCode,
                });
                return cachedSourceResult;
              }

              const result = await withTimeout(
                resolveDiamondThenBedrock({
                  campaignId: campaignId!,
                  polygon: polygon as GeoJSON.Polygon,
                  regionCode,
                }),
                sourceTimeoutMs,
                `Provision source resolution exceeded ${Math.round(sourceTimeoutMs / 1000)}s before Diamond/Bedrock returned. Check S3/DuckDB/httpfs runtime logs.`
              );
              cachedSourceKey = sourceCacheKey;
              cachedSourceResult = result;
              return result;
            }),
          ]);
          const {
            addressSource,
            snapshot,
            addressesToInsert: resolvedAddresses,
            bedrockLinkGeometry,
            sourceMetrics,
          } = resolvedProvision;
          let addressesToInsert = resolvedAddresses;
          timings.sourceMetrics(sourceMetrics ?? snapshot.metadata?.tile_metrics ?? null);
          timings.count('addresses_scanned', resolvedAddresses.length);
          timings.count('buildings_scanned', bedrockLinkGeometry?.buildings.length ?? snapshot.counts.buildings ?? 0);
          timings.count('parcels_scanned', bedrockLinkGeometry?.parcels.length ?? snapshot.counts.parcels ?? 0);

          await updateCampaignProvision(supabase, campaignId!, {
            provision_source: dbProvisionSource(addressSource),
            provision_phase: 'source_probed',
            provision_timings: timings.snapshot(),
          });

          let finalAddressCount = existingAddressCount;
          let campaignLinkerAddresses: CampaignAddressLinkerRow[] = [];
          await updateCampaignProvision(supabase, campaignId!, {
            provision_phase: 'addresses_loading',
          });

          addressesToInsert = deduplicateAddresses(addressesToInsert);
          const hasResolvedAddresses = addressesToInsert.length > 0;
          const hasStaticGeometry = snapshotHasStaticPmtilesGeometry(snapshot);
          if (!hasResolvedAddresses && !hasStaticGeometry) {
            throw new ProvisionError(
              'Provisioning did not find any addresses in this territory. Try a larger polygon or a nearby area.',
              422
            );
          }

          const buildingLinkConfidence = 0;
          const mapMode = 'standard_pins';
          const effectiveBuildingCount =
            snapshot.counts.buildings > 0
              ? snapshot.counts.buildings
              : snapshotHasStaticBuildingPmtiles(snapshot)
                ? finalAddressCount
                : 0;

          const [
            addressInsertResult,
            materializedBuildingResult,
            _snapshotMetadataResult,
            parcelPreparationResult,
          ] = await Promise.all([
            timings.measure('address_insert_ms', async () => {
              if (hasResolvedAddresses) {
                return bulkInsertAddresses(supabase, campaignId!, addressesToInsert);
              }
              const existingAddresses = await fetchCampaignLinkerAddresses(supabase, campaignId!);
              return { count: existingAddresses.length, addresses: existingAddresses };
            }),
            timings.measure('building_materialization_ms', () => materializeBuildingGeoJSONForMapReady({
              supabase,
              campaignId: campaignId!,
              polygon: polygon as GeoJSON.Polygon,
              source: addressSource,
              snapshot,
              bedrockLinkGeometry,
            })),
            timings.measure('snapshot_metadata_ms', () => upsertSnapshotMetadata(supabase, campaignId!, snapshot)),
            timings.measure('parcel_enrichment_ms', () => prepareProvisionParcels({
              supabase,
              campaignId: campaignId!,
              regionCode,
              bedrockLinkGeometry,
            })),
          ]);

          finalAddressCount = addressInsertResult.count;
          campaignLinkerAddresses = addressInsertResult.addresses;
          const preparedParcelCount = parcelPreparationResult.count;
          const parcelEnrichmentStatus = parcelPreparationResult.status;
          timings.count('addresses_inserted', finalAddressCount);
          timings.count('buildings_materialized', materializedBuildingResult.buildings.length);
          timings.count('parcels_inserted', preparedParcelCount);

          if (finalAddressCount > 0) {
            await updateCampaignProvision(supabase, campaignId!, {
              provision_phase: 'addresses_ready',
              addresses_ready_at: readyAt,
              provision_timings: timings.snapshot(),
            });
          }
          const cachedBuildingGeoJSONCount = materializedBuildingResult.count;

          await updateCampaignProvision(supabase, campaignId!, {
            provision_status: 'pending',
            provision_phase: 'map_ready',
            provision_source: dbProvisionSource(addressSource),
            provisioned_at: readyAt,
            map_ready_at: readyAt,
            has_parcels: preparedParcelCount > 0,
            building_link_confidence: buildingLinkConfidence,
            map_mode: mapMode,
            parcel_enrichment_status: parcelEnrichmentStatus,
            provision_timings: timings.snapshot(),
          });

          console.log('[Provision] Static S3 geometry is map-ready; no legacy Gold/Lambda/White Gold fallbacks will run.', {
            cachedBuildingGeoJSONCount,
          });
          const postProcessing = await timings.measure('postprocessing_ms', () => runCampaignPostProcessing({
            supabase,
            campaignId: campaignId!,
            source: addressSource,
            insertedCount: finalAddressCount,
            readyAt,
            expectedBuildingCount: cachedBuildingGeoJSONCount,
            materializedBuildings: materializedBuildingResult.buildings,
            campaignAddresses: campaignLinkerAddresses,
            bedrockLinkGeometry,
            timings,
          }));
          timings.count('links_created', postProcessing.linkedAddressCount);
          await persistProvisionTimings(supabase, campaignId!, timings.snapshot());

          if (!postProcessing.optimized) {
            await updateCampaignProvision(supabase, campaignId!, {
              provision_status: 'ready',
              provision_phase: postProcessing.linkedAddressCount === 0 && finalAddressCount > 0
                ? 'linking_failed'
                : 'map_ready',
              provision_error: null,
              provision_message: null,
              provisioned_at: readyAt,
              map_ready_at: readyAt,
              provision_timings: timings.snapshot(),
            });
          }

          await sendCampaignReadyNotificationOnce(campaignId!).catch((error) => {
            console.error('[Provision] Campaign-ready push notification failed:', error);
          });

          const responseBuildingLinkConfidence = finalAddressCount > 0
            ? Number(((postProcessing.linkedAddressCount / finalAddressCount) * 100).toFixed(2))
            : 0;
          const responseMapMode = responseBuildingLinkConfidence >= 80 ? 'hybrid' : 'standard_pins';

          const result = {
            success: true,
            campaign_id: campaignId,
            addresses_saved: finalAddressCount,
            buildings_saved: effectiveBuildingCount,
            source: addressSource,
            links_created: postProcessing.linkedAddressCount,
            units_created: postProcessing.unitsCreated,
            townhouses_identified: postProcessing.townhousesIdentified,
            has_parcels: preparedParcelCount > 0,
            parcel_count: preparedParcelCount,
            building_link_confidence: responseBuildingLinkConfidence,
            map_mode: responseMapMode,
            linked_address_count: postProcessing.linkedAddressCount,
            skipped_manual_link_count: postProcessing.skippedManualCount,
            unlinked_address_count: postProcessing.unlinkedAddressCount,
            total_campaign_addresses: finalAddressCount,
            linker_path: postProcessing.linkerPath,
            provision_status: 'ready',
            provision_phase: postProcessing.optimized
              ? 'linked'
              : postProcessing.linkedAddressCount === 0 && finalAddressCount > 0
                ? 'linking_failed'
                : 'map_ready',
            provision_source: dbProvisionSource(addressSource),
            map_ready: true,
            optimized: postProcessing.optimized,
            postprocess_deferred: postProcessing.postprocessDeferred,
            parcel_enrichment_status: parcelEnrichmentStatus,
            map_layers: {
              buildings: snapshot.urls.buildings,
            },
            snapshot_metadata: {
              bucket: snapshot.bucket,
              prefix: snapshot.prefix,
              overture_release: snapshot.metadata?.overture_release,
              tile_metrics: snapshot.metadata?.tile_metrics,
            },
            provision_timings: timings.snapshot(),
            warning: snapshot.warning ?? null,
            message: postProcessing.message,
          };

          if (parcelPreparationResult.shouldRunDeferred) {
            if (waitForLinker) {
              scheduleDeferredParcelEnrichment(campaignId!);
            } else {
              await runDeferredParcelEnrichment(campaignId!);
            }
          }

          return result;
	        });
	      } catch (error) {
        console.error('[Provision] Background provisioning error:', error);

        try {
          const supabase = createAdminClient();
          await markCampaignProvisionFailed(supabase, campaignId!, error);
          await persistProvisionTimings(supabase, campaignId!, timings.snapshot());
	        } catch (updateError) {
	          console.error('[Provision] Failed to update failed background provision state:', updateError);
	        }
	        throw error;
	      }
	    };

	    if (waitForLinker) {
	      const result = await runProvisionWorker();
	      return NextResponse.json(result);
	    }

	    after(async () => {
	      await runProvisionWorker().catch((error) => {
	        console.error('[Provision] Background worker failed after accepted response:', error);
	      });
	    });

    return NextResponse.json({
      accepted: true,
      campaign_id: campaignId,
      provision_status: 'pending',
      provision_phase: 'created',
      provision_timings: timings.snapshot(),
    });
  } catch (error) {
    console.error('[Provision] Error:', error);
    const message = provisionFailureMessage(error);

    if (campaignId) {
      try {
        const supabase = createAdminClient();
        await markCampaignProvisionFailed(supabase, campaignId, error);
        await persistProvisionTimings(supabase, campaignId, timings.snapshot());
      } catch (updateError) {
        console.error('[Provision] Failed to update provision_status:', updateError);
      }
    }

    const status = error instanceof ProvisionError ? error.status : 500;
    return NextResponse.json(
      {
        error: message,
        provision_status: 'failed',
        provision_phase: 'failed',
        provision_timings: timings.snapshot(),
      },
      { status }
    );
  }
}
