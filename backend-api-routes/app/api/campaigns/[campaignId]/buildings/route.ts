import { createClient } from "@supabase/supabase-js";
import { GetObjectCommand, S3Client } from "@aws-sdk/client-s3";
import zlib from "zlib";
import { NextResponse } from "next/server";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

const AWS_REGION = process.env.AWS_REGION ?? "us-east-1";

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
 *      Used for Silver campaigns where building polygons live in S3, not the buildings table.
 *   3. Empty FeatureCollection — campaign has no buildings yet (e.g. not provisioned).
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

      rpcBasePolygonFeatures = polygonFeatures.filter((feature) => !isManualFeature(feature));
      rpcManualPolygonFeatures = polygonFeatures.filter(isManualFeature);
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
          { headers: { "Content-Type": "application/json" } }
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
          .select("building_id, address_id")
          .eq("campaign_id", campaignId);

        if (links && links.length > 0) {
          const buildingRowIds = Array.from(
            new Set((links as Array<{ building_id: string; address_id: string }>).map((link) => link.building_id))
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
          for (const link of links as Array<{ building_id: string; address_id: string }>) {
            const publicBuildingId =
              publicIdByRowId.get(link.building_id.toLowerCase()) ?? link.building_id.toLowerCase();
            const bucket = linkMap.get(publicBuildingId) ?? [];
            bucket.push(link.address_id);
            linkMap.set(publicBuildingId, bucket);
          }

          const enriched = geojson.features.map((f) => {
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
            `[buildings] S3 enriched ${enriched.length} features with building_address_links (${links.length} links)`
          );
          const mergedFeatures = dedupeFeatures([
            ...enriched,
            ...rpcManualPolygonFeatures,
            ...rpcManualAddressProxyFeatures,
          ]);

          return NextResponse.json(
            { type: "FeatureCollection", features: mergedFeatures },
            { headers: { "Content-Type": "application/json" } }
          );
        }

        // No links yet — return raw S3 data as-is (e.g. campaign just created, links still writing)
        const polygonFeatures = (geojson.features ?? []).filter((feature) =>
          isPolygonFeature(feature as GeoJSONFeature)
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
          headers: { "Content-Type": "application/json" },
        });
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
        { headers: { "Content-Type": "application/json" } }
      );
    }

    // -------------------------------------------------------------------------
    // Step 3: Nothing available
    // -------------------------------------------------------------------------
    console.log(`[buildings] No buildings available for campaign ${campaignId}`);
    return NextResponse.json(EMPTY_FEATURE_COLLECTION, {
      headers: { "Content-Type": "application/json" },
    });

  } catch (err) {
    console.error("[buildings] GET error:", err);
    return NextResponse.json(EMPTY_FEATURE_COLLECTION, {
      headers: { "Content-Type": "application/json" },
    });
  }
}
