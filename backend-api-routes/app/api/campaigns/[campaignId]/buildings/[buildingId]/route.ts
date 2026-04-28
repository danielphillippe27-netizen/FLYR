import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

type RouteContext = { params: Promise<{ campaignId: string; buildingId: string }> };

type BuildingRow = {
  id: string;
  gers_id: string | null;
  campaign_id: string | null;
};

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

  return false;
}

async function resolveBuildingRow(
  supabase: any,
  buildingIdParam: string
): Promise<BuildingRow | null> {
  const uuidMatch = buildingIdParam.match(
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
  );

  const query = supabase
    .from("buildings")
    .select("id, gers_id, campaign_id")
    .limit(1);

  const builder = uuidMatch
    ? query.or(`id.eq.${buildingIdParam},gers_id.eq.${buildingIdParam}`)
    : query.eq("gers_id", buildingIdParam);

  const { data, error } = await builder.maybeSingle();
  if (error || !data) return null;
  return data as BuildingRow;
}

function normalizeBuildingIdentifier(value: string | null | undefined): string | null {
  if (!value) return null;
  const trimmed = value.trim().toLowerCase();
  return trimmed.length > 0 ? trimmed : null;
}

export async function DELETE(request: Request, context: RouteContext): Promise<Response> {
  try {
    const token = getAuthToken(request);
    if (!token) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const { campaignId, buildingId: buildingIdParam } = await context.params;
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

    const buildingRow = await resolveBuildingRow(supabase, buildingIdParam);
    const publicBuildingId =
      normalizeBuildingIdentifier(buildingRow?.gers_id) ??
      normalizeBuildingIdentifier(buildingRow?.id) ??
      normalizeBuildingIdentifier(buildingIdParam);

    if (!publicBuildingId) {
      return NextResponse.json({ error: "Building not found" }, { status: 404 });
    }

    let linkedAddressIds: string[] = [];

    if (buildingRow?.id) {
      const { data: links, error: linksError } = await supabase
        .from("building_address_links")
        .select("address_id")
        .eq("campaign_id", campaignId)
        .eq("building_id", buildingRow.id);

      if (linksError) {
        console.error("[campaign-building-delete] link lookup error:", linksError);
        return NextResponse.json({ error: "Failed to load building links" }, { status: 500 });
      }

      linkedAddressIds = (links ?? []).map((row: { address_id: string }) => row.address_id);
    }

    const { data: addressesByBuildingId, error: addressesError } = await supabase
      .from("campaign_addresses")
      .select("id")
      .eq("campaign_id", campaignId)
      .eq("building_gers_id", publicBuildingId);

    if (addressesError) {
      console.error("[campaign-building-delete] address lookup error:", addressesError);
      return NextResponse.json({ error: "Failed to load building addresses" }, { status: 500 });
    }

    linkedAddressIds = Array.from(
      new Set([
        ...linkedAddressIds,
        ...(addressesByBuildingId ?? []).map((row: { id: string }) => row.id),
      ])
    );

    if (!buildingRow && linkedAddressIds.length === 0) {
      return NextResponse.json({ error: "Building not found" }, { status: 404 });
    }

    const { error: hideError } = await supabase
      .from("campaign_hidden_buildings")
      .upsert(
        {
          campaign_id: campaignId,
          public_building_id: publicBuildingId,
        },
        {
          onConflict: "campaign_id,public_building_id",
          ignoreDuplicates: false,
        }
      );

    if (hideError) {
      console.error("[campaign-building-delete] hidden building upsert error:", hideError);
      return NextResponse.json({ error: "Failed to suppress building" }, { status: 500 });
    }

    if (linkedAddressIds.length > 0) {
      const { error: deleteAddressesError } = await supabase
        .from("campaign_addresses")
        .delete()
        .eq("campaign_id", campaignId)
        .in("id", linkedAddressIds);

      if (deleteAddressesError) {
        console.error("[campaign-building-delete] address delete error:", deleteAddressesError);
        return NextResponse.json({ error: "Failed to delete linked addresses" }, { status: 500 });
      }
    }

    if (buildingRow?.id) {
      const { error: deleteLinksError } = await supabase
        .from("building_address_links")
        .delete()
        .eq("campaign_id", campaignId)
        .eq("building_id", buildingRow.id);

      if (deleteLinksError) {
        console.error("[campaign-building-delete] link delete error:", deleteLinksError);
        return NextResponse.json({ error: "Failed to delete building links" }, { status: 500 });
      }
    }

    const { error: deleteStatsError } = await supabase
      .from("building_stats")
      .delete()
      .eq("campaign_id", campaignId)
      .eq("gers_id", publicBuildingId);

    if (deleteStatsError) {
      console.warn("[campaign-building-delete] building stats cleanup warning:", deleteStatsError);
    }

    const { error: deleteUnitsError } = await supabase
      .from("building_units")
      .delete()
      .eq("campaign_id", campaignId)
      .eq("parent_building_id", publicBuildingId);

    if (deleteUnitsError) {
      console.warn("[campaign-building-delete] building units cleanup warning:", deleteUnitsError);
    }

    const shouldDeleteBuildingRow =
      Boolean(buildingRow?.id) &&
      buildingRow?.campaign_id === campaignId;

    if (shouldDeleteBuildingRow && buildingRow?.id) {
      const { error: deleteBuildingError } = await supabase
        .from("buildings")
        .delete()
        .eq("id", buildingRow.id);

      if (deleteBuildingError) {
        console.error("[campaign-building-delete] building delete error:", deleteBuildingError);
        return NextResponse.json({ error: "Failed to delete building" }, { status: 500 });
      }
    }

    return NextResponse.json({
      deleted: true,
      building_id: publicBuildingId,
      deleted_address_count: linkedAddressIds.length,
    });
  } catch (error) {
    console.error("[campaign-building-delete] DELETE error:", error);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}
