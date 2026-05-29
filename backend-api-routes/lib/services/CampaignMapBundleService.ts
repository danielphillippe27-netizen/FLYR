import type { SupabaseClient } from '@supabase/supabase-js';

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
  counts?: Record<string, unknown>;
  updated_at?: string;
};

type CampaignMapBundleLink = {
  id?: string;
  building_id: string;
  address_id: string;
  match_type: string;
  confidence: number;
  distance_meters: number;
};

type DisplayModeHint = 'buildings' | 'addresses';
type LinksStatus = 'fresh' | 'stale_reused' | 'client_fallback_required';

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
const LINK_REFRESH_BUDGET_MS = 2_500;

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

function numericValue(value: unknown, fallback = 0): number {
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : fallback;
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

function fnv1a64(values: string[]): string {
  let hash = 14_695_981_039_346_656_037n;
  const prime = 1_099_511_628_211n;
  const mask = 0xffff_ffff_ffff_ffffn;
  for (const value of values) {
    for (const byte of Buffer.from(value, 'utf8')) {
      hash ^= BigInt(byte);
      hash = (hash * prime) & mask;
    }
    hash ^= 0xffn;
    hash = (hash * prime) & mask;
  }
  return hash.toString(16);
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
    `b${buildings.features.length}:${fnv1a64(buildingIds)}`,
    `a${addresses.features.length}:${fnv1a64(addressIds)}`,
    `p${parcels.features.length}:${fnv1a64(parcelIds)}`,
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

function withTimeout<T>(promise: Promise<T>, timeoutMs: number, label: string): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`${label} timed out after ${timeoutMs}ms`)), timeoutMs);
    promise.then(
      (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      (error) => {
        clearTimeout(timer);
        reject(error);
      }
    );
  });
}

function displayModeHint(buildings: FeatureCollection, addresses: FeatureCollection, links: CampaignMapBundleLink[]): DisplayModeHint {
  const buildingCount = buildings.features.length;
  const addressCount = addresses.features.length;
  if (addressCount >= 20 && buildingCount <= 1) return 'addresses';
  if (addressCount > 0 && links.length / addressCount < 0.15) return 'addresses';
  return 'buildings';
}

function responseFromRow(row: CurrentBundleRow): CanonicalCampaignMapBundleResponse {
  return {
    campaign_id: row.campaign_id,
    asset_signature: row.asset_signature,
    source_version: row.source_version,
    display_mode_hint: row.display_mode_hint === 'addresses' ? 'addresses' : 'buildings',
    links_status: row.links_status ?? 'fresh',
    addresses: asFeatureCollection(row.addresses_geojson),
    buildings: asFeatureCollection(row.buildings_geojson),
    parcels: asFeatureCollection(row.parcels_geojson),
    roads: asFeatureCollection(row.roads_geojson),
    links: Array.isArray(row.links) ? row.links : [],
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
  constructor(private readonly supabase: SupabaseClient) {}

  async resolve(campaignId: string, localSignature?: string | null): Promise<CampaignMapBundleServiceResult> {
    const source = await this.fetchSourceVersion(campaignId);
    const current = await this.fetchCurrentBundle(campaignId);

    if (
      current &&
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
      !currentBundleIsFresh(current);

    if (!shouldRebuild && current) {
      return { status: 'ok', bundle: responseFromRow(current) };
    }

    const bundle = await this.rebuildBundle(campaignId, source.sourceVersion, current);
    return { status: 'ok', bundle };
  }

  private async fetchSourceVersion(campaignId: string): Promise<{ sourceVersion: string; raw: SourceVersionResult }> {
    const { data, error } = await this.supabase.rpc('rpc_get_campaign_map_source_version', {
      p_campaign_id: campaignId,
    });
    if (error) {
      throw new Error(`Failed to compute map source version: ${error.message}`);
    }
    const raw = (data ?? {}) as SourceVersionResult;
    const sourceVersion = normalizedString(raw.source_version) ?? `fallback:${campaignId}`;
    return { sourceVersion, raw };
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
    current: CurrentBundleRow | null
  ): Promise<CanonicalCampaignMapBundleResponse> {
    const now = new Date();
    const nowIso = now.toISOString();
    const sameSource = current?.source_version === sourceVersion;
    const currentFetchedAt = current?.layer_fetched_at ?? {};

    const linkResult = await this.refreshLinksWithBudget(campaignId, current);
    const shouldReuseAddresses = sameSource && current && isFresh(currentFetchedAt.addresses, ADDRESS_TTL_MS);
    const shouldReuseBuildings = sameSource && current && isFresh(currentFetchedAt.buildings, STATIC_GEOMETRY_TTL_MS);
    const shouldReuseParcels = sameSource && current && isFresh(currentFetchedAt.parcels, STATIC_GEOMETRY_TTL_MS);
    const shouldReuseRoads = sameSource && current && isFresh(currentFetchedAt.roads, STATIC_GEOMETRY_TTL_MS);

    const [addresses, buildings, parcels, roads] = await Promise.all([
      shouldReuseAddresses ? Promise.resolve(asFeatureCollection(current!.addresses_geojson)) : this.fetchFeatureCollection('rpc_get_campaign_addresses', campaignId),
      shouldReuseBuildings ? Promise.resolve(asFeatureCollection(current!.buildings_geojson)) : this.fetchFeatureCollection('rpc_get_campaign_renderable_buildings', campaignId),
      shouldReuseParcels ? Promise.resolve(asFeatureCollection(current!.parcels_geojson)) : this.fetchFeatureCollection('rpc_get_campaign_parcels', campaignId),
      shouldReuseRoads ? Promise.resolve(asFeatureCollection(current!.roads_geojson)) : this.fetchFeatureCollection('rpc_get_campaign_roads_v2', campaignId),
    ]);

    const links = linkResult.status === 'fresh'
      ? await this.fetchLinks(campaignId)
      : linkResult.links;
    const signature = assetSignature(campaignId, buildings, addresses, parcels);
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
    };
    const hint = displayModeHint(buildings, addresses, links);

    const { data, error } = await this.supabase.rpc('rpc_upsert_campaign_map_bundle', {
      p_campaign_id: campaignId,
      p_asset_signature: signature,
      p_source_version: sourceVersion,
      p_buildings_geojson: buildings,
      p_addresses_geojson: addresses,
      p_parcels_geojson: parcels,
      p_roads_geojson: roads,
      p_links: links,
      p_display_mode_hint: hint,
      p_counts: counts,
      p_layer_fetched_at: layerFetchedAt,
      p_links_status: linkResult.status,
      p_built_at: nowIso,
      p_expires_at: expiresAt,
    });
    if (error) {
      throw new Error(`Failed to persist campaign map bundle: ${error.message}`);
    }

    const persisted = data as Partial<CanonicalCampaignMapBundleResponse> | null;
    return {
      campaign_id: campaignId,
      asset_signature: signature,
      source_version: sourceVersion,
      display_mode_hint: hint,
      links_status: linkResult.status,
      addresses,
      buildings,
      parcels,
      roads,
      links,
      counts,
      layer_fetched_at: layerFetchedAt,
      built_at: normalizedString(persisted?.built_at) ?? nowIso,
      expires_at: normalizedString(persisted?.expires_at) ?? expiresAt,
      updated_at: normalizedString(persisted?.updated_at),
    };
  }

  private async refreshLinksWithBudget(
    campaignId: string,
    current: CurrentBundleRow | null
  ): Promise<{ status: LinksStatus; links: CampaignMapBundleLink[] }> {
    try {
      await withTimeout(
        this.supabase.rpc('rpc_refresh_campaign_map_links', { p_campaign_id: campaignId }).then(({ error }) => {
          if (error) throw new Error(error.message);
        }),
        LINK_REFRESH_BUDGET_MS,
        'Campaign map link refresh'
      );
      return { status: 'fresh', links: [] };
    } catch (error) {
      console.warn('[CampaignMapBundle] Link refresh skipped:', error instanceof Error ? error.message : error);
      const fallbackLinks = Array.isArray(current?.links) ? current!.links : [];
      return {
        status: fallbackLinks.length > 0 ? 'stale_reused' : 'client_fallback_required',
        links: fallbackLinks,
      };
    }
  }

  private async fetchFeatureCollection(rpcName: string, campaignId: string): Promise<FeatureCollection> {
    const { data, error } = await this.supabase.rpc(rpcName, { p_campaign_id: campaignId });
    if (error) {
      console.warn(`[CampaignMapBundle] ${rpcName} failed:`, error.message);
      return { ...EMPTY_FEATURE_COLLECTION };
    }
    return asFeatureCollection(data);
  }

  private async fetchLinks(campaignId: string): Promise<CampaignMapBundleLink[]> {
    const { data, error } = await this.supabase
      .from('campaign_addresses')
      .select('id, building_gers_id, match_source, confidence')
      .eq('campaign_id', campaignId)
      .not('building_gers_id', 'is', null);
    if (error) {
      console.warn('[CampaignMapBundle] Failed to fetch links:', error.message);
      return [];
    }
    return ((data ?? []) as Array<{
      id: string;
      building_gers_id: string | null;
      match_source: string | null;
      confidence: number | null;
    }>).flatMap((row) => {
      const buildingId = normalizedString(row.building_gers_id);
      if (!buildingId) return [];
      return [{
        id: `${buildingId.toLowerCase()}:${row.id.toLowerCase()}`,
        building_id: buildingId,
        address_id: row.id,
        match_type: row.match_source ?? 'auto',
        confidence: row.confidence ?? 0.5,
        distance_meters: 0,
      }];
    });
  }
}
