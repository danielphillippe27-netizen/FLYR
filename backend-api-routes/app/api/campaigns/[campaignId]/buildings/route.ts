import { createClient } from "@supabase/supabase-js";
import { GetObjectCommand, S3Client } from "@aws-sdk/client-s3";
import zlib from "zlib";
import { NextResponse } from "next/server";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

const AWS_REGION = process.env.AWS_REGION ?? "us-east-1";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type RouteContext = { params: Promise<{ campaignId: string }> };

function getAuthUser(request: Request): string | null {
  const authHeader = request.headers.get("authorization");
  return authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
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
const MANUAL_HOME_PROXY_HALF_SIDE_METERS = 2.3 * 3.0;

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

type CampaignAddressRow = {
  id: string;
  formatted: string | null;
  house_number: string | null;
  street_name: string | null;
  building_id: string | null;
  visited: boolean | null;
  scans: number | null;
};

type BuildingAddressLinkRow = {
  building_id: string;
  address_id: string;
  match_type?: string | null;
  confidence?: number | null;
};

function normalizedString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function finiteNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function isPolygonFeature(feature: GeoJSONFeature): boolean {
  const geometryType = normalizedString(feature.geometry?.type);
  return geometryType === "Polygon" || geometryType === "MultiPolygon";
}

function isManualFeature(feature: GeoJSONFeature): boolean {
  const source = normalizedString(feature.properties?.source)?.toLowerCase();
  return source === "manual";
}

function isManualAddressPointFeature(feature: GeoJSONFeature): boolean {
  const geometryType = normalizedString(feature.geometry?.type);
  return geometryType === "Point" && isManualFeature(feature);
}

function squarePolygonCoordinates(
  longitude: number,
  latitude: number,
  halfSideMeters: number
): number[][] {
  const latDelta = halfSideMeters / 111_320.0;
  const metersPerLonDegree = Math.max(
    Math.cos((latitude * Math.PI) / 180.0) * 111_320.0,
    0.0001
  );
  const lonDelta = halfSideMeters / metersPerLonDegree;

  return [
    [longitude - lonDelta, latitude - latDelta],
    [longitude + lonDelta, latitude - latDelta],
    [longitude + lonDelta, latitude + latDelta],
    [longitude - lonDelta, latitude + latDelta],
    [longitude - lonDelta, latitude - latDelta],
  ];
}

function buildManualAddressProxyFeature(feature: GeoJSONFeature): GeoJSONFeature | null {
  if (!isManualAddressPointFeature(feature)) return null;

  const coordinates = Array.isArray(feature.geometry?.coordinates)
    ? feature.geometry?.coordinates
    : null;
  const longitude = coordinates && coordinates.length > 0 ? finiteNumber(coordinates[0]) : null;
  const latitude = coordinates && coordinates.length > 1 ? finiteNumber(coordinates[1]) : null;

  if (longitude == null || latitude == null) return null;

  const props = feature.properties ?? {};
  const addressId =
    normalizedString(props.address_id) ??
    normalizedString(props.id) ??
    normalizedString(feature.id);

  if (!addressId) return null;

  const houseNumber = normalizedString(props.house_number);
  const streetName = normalizedString(props.street_name);
  const fallbackAddressText = [houseNumber, streetName].filter(Boolean).join(" ").trim();
  const addressText =
    normalizedString(props.address_text) ??
    normalizedString(props.formatted) ??
    (fallbackAddressText.length > 0 ? fallbackAddressText : "Address");

  const height =
    finiteNumber(props.height_m) ??
    finiteNumber(props.height) ??
    9;

  return {
    type: "Feature",
    id: addressId,
    geometry: {
      type: "Polygon",
      coordinates: [squarePolygonCoordinates(longitude, latitude, MANUAL_HOME_PROXY_HALF_SIDE_METERS)],
    },
    properties: {
      ...props,
      id: addressId,
      gers_id: normalizedString(props.gers_id) ?? addressId,
      building_id: normalizedString(props.building_id) ?? addressId,
      address_id: addressId,
      address_text: addressText,
      house_number: houseNumber,
      street_name: streetName,
      source: "manual",
      feature_type: normalizedString(props.feature_type) ?? "address_proxy",
      feature_status: normalizedString(props.feature_status) ?? "manual",
      height,
      height_m: height,
      min_height: finiteNumber(props.min_height) ?? 0,
      is_townhome: false,
      units_count: Math.max(1, Math.round(finiteNumber(props.units_count) ?? 1)),
      address_count: Math.max(1, Math.round(finiteNumber(props.address_count) ?? 1)),
      status: normalizedString(props.status) ?? "not_visited",
      scans_today: Math.max(0, Math.round(finiteNumber(props.scans_today) ?? 0)),
      scans_total: Math.max(0, Math.round(finiteNumber(props.scans_total) ?? 0)),
      qr_scanned: Boolean(props.qr_scanned),
    },
  };
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
    normalizedString(feature.properties?.gers_id),
    normalizedString(feature.properties?.building_id),
    normalizedString(feature.properties?.id),
    normalizedString(feature.id),
  ]
    .filter((value): value is string => Boolean(value))
    .map((value) => value.toLowerCase());

  return Array.from(new Set(identifiers));
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

function linkRank(link: BuildingAddressLinkRow): number {
  const matchType = normalizedString(link.match_type)?.toLowerCase() ?? "";
  const methodScore =
    matchType === "manual" ? 5 :
    matchType === "containment_verified" ? 4 :
    matchType === "point_on_surface" ? 3 :
    matchType === "parcel_verified" ? 2 :
    matchType === "proximity_fallback" ? 0 :
    1;
  return methodScore * 10 + (typeof link.confidence === "number" ? link.confidence : 0);
}

function dedupeLinksByAddress(links: BuildingAddressLinkRow[]): BuildingAddressLinkRow[] {
  const bestByAddress = new Map<string, BuildingAddressLinkRow>();

  for (const link of links) {
    const addressId = normalizedString(link.address_id)?.toLowerCase();
    const buildingId = normalizedString(link.building_id);
    if (!addressId || !buildingId) continue;

    const existing = bestByAddress.get(addressId);
    if (!existing || linkRank(link) > linkRank(existing)) {
      bestByAddress.set(addressId, link);
    }
  }

  return Array.from(bestByAddress.values());
}

function featureAddressAssignmentRank(feature: GeoJSONFeature): number {
  const props = feature.properties ?? {};
  const source = normalizedString(props.source)?.toLowerCase() ?? "";
  const matchMethod = normalizedString(props.match_method)?.toLowerCase() ?? "";
  const featureStatus = normalizedString(props.feature_status)?.toLowerCase() ?? "";
  const confidence = finiteNumber(props.confidence) ?? 0;

  const sourceScore = source === "manual" ? 6 : source === "gold" ? 5 : source === "silver" ? 3 : 1;
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
      address_text: null,
      house_number: null,
      street_name: null,
      address_count: 0,
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
 * Fetch building GeoJSON from S3 using bucket + key from campaign_snapshots.
 * Returns null if the object cannot be fetched (caller falls back to empty).
 */
async function fetchFromS3(bucket: string, key: string): Promise<unknown | null> {
  const hasCredentials =
    process.env.AWS_ACCESS_KEY_ID && process.env.AWS_SECRET_ACCESS_KEY;
  if (!hasCredentials) {
    console.warn("[buildings] S3 credentials not set; skipping S3 fetch");
    return null;
  }

  const s3 = new S3Client({
    region: AWS_REGION,
    credentials: {
      accessKeyId:     process.env.AWS_ACCESS_KEY_ID!,
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

    let text: string;
    if (key.endsWith(".gz")) {
      text = zlib.gunzipSync(raw).toString("utf8");
    } else {
      text = raw.toString("utf8");
    }

    return JSON.parse(text);
  } catch (err) {
    console.error(`[buildings] S3 fetch failed bucket=${bucket} key=${key}:`, err);
    return null;
  }
}

/**
 * GET /api/campaigns/[campaignId]/buildings
 *
 * Priority:
 *   1. rpc_get_campaign_full_features — Gold path or Silver path via DB.
 *      Returns Polygon/MultiPolygon features; iOS MapFeaturesService uses these for 3D extrusion.
 *   2. S3 fallback — reads campaign_snapshots (bucket + buildings_key), fetches + gunzips from S3.
 *      Used for Silver/Lambda campaigns where building polygons live in S3, not the buildings table.
 *   3. Gold DB fallback — reads ref_buildings_gold when the campaign is map-ready but linking is still pending.
 *   4. Empty FeatureCollection — campaign has no buildings yet (e.g. not provisioned).
 */
export async function GET(request: Request, context: RouteContext): Promise<Response> {
  try {
    const token = getAuthUser(request);
    if (!token) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const { campaignId } = await context.params;
    const supabaseAnon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    const { data: { user }, error: userError } = await supabaseAnon.auth.getUser(token);
    if (userError || !user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const canAccess = await ensureCampaignAccess(supabase, campaignId, user.id);
    if (!canAccess) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 });
    }

    const { data: campaignMeta } = await supabase
      .from('campaigns')
      .select('territory_boundary, provision_source')
      .eq('id', campaignId)
      .maybeSingle();

    const campaignRow = (campaignMeta ?? null) as CampaignRow | null;

    const { data: hiddenBuildings } = await supabase
      .from("campaign_hidden_buildings")
      .select("public_building_id")
      .eq("campaign_id", campaignId);

    const hiddenBuildingIds = new Set(
      ((hiddenBuildings ?? []) as HiddenBuildingRow[])
        .map((row) => row.public_building_id.trim().toLowerCase())
        .filter((value) => value.length > 0)
    );

    // -------------------------------------------------------------------------
    // Step 1: unified RPC (Gold → Silver → address_point)
    // -------------------------------------------------------------------------
    const { data: rpcResult, error: rpcError } = await supabase
      .rpc("rpc_get_campaign_full_features", { p_campaign_id: campaignId })
      .single();

    let rpcBasePolygonFeatures: GeoJSONFeature[] = [];
    let rpcManualPolygonFeatures: GeoJSONFeature[] = [];
    let rpcManualAddressProxyFeatures: GeoJSONFeature[] = [];

    if (!rpcError && rpcResult) {
      const fc = rpcResult as { type?: string; features?: unknown[] };
      const features = (fc?.features ?? []) as GeoJSONFeature[];
      const polygonFeatures = features.filter(isPolygonFeature);

      rpcBasePolygonFeatures = filterHiddenBuildings(
        polygonFeatures.filter((feature) => !isManualFeature(feature)),
        hiddenBuildingIds
      );
      rpcBasePolygonFeatures = enforceUniqueFeatureAddressAssignments(rpcBasePolygonFeatures);
      rpcManualPolygonFeatures = filterHiddenBuildings(
        polygonFeatures.filter(isManualFeature),
        hiddenBuildingIds
      );
      rpcManualAddressProxyFeatures = features
        .map(buildManualAddressProxyFeature)
        .filter((feature): feature is GeoJSONFeature => feature !== null);

      if (rpcBasePolygonFeatures.length > 0) {
        const mergedFeatures = dedupeFeatures([
          ...rpcBasePolygonFeatures,
          ...rpcManualPolygonFeatures,
          ...rpcManualAddressProxyFeatures,
        ]);
        console.log(
          `[buildings] RPC returned ${mergedFeatures.length} merged polygon/proxy features for ${campaignId}`
        );
        return NextResponse.json(
          { type: "FeatureCollection", features: mergedFeatures },
          { headers: JSON_NO_STORE_HEADERS }
        );
      }
    } else if (rpcError) {
      console.warn("[buildings] RPC error:", rpcError);
    }

    // -------------------------------------------------------------------------
    // Step 2: S3 snapshot fallback
    // -------------------------------------------------------------------------
    const { data: snapshot } = await supabase
      .from("campaign_snapshots")
      .select("bucket, buildings_key")
      .eq("campaign_id", campaignId)
      .maybeSingle();

    const snap = snapshot as { bucket: string; buildings_key: string | null } | null;

    if (snap?.buildings_key) {
      console.log(
        `[buildings] S3 fallback: bucket=${snap.bucket} key=${snap.buildings_key}`
      );
      const geojson = await fetchFromS3(snap.bucket, snap.buildings_key) as {
        type: string;
        features: Array<{ id?: unknown; properties?: Record<string, unknown>; geometry?: unknown }>;
      } | null;

      if (geojson) {
        // Enrich S3 buildings with address_id + address_count from building_address_links.
        // This mirrors what the Gold RPC does automatically via the building_id FK, and
        // allows the iOS tap resolver (resolveAddressForBuilding) to match buildings to addresses.
        const { data: links } = await supabase
          .from("building_address_links")
          .select("building_id, address_id, match_type, confidence")
          .eq("campaign_id", campaignId);

        if (links && links.length > 0) {
          const uniqueAddressLinks = dedupeLinksByAddress(links as BuildingAddressLinkRow[]);
          const buildingRowIds = Array.from(
            new Set(uniqueAddressLinks.map((link) => link.building_id))
          );
          const { data: buildings } = await supabase
            .from("buildings")
            .select("id, gers_id")
            .in("id", buildingRowIds);

          const publicIdByRowId = new Map<string, string>();
          for (const building of (buildings ?? []) as Array<{ id: string; gers_id: string | null }>) {
            publicIdByRowId.set(building.id.toLowerCase(), (building.gers_id ?? building.id).toLowerCase());
          }

          // Map: public building id (prefer gers_id, fallback buildings.id) → [address_id UUIDs]
          const linkMap = new Map<string, string[]>();
          for (const link of uniqueAddressLinks) {
            const publicBuildingId =
              publicIdByRowId.get(link.building_id.toLowerCase()) ?? link.building_id.toLowerCase();
            const bucket = linkMap.get(publicBuildingId) ?? [];
            bucket.push(link.address_id);
            linkMap.set(publicBuildingId, bucket);
          }

          const enriched = filterHiddenBuildings(geojson.features as GeoJSONFeature[], hiddenBuildingIds).map((f) => {
            const props = f.properties ?? {};
            // Match the same ID resolution used by StableLinkerService when it wrote the links
            const gersId =
              (props.gers_id as string | null) ??
              (props.id as string | null) ??
              (f.id != null ? String(f.id) : null);

            const linked = gersId ? (linkMap.get(gersId.toLowerCase()) ?? []) : [];
            return {
              ...f,
              properties: {
                ...props,
                // Follow the same Gold RPC convention: address_id only when exactly one linked address
                address_id:    linked.length === 1 ? linked[0] : null,
                address_count: linked.length,
                source:        props.source ?? "silver",
              },
            };
          });

          console.log(
            `[buildings] S3 enriched ${enriched.length} features with building_address_links (${uniqueAddressLinks.length}/${links.length} unique address links)`
          );
          const mergedFeatures = dedupeFeatures([
            ...enriched,
            ...rpcManualPolygonFeatures,
            ...rpcManualAddressProxyFeatures,
          ]);

          return NextResponse.json(
            { type: "FeatureCollection", features: mergedFeatures },
            { headers: JSON_NO_STORE_HEADERS }
          );
        }

        // No links yet — return raw S3 data as-is (e.g. campaign just created, links still writing)
        const polygonFeatures = filterHiddenBuildings(
          (geojson.features ?? []).filter((feature) => isPolygonFeature(feature as GeoJSONFeature)) as GeoJSONFeature[],
          hiddenBuildingIds
        );
        const mergedFeatures = dedupeFeatures([
          ...(polygonFeatures as GeoJSONFeature[]),
          ...rpcManualPolygonFeatures,
          ...rpcManualAddressProxyFeatures,
        ]);

        return NextResponse.json({
          type: "FeatureCollection",
          features: mergedFeatures,
        }, {
          headers: JSON_NO_STORE_HEADERS,
        });
      }
    }

    if (campaignRow?.provision_source === 'gold') {
      const goldFallback = await fetchGoldFallbackFeatures(
        supabase,
        campaignId,
        campaignRow.territory_boundary
      );

      if (goldFallback) {
        const mergedFeatures = dedupeFeatures([
          ...filterHiddenBuildings(goldFallback.features as GeoJSONFeature[], hiddenBuildingIds),
          ...rpcManualPolygonFeatures,
          ...rpcManualAddressProxyFeatures,
        ]);

        if (mergedFeatures.length > 0) {
          console.log(`[buildings] Gold fallback returned ${mergedFeatures.length} polygon/proxy features`);
          return NextResponse.json(
            { type: 'FeatureCollection', features: mergedFeatures },
            { headers: JSON_NO_STORE_HEADERS }
          );
        }
      }
    }

    if (rpcManualPolygonFeatures.length > 0 || rpcManualAddressProxyFeatures.length > 0) {
      const mergedFeatures = dedupeFeatures([
        ...rpcManualPolygonFeatures,
        ...rpcManualAddressProxyFeatures,
      ]);
      console.log(
        `[buildings] Returning ${mergedFeatures.length} manual polygon/proxy features for ${campaignId}`
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
