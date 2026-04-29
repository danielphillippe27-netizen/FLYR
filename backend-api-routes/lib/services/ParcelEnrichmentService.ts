import { GetObjectCommand, ListObjectsV2Command, S3Client } from '@aws-sdk/client-s3';
import { bbox as turfBbox, booleanIntersects, feature } from '@turf/turf';
import type { SupabaseClient } from '@supabase/supabase-js';
import { gunzipSync } from 'zlib';
import * as wkx from 'wkx';
import { fetchAllInPages } from '@/lib/supabase/fetchAllInPages';
import { StableLinkerService, type BuildingFeature as SnapshotBuildingFeature } from '@/lib/services/StableLinkerService';
import { TownhouseSplitterService } from '@/lib/services/TownhouseSplitterService';
import { CampaignMapModeService } from '@/lib/services/CampaignMapModeService';

const PARCEL_BUCKET = 'flyr-pro-addresses-2025';
const PARCEL_PREFIX = 'gold-standard/canada/ontario';
const PARCEL_BATCH_SIZE = 500;

export type ParcelEnrichmentStatus =
  | 'not_started'
  | 'queued'
  | 'processing'
  | 'ready'
  | 'failed'
  | 'skipped';

type SupportedParcelSourceId =
  | 'toronto_parcels'
  | 'ajax_parcels'
  | 'pickering_parcels'
  | 'oshawa_parcels'
  | 'clarington_parcels';

type GeoJSONPolygon = {
  type: 'Polygon';
  coordinates: number[][][];
};

type GeoJSONMultiPolygon = {
  type: 'MultiPolygon';
  coordinates: number[][][][];
};

type GeoJSONGeometry = GeoJSONPolygon | GeoJSONMultiPolygon;

type CampaignRow = {
  id: string;
  bbox: number[] | null;
  territory_boundary: GeoJSONPolygon | null;
  region: string | null;
};

type NormalizedParcelRecord = {
  externalId: string;
  geometry: GeoJSONMultiPolygon;
  properties: Record<string, unknown>;
};

type CampaignBuildingRow = {
  id: string;
  gers_id: string;
  geom: unknown;
  height: number | null;
  house_name: string | null;
  addr_street: string | null;
};

export interface ParcelPreparationResult {
  status: 'ready' | 'skipped' | 'failed';
  sourceId: string | null;
  parcelCount: number;
  parcels: Array<{
    externalId: string;
    geometry: GeoJSONMultiPolygon;
    properties: Record<string, unknown>;
  }>;
  error: string | null;
  debug: ParcelEnrichmentDebug;
}

type ParcelEnrichmentDebug = {
  mode?: 'bbox_only' | 'polygon_intersects';
  source_id?: string | null;
  s3_key?: string | null;
  scanned_lines?: number;
  parsed_records?: number;
  bbox_candidates?: number;
  polygon_matches?: number;
  inserted_count?: number;
  skipped_reason?: string | null;
  unsupported_localities?: string[];
  locality_counts?: Array<{ source_id: SupportedParcelSourceId; count: number }>;
  relink?: {
    strategy?: 'campaign_buildings' | 'snapshot' | 'none';
    gold_linker_ran: boolean;
    consolidated_linker_ran: boolean;
    snapshot_linker_ran?: boolean;
    snapshot_linker_used_parcels?: boolean;
    multi_unit_flags_refreshed: boolean;
    campaign_building_count?: number;
    snapshot_building_count?: number;
    townhouse_refresh_attempted: boolean;
    townhouse_refresh_applied: boolean;
  };
  started_at?: string;
  completed_at?: string;
};

const LOCALITY_TO_SOURCE_ID: Record<string, SupportedParcelSourceId> = {
  ajax: 'ajax_parcels',
  bowmanville: 'clarington_parcels',
  clarington: 'clarington_parcels',
  courtice: 'clarington_parcels',
  'east york': 'toronto_parcels',
  etobicoke: 'toronto_parcels',
  newcastle: 'clarington_parcels',
  'north york': 'toronto_parcels',
  oshawa: 'oshawa_parcels',
  pickering: 'pickering_parcels',
  scarborough: 'toronto_parcels',
  toronto: 'toronto_parcels',
  york: 'toronto_parcels',
};

function normalizeLocality(value: string | null | undefined): string | null {
  if (!value) return null;
  const normalized = value.trim().toLowerCase();
  return normalized || null;
}

function getCampaignBbox(campaign: CampaignRow): number[] | null {
  if (Array.isArray(campaign.bbox) && campaign.bbox.length === 4) {
    return campaign.bbox;
  }

  if (campaign.territory_boundary) {
    try {
      return turfBbox(feature(campaign.territory_boundary));
    } catch {
      return null;
    }
  }

  return null;
}

function intersectsBbox(geometry: GeoJSONGeometry, bbox: number[]): boolean {
  try {
    const [minLon, minLat, maxLon, maxLat] = bbox;
    const [geomMinLon, geomMinLat, geomMaxLon, geomMaxLat] = turfBbox(feature(geometry));

    return !(
      geomMaxLon < minLon ||
      geomMinLon > maxLon ||
      geomMaxLat < minLat ||
      geomMinLat > maxLat
    );
  } catch {
    return false;
  }
}

function isWithinCampaignPolygon(geometry: GeoJSONGeometry, polygon: GeoJSONPolygon): boolean {
  try {
    return booleanIntersects(feature(geometry), feature(polygon));
  } catch {
    return false;
  }
}

function toMultiPolygonGeometry(geometry: unknown): GeoJSONMultiPolygon | null {
  if (!geometry || typeof geometry !== 'object') return null;
  const candidate = geometry as { type?: string; coordinates?: unknown };

  if (candidate.type === 'MultiPolygon' && Array.isArray(candidate.coordinates)) {
    return {
      type: 'MultiPolygon',
      coordinates: candidate.coordinates as number[][][][],
    };
  }

  if (candidate.type === 'Polygon' && Array.isArray(candidate.coordinates)) {
    return {
      type: 'MultiPolygon',
      coordinates: [candidate.coordinates as number[][][]],
    };
  }

  return null;
}

function parseGeometryValue(geometry: unknown): GeoJSONMultiPolygon | null {
  if (!geometry) return null;

  if (typeof geometry === 'object') {
    return toMultiPolygonGeometry(geometry);
  }

  if (typeof geometry !== 'string') {
    return null;
  }

  const trimmed = geometry.trim();
  if (!trimmed) return null;

  try {
    return toMultiPolygonGeometry(JSON.parse(trimmed));
  } catch {
    // Fall through to WKT parsing.
  }

  try {
    const parsed = wkx.Geometry.parse(trimmed);
    return toMultiPolygonGeometry(parsed.toGeoJSON());
  } catch {
    return null;
  }
}

function normalizeParcelLine(raw: unknown): NormalizedParcelRecord | null {
  if (!raw || typeof raw !== 'object') return null;

  const record = raw as Record<string, unknown>;
  const isFeature = record.type === 'Feature';

  const featureProperties = isFeature && record.properties && typeof record.properties === 'object'
    ? { ...(record.properties as Record<string, unknown>) }
    : {};

  const geometry = parseGeometryValue(
    isFeature ? record.geometry : (record.geometry ?? record.geom ?? record.geom_json)
  );

  if (!geometry) return null;

  const properties = isFeature
    ? featureProperties
    : Object.fromEntries(
        Object.entries(record).filter(([key]) => !['geometry', 'geom', 'geom_json'].includes(key))
      );

  const externalIdCandidate =
    featureProperties.external_id ??
    featureProperties.parcel_id ??
    featureProperties.PARCELID ??
    record.external_id ??
    record.parcel_id ??
    record.id;

  const externalId = typeof externalIdCandidate === 'string' || typeof externalIdCandidate === 'number'
    ? String(externalIdCandidate).trim()
    : '';

  if (!externalId) return null;

  return {
    externalId,
    geometry,
    properties,
  };
}

async function streamBodyToString(body: { transformToString?: () => Promise<string> } | undefined) {
  if (!body?.transformToString) return '';
  return body.transformToString();
}

async function streamBodyToBytes(body: { transformToByteArray?: () => Promise<Uint8Array> } | undefined) {
  if (!body?.transformToByteArray) return null;
  return body.transformToByteArray();
}

export class ParcelEnrichmentService {
  private readonly s3: S3Client;

  constructor(private readonly supabase: SupabaseClient) {
    this.s3 = new S3Client({ region: process.env.AWS_REGION || 'us-east-2' });
  }

  async markQueued(campaignId: string) {
    await this.supabase
      .from('campaigns')
      .update({
        parcel_enrichment_status: 'queued',
        parcel_enrichment_error: null,
        parcel_enrichment_debug: {
          status: 'queued',
          queued_at: new Date().toISOString(),
        },
      })
      .eq('id', campaignId);
  }

  async prepareParcelsForProvision(campaignId: string): Promise<ParcelPreparationResult> {
    const campaign = await this.getCampaign(campaignId);
    const result = await this.loadCampaignParcels(campaignId, campaign);

    if (result.status === 'ready') {
      await this.replaceCampaignParcels(campaignId, result.parcels);
    }

    await this.markTerminalState(campaignId, result.status, {
      sourceId: result.sourceId,
      parcelCount: result.parcelCount,
      error: result.error,
      debug: result.debug,
    });

    return result;
  }

  async runForCampaign(campaignId: string) {
    const campaign = await this.getCampaign(campaignId);
    const campaignPolygon = campaign.territory_boundary;
    const debug: ParcelEnrichmentDebug = {
      mode: campaignPolygon ? 'polygon_intersects' : 'bbox_only',
      started_at: new Date().toISOString(),
    };

    await this.supabase
      .from('campaigns')
      .update({
        parcel_enrichment_status: 'processing',
        parcel_enrichment_error: null,
        parcel_enrichment_debug: debug,
      })
      .eq('id', campaignId);

    try {
      const result = await this.loadCampaignParcels(campaignId, campaign, debug);
      if (result.status !== 'ready') {
        await this.markTerminalState(campaignId, result.status, {
          sourceId: result.sourceId,
          parcelCount: result.parcelCount,
          error: result.error,
          debug: result.debug,
        });
        await new CampaignMapModeService(this.supabase).computeAndPersist(campaignId, {
          hasParcels: false,
          parcelCount: 0,
        });
        return;
      }

      await this.replaceCampaignParcels(campaignId, result.parcels);
      if (result.parcelCount === 0) {
        await this.markTerminalState(campaignId, 'ready', {
          sourceId: result.sourceId,
          parcelCount: 0,
          debug: result.debug,
        });
        await new CampaignMapModeService(this.supabase).computeAndPersist(campaignId, {
          hasParcels: false,
          parcelCount: 0,
        });
        return;
      }

      const relinkResult = await this.relinkCampaign(campaignId, campaign.territory_boundary, result.parcels);
      const multiUnitFlagsRefreshed = await this.refreshMultiUnitFlags(campaignId);
      const townhouseRefreshResult = await this.refreshTownhouseUnits(campaignId);

      await this.markTerminalState(campaignId, 'ready', {
        sourceId: result.sourceId,
        parcelCount: result.parcelCount,
        debug: {
          ...result.debug,
          relink: {
            strategy: relinkResult.strategy,
            gold_linker_ran: relinkResult.gold_linker_ran,
            consolidated_linker_ran: relinkResult.consolidated_linker_ran,
            snapshot_linker_ran: relinkResult.snapshot_linker_ran,
            snapshot_linker_used_parcels: relinkResult.snapshot_linker_used_parcels,
            multi_unit_flags_refreshed: multiUnitFlagsRefreshed,
            campaign_building_count: relinkResult.campaign_building_count,
            snapshot_building_count: relinkResult.snapshot_building_count,
            townhouse_refresh_attempted: townhouseRefreshResult.attempted,
            townhouse_refresh_applied: townhouseRefreshResult.applied,
          },
          completed_at: new Date().toISOString(),
        },
      });
      await new CampaignMapModeService(this.supabase).computeAndPersist(campaignId, {
        hasParcels: result.parcelCount > 0,
        parcelCount: result.parcelCount,
      });
    } catch (error) {
      await this.markTerminalState(campaignId, 'failed', {
        error: error instanceof Error ? error.message : 'Unknown parcel enrichment error.',
        debug: {
          ...debug,
          completed_at: new Date().toISOString(),
        },
      });
    }
  }

  private async getCampaign(campaignId: string): Promise<CampaignRow> {
    const { data: campaign, error: campaignError } = await this.supabase
      .from('campaigns')
      .select('id, bbox, territory_boundary, region')
      .eq('id', campaignId)
      .single<CampaignRow>();

    if (campaignError || !campaign) {
      throw new Error(`Campaign lookup failed: ${campaignError?.message || 'not found'}`);
    }

    return campaign;
  }

  private async loadCampaignParcels(
    campaignId: string,
    campaign: CampaignRow,
    debugOverride?: ParcelEnrichmentDebug
  ): Promise<ParcelPreparationResult> {
    const regionCode = (campaign.region || '').trim().toUpperCase();
    const bbox = getCampaignBbox(campaign);
    const campaignPolygon = campaign.territory_boundary;
    if (!bbox) {
      return {
        status: 'failed',
        sourceId: null,
        parcelCount: 0,
        parcels: [],
        error: 'Campaign has no bbox or territory boundary for parcel filtering.',
        debug: {
          ...(debugOverride ?? {}),
          mode: campaignPolygon ? 'polygon_intersects' : 'bbox_only',
          skipped_reason: 'Campaign has no bbox or territory boundary for parcel filtering.',
          completed_at: new Date().toISOString(),
        },
      };
    }

    const debug: ParcelEnrichmentDebug = {
      mode: campaignPolygon ? 'polygon_intersects' : 'bbox_only',
      started_at: debugOverride?.started_at ?? new Date().toISOString(),
      ...debugOverride,
    };

    const sourceResolution = await this.inferSourceId(campaignId);
    debug.unsupported_localities = sourceResolution.unsupportedLocalities;
    debug.locality_counts = sourceResolution.localityCounts;
    const sourceId = sourceResolution.sourceId;
    if (!sourceId) {
      return {
        status: 'skipped',
        sourceId: null,
        parcelCount: 0,
        parcels: [],
        error: 'No supported parcel source could be inferred from campaign localities.',
        debug: {
          ...debug,
          skipped_reason: 'No supported parcel source could be inferred from campaign localities.',
          completed_at: new Date().toISOString(),
        },
      };
    }
    debug.source_id = sourceId;

    const key = await this.findLatestParcelKey(sourceId);
    if (!key) {
      return {
        status: 'failed',
        sourceId,
        parcelCount: 0,
        parcels: [],
        error: `No parcel object found for source_id ${sourceId}.`,
        debug: {
          ...debug,
          s3_key: null,
          skipped_reason: `No parcel object found for source_id ${sourceId}.`,
          completed_at: new Date().toISOString(),
        },
      };
    }
    debug.s3_key = key;

    const response = await this.s3.send(
      new GetObjectCommand({
        Bucket: PARCEL_BUCKET,
        Key: key,
      })
    );
    const body = await streamBodyToString(response.Body);
    if (!body.trim()) {
      return {
        status: 'failed',
        sourceId,
        parcelCount: 0,
        parcels: [],
        error: `Parcel file ${key} was empty.`,
        debug: {
          ...debug,
          scanned_lines: 0,
          parsed_records: 0,
          bbox_candidates: 0,
          polygon_matches: 0,
          inserted_count: 0,
          completed_at: new Date().toISOString(),
        },
      };
    }

    const deduped = new Map<string, NormalizedParcelRecord>();
    let scannedLines = 0;
    let parsedRecords = 0;
    let bboxCandidates = 0;
    let polygonMatches = 0;
    for (const line of body.split(/\r?\n/)) {
      const trimmed = line.trim();
      if (!trimmed) continue;
      scannedLines += 1;

      try {
        const parsed = JSON.parse(trimmed);
        const parcel = normalizeParcelLine(parsed);
        if (!parcel) continue;
        parsedRecords += 1;
        if (!intersectsBbox(parcel.geometry, bbox)) continue;
        bboxCandidates += 1;
        if (campaignPolygon && !isWithinCampaignPolygon(parcel.geometry, campaignPolygon)) continue;
        polygonMatches += 1;
        deduped.set(parcel.externalId, parcel);
      } catch (error) {
        console.warn('[ParcelEnrichment] Skipping malformed parcel line:', error);
      }
    }

    const parcels = Array.from(deduped.values());
    debug.scanned_lines = scannedLines;
    debug.parsed_records = parsedRecords;
    debug.bbox_candidates = bboxCandidates;
    debug.polygon_matches = polygonMatches;
    debug.inserted_count = parcels.length;
    debug.completed_at = new Date().toISOString();

    return {
      status: 'ready',
      sourceId,
      parcelCount: parcels.length,
      parcels,
      error: null,
      debug,
    };
  }

  private async replaceCampaignParcels(campaignId: string, parcels: NormalizedParcelRecord[]) {
    await this.supabase
      .from('campaign_parcels')
      .delete()
      .eq('campaign_id', campaignId);

    if (parcels.length === 0) {
      return;
    }

    for (let i = 0; i < parcels.length; i += PARCEL_BATCH_SIZE) {
      const batch = parcels.slice(i, i + PARCEL_BATCH_SIZE).map((parcel) => ({
        campaign_id: campaignId,
        external_id: parcel.externalId,
        geom: JSON.stringify(parcel.geometry),
        properties: parcel.properties,
      }));

      const { error } = await this.supabase
        .from('campaign_parcels')
        .insert(batch);

      if (error) {
        throw new Error(`Parcel insert failed: ${error.message}`);
      }
    }
  }

  private async inferSourceId(campaignId: string): Promise<{
    sourceId: SupportedParcelSourceId | null;
    unsupportedLocalities: string[];
    localityCounts: Array<{ source_id: SupportedParcelSourceId; count: number }>;
  }> {
    const rows = await fetchAllInPages((from, to) =>
      this.supabase
        .from('campaign_addresses')
        .select('locality')
        .eq('campaign_id', campaignId)
        .range(from, to)
    );

    const localityCounts = new Map<SupportedParcelSourceId, number>();
    const unsupportedLocalities = new Set<string>();

    for (const row of rows) {
      const locality = normalizeLocality((row as { locality?: string | null }).locality);
      if (!locality) continue;
      const sourceId = LOCALITY_TO_SOURCE_ID[locality];
      if (!sourceId) {
        unsupportedLocalities.add(locality);
        continue;
      }
      localityCounts.set(sourceId, (localityCounts.get(sourceId) || 0) + 1);
    }

    const ranked = Array.from(localityCounts.entries()).sort((a, b) => b[1] - a[1]);
    const localitySummary = ranked.map(([source_id, count]) => ({ source_id, count }));
    if (ranked.length === 0) {
      if (unsupportedLocalities.size > 0) {
        console.warn('[ParcelEnrichment] Unsupported localities:', Array.from(unsupportedLocalities));
      }
      return {
        sourceId: null,
        unsupportedLocalities: Array.from(unsupportedLocalities).sort(),
        localityCounts: localitySummary,
      };
    }

    return {
      sourceId: ranked[0][0],
      unsupportedLocalities: Array.from(unsupportedLocalities).sort(),
      localityCounts: localitySummary,
    };
  }

  private async findLatestParcelKey(sourceId: SupportedParcelSourceId): Promise<string | null> {
    const prefix = `${PARCEL_PREFIX}/${sourceId}/`;
    let continuationToken: string | undefined;
    let latestKey: string | null = null;
    let latestDate = '';

    do {
      const response = await this.s3.send(
        new ListObjectsV2Command({
          Bucket: PARCEL_BUCKET,
          Prefix: prefix,
          ContinuationToken: continuationToken,
        })
      );

      for (const object of response.Contents || []) {
        const key = object.Key || '';
        const match = key.match(new RegExp(`/${sourceId}/(\\d{8})/${sourceId}_gold\\.ndjson$`));
        if (!match) continue;
        const datePart = match[1];
        if (datePart > latestDate) {
          latestDate = datePart;
          latestKey = key;
        }
      }

      continuationToken = response.IsTruncated ? response.NextContinuationToken : undefined;
    } while (continuationToken);

    return latestKey;
  }

  private async relinkCampaign(
    campaignId: string,
    polygon: GeoJSONPolygon | null,
    parcels: NormalizedParcelRecord[]
  ): Promise<{
    strategy: 'campaign_buildings' | 'snapshot' | 'none';
    gold_linker_ran: boolean;
    consolidated_linker_ran: boolean;
    snapshot_linker_ran: boolean;
    snapshot_linker_used_parcels: boolean;
    campaign_building_count: number;
    snapshot_building_count: number;
  }> {
    const campaignBuildings = await this.loadCampaignBuildings(campaignId);
    const campaignBuildingCount = campaignBuildings.features.length;
    const linker = new StableLinkerService(this.supabase);

    if (campaignBuildingCount > 0) {
      console.log('[ParcelEnrichment] Relinking with campaign building store:', {
        campaignId,
        campaignBuildingCount,
        hasPolygon: Boolean(polygon),
        parcelCount: parcels.length,
      });
      await linker.runSpatialJoin(
        campaignId,
        { features: campaignBuildings.features },
        '2026-01-21.0',
        {
          parcels: parcels.map((parcel) => ({
            externalId: parcel.externalId,
            geometry: parcel.geometry,
          })),
          resetExisting: true,
          persistenceMode: 'gold',
        }
      );

      return {
        strategy: 'campaign_buildings',
        gold_linker_ran: true,
        consolidated_linker_ran: true,
        snapshot_linker_ran: false,
        snapshot_linker_used_parcels: true,
        campaign_building_count: campaignBuildingCount,
        snapshot_building_count: 0,
      };
    }

    const snapshot = await this.loadSnapshotBuildings(campaignId);
    if (!snapshot || snapshot.buildingsGeoJSON.features.length === 0) {
      console.warn('[ParcelEnrichment] No viable building source for parcel-aware relink:', {
        campaignId,
        campaignBuildingCount,
      });
      return {
        strategy: 'none',
        gold_linker_ran: false,
        consolidated_linker_ran: false,
        snapshot_linker_ran: false,
        snapshot_linker_used_parcels: false,
        campaign_building_count: campaignBuildingCount,
        snapshot_building_count: 0,
      };
    }

    console.log('[ParcelEnrichment] Relinking with snapshot parcel bridge:', {
      campaignId,
      campaignBuildingCount,
      snapshotBuildingCount: snapshot.buildingsGeoJSON.features.length,
      parcelCount: parcels.length,
    });
    await linker.runSpatialJoin(
      campaignId,
      snapshot.buildingsGeoJSON,
      snapshot.overtureRelease,
      {
        parcels: parcels.map((parcel) => ({
          externalId: parcel.externalId,
          geometry: parcel.geometry,
        })),
        resetExisting: true,
      }
    );

    return {
      strategy: 'snapshot',
      gold_linker_ran: false,
      consolidated_linker_ran: true,
      snapshot_linker_ran: true,
      snapshot_linker_used_parcels: true,
      campaign_building_count: campaignBuildingCount,
      snapshot_building_count: snapshot.buildingsGeoJSON.features.length,
    };
  }

  private async refreshMultiUnitFlags(campaignId: string): Promise<boolean> {
    const links = await fetchAllInPages((from, to) =>
      this.supabase
        .from('building_address_links')
        .select('id, building_id')
        .eq('campaign_id', campaignId)
        .order('id', { ascending: true })
        .range(from, to)
    );

    if (links.length === 0) return false;

    const counts = new Map<string, number>();
    for (const row of links) {
      const buildingId = String((row as { building_id?: string | null }).building_id || '');
      if (!buildingId) continue;
      counts.set(buildingId, (counts.get(buildingId) || 0) + 1);
    }

    await Promise.all(
      links.map((row) => {
        const record = row as { id: string; building_id?: string | null };
        const buildingId = String(record.building_id || '');
        const unitCount = counts.get(buildingId) || 1;
        return this.supabase
          .from('building_address_links')
          .update({
            unit_count: unitCount,
            is_multi_unit: unitCount > 1,
            unit_arrangement: unitCount > 1 ? 'horizontal' : 'single',
          })
          .eq('id', record.id);
      })
    );

    return true;
  }

  private async refreshTownhouseUnits(campaignId: string): Promise<{
    attempted: boolean;
    applied: boolean;
  }> {
    const snapshot = await this.loadSnapshotBuildings(campaignId);
    if (!snapshot || snapshot.buildingsGeoJSON.features.length === 0) {
      return {
        attempted: false,
        applied: false,
      };
    }

    const splitter = new TownhouseSplitterService(this.supabase);
    await splitter.processCampaignTownhouses(
      campaignId,
      snapshot.buildingsGeoJSON as { features: Array<{ type: 'Feature'; geometry: { type: 'Polygon'; coordinates: number[][][] }; properties: { gers_id: string } }> },
      snapshot.overtureRelease
    );
    return {
      attempted: true,
      applied: true,
    };
  }

  private async loadCampaignBuildings(campaignId: string): Promise<{ features: SnapshotBuildingFeature[] }> {
    const rows = await fetchAllInPages((from, to) =>
      this.supabase
        .from('buildings')
        .select('id, gers_id, geom, height, house_name, addr_street')
        .eq('campaign_id', campaignId)
        .eq('is_hidden', false)
        .order('id', { ascending: true })
        .range(from, to)
    );

    const features: SnapshotBuildingFeature[] = [];
    for (const row of rows as CampaignBuildingRow[]) {
      const geometry = parseGeometryValue(row.geom);
      const polygon = geometry?.coordinates?.[0];
      if (!polygon || polygon.length === 0) {
        continue;
      }

      features.push({
        type: 'Feature',
        geometry: {
          type: 'Polygon',
          coordinates: polygon,
        },
        properties: {
          gers_id: row.id,
          name: row.house_name ?? row.gers_id ?? null,
          height: row.height ?? null,
          layer: 'building',
          primary_street: row.addr_street ?? null,
        },
      });
    }

    return { features };
  }

  private async loadSnapshotBuildings(campaignId: string): Promise<{
    overtureRelease: string;
    buildingsGeoJSON: { features: SnapshotBuildingFeature[] };
  } | null> {
    const { data: snapshot, error: snapshotError } = await this.supabase
      .from('campaign_snapshots')
      .select('bucket, buildings_key, overture_release')
      .eq('campaign_id', campaignId)
      .maybeSingle();

    if (snapshotError || !snapshot?.bucket || !snapshot?.buildings_key) {
      return null;
    }

    const response = await this.s3.send(
      new GetObjectCommand({
        Bucket: snapshot.bucket,
        Key: snapshot.buildings_key,
      })
    );

    const bytes = await streamBodyToBytes(response.Body);
    if (!bytes) return null;

    const decompressed = gunzipSync(Buffer.from(bytes));
    const buildingsGeoJSON = JSON.parse(decompressed.toString('utf-8')) as { features?: SnapshotBuildingFeature[] };
    if (!Array.isArray(buildingsGeoJSON.features) || buildingsGeoJSON.features.length === 0) {
      return null;
    }

    return {
      overtureRelease: snapshot.overture_release || '2026-01-21.0',
      buildingsGeoJSON: {
        features: buildingsGeoJSON.features,
      },
    };
  }

  private async markTerminalState(
    campaignId: string,
    status: Extract<ParcelEnrichmentStatus, 'ready' | 'failed' | 'skipped'>,
    options: {
      sourceId?: string | null;
      parcelCount?: number;
      error?: string | null;
      debug?: ParcelEnrichmentDebug;
    }
  ) {
    await this.supabase
      .from('campaigns')
      .update({
        parcel_enrichment_status: status,
        parcel_source_id: options.sourceId ?? null,
        parcel_count: options.parcelCount ?? 0,
        parcel_enriched_at: status === 'ready' ? new Date().toISOString() : null,
        parcel_enrichment_error: options.error ?? null,
        parcel_enrichment_debug: options.debug ?? {},
      })
      .eq('id', campaignId);
  }
}
