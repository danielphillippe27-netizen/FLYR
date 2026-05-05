import { GetObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import zlib from "zlib";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;
const AWS_REGION = process.env.AWS_REGION ?? "us-east-1";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type RouteContext = { params: Promise<{ campaignId: string }> };

type GeoJSONFeature = {
  id?: unknown;
  type?: string;
  geometry?: {
    type?: string;
    coordinates?: unknown;
  };
  properties?: Record<string, unknown>;
};

const EMPTY_FEATURE_COLLECTION = { type: "FeatureCollection", features: [] };
const JSON_NO_STORE_HEADERS = {
  "Content-Type": "application/json",
  "Cache-Control": "no-store, max-age=0",
};

function getAuthUser(request: Request): string | null {
  const authHeader = request.headers.get("authorization");
  return authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
}

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

function normalizedString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function featureCollectionFromRPC(raw: unknown): { type: "FeatureCollection"; features: GeoJSONFeature[] } {
  if (!raw) return { type: "FeatureCollection", features: [] };
  if (typeof raw === "string") {
    try {
      return featureCollectionFromRPC(JSON.parse(raw));
    } catch {
      return { type: "FeatureCollection", features: [] };
    }
  }
  if (typeof raw === "object") {
    const obj = raw as { type?: unknown; features?: unknown };
    if (obj.type === "FeatureCollection" && Array.isArray(obj.features)) {
      return { type: "FeatureCollection", features: obj.features as GeoJSONFeature[] };
    }
  }
  return { type: "FeatureCollection", features: [] };
}

function isPointFeature(feature: GeoJSONFeature): boolean {
  return normalizedString(feature.geometry?.type) === "Point" && Array.isArray(feature.geometry?.coordinates);
}

function snapshotAddressFeature(feature: GeoJSONFeature): GeoJSONFeature | null {
  if (!isPointFeature(feature)) return null;
  const props = feature.properties ?? {};
  const id =
    normalizedString(props.id) ??
    normalizedString(props.address_id) ??
    normalizedString(props.gers_id) ??
    normalizedString(feature.id);
  if (!id) return null;

  const houseNumber = normalizedString(props.house_number);
  const streetName = normalizedString(props.street_name);
  const fallbackFormatted = [houseNumber, streetName].filter(Boolean).join(" ").trim();
  const formatted =
    normalizedString(props.formatted) ??
    normalizedString(props.label) ??
    (fallbackFormatted.length > 0 ? fallbackFormatted : "Address");

  return {
    type: "Feature",
    id,
    geometry: feature.geometry,
    properties: {
      ...props,
      id,
      gers_id: normalizedString(props.gers_id) ?? id,
      building_gers_id:
        normalizedString(props.building_gers_id) ??
        normalizedString(props.building_id) ??
        normalizedString(props.gers_id) ??
        null,
      house_number: houseNumber,
      street_name: streetName,
      postal_code: normalizedString(props.postal_code),
      locality: normalizedString(props.locality) ?? normalizedString(props.city),
      formatted,
      source: "silver",
    },
  };
}

async function fetchSilverSnapshotAddresses(bucket: string, key: string): Promise<GeoJSONFeature[] | null> {
  const hasCredentials =
    process.env.AWS_ACCESS_KEY_ID && process.env.AWS_SECRET_ACCESS_KEY;
  if (!hasCredentials) {
    console.warn("[addresses] S3 credentials not set; skipping Silver snapshot fetch");
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
    const response = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
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
    return ((geojson.features ?? []) as GeoJSONFeature[])
      .map(snapshotAddressFeature)
      .filter((feature): feature is GeoJSONFeature => feature !== null);
  } catch (err) {
    console.error(`[addresses] Silver snapshot fetch failed bucket=${bucket} key=${key}:`, err);
    return null;
  }
}

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
      .from("campaigns")
      .select("provision_source")
      .eq("id", campaignId)
      .maybeSingle();
    const provisionSource = normalizedString((campaignMeta as { provision_source?: unknown } | null)?.provision_source);

    const { data: rpcResult, error: rpcError } = await supabase.rpc(
      "rpc_get_campaign_addresses",
      { p_campaign_id: campaignId }
    );

    if (!rpcError) {
      const dbAddresses = featureCollectionFromRPC(rpcResult);
      if (dbAddresses.features.length > 0) {
        console.log(`[addresses] DB selected for ${campaignId}; returned ${dbAddresses.features.length} addresses`);
        return NextResponse.json(dbAddresses, { headers: JSON_NO_STORE_HEADERS });
      }
    } else {
      console.warn("[addresses] RPC error:", rpcError);
    }

    if (provisionSource === "gold") {
      return NextResponse.json(EMPTY_FEATURE_COLLECTION, { headers: JSON_NO_STORE_HEADERS });
    }

    const { data: snapshot } = await supabase
      .from("campaign_snapshots")
      .select("bucket, addresses_key")
      .eq("campaign_id", campaignId)
      .maybeSingle();
    const snap = snapshot as { bucket: string | null; addresses_key: string | null } | null;

    if (snap?.bucket && snap.addresses_key) {
      const features = await fetchSilverSnapshotAddresses(snap.bucket, snap.addresses_key);
      if (features && features.length > 0) {
        console.log(`[addresses] Silver selected for ${campaignId}; returned ${features.length} addresses`);
        return NextResponse.json(
          { type: "FeatureCollection", features },
          { headers: JSON_NO_STORE_HEADERS }
        );
      }
    }

    return NextResponse.json(EMPTY_FEATURE_COLLECTION, { headers: JSON_NO_STORE_HEADERS });
  } catch (err) {
    console.error("[addresses] GET error:", err);
    return NextResponse.json(EMPTY_FEATURE_COLLECTION, { headers: JSON_NO_STORE_HEADERS });
  }
}
