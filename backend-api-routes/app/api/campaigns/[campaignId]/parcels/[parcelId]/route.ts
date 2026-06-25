import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import { invalidateCampaignMapBundle } from "@/lib/services/CampaignMapBundleInvalidation";

const SUPABASE_URL = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

type RouteContext = { params: Promise<{ campaignId: string; parcelId: string }> };

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function getAuthToken(request: Request): string | null {
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

  const row = campaign as { owner_id: string; workspace_id: string | null };
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
    if (workspace && (workspace as { owner_id: string }).owner_id === userId) {
      return true;
    }
  }

  const { data: campaignMember } = await supabase
    .from("campaign_members")
    .select("campaign_id")
    .eq("campaign_id", campaignId)
    .eq("user_id", userId)
    .maybeSingle();
  return Boolean(campaignMember);
}

export async function DELETE(request: Request, context: RouteContext): Promise<Response> {
  try {
    const token = getAuthToken(request);
    if (!token) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const { campaignId, parcelId } = await context.params;
    const supabaseAnon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    const {
      data: { user },
      error: userError,
    } = await supabaseAnon.auth.getUser(token);
    if (userError || !user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const canAccess = await ensureCampaignAccess(supabase, campaignId, user.id);
    if (!canAccess) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 });
    }

    const parcelQuery = supabase
      .from("campaign_parcels")
      .select("id, external_id")
      .eq("campaign_id", campaignId)
      .limit(1);
    const { data: parcel, error: lookupError } = await (UUID_RE.test(parcelId)
      ? parcelQuery.or(`id.eq.${parcelId},external_id.eq.${parcelId}`)
      : parcelQuery.eq("external_id", parcelId)
    ).maybeSingle();

    if (lookupError) {
      console.error("[campaign-parcel] lookup error:", lookupError);
      return NextResponse.json({ error: "Failed to load parcel" }, { status: 500 });
    }
    if (!parcel) {
      return NextResponse.json({ error: "Parcel not found" }, { status: 404 });
    }

    const parcelRow = parcel as { id: string; external_id: string | null };
    const { error: deleteError } = await supabase
      .from("campaign_parcels")
      .delete()
      .eq("campaign_id", campaignId)
      .eq("id", parcelRow.id);

    if (deleteError) {
      console.error("[campaign-parcel] delete error:", deleteError);
      return NextResponse.json({ error: "Failed to delete parcel" }, { status: 500 });
    }

    const { count } = await supabase
      .from("campaign_parcels")
      .select("id", { count: "exact", head: true })
      .eq("campaign_id", campaignId);

    await supabase
      .from("campaigns")
      .update({
        parcel_count: count ?? 0,
        parcel_enriched_at: new Date().toISOString(),
      })
      .eq("id", campaignId);

    await invalidateCampaignMapBundle(supabase, campaignId);

    return NextResponse.json({
      deleted: true,
      parcel_id: parcelRow.external_id ?? parcelRow.id,
      campaign_parcel_id: parcelRow.id,
    });
  } catch (error) {
    console.error("[campaign-parcel] DELETE error:", error);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
