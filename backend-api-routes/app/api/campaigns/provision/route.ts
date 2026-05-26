import { after, NextRequest, NextResponse } from 'next/server';
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
} from '@/lib/services/ParcelEnrichmentService';
import { isParcelRegionSupported } from '@/lib/geo/parcelRegions';

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
};

type CampaignPostProcessingResult = {
  optimized: boolean;
  postprocessDeferred: boolean;
  linkedAddressCount: number;
  skippedManualCount: number;
  unlinkedAddressCount: number;
  message: string;
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

const DEFAULT_STATIC_GEOMETRY_ADDRESS_HYDRATION_LIMIT = 2000;
const FALLBACK_INSERT_BATCH_SIZE = 500;
const BULK_ADDRESS_RPC = 'add_campaign_addresses';
const POLISHED_BUILDING_GEOMETRY_VERSION = 7;
const MAX_PROVISION_ERROR_LENGTH = 2000;
const DEFAULT_SOURCE_RESOLUTION_TIMEOUT_MS = 240_000;

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
  const { error: updateError } = await supabase
    .from('campaigns')
    .update({
      provision_status: 'failed',
      provision_phase: 'failed',
      provision_error: message,
      provision_message: message,
    })
    .eq('id', campaignId);

  if (updateError) {
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

async function cachePolishedBuildingGeoJSON(
  supabase: ReturnType<typeof createAdminClient>,
  campaignId: string,
  source: 'gold' | 'silver',
  featureCollection: unknown
): Promise<number> {
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

  if (renderableFeatures.length === 0) return 0;

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
    return 0;
  }

  console.log('[Provision] Cached polished building GeoJSON', {
    campaignId,
    source,
    features: renderableFeatures.length,
  });
  return renderableFeatures.length;
}

async function materializeBuildingGeoJSONForMapReady(params: {
  supabase: ReturnType<typeof createAdminClient>;
  campaignId: string;
  polygon: GeoJSON.Polygon;
  source: ProvisionSource;
  snapshot: LambdaSnapshotResponse | null;
  bedrockLinkGeometry?: BedrockLinkGeometry | null;
}): Promise<number> {
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

  if (!snapshot || !snapshotHasStaticBuildingPmtiles(snapshot)) return 0;

  const bbox = bboxFromPolygon(polygon);
  if (!bbox) return 0;

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
    return 0;
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

async function bulkInsertAddresses(
  supabase: ReturnType<typeof createAdminClient>,
  campaignId: string,
  addresses: StandardCampaignAddress[]
): Promise<number> {
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
    return countCampaignAddresses(supabase, campaignId);
  }

  const existingSignatures = await fetchCampaignAddressSignatures(supabase, campaignId);
  const addressesToWrite = filterAddressesAgainstExisting(uniqueAddresses, existingSignatures);

  if (addressesToWrite.length === 0) {
    return countCampaignAddresses(supabase, campaignId);
  }

  const countBeforeRpc = await countCampaignAddresses(supabase, campaignId);
  const { error: rpcError } = await supabase.rpc(BULK_ADDRESS_RPC, {
    p_campaign_id: campaignId,
    p_addresses: addressesToWrite,
  });

  if (!rpcError) {
    const countAfterRpc = await countCampaignAddresses(supabase, campaignId);
    if (countAfterRpc > countBeforeRpc) {
      return countAfterRpc;
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

  return countCampaignAddresses(supabase, campaignId);
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

async function resolveDiamondThenBedrock(options: {
  campaignId: string;
  polygon: GeoJSON.Polygon;
  regionCode: string;
}): Promise<{
  addressSource: ProvisionSource;
  snapshot: LambdaSnapshotResponse;
  addressesToInsert: StandardCampaignAddress[];
  bedrockLinkGeometry: BedrockLinkGeometry | null;
}> {
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
      };
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
}): Promise<CampaignPostProcessingResult> {
  const label = sourceDisplayName(params.source);

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
      message: `${label} campaign is map-ready. Linking deferred to device.`,
    };
  }

  const { data, error } = await params.supabase.rpc('auto_link_campaign_addresses', {
    p_campaign_id: params.campaignId,
  });

  if (error) {
    console.error('[Provision] Backend auto-link RPC failed; leaving iOS fallback enabled.', {
      campaignId: params.campaignId,
      code: error.code,
      message: error.message,
      details: error.details,
      hint: error.hint,
    });

    return {
      optimized: false,
      postprocessDeferred: true,
      linkedAddressCount: 0,
      skippedManualCount: 0,
      unlinkedAddressCount: params.insertedCount,
      message: `${label} campaign is map-ready. Linking deferred to device.`,
    };
  }

  const result = (data ?? {}) as AutoLinkCampaignAddressesResult;
  const linkedAddressCount = jsonNumber(result.linked);
  const skippedManualCount = jsonNumber(result.skipped_manual);
  const unlinkedAddressCount = jsonNumber(result.unlinked);

  await updateCampaignProvision(params.supabase, params.campaignId, {
    provision_status: 'ready',
    provision_phase: 'linked',
    optimized_at: params.readyAt,
  });

  console.log('[Provision] Backend auto-link RPC completed.', {
    campaignId: params.campaignId,
    linkedAddressCount,
    skippedManualCount,
    unlinkedAddressCount,
  });

  return {
    optimized: true,
    postprocessDeferred: false,
    linkedAddressCount,
    skippedManualCount,
    unlinkedAddressCount,
    message: `${label} campaign is map-ready. ${linkedAddressCount} addresses auto-linked.`,
  };
}

export async function POST(request: NextRequest) {
  console.log('[Provision] Starting Diamond/Bedrock S3 map-ready provisioning...');

  let campaignId: string | null = null;

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

    const regionResolution = await resolveCampaignRegion({
      currentRegion: campaign.region,
      polygon,
      bbox: campaign.bbox,
    });
    const regionCode = regionResolution.regionCode;

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

          const existingAddressCount = await countCampaignAddresses(supabase, campaignId!);
          const resolvedProvision = await withTimeout(
            resolveDiamondThenBedrock({
              campaignId: campaignId!,
              polygon: polygon as GeoJSON.Polygon,
              regionCode,
            }),
            sourceTimeoutMs,
            `Provision source resolution exceeded ${Math.round(sourceTimeoutMs / 1000)}s before Diamond/Bedrock returned. Check S3/DuckDB/httpfs runtime logs.`
          );
          const {
            addressSource,
            snapshot,
            addressesToInsert: resolvedAddresses,
            bedrockLinkGeometry,
          } = resolvedProvision;
          let addressesToInsert = resolvedAddresses;

          await updateCampaignProvision(supabase, campaignId!, {
            provision_source: dbProvisionSource(addressSource),
            provision_phase: 'source_probed',
          });

          let finalAddressCount = existingAddressCount;
          await updateCampaignProvision(supabase, campaignId!, {
            provision_phase: 'addresses_loading',
          });

          addressesToInsert = deduplicateAddresses(addressesToInsert);
          const hasResolvedAddresses = addressesToInsert.length > 0;
          if (hasResolvedAddresses) {
            finalAddressCount = await bulkInsertAddresses(supabase, campaignId!, addressesToInsert);
          }

          const hasStaticGeometry = snapshotHasStaticPmtilesGeometry(snapshot);
          if (!hasResolvedAddresses && !hasStaticGeometry) {
            throw new ProvisionError(
              'Provisioning did not find any addresses in this territory. Try a larger polygon or a nearby area.',
              422
            );
          }

          if (finalAddressCount > 0) {
            await updateCampaignProvision(supabase, campaignId!, {
              provision_phase: 'addresses_ready',
              addresses_ready_at: readyAt,
            });
          }

          await upsertSnapshotMetadata(supabase, campaignId!, snapshot);

          const buildingLinkConfidence = 0;
          const mapMode = 'standard_pins';
          const effectiveBuildingCount =
            snapshot.counts.buildings > 0
              ? snapshot.counts.buildings
              : snapshotHasStaticBuildingPmtiles(snapshot)
                ? finalAddressCount
                : 0;
          const parcelEnrichmentStatus = isParcelRegionSupported(regionCode) ? 'queued' : 'skipped';

          if (parcelEnrichmentStatus === 'queued') {
            await new ParcelEnrichmentService(supabase).markQueued(campaignId!);
          }

          const cachedBuildingGeoJSONCount = await materializeBuildingGeoJSONForMapReady({
            supabase,
            campaignId: campaignId!,
            polygon: polygon as GeoJSON.Polygon,
            source: addressSource,
            snapshot,
            bedrockLinkGeometry,
          });

          await updateCampaignProvision(supabase, campaignId!, {
            provision_status: 'ready',
            provision_phase: 'map_ready',
            provision_source: dbProvisionSource(addressSource),
            provisioned_at: readyAt,
            map_ready_at: readyAt,
            has_parcels: false,
            building_link_confidence: buildingLinkConfidence,
            map_mode: mapMode,
            parcel_enrichment_status: parcelEnrichmentStatus,
          });

          console.log('[Provision] Static S3 geometry is map-ready; no legacy Gold/Lambda/White Gold fallbacks will run.', {
            cachedBuildingGeoJSONCount,
          });
          const postProcessing = await runCampaignPostProcessing({
            supabase,
            campaignId: campaignId!,
            source: addressSource,
            insertedCount: finalAddressCount,
            readyAt,
            expectedBuildingCount: cachedBuildingGeoJSONCount,
          });

          return {
            success: true,
            campaign_id: campaignId,
            addresses_saved: finalAddressCount,
            buildings_saved: effectiveBuildingCount,
            source: addressSource,
            links_created: postProcessing.linkedAddressCount,
            units_created: 0,
            has_parcels: false,
            building_link_confidence: buildingLinkConfidence,
            map_mode: mapMode,
            linked_address_count: postProcessing.linkedAddressCount,
            skipped_manual_link_count: postProcessing.skippedManualCount,
            unlinked_address_count: postProcessing.unlinkedAddressCount,
            total_campaign_addresses: finalAddressCount,
            provision_status: 'ready',
            provision_phase: postProcessing.optimized ? 'linked' : 'map_ready',
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
            warning: snapshot.warning ?? null,
            message: postProcessing.message,
          };
	        });
	      } catch (error) {
        console.error('[Provision] Background provisioning error:', error);

        try {
          const supabase = createAdminClient();
          await markCampaignProvisionFailed(supabase, campaignId!, error);
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
    });
  } catch (error) {
    console.error('[Provision] Error:', error);
    const message = provisionFailureMessage(error);

    if (campaignId) {
      try {
        const supabase = createAdminClient();
        await markCampaignProvisionFailed(supabase, campaignId, error);
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
      },
      { status }
    );
  }
}
