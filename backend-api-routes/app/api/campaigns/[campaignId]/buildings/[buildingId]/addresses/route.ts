import { NextResponse } from "next/server";
import { StableLinkerService } from "@/lib/services/StableLinkerService";
import { invalidateCampaignMapBundle } from "@/lib/services/CampaignMapBundleInvalidation";
import { isUuid, resolveCampaignBuilding } from "@/app/api/campaigns/_utils/resolve-campaign-building";
import { createAdminClient } from "@/lib/supabase/server";

type RouteContext = { params: Promise<{ campaignId: string; buildingId: string }> };

type ResolvedBuilding = {
  rowId: string | null;
  publicId: string;
};

type LinkedAddressRow = {
  address_id: string;
  match_type: string | null;
};

const ADDRESS_SELECT =
  "id, house_number, street_name, formatted, locality, region, postal_code, gers_id, building_gers_id, scans, last_scanned_at, qr_code_base64, contact_name, lead_status, product_interest, follow_up_date, raw_transcript, ai_summary";

function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function mergeAddressesById<T extends { id: string }>(groups: T[][]): T[] {
  const seen = new Set<string>();
  const merged: T[] = [];

  for (const group of groups) {
    for (const address of group) {
      const key = String(address.id ?? "").toLowerCase();
      if (!key || seen.has(key)) continue;
      seen.add(key);
      merged.push(address);
    }
  }

  return merged;
}

async function fetchGoldAddresses(
  supabase: any,
  campaignId: string,
  buildingIds: string[]
) {
  const candidates = Array.from(
    new Set(
      buildingIds
        .map((value) => value.trim())
        .filter((value) => value.length > 0)
    )
  );

  if (candidates.length === 0) {
    return { data: [], error: null };
  }

  const uuidCandidates = candidates.filter(isUuid);
  const externalCandidates = candidates.filter((candidate) => !isUuid(candidate));
  const groups: Array<Array<{ id: string }>> = [];

  if (uuidCandidates.length > 0) {
    const { data, error } = await supabase
      .from("campaign_addresses")
      .select(ADDRESS_SELECT)
      .eq("campaign_id", campaignId)
      .in("building_id", uuidCandidates);

    if (error) return { data: null, error };
    groups.push((data ?? []) as Array<{ id: string }>);
  }

  if (externalCandidates.length > 0) {
    const { data, error } = await supabase
      .from("campaign_addresses")
      .select(ADDRESS_SELECT)
      .eq("campaign_id", campaignId)
      .in("building_gers_id", externalCandidates);

    if (error) return { data: null, error };
    groups.push((data ?? []) as Array<{ id: string }>);
  }

  return { data: mergeAddressesById(groups), error: null };
}

async function fetchLinkedAddresses(
  supabase: any,
  campaignId: string,
  buildingRowId: string,
  allowedMatchTypes?: Set<string>
) {
  const { data: links, error: linksError } = await supabase
    .from("building_address_links")
    .select("address_id, match_type")
    .eq("campaign_id", campaignId)
    .eq("building_id", buildingRowId);

  if (linksError) {
    return { data: null, error: linksError };
  }

  const addressIds = Array.from(
    new Set(
      ((links ?? []) as LinkedAddressRow[])
        .filter((row) => {
          if (!allowedMatchTypes) return true;
          return allowedMatchTypes.has((row.match_type ?? "").toLowerCase());
        })
        .map((row) => row.address_id)
        .filter(Boolean)
    )
  );

  if (addressIds.length === 0) {
    return { data: [], error: null };
  }

  return supabase
    .from("campaign_addresses")
    .select(ADDRESS_SELECT)
    .eq("campaign_id", campaignId)
    .in("id", addressIds);
}

function getAuthUser(request: Request) {
  const authHeader = request.headers.get("authorization");
  const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
  return token;
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

  const { data: campaignMember } = await supabase
    .from("campaign_members")
    .select("campaign_id")
    .eq("campaign_id", campaignId)
    .eq("user_id", userId)
    .maybeSingle();
  if (campaignMember) return true;

  return false;
}

/** GET /api/campaigns/[campaignId]/buildings/[buildingId]/addresses — all addresses linked to this building */
export async function GET(request: Request, context: RouteContext) {
  try {
    const token = getAuthUser(request);
    if (!token) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const { campaignId, buildingId: buildingIdParam } = await context.params;
    const supabase = createAdminClient();
    const {
      data: { user },
      error: userError,
    } = await supabase.auth.getUser(token);
    if (userError || !user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const canAccess = await ensureCampaignAccess(
      supabase,
      campaignId,
      user.id
    );
    if (!canAccess) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 });
    }

    const resolvedBuilding = await resolveCampaignBuilding(supabase, campaignId, buildingIdParam);
    const buildingIdCandidates = Array.from(
      new Set(
        [buildingIdParam, resolvedBuilding?.rowId, resolvedBuilding?.publicId]
          .filter((value): value is string => Boolean(value))
          .map((value) => value.trim())
          .filter((value) => value.length > 0)
      )
    );

    const { data: goldAddresses, error: goldError } = await fetchGoldAddresses(
      supabase,
      campaignId,
      buildingIdCandidates
    );

    if (goldError) {
      console.error("[buildings/addresses] gold fallback error:", goldError);
      return NextResponse.json(
        { error: "Failed to fetch addresses", addresses: [] },
        { status: 500 }
      );
    }

    const goldAddressRows = (goldAddresses ?? []) as Array<{ id: string }>;
    if (goldAddressRows.length > 0) {
      if (!resolvedBuilding) {
        return NextResponse.json({ addresses: goldAddressRows });
      }

      const { data: manualLinkedAddresses, error: manualLinkedError } = resolvedBuilding.rowId
        ? await fetchLinkedAddresses(
            supabase,
            campaignId,
            resolvedBuilding.rowId,
            new Set(["manual"])
          )
        : { data: [], error: null };

      if (manualLinkedError) {
        console.warn("[buildings/addresses] manual link fallback warning:", manualLinkedError);
        return NextResponse.json({ addresses: goldAddressRows });
      }

      return NextResponse.json({
        addresses: mergeAddressesById([
          goldAddressRows,
          (manualLinkedAddresses ?? []) as Array<{ id: string }>,
        ]),
      });
    }

    if (!resolvedBuilding) {
      return NextResponse.json(
        { error: "Building not found", addresses: [] },
        { status: 404 }
      );
    }

    const { data: linkedAddresses, error: linkedError } = resolvedBuilding.rowId
      ? await fetchLinkedAddresses(
          supabase,
          campaignId,
          resolvedBuilding.rowId
        )
      : { data: [], error: null };

    if (linkedError) {
      console.error("[buildings/addresses] link fallback error:", linkedError);
      return NextResponse.json(
        { error: "Failed to fetch addresses", addresses: [] },
        { status: 500 }
      );
    }

    return NextResponse.json({ addresses: linkedAddresses ?? [] });
  } catch (err) {
    console.error("[buildings/addresses] GET", err);
    return NextResponse.json(
      { error: "Internal server error", addresses: [] },
      { status: 500 }
    );
  }
}

/** POST /api/campaigns/[campaignId]/buildings/[buildingId]/addresses — link an address to the building (body: { address_id }) */
export async function POST(request: Request, context: RouteContext) {
  try {
    const token = getAuthUser(request);
    if (!token) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const { campaignId, buildingId: buildingIdParam } = await context.params;
    let body: { address_id?: string; longitude?: unknown; latitude?: unknown };
    try {
      body = await request.json();
    } catch {
      return NextResponse.json(
        { error: "Invalid JSON body; expected { address_id: UUID }" },
        { status: 400 }
      );
    }

    const addressId = body.address_id;
    if (!addressId) {
      return NextResponse.json(
        { error: "Missing address_id in body" },
        { status: 400 }
      );
    }
    const longitude = body.longitude;
    const latitude = body.latitude;
    const hasMoveCoordinate = longitude !== undefined || latitude !== undefined;
    if (hasMoveCoordinate && (!isFiniteNumber(longitude) || !isFiniteNumber(latitude))) {
      return NextResponse.json(
        { error: "longitude and latitude must both be numbers when provided" },
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

    const canAccess = await ensureCampaignAccess(
      supabase,
      campaignId,
      user.id
    );
    if (!canAccess) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 });
    }

    const resolvedBuilding = await resolveCampaignBuilding(supabase, campaignId, buildingIdParam);
    if (!resolvedBuilding) {
      return NextResponse.json({ error: "Building not found" }, { status: 404 });
    }

    const linker = new StableLinkerService(supabase);
    const coordinate = hasMoveCoordinate && isFiniteNumber(longitude) && isFiniteNumber(latitude)
      ? [longitude, latitude] as [number, number]
      : undefined;
    const stableLink = resolvedBuilding.rowId
      ? await linker.assignAddressToBuilding({
          campaignId,
          addressId,
          buildingRowId: resolvedBuilding.rowId,
          buildingPublicId: resolvedBuilding.publicId,
          assignedBy: user.id,
          coordinate,
        })
      : await linker.assignAddressToExternalBuilding({
          campaignId,
          addressId,
          buildingPublicId: resolvedBuilding.publicId,
          assignedBy: user.id,
          coordinate,
        });

    await invalidateCampaignMapBundle(supabase, campaignId);

    return NextResponse.json({
      linked: true,
      address_id: addressId,
      building_id: resolvedBuilding.publicId,
      linked_address_ids: stableLink.linkedAddressIds,
      unit_count: stableLink.unitCount,
    });
  } catch (err) {
    console.error("[buildings/addresses] POST", err);
    if (err instanceof Error && err.message.includes("database migration required for external building ids")) {
      return NextResponse.json(
        { error: err.message },
        { status: 409 }
      );
    }
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}

/** DELETE /api/campaigns/[campaignId]/buildings/[buildingId]/addresses?address_id=... — unlink an address */
export async function DELETE(request: Request, context: RouteContext) {
  try {
    const token = getAuthUser(request);
    if (!token) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const { campaignId, buildingId: buildingIdParam } = await context.params;
    const url = new URL(request.url);
    const addressId = url.searchParams.get("address_id");
    if (!addressId) {
      return NextResponse.json(
        { error: "Missing query parameter: address_id" },
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

    const canAccess = await ensureCampaignAccess(
      supabase,
      campaignId,
      user.id
    );
    if (!canAccess) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 });
    }

    const resolvedBuilding = await resolveCampaignBuilding(supabase, campaignId, buildingIdParam);
    if (!resolvedBuilding) {
      return NextResponse.json({ error: "Building not found" }, { status: 404 });
    }

    const deleteManualAddress = url.searchParams.get("mode") === "delete_manual";
    const result = await new StableLinkerService(supabase).unassignAddressFromBuilding({
      campaignId,
      addressId,
      buildingRowId: resolvedBuilding.rowId,
      buildingPublicId: resolvedBuilding.publicId,
      deleteManualAddress,
    });

    await invalidateCampaignMapBundle(supabase, campaignId);

    return NextResponse.json({
      unlinked: true,
      deleted: deleteManualAddress,
      address_id: addressId,
      building_id: resolvedBuilding.publicId,
      linked_address_ids: result.linkedAddressIds,
      unit_count: result.unitCount,
    });
  } catch (err) {
    console.error("[buildings/addresses] DELETE", err);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}
