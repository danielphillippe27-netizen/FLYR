import { createClient } from "@supabase/supabase-js";
import { GetObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { NextResponse } from "next/server";
import zlib from "zlib";
import { fetchScopedPmtilesBuildingFeatures } from "@/app/api/campaigns/_utils/scoped-pmtiles-buildings";
import { resolvePmtilesKey, type CampaignSnapshotRow } from "@/lib/diamond/geometry";
import { filterLinkableBuildingFootprints } from "@/lib/geo/buildingFootprintFilter";
import { fetchAllInPages } from "@/lib/supabase/fetchAllInPages";

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || "";
const AWS_REGION = process.env.AWS_REGION ?? "us-east-1";
const POLISHED_BUILDING_GEOMETRY_VERSION = 9;

export const dynamic = "force-dynamic";
export const revalidate = 0;
export const maxDuration = 300;

type RouteContext = { params: Promise<{ campaignId: string }> };
type AuthenticatedRequestUser = { id: string; email: string | null };

function getAuthUser(request: Request): string | null {
  const authHeader = request.headers.get("authorization");
  return authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
}

function createUserScopedSupabase(token: string) {
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: {
      headers: {
        Authorization: `Bearer ${token}`,
      },
    },
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

function createAuthSupabase() {
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

function createAdminSupabase() {
  if (!SUPABASE_SERVICE_ROLE_KEY) return null;
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

function decodeBearerUser(token: string): AuthenticatedRequestUser | null {
  const [, payload] = token.split(".");
  if (!payload) return null;

  try {
    const decoded = JSON.parse(Buffer.from(payload, "base64url").toString("utf8")) as {
      sub?: unknown;
      email?: unknown;
      exp?: unknown;
    };
    const userId = normalizedString(decoded.sub);
    if (!userId) return null;
    const exp = typeof decoded.exp === "number" ? decoded.exp : null;
    if (exp != null && exp <= Math.floor(Date.now() / 1000)) return null;
    return {
      id: userId,
      email: normalizedString(decoded.email),
    };
  } catch {
    return null;
  }
}

/** Ensure the campaign exists and the user can access it (owner or workspace member). */
async function ensureCampaignAccess(
  supabase: any,
  campaignId: string,
  userId: string
): Promise<boolean> {
  const { data: campaign, error: campError } = await supabase
    .from("campaigns")
    .select("id, owner_id, workspace_id")
    .eq("id", campaignId)
    .maybeSingle();
  if (campError || !campaign) return false;
  const row = campaign as { id: string; owner_id: string; workspace_id: string | null };
  if (row.owner_id === userId) return true;
  if (row.workspace_id) {
    const { data: member } = await supabase
      .from("workspace_members")
      .select("user_id")
      .eq("workspace_id", row.workspace_id)
      .eq("user_id", userId)
      .maybeSingle();
    if (member) return true;
    const { data: workspace } = await supabase
      .from("workspaces")
      .select("owner_id")
      .eq("id", row.workspace_id)
      .maybeSingle();
    if (workspace && (workspace as { owner_id: string }).owner_id === userId) return true;
  }
  return false;
}

const EMPTY_FEATURE_COLLECTION = { type: "FeatureCollection", features: [] };
const JSON_NO_STORE_HEADERS = {
  "Content-Type": "application/json",
  "Cache-Control": "no-store, max-age=0",
};
type GeoJSONGeometry = {
  type?: string;
  coordinates?: unknown;
};

type GeoJSONFeature = {
  id?: unknown;
  type?: string;
  geometry?: GeoJSONGeometry;
  properties?: Record<string, unknown>;
};

type HiddenBuildingRow = {
  public_building_id: string;
};

type CampaignRow = {
  territory_boundary: GeoJSON.Polygon | null;
  provision_source: string | null;
};

type GoldBuildingRow = {
  id: string;
  area_sqm?: number | null;
  building_type?: string | null;
  geom_geojson?: string | null;
  geom?: unknown;
};

type MaterializedCampaignBuildingRow = {
  id: string;
  gers_id: string | null;
  geom?: unknown;
  height_m: number | null;
  height: number | null;
  latest_status: string | null;
  is_hidden: boolean | null;
  units_count: number | null;
  addr_housenumber: string | null;
  addr_street: string | null;
};

type CampaignAddressRow = {
  id: string;
  formatted: string | null;
  house_number: string | null;
  street_name: string | null;
  building_id: string | null;
  building_gers_id: string | null;
  confidence: number | null;
  geom?: unknown;
  match_source: string | null;
  visited: boolean | null;
  scans: number | null;
};

type BuildingAddressLinkRow = {
  address_id: string;
  building_id: string;
  confidence: number | null;
  match_type: string | null;
};

type BuildingIdentityRow = {
  id: string;
  gers_id: string | null;
};

type PolishedBuildingCacheRow = {
  feature_collection: unknown;
  feature_count: number | null;
  source: string | null;
  updated_at: string | null;
};

function normalizedString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function finiteNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function bboxFromPolygon(rawPolygon: unknown): [number, number, number, number] | null {
  let polygon = rawPolygon;
  if (typeof polygon === "string") {
    try {
      polygon = JSON.parse(polygon);
    } catch {
      return null;
    }
  }

  const coordinates =
    polygon && typeof polygon === "object" && Array.isArray((polygon as GeoJSON.Polygon).coordinates)
      ? (polygon as GeoJSON.Polygon).coordinates
      : null;

  const positions = coordinates?.flat().filter(
    (position): position is number[] =>
      Array.isArray(position) &&
      typeof position[0] === "number" &&
      typeof position[1] === "number" &&
      Number.isFinite(position[0]) &&
      Number.isFinite(position[1])
  ) ?? [];

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

function isPolygonFeature(feature: GeoJSONFeature): boolean {
  const geometryType = normalizedString(feature.geometry?.type);
  return geometryType === "Polygon" || geometryType === "MultiPolygon";
}

function stripGeometryCrs(geometry: GeoJSONGeometry): GeoJSONGeometry {
  const { crs: _crs, ...cleanGeometry } = geometry as GeoJSONGeometry & { crs?: unknown };
  return cleanGeometry;
}

function polygonGeometryFromValue(value: unknown): GeoJSONGeometry | null {
  if (!value) return null;

  if (typeof value === "object") {
    const geometry = value as GeoJSONGeometry;
    if (geometry.type === "Polygon" || geometry.type === "MultiPolygon") {
      return stripGeometryCrs(geometry);
    }
    return null;
  }

  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed) return null;

  try {
    return polygonGeometryFromValue(JSON.parse(trimmed));
  } catch {
    return null;
  }
}

function isManualFeature(feature: GeoJSONFeature): boolean {
  const source = normalizedString(feature.properties?.source)?.toLowerCase();
  return source === "manual";
}

function isGoldFeature(feature: GeoJSONFeature): boolean {
  const source = normalizedString(feature.properties?.source)?.toLowerCase();
  return source === "gold";
}

function isSilverFeature(feature: GeoJSONFeature): boolean {
  const source = normalizedString(feature.properties?.source)?.toLowerCase();
  return source === "silver" || source === "lambda" || source === "snapshot";
}

function dedupeFeatures(features: GeoJSONFeature[]): GeoJSONFeature[] {
  const seen = new Set<string>();
  const deduped: GeoJSONFeature[] = [];

  for (const feature of features) {
    const key =
      normalizedString(feature.id) ??
      normalizedString(feature.properties?.id) ??
      JSON.stringify(feature);
    if (seen.has(key)) continue;
    seen.add(key);
    deduped.push(feature);
  }

  return deduped;
}

function buildingIdentifierCandidates(feature: GeoJSONFeature): string[] {
  const identifiers = [
    normalizedString(feature.properties?.public_building_id),
    normalizedString(feature.properties?.canonical_building_id),
    normalizedString(feature.properties?.gers_id),
    normalizedString(feature.properties?.building_id),
    normalizedString(feature.properties?.id),
    normalizedString(feature.id),
  ]
    .filter((value): value is string => Boolean(value))
    .map((value) => value.toLowerCase());

  return Array.from(new Set(identifiers));
}

function primaryBuildingIdentifier(feature: GeoJSONFeature): string | null {
  return (
    normalizedString(feature.properties?.public_building_id) ??
    normalizedString(feature.properties?.canonical_building_id) ??
    normalizedString(feature.properties?.gers_id) ??
    normalizedString(feature.properties?.building_id) ??
    normalizedString(feature.properties?.id) ??
    normalizedString(feature.id)
  );
}

function normalizeBuildingIdentityFeature(feature: GeoJSONFeature): GeoJSONFeature {
  const props = feature.properties ?? {};
  const publicId = primaryBuildingIdentifier(feature);
  if (!publicId) return feature;

  const existingGersId = normalizedString(props.gers_id);
  const existingBuildingId = normalizedString(props.building_id);
  const featureSource = normalizedString(props.source)?.toLowerCase() ?? "";
  const identifierSource =
    normalizedString(props.building_identifier_source) ??
    (featureSource.includes("diamond") || featureSource.startsWith("bedrock") ? "diamond" : null) ??
    (existingGersId ? "gers" : existingBuildingId ? "diamond" : "feature");

  return {
    ...feature,
    id: normalizedString(feature.id) ?? publicId,
    properties: {
      ...props,
      id: normalizedString(props.id) ?? publicId,
      building_id: existingBuildingId ?? publicId,
      // Mapbox promoteId and older iOS paths still read `gers_id`. Treat it as
      // our public building id, not strictly an Overture/GERS-only identifier.
      gers_id: existingGersId ?? publicId,
      public_building_id: normalizedString(props.public_building_id) ?? publicId,
      canonical_building_id: normalizedString(props.canonical_building_id) ?? publicId,
      building_identifier_source: identifierSource,
    },
  };
}

function filterHiddenBuildings(
  features: GeoJSONFeature[],
  hiddenBuildingIds: Set<string>
): GeoJSONFeature[] {
  if (hiddenBuildingIds.size == 0) return features;
  return features.filter((feature) =>
    !buildingIdentifierCandidates(feature).some((candidate) => hiddenBuildingIds.has(candidate))
  );
}

function isAddressProxyFeature(feature: GeoJSONFeature): boolean {
  const props = feature.properties ?? {};
  const source = normalizedString(props.source)?.toLowerCase();
  const featureType = normalizedString(props.feature_type)?.toLowerCase();
  const featureStatus = normalizedString(props.feature_status)?.toLowerCase();
  const identifierSource = normalizedString(props.building_identifier_source)?.toLowerCase();
  const ids = [
    normalizedString(feature.id),
    normalizedString(props.id),
    normalizedString(props.gers_id),
    normalizedString(props.building_id),
    normalizedString(props.public_building_id),
    normalizedString(props.canonical_building_id),
  ].flatMap((value) => {
    const normalized = value?.toLowerCase();
    return normalized ? [normalized] : [];
  });
  return source === "address_proxy" ||
    featureType === "address_proxy" ||
    featureStatus === "missing_footprint_proxy" ||
    identifierSource === "address_proxy" ||
    ids.some((id) => id.startsWith("address-proxy-"));
}

function filterLinkableBuildingFeatures(
  features: GeoJSONFeature[],
  context: string
): GeoJSONFeature[] {
  const filtered = features.filter((feature) => {
    if (isAddressProxyFeature(feature)) return false;
    return filterLinkableBuildingFootprints([feature], { allowManual: true }).length > 0;
  });
  const removed = features.length - filtered.length;
  if (removed > 0) {
    console.log(`[buildings] Filtered ${removed} building feature(s) under minimum area from ${context}`);
  }
  return filtered;
}

function featureAddressAssignmentRank(feature: GeoJSONFeature): number {
  const props = feature.properties ?? {};
  const source = normalizedString(props.source)?.toLowerCase() ?? "";
  const matchMethod = normalizedString(props.match_method)?.toLowerCase() ?? "";
  const featureStatus = normalizedString(props.feature_status)?.toLowerCase() ?? "";
  const confidence = finiteNumber(props.confidence) ?? 0;

  const sourceScore = source === "manual" ? 6 : source === "gold" ? 5 : source === "silver" ? 4 : 1;
  const methodScore =
    matchMethod === "manual" ? 5 :
    matchMethod === "containment_verified" ? 4 :
    matchMethod === "point_on_surface" ? 3 :
    matchMethod === "parcel_verified" ? 2 :
    matchMethod === "proximity_fallback" ? 0 :
    featureStatus === "matched" ? 1 :
    0;

  return sourceScore * 100 + methodScore * 10 + confidence;
}

function clearAddressAssignment(feature: GeoJSONFeature): GeoJSONFeature {
  const props = feature.properties ?? {};
  return {
    ...feature,
    properties: {
      ...props,
      address_id: null,
      address_ids: [],
      address_text: null,
      house_number: null,
      street_name: null,
      address_count: 0,
      is_linked: false,
      feature_status: props.feature_status ?? "orphan_building",
    },
  };
}

function enforceUniqueFeatureAddressAssignments(features: GeoJSONFeature[]): GeoJSONFeature[] {
  const bestIndexByAddress = new Map<string, number>();

  for (const [index, feature] of features.entries()) {
    const addressId = normalizedString(feature.properties?.address_id)?.toLowerCase();
    if (!addressId) continue;

    const existingIndex = bestIndexByAddress.get(addressId);
    if (
      existingIndex == null ||
      featureAddressAssignmentRank(feature) > featureAddressAssignmentRank(features[existingIndex])
    ) {
      bestIndexByAddress.set(addressId, index);
    }
  }

  const winningIndexes = new Set(bestIndexByAddress.values());
  return features.map((feature, index) => {
    const addressId = normalizedString(feature.properties?.address_id);
    return addressId && !winningIndexes.has(index) ? clearAddressAssignment(feature) : feature;
  });
}

async function enrichFeaturesWithPersistedLinks(
  supabase: any,
  campaignId: string,
  features: GeoJSONFeature[]
): Promise<GeoJSONFeature[]> {
  if (features.length === 0) return features;

  const [links, addresses, buildings] = await Promise.all([
    fetchAllInPages<BuildingAddressLinkRow>((from, to) =>
      supabase
        .from("building_address_links")
        .select("address_id, building_id, confidence, match_type")
        .eq("campaign_id", campaignId)
        .range(from, to)
    ),
    fetchAllInPages<CampaignAddressRow>((from, to) =>
      supabase
        .from("campaign_addresses")
        .select("id, formatted, house_number, street_name, building_id, building_gers_id, confidence, match_source, visited, scans, geom")
        .eq("campaign_id", campaignId)
        .range(from, to)
    ),
    fetchAllInPages<BuildingIdentityRow>((from, to) =>
      supabase
        .from("buildings")
        .select("id, gers_id")
        .eq("campaign_id", campaignId)
        .range(from, to)
    ),
  ]);

  const addressById = new Map(addresses.map((address) => [address.id, address]));
  const directAddressesByBuildingId = new Map<string, CampaignAddressRow[]>();
  for (const address of addresses) {
    const keys = [
      normalizedString(address.building_id),
      normalizedString(address.building_gers_id),
    ]
      .filter((value): value is string => Boolean(value))
      .map((value) => value.toLowerCase());
    for (const key of Array.from(new Set(keys))) {
      const group = directAddressesByBuildingId.get(key) ?? [];
      group.push(address);
      directAddressesByBuildingId.set(key, group);
    }
  }

  const buildingAliasesByRowId = new Map<string, string[]>();
  for (const building of buildings) {
    const aliases = [
      normalizedString(building.id),
      normalizedString(building.gers_id),
    ]
      .filter((value): value is string => Boolean(value))
      .map((value) => value.toLowerCase());
    if (aliases.length > 0) {
      buildingAliasesByRowId.set(building.id.toLowerCase(), Array.from(new Set(aliases)));
    }
  }

  const linksByBuildingId = new Map<string, BuildingAddressLinkRow[]>();
  for (const link of links) {
    const rowId = normalizedString(link.building_id)?.toLowerCase();
    if (!rowId) continue;
    const aliases = buildingAliasesByRowId.get(rowId) ?? [rowId];
    for (const key of aliases) {
      const group = linksByBuildingId.get(key) ?? [];
      group.push(link);
      linksByBuildingId.set(key, group);
    }
  }

  return features.map((feature) => {
    const candidateKeys = buildingIdentifierCandidates(feature);
    const buildingLinks = Array.from(
      new Map(
        candidateKeys
          .flatMap((candidate) => linksByBuildingId.get(candidate) ?? [])
          .map((link) => [`${link.building_id}:${link.address_id}`, link])
      ).values()
    );

    const directlyLinkedAddresses = Array.from(
      new Map(
        candidateKeys
          .flatMap((candidate) => directAddressesByBuildingId.get(candidate) ?? [])
          .map((address) => [address.id, address])
      ).values()
    );
    const linkedAddresses = Array.from(
      new Map([
        ...buildingLinks
          .map((link) => addressById.get(link.address_id) ?? null)
          .filter((address): address is CampaignAddressRow => address !== null)
          .map((address) => [address.id, address] as const),
        ...directlyLinkedAddresses.map((address) => [address.id, address] as const),
        ...[
          normalizedString(feature.properties?.address_id)
        ]
          .map((addressId) => addressId ? addressById.get(addressId) ?? null : null)
          .filter((address): address is CampaignAddressRow => address !== null)
          .map((address) => [address.id, address] as const),
      ]).values()
    );

    if (linkedAddresses.length === 0) {
      return {
        ...feature,
        properties: {
          ...(feature.properties ?? {}),
          address_id: null,
          address_text: null,
          house_number: null,
          street_name: null,
          address_count: 0,
          confidence: null,
          match_method: null,
          feature_type: "orphan",
          feature_status: "orphan_building",
          is_linked: false,
          status: "not_visited",
          scans_total: 0,
          qr_scanned: false,
        },
      };
    }

    const firstAddress = linkedAddresses[0] ?? null;
    const scansTotal = linkedAddresses.reduce((sum, address) => sum + (address.scans ?? 0), 0);
    const visited = linkedAddresses.some((address) => address.visited === true);
    const bestConfidence = [...buildingLinks, ...linkedAddresses].reduce(
      (best, linkOrAddress) => Math.max(best, finiteNumber(linkOrAddress.confidence) ?? 0),
      0
    );
    const bestMatchType =
      buildingLinks.find((link) => normalizedString(link.match_type))?.match_type ??
      linkedAddresses.find((address) => normalizedString(address.match_source))?.match_source ??
      null;

    return {
      ...feature,
      properties: {
        ...(feature.properties ?? {}),
        address_count: linkedAddresses.length,
        address_ids: linkedAddresses.map((address) => address.id),
        address_id: linkedAddresses.length === 1 ? firstAddress?.id ?? null : null,
        address_text: linkedAddresses.length === 1 ? firstAddress?.formatted ?? null : null,
        house_number: linkedAddresses.length === 1 ? firstAddress?.house_number ?? null : null,
        street_name: linkedAddresses.length === 1 ? firstAddress?.street_name ?? null : null,
        confidence: bestConfidence || (feature.properties?.confidence ?? null),
        match_method: bestMatchType ?? feature.properties?.match_method ?? null,
        feature_type: linkedAddresses.length > 0 ? "matched_house" : feature.properties?.feature_type,
        feature_status: linkedAddresses.length > 0 ? "matched" : feature.properties?.feature_status,
        is_townhome: linkedAddresses.length > 1 ? true : feature.properties?.is_townhome,
        units_count: linkedAddresses.length > 1
          ? linkedAddresses.length
          : feature.properties?.units_count ?? 1,
        is_linked: linkedAddresses.length > 0,
        status: visited ? "visited" : "not_visited",
        scans_total: scansTotal,
        qr_scanned: scansTotal > 0,
      },
    };
  });
}

function materializedBuildingFeature(row: MaterializedCampaignBuildingRow): GeoJSONFeature | null {
  if (row.is_hidden === true) return null;
  const geometry = polygonGeometryFromValue(row.geom);
  if (!geometry) return null;

  const publicId = normalizedString(row.gers_id) ?? row.id;
  const height = finiteNumber(row.height_m) ?? finiteNumber(row.height) ?? 9;
  const unitsCount = Math.max(1, Math.round(finiteNumber(row.units_count) ?? 1));

  return normalizeBuildingIdentityFeature({
    type: "Feature",
    id: publicId,
    geometry,
    properties: {
      id: row.id,
      building_id: row.id,
      gers_id: publicId,
      public_building_id: publicId,
      canonical_building_id: publicId,
      building_identifier_source: normalizedString(row.gers_id) ? "gers" : "materialized",
      source: "silver",
      height,
      height_m: height,
      min_height: 0,
      units_count: unitsCount,
      address_count: 0,
      address_id: null,
      address_ids: [],
      address_text: null,
      house_number: normalizedString(row.addr_housenumber),
      street_name: normalizedString(row.addr_street),
      feature_type: "orphan",
      feature_status: "orphan_building",
      is_linked: false,
      status: normalizedString(row.latest_status) ?? "not_visited",
      scans_today: 0,
      scans_total: 0,
      qr_scanned: false,
      polished_geometry_version: POLISHED_BUILDING_GEOMETRY_VERSION,
    },
  });
}

async function fetchMaterializedCampaignBuildingFeatures(
  supabase: any,
  campaignId: string,
  hiddenBuildingIds: Set<string>
): Promise<GeoJSONFeature[]> {
  try {
    const rows = await fetchAllInPages<MaterializedCampaignBuildingRow>((from, to) =>
      supabase
        .from("buildings")
        .select("id, gers_id, geom, height_m, height, latest_status, is_hidden, units_count, addr_housenumber, addr_street")
        .eq("campaign_id", campaignId)
        .range(from, to)
    );

    const features = filterHiddenBuildings(
      rows
        .map(materializedBuildingFeature)
        .filter((feature): feature is GeoJSONFeature => feature !== null),
      hiddenBuildingIds
    );

    return filterLinkableBuildingFeatures(features, "materialized-buildings");
  } catch (error) {
    console.warn(
      "[buildings] Materialized building fallback failed:",
      error instanceof Error ? error.message : error
    );
    return [];
  }
}

function featureCollectionFromCache(raw: unknown): { type: "FeatureCollection"; features: GeoJSONFeature[] } | null {
  if (!raw || typeof raw !== "object") return null;
  const collection = raw as { type?: unknown; features?: unknown };
  if (collection.type !== "FeatureCollection" || !Array.isArray(collection.features)) return null;

  const features = (collection.features as unknown[])
    .filter((feature): feature is GeoJSONFeature => {
      if (!feature || typeof feature !== "object") return false;
      const candidate = feature as GeoJSONFeature;
      return candidate.type === "Feature" && Boolean(candidate.geometry);
    });

  return {
    type: "FeatureCollection",
    features,
  };
}

function isMissingPolishedCacheTable(error: unknown): boolean {
  const message = String((error as { message?: unknown })?.message ?? "").toLowerCase();
  return message.includes("campaign_polished_building_features") ||
    message.includes("schema cache") ||
    message.includes("does not exist");
}

async function readPolishedBuildingCache(
  supabase: any,
  campaignId: string
): Promise<{ type: "FeatureCollection"; features: GeoJSONFeature[] } | null> {
  const { data, error } = await supabase
    .from("campaign_polished_building_features")
    .select("feature_collection, feature_count, source, updated_at")
    .eq("campaign_id", campaignId)
    .maybeSingle();

  if (error) {
    if (!isMissingPolishedCacheTable(error)) {
      console.warn("[buildings] Polished cache read failed:", error.message);
    }
    return null;
  }

  const row = data as PolishedBuildingCacheRow | null;
  const cached = featureCollectionFromCache(row?.feature_collection);
  if (!cached || cached.features.length === 0) {
    if (row && (row.feature_count ?? 0) === 0) {
      console.warn(
        `[buildings] Polished cache for ${campaignId} is empty; deleting stale row and rebuilding`
      );
      const { error: deleteError } = await supabase
        .from("campaign_polished_building_features")
        .delete()
        .eq("campaign_id", campaignId);
      if (deleteError && !isMissingPolishedCacheTable(deleteError)) {
        console.warn("[buildings] Polished empty-cache delete failed:", deleteError.message);
      }
    }
    return null;
  }
  const cacheGeometryVersion = finiteNumber(
    cached.features[0]?.properties?.polished_geometry_version
  );
  if (cacheGeometryVersion !== POLISHED_BUILDING_GEOMETRY_VERSION) {
    console.log(
      `[buildings] Polished cache for ${campaignId} is geometry version ${cacheGeometryVersion ?? "none"}; rebuilding`
    );
    const { error: deleteError } = await supabase
      .from("campaign_polished_building_features")
      .delete()
      .eq("campaign_id", campaignId);
    if (deleteError && !isMissingPolishedCacheTable(deleteError)) {
      console.warn("[buildings] Polished cache delete failed:", deleteError.message);
    }
    return null;
  }

  const polygonFeatures = cached.features.filter(isPolygonFeature);
  const removedNonPolygons = cached.features.length - polygonFeatures.length;
  if (removedNonPolygons > 0) {
    console.warn(
      `[buildings] Polished cache for ${campaignId} contained ${removedNonPolygons} non-polygon feature(s); ignoring them`
    );
  }
  const renderableFeatures = filterLinkableBuildingFeatures(
    polygonFeatures.map(normalizeBuildingIdentityFeature),
    "polished-cache"
  );

  if (renderableFeatures.length === 0) {
    console.warn(
      `[buildings] Polished cache for ${campaignId} has no renderable building polygons; deleting cache row and rebuilding`
    );
    const { error: deleteError } = await supabase
      .from("campaign_polished_building_features")
      .delete()
      .eq("campaign_id", campaignId);
    if (deleteError && !isMissingPolishedCacheTable(deleteError)) {
      console.warn("[buildings] Polished cache delete failed:", deleteError.message);
    }
    return null;
  }

  console.log(
    `[buildings] Polished cache hit for ${campaignId}; returned ${renderableFeatures.length} features`
  );
  const enrichedFeatures = await enrichFeaturesWithPersistedLinks(
    supabase,
    campaignId,
    renderableFeatures
  );

  return {
    type: "FeatureCollection",
    features: enrichedFeatures,
  };
}

async function writePolishedBuildingCache(
  supabase: any,
  campaignId: string,
  source: "gold" | "silver" | "manual" | "mixed",
  features: GeoJSONFeature[]
): Promise<void> {
  if (features.length === 0) return;

  const normalizedFeatures = filterLinkableBuildingFeatures(
    features.map(normalizeBuildingIdentityFeature),
    "polished-write"
  );
  if (normalizedFeatures.length === 0) return;
  const featureCollection = {
    type: "FeatureCollection",
    features: normalizedFeatures.map((feature) => ({
      ...feature,
      properties: {
        ...(feature.properties ?? {}),
        polished_geometry_version: POLISHED_BUILDING_GEOMETRY_VERSION,
      },
    })),
  };

  const { error } = await supabase
    .from("campaign_polished_building_features")
    .upsert(
      {
        campaign_id: campaignId,
        source,
        feature_count: features.length,
        feature_collection: featureCollection,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "campaign_id" }
    );

  if (error) {
    if (!isMissingPolishedCacheTable(error)) {
      console.warn("[buildings] Polished cache write failed:", error.message);
    }
    return;
  }

  console.log(`[buildings] Stored polished ${source} cache for ${campaignId}; features=${features.length}`);
}

function snapshotDeclaresZeroBuildings(snapshot: CampaignSnapshotRow | null): boolean {
  if (!snapshot || snapshot.buildings_count !== 0) return false;

  const metrics = snapshot.tile_metrics;
  const pmtilesMetric =
    metrics && typeof metrics === "object"
      ? (metrics as Record<string, unknown>).pmtiles_key
      : null;
  const hasStaticBuildingPmtiles = [snapshot.buildings_key, snapshot.buildings_url, pmtilesMetric]
    .some((value) => typeof value === "string" && value.toLowerCase().endsWith(".pmtiles"));

  return !hasStaticBuildingPmtiles;
}

async function hasManualBuildings(supabase: any, campaignId: string): Promise<boolean> {
  const { data, error } = await supabase
    .from("buildings")
    .select("id")
    .eq("campaign_id", campaignId)
    .eq("source", "manual")
    .limit(1);

  if (error) {
    console.warn("[buildings] Manual building probe failed:", error.message);
    return true;
  }

  return Array.isArray(data) && data.length > 0;
}

function parseGoldBuildingRows(raw: unknown): GoldBuildingRow[] {
  if (!raw) return [];

  if (Array.isArray(raw)) {
    if (raw.length === 0) return [];
    const first = raw[0] as Record<string, unknown>;
    if ('geom_geojson' in first) {
      return raw as GoldBuildingRow[];
    }
    if (first?.type === 'Feature') {
      return raw
        .map((feature) => featureToGoldBuildingRow(feature as Record<string, unknown>))
        .filter((value): value is GoldBuildingRow => value !== null);
    }
    return raw as GoldBuildingRow[];
  }

  if (typeof raw === 'string') {
    try {
      return parseGoldBuildingRows(JSON.parse(raw));
    } catch {
      return [];
    }
  }

  if (typeof raw === 'object') {
    const obj = raw as Record<string, unknown>;
    if ('get_gold_buildings_in_polygon_geojson' in obj) {
      return parseGoldBuildingRows(obj.get_gold_buildings_in_polygon_geojson);
    }
    if (obj.type === 'FeatureCollection' && Array.isArray(obj.features)) {
      return obj.features
        .map((feature) => featureToGoldBuildingRow(feature as Record<string, unknown>))
        .filter((value): value is GoldBuildingRow => value !== null);
    }
    if (obj.type === 'Feature') {
      const one = featureToGoldBuildingRow(obj);
      return one ? [one] : [];
    }
  }

  return [];
}

function featureToGoldBuildingRow(feature: Record<string, unknown>): GoldBuildingRow | null {
  const geometry = feature.geometry as Record<string, unknown> | undefined;
  if (!geometry) return null;
  const properties = (feature.properties as Record<string, unknown> | undefined) ?? {};
  const id = properties.id ?? feature.id;
  if (!id) return null;

  return {
    id: String(id),
    area_sqm: typeof properties.area_sqm === 'number' ? properties.area_sqm : null,
    building_type: typeof properties.building_type === 'string' ? properties.building_type : null,
    geom_geojson: JSON.stringify(geometry),
    geom: geometry,
  };
}

function toGoldBuildingGeometry(building: GoldBuildingRow): GeoJSON.Polygon | GeoJSON.MultiPolygon | null {
  if (typeof building.geom_geojson === 'string' && building.geom_geojson.trim()) {
    try {
      return JSON.parse(building.geom_geojson) as GeoJSON.Polygon | GeoJSON.MultiPolygon;
    } catch {
      return null;
    }
  }

  if (typeof building.geom === 'string' && building.geom.trim()) {
    try {
      return JSON.parse(building.geom) as GeoJSON.Polygon | GeoJSON.MultiPolygon;
    } catch {
      return null;
    }
  }

  if (building.geom && typeof building.geom === 'object') {
    const candidate = building.geom as { type?: unknown; coordinates?: unknown };
    if (
      (candidate.type === 'Polygon' || candidate.type === 'MultiPolygon') &&
      Array.isArray(candidate.coordinates)
    ) {
      return candidate as GeoJSON.Polygon | GeoJSON.MultiPolygon;
    }
  }

  return null;
}

function buildGoldFallbackFeatureCollection(
  buildings: GoldBuildingRow[],
  campaignAddresses: CampaignAddressRow[]
) {
  const addressesByBuildingId = new Map<string, CampaignAddressRow[]>();

  for (const address of campaignAddresses) {
    if (!address.building_id) continue;
    const group = addressesByBuildingId.get(address.building_id) ?? [];
    group.push(address);
    addressesByBuildingId.set(address.building_id, group);
  }

  const features = buildings.flatMap((building) => {
    const geometry = toGoldBuildingGeometry(building);
    if (!geometry) return [];

    const linkedAddresses = addressesByBuildingId.get(building.id) ?? [];
    const firstAddress = linkedAddresses[0] ?? null;
    const scansTotal = linkedAddresses.reduce((sum, address) => sum + (address.scans ?? 0), 0);
    const visited = linkedAddresses.some((address) => address.visited === true);

    return [{
      type: 'Feature',
      id: building.id,
      geometry,
      properties: {
        id: building.id,
        building_id: building.id,
        gers_id: building.id,
        public_building_id: building.id,
        canonical_building_id: building.id,
        building_identifier_source: 'gold',
        source: 'gold',
        address_count: linkedAddresses.length,
        address_id: linkedAddresses.length === 1 ? firstAddress?.id ?? null : null,
        address_text: linkedAddresses.length === 1 ? firstAddress?.formatted ?? null : null,
        house_number: linkedAddresses.length === 1 ? firstAddress?.house_number ?? null : null,
        street_name: linkedAddresses.length === 1 ? firstAddress?.street_name ?? null : null,
        height: 10,
        height_m: 10,
        min_height: 0,
        area_sqm: building.area_sqm ?? null,
        building_type: building.building_type ?? null,
        feature_type: linkedAddresses.length > 0 ? 'matched_house' : 'orphan',
        feature_status: linkedAddresses.length > 0 ? 'matched' : 'orphan_building',
        is_linked: linkedAddresses.length > 0,
        status: visited ? 'visited' : 'not_visited',
        scans_today: 0,
        scans_total: scansTotal,
        qr_scanned: scansTotal > 0,
      },
    }];
  });

  return {
    type: 'FeatureCollection',
    features,
  };
}

async function fetchGoldFallbackFeatures(
  supabase: any,
  campaignId: string,
  territoryBoundary: GeoJSON.Polygon | null
) {
  const { data: addresses, error: addressError } = await supabase
    .from('campaign_addresses')
    .select('id, formatted, house_number, street_name, building_id, visited, scans')
    .eq('campaign_id', campaignId)
    .order('id', { ascending: true });

  if (addressError) {
    console.warn('[buildings] Gold fallback address query failed:', addressError.message);
    return null;
  }

  const campaignAddresses = (addresses ?? []) as CampaignAddressRow[];
  const linkedBuildingIds = Array.from(
    new Set(
      campaignAddresses
        .map((address) => address.building_id)
        .filter((value): value is string => typeof value === 'string' && value.length > 0)
    )
  );

  let goldBuildings: GoldBuildingRow[] = [];

  if (linkedBuildingIds.length > 0) {
    const { data: linkedBuildings, error: linkedBuildingsError } = await supabase
      .from('ref_buildings_gold')
      .select('id, area_sqm, building_type, geom')
      .in('id', linkedBuildingIds);

    if (!linkedBuildingsError && Array.isArray(linkedBuildings) && linkedBuildings.length > 0) {
      goldBuildings = linkedBuildings as GoldBuildingRow[];
    } else if (linkedBuildingsError) {
      console.warn('[buildings] Gold fallback linked-building query failed:', linkedBuildingsError.message);
    }
  }

  if (goldBuildings.length === 0 && territoryBoundary) {
    const { data: polygonBuildings, error: polygonBuildingsError } = await supabase.rpc(
      'get_gold_buildings_in_polygon_geojson',
      { p_polygon_geojson: JSON.stringify(territoryBoundary) }
    );

    if (polygonBuildingsError) {
      console.warn('[buildings] Gold fallback polygon query failed:', polygonBuildingsError.message);
      return null;
    }

    goldBuildings = parseGoldBuildingRows(polygonBuildings);
  }

  if (goldBuildings.length === 0) {
    return null;
  }

  const fallback = buildGoldFallbackFeatureCollection(goldBuildings, campaignAddresses);
  return fallback.features.length > 0 ? fallback : null;
}

/**
 * Fetch Silver building GeoJSON from S3 using bucket + key from campaign_snapshots.
 * Only used when the campaign has no Gold buildings, so Gold/Silver never mix.
 */
async function fetchSilverSnapshotFeatures(
  bucket: string,
  key: string,
  hiddenBuildingIds: Set<string>
): Promise<GeoJSONFeature[] | null> {
  const hasCredentials =
    process.env.AWS_ACCESS_KEY_ID && process.env.AWS_SECRET_ACCESS_KEY;
  if (!hasCredentials) {
    console.warn("[buildings] S3 credentials not set; skipping Silver snapshot fetch");
    return null;
  }

  const s3 = new S3Client({
    region: AWS_REGION,
    credentials: {
      accessKeyId: process.env.AWS_ACCESS_KEY_ID!,
      secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY!,
    },
  });

  try {
    const cmd = new GetObjectCommand({ Bucket: bucket, Key: key });
    const response = await s3.send(cmd);
    const chunks: Buffer[] = [];
    if (response.Body) {
      for await (const chunk of response.Body as AsyncIterable<Uint8Array>) {
        chunks.push(Buffer.from(chunk));
      }
    }
    const raw = Buffer.concat(chunks);
    const text = key.endsWith(".gz")
      ? zlib.gunzipSync(raw).toString("utf8")
      : raw.toString("utf8");
    const geojson = JSON.parse(text) as { features?: unknown[] };
    return filterLinkableBuildingFeatures(filterHiddenBuildings(
      ((geojson.features ?? []) as GeoJSONFeature[]).filter(isPolygonFeature),
      hiddenBuildingIds
    ).map((feature) => {
      const normalized = normalizeBuildingIdentityFeature(feature);
      return {
        ...normalized,
        properties: {
          ...(normalized.properties ?? {}),
          source: normalizedString(feature.properties?.source) ?? "silver",
        },
      };
    }), "silver-snapshot");
  } catch (err) {
    console.error(`[buildings] Silver snapshot fetch failed bucket=${bucket} key=${key}:`, err);
    return null;
  }
}

async function responseForSelectedSource(
  supabase: any,
  campaignId: string,
  sourceName: "Gold" | "Silver",
  baseFeatures: GeoJSONFeature[],
  manualPolygonFeatures: GeoJSONFeature[]
): Promise<Response> {
  const linkableBaseFeatures = enforceUniqueFeatureAddressAssignments(filterLinkableBuildingFeatures(
    baseFeatures.map(normalizeBuildingIdentityFeature),
    `${sourceName.toLowerCase()}-base`
  ));
  const linkableManualFeatures = filterLinkableBuildingFeatures(
    manualPolygonFeatures.map(normalizeBuildingIdentityFeature),
    "manual-polygons"
  );
  const mergedFeatures = dedupeFeatures([
    ...linkableBaseFeatures,
    ...linkableManualFeatures,
  ]);
  const linkedFeatures = await enrichFeaturesWithPersistedLinks(supabase, campaignId, mergedFeatures);
  await writePolishedBuildingCache(
    supabase,
    campaignId,
    sourceName === "Gold" ? "gold" : "silver",
    linkedFeatures
  );
  console.log(
    `[buildings] ${sourceName} selected for ${campaignId}; returned ${linkedFeatures.length} polygon features`
  );
  return NextResponse.json(
    { type: "FeatureCollection", features: linkedFeatures },
    { headers: JSON_NO_STORE_HEADERS }
  );
}

/**
 * GET /api/campaigns/[campaignId]/buildings
 *
 * Priority:
 *   1. Gold polygons from rpc_get_campaign_full_features / ref_buildings_gold.
 *   2. Silver polygons from rpc_get_campaign_full_features / campaign_snapshots, only when Gold is absent.
 *   3. Manual user-created polygons can accompany the selected source.
 *   4. Empty FeatureCollection — campaign has neither Gold nor Silver buildings yet.
 */
export async function GET(request: Request, context: RouteContext): Promise<Response> {
  try {
    const token = getAuthUser(request);
    if (!token) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const { campaignId } = await context.params;
    const supabaseAnon = createAuthSupabase();
    const { data: { user } } = await supabaseAnon.auth.getUser(token);
    const requestUser = user
      ? { id: user.id, email: user.email ?? null }
      : decodeBearerUser(token);
    if (!requestUser) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const supabase = createUserScopedSupabase(token);
    const canAccess = await ensureCampaignAccess(supabase, campaignId, requestUser.id);
    if (!canAccess) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 });
    }
    const dataSupabase = createAdminSupabase() ?? supabase;

    const { data: campaignMeta } = await dataSupabase
      .from('campaigns')
      .select('territory_boundary, provision_source')
      .eq('id', campaignId)
      .maybeSingle();

    const campaignRow = (campaignMeta ?? null) as CampaignRow | null;
    const requestUrl = new URL(request.url);
    const bypassPolishedCache =
      requestUrl.searchParams.get("refresh") === "1" ||
      requestUrl.searchParams.get("cache") === "bypass";

    if (!bypassPolishedCache) {
      try {
        const cached = await readPolishedBuildingCache(dataSupabase, campaignId);
        if (cached) {
          return NextResponse.json(cached, { headers: JSON_NO_STORE_HEADERS });
        }
      } catch (cacheError) {
        console.warn(
          `[buildings] Polished cache read/serialize failed for ${campaignId}; rebuilding on demand:`,
          cacheError instanceof Error ? cacheError.message : cacheError
        );
      }
    }

    const { data: hiddenBuildings } = await dataSupabase
      .from("campaign_hidden_buildings")
      .select("public_building_id")
      .eq("campaign_id", campaignId);

    const hiddenBuildingIds = new Set(
      ((hiddenBuildings ?? []) as HiddenBuildingRow[])
        .map((row) => normalizedString(row.public_building_id)?.toLowerCase() ?? "")
        .filter((value) => value.length > 0)
    );

    const materializedFeatures = await fetchMaterializedCampaignBuildingFeatures(
      dataSupabase,
      campaignId,
      hiddenBuildingIds
    );
    if (materializedFeatures.length > 0) {
      console.log(
        `[buildings] Materialized table selected for ${campaignId}; returned ${materializedFeatures.length} features`
      );
      return await responseForSelectedSource(
        dataSupabase,
        campaignId,
        "Silver",
        materializedFeatures,
        []
      );
    }

    const { data: snapshot } = await dataSupabase
      .from("campaign_snapshots")
      .select("bucket, prefix, buildings_key, addresses_key, buildings_url, metadata_key, buildings_count, created_at, tile_metrics")
      .eq("campaign_id", campaignId)
      .maybeSingle();

    const snap = snapshot as CampaignSnapshotRow | null;
    const manualBuildingsExist = await hasManualBuildings(dataSupabase, campaignId);
    if (snapshotDeclaresZeroBuildings(snap) && !manualBuildingsExist) {
      console.log(`[buildings] Snapshot declares zero buildings for ${campaignId}; returning empty collection`);
      return NextResponse.json(EMPTY_FEATURE_COLLECTION, {
        headers: JSON_NO_STORE_HEADERS,
      });
    }

    const territoryBbox = bboxFromPolygon(campaignRow?.territory_boundary ?? null);
    let scopedPmtilesBuildingsAttempted = false;
    let scopedPmtilesBuildings: GeoJSONFeature[] | null = null;
    const loadScopedPmtilesBuildings = async (stage: string): Promise<GeoJSONFeature[] | null> => {
      if (scopedPmtilesBuildingsAttempted) return scopedPmtilesBuildings;
      scopedPmtilesBuildingsAttempted = true;
      if (!snap || !territoryBbox || !resolvePmtilesKey(snap)) return null;

      try {
        const scopedPmtilesFeatureCollection = await fetchScopedPmtilesBuildingFeatures(
          snap,
          territoryBbox,
          hiddenBuildingIds,
          campaignRow?.territory_boundary ?? null
        );
        scopedPmtilesBuildings = (scopedPmtilesFeatureCollection?.features ?? []) as GeoJSONFeature[];
        console.log(`[buildings] Scoped PMTiles ${stage} features=${scopedPmtilesBuildings.length}`);
        return scopedPmtilesBuildings;
      } catch (pmtilesError) {
        console.warn(
          `[buildings] Scoped PMTiles ${stage} failed:`,
          pmtilesError instanceof Error ? pmtilesError.message : pmtilesError
        );
        return null;
      }
    };

    // -------------------------------------------------------------------------
    // Step 1: unified RPC, with Gold and Silver kept in separate buckets.
    // -------------------------------------------------------------------------
    const { data: rpcResult, error: rpcError } = await dataSupabase
      .rpc("rpc_get_campaign_full_features", { p_campaign_id: campaignId })
      .single();

    let rpcGoldPolygonFeatures: GeoJSONFeature[] = [];
    let rpcSilverPolygonFeatures: GeoJSONFeature[] = [];
    let rpcManualPolygonFeatures: GeoJSONFeature[] = [];

    if (!rpcError && rpcResult) {
      const fc = rpcResult as { type?: string; features?: unknown[] };
      const features = (fc?.features ?? []) as GeoJSONFeature[];
      const polygonFeatures = features.filter(isPolygonFeature);

      rpcGoldPolygonFeatures = filterHiddenBuildings(
        polygonFeatures.filter(isGoldFeature),
        hiddenBuildingIds
      );
      rpcSilverPolygonFeatures = filterHiddenBuildings(
        polygonFeatures.filter(isSilverFeature),
        hiddenBuildingIds
      );
      rpcManualPolygonFeatures = filterHiddenBuildings(
        polygonFeatures.filter(isManualFeature),
        hiddenBuildingIds
      );
      if (rpcGoldPolygonFeatures.length > 0) {
        return await responseForSelectedSource(
          dataSupabase,
          campaignId,
          "Gold",
          rpcGoldPolygonFeatures,
          rpcManualPolygonFeatures
        );
      }
    } else if (rpcError) {
      console.warn("[buildings] RPC error:", rpcError);
    }

    const goldFallback = campaignRow?.provision_source === "gold"
      ? await fetchGoldFallbackFeatures(
          dataSupabase,
          campaignId,
          campaignRow?.territory_boundary ?? null
        )
      : null;

    if (goldFallback) {
      return await responseForSelectedSource(
        dataSupabase,
        campaignId,
        "Gold",
        filterHiddenBuildings(goldFallback.features as GeoJSONFeature[], hiddenBuildingIds),
        rpcManualPolygonFeatures
        );
    }

    if (rpcSilverPolygonFeatures.length > 0) {
      return await responseForSelectedSource(
        dataSupabase,
        campaignId,
        "Silver",
        rpcSilverPolygonFeatures,
        rpcManualPolygonFeatures
        );
    }

    const scopedFeatures = await loadScopedPmtilesBuildings("fallback");
    if (scopedFeatures && scopedFeatures.length > 0) {
      return await responseForSelectedSource(
        dataSupabase,
        campaignId,
        "Silver",
        scopedFeatures,
        rpcManualPolygonFeatures
        );
    }

    if (snap?.buildings_key && !snap.buildings_key.toLowerCase().endsWith(".pmtiles")) {
      const silverSnapshotFeatures = await fetchSilverSnapshotFeatures(
        snap.bucket,
        snap.buildings_key,
        hiddenBuildingIds
      );
      if (silverSnapshotFeatures && silverSnapshotFeatures.length > 0) {
        return await responseForSelectedSource(
          dataSupabase,
          campaignId,
          "Silver",
          silverSnapshotFeatures,
          rpcManualPolygonFeatures
        );
      }
    }

    if (rpcManualPolygonFeatures.length > 0) {
      const linkableManualFeatures = filterLinkableBuildingFeatures(
        rpcManualPolygonFeatures.map(normalizeBuildingIdentityFeature),
        "manual-only-polygons"
      );
      const mergedFeatures = dedupeFeatures(linkableManualFeatures);
      await writePolishedBuildingCache(dataSupabase, campaignId, "manual", mergedFeatures);
      console.log(
        `[buildings] Returning ${mergedFeatures.length} manual polygon features for ${campaignId}`
      );
      return NextResponse.json(
        { type: "FeatureCollection", features: mergedFeatures },
        { headers: JSON_NO_STORE_HEADERS }
      );
    }

    // -------------------------------------------------------------------------
    // Step 3: Nothing available
    // -------------------------------------------------------------------------
    console.log(`[buildings] No buildings available for campaign ${campaignId}`);
    return NextResponse.json(EMPTY_FEATURE_COLLECTION, {
      headers: JSON_NO_STORE_HEADERS,
    });

  } catch (err) {
    console.error("[buildings] GET error:", err);
    return NextResponse.json(EMPTY_FEATURE_COLLECTION, {
      headers: JSON_NO_STORE_HEADERS,
    });
  }
}
