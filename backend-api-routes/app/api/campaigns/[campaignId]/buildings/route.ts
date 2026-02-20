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
  supabase: ReturnType<typeof createClient>,
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

    if (!rpcError && rpcResult) {
      const fc = rpcResult as { type?: string; features?: unknown[] };
      const features = fc?.features ?? [];
      const polygonFeatures = (features as Array<{ geometry?: { type?: string } }>)
        .filter((f) => {
          const t = f?.geometry?.type;
          return t === "Polygon" || t === "MultiPolygon";
        });

      if (polygonFeatures.length > 0) {
        console.log(
          `[buildings] RPC returned ${polygonFeatures.length} polygon features for ${campaignId}`
        );
        return NextResponse.json(
          { type: "FeatureCollection", features: polygonFeatures },
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
      const geojson = await fetchFromS3(snap.bucket, snap.buildings_key);
      if (geojson) {
        return NextResponse.json(geojson, {
          headers: { "Content-Type": "application/json" },
        });
      }
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
