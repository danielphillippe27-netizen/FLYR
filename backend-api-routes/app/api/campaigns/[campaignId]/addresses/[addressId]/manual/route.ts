import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

type RouteContext = { params: Promise<{ campaignId: string; addressId: string }> };

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
  if (campaignMember) return true;

  return false;
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function pointGeoJSON(longitude: number, latitude: number) {
  return { type: "Point", coordinates: [longitude, latitude] as [number, number] };
}

export async function PATCH(request: Request, context: RouteContext): Promise<Response> {
  try {
    const token = getAuthToken(request);
    if (!token) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const body = await request.json().catch(() => null);
    if (!body || typeof body !== "object") {
      return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
    }

    const longitude = (body as { longitude?: unknown }).longitude;
    const latitude = (body as { latitude?: unknown }).latitude;
    if (!isFiniteNumber(longitude) || !isFiniteNumber(latitude)) {
      return NextResponse.json(
        { error: "longitude and latitude are required numbers" },
        { status: 400 }
      );
    }

    const { campaignId, addressId } = await context.params;
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

    const { data: row, error: lookupError } = await supabase
      .from("campaign_addresses")
      .select("id")
      .eq("campaign_id", campaignId)
      .eq("id", addressId)
      .maybeSingle();

    if (lookupError || !row) {
      return NextResponse.json({ error: "Address not found" }, { status: 404 });
    }

    const { error: updateError } = await supabase
      .from("campaign_addresses")
      .update({ geom: JSON.stringify(pointGeoJSON(longitude, latitude)) })
      .eq("campaign_id", campaignId)
      .eq("id", addressId);

    if (updateError) {
      console.error("[manual-address] move error:", updateError);
      return NextResponse.json(
        { error: "Failed to move address" },
        { status: 500 }
      );
    }

    return NextResponse.json({ moved: true, address_id: addressId });
  } catch (error) {
    console.error("[manual-address] PATCH error:", error);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}

export async function DELETE(request: Request, context: RouteContext): Promise<Response> {
  try {
    const token = getAuthToken(request);
    if (!token) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const { campaignId, addressId } = await context.params;
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

    const { data: row, error: lookupError } = await supabase
      .from("campaign_addresses")
      .select("id, source")
      .eq("campaign_id", campaignId)
      .eq("id", addressId)
      .maybeSingle();

    if (lookupError || !row) {
      return NextResponse.json({ error: "Address not found" }, { status: 404 });
    }
    if ((row as { source: string | null }).source !== "manual") {
      return NextResponse.json(
        { error: "Only manual addresses can be deleted from tools" },
        { status: 409 }
      );
    }

    const { error: deleteError } = await supabase
      .from("campaign_addresses")
      .delete()
      .eq("campaign_id", campaignId)
      .eq("id", addressId)
      .eq("source", "manual");

    if (deleteError) {
      console.error("[manual-address] delete error:", deleteError);
      return NextResponse.json(
        { error: "Failed to delete manual address" },
        { status: 500 }
      );
    }

    return NextResponse.json({ deleted: true, address_id: addressId });
  } catch (error) {
    console.error("[manual-address] DELETE error:", error);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}
