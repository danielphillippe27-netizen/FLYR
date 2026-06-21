import { NextResponse } from "next/server";
import {
  TownhouseSplitterService,
  type SplitAxisMode,
} from "@/lib/services/TownhouseSplitterService";
import { invalidateCampaignMapBundle } from "@/lib/services/CampaignMapBundleInvalidation";
import { createAdminClient } from "@/lib/supabase/server";
import { resolveCampaignBuilding } from "@/app/api/campaigns/_utils/resolve-campaign-building";

type RouteContext = { params: Promise<{ campaignId: string; buildingId: string }> };

type SplitPatchBody = {
  split_axis_mode?: SplitAxisMode;
  reverse_order?: boolean;
};

function getAuthUser(request: Request) {
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
    if (workspace && (workspace as { owner_id: string }).owner_id === userId) return true;
  }

  const { data: campaignMember } = await supabase
    .from("campaign_members")
    .select("campaign_id")
    .eq("campaign_id", campaignId)
    .eq("user_id", userId)
    .maybeSingle();
  return Boolean(campaignMember);
}

function validSplitAxisMode(value: unknown): value is SplitAxisMode {
  return value === "auto" || value === "long" || value === "short";
}

export async function PATCH(request: Request, context: RouteContext) {
  try {
    const token = getAuthUser(request);
    if (!token) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const { campaignId, buildingId } = await context.params;
    const body = (await request.json().catch(() => null)) as SplitPatchBody | null;
    if (!body || (body.split_axis_mode === undefined && body.reverse_order === undefined)) {
      return NextResponse.json(
        { error: "Expected split_axis_mode and/or reverse_order" },
        { status: 400 }
      );
    }

    if (body.split_axis_mode !== undefined && !validSplitAxisMode(body.split_axis_mode)) {
      return NextResponse.json(
        { error: "split_axis_mode must be auto, long, or short" },
        { status: 400 }
      );
    }
    if (body.reverse_order !== undefined && typeof body.reverse_order !== "boolean") {
      return NextResponse.json(
        { error: "reverse_order must be a boolean" },
        { status: 400 }
      );
    }

    const supabase = createAdminClient();
    const {
      data: { user },
      error: userError,
    } = await supabase.auth.getUser(token);
    if (userError || !user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const canAccess = await ensureCampaignAccess(supabase, campaignId, user.id);
    if (!canAccess) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 });
    }

    const resolvedBuilding = await resolveCampaignBuilding(supabase, campaignId, buildingId);
    if (!resolvedBuilding) {
      return NextResponse.json({ error: "Building not found" }, { status: 404 });
    }

    const { data: existingOverride } = await supabase
      .from("building_split_overrides")
      .select("split_axis_mode, reverse_order")
      .eq("campaign_id", campaignId)
      .eq("parent_building_id", resolvedBuilding.publicId)
      .maybeSingle();
    const existing = existingOverride as { split_axis_mode: SplitAxisMode | null; reverse_order: boolean | null } | null;
    const nextSplitAxisMode = body.split_axis_mode ?? existing?.split_axis_mode ?? "auto";
    const nextReverseOrder = body.reverse_order ?? existing?.reverse_order ?? false;

    const override = {
      campaign_id: campaignId,
      parent_building_id: resolvedBuilding.publicId,
      split_axis_mode: nextSplitAxisMode,
      reverse_order: nextReverseOrder,
      updated_by: user.id,
      updated_at: new Date().toISOString(),
    };

    const { error: upsertError } = await supabase
      .from("building_split_overrides")
      .upsert(override, { onConflict: "campaign_id,parent_building_id" });
    if (upsertError) {
      console.error("[building-split] override upsert error:", upsertError);
      return NextResponse.json({ error: "Failed to save split override" }, { status: 500 });
    }

    const townhouseSplit = await new TownhouseSplitterService(supabase).recalculateBuildingUnits({
      campaignId,
      parentBuildingId: resolvedBuilding.publicId,
      buildingRowId: resolvedBuilding.rowId,
      override: {
        split_axis_mode: nextSplitAxisMode,
        reverse_order: nextReverseOrder,
      },
    });

    await invalidateCampaignMapBundle(supabase, campaignId);

    return NextResponse.json({
      updated: true,
      building_id: resolvedBuilding.publicId,
      split_axis_mode: nextSplitAxisMode,
      reverse_order: nextReverseOrder,
      townhouse_split: townhouseSplit,
    });
  } catch (error) {
    console.error("[building-split] PATCH", error);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
