import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

type RouteContext = { params: Promise<{ campaignId: string; buildingId: string }> };

type ResolvedBuilding = {
  rowId: string;
  publicId: string;
};

type BuildingAddressLinkRow = {
  address_id: string;
  match_type: string | null;
  confidence: number | null;
  distance_meters: number | null;
};

const ADDRESS_SELECT =
  "id, house_number, street_name, formatted, locality, region, postal_code, gers_id, building_gers_id, scans, last_scanned_at, qr_code_base64, contact_name, lead_status, product_interest, follow_up_date, raw_transcript, ai_summary";

/**
 * Resolve a public building identifier to both the buildings row UUID and the public id shown on the map.
 * Supports both UUID-based manual buildings (buildings.id) and GERS-linked imported buildings.
 */
async function resolveBuilding(
  supabase: any,
  buildingIdParam: string
): Promise<ResolvedBuilding | null> {
  const uuidMatch = buildingIdParam.match(
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
  );
  const query = supabase.from("buildings").select("id, gers_id").limit(1);
  const builder = uuidMatch
    ? query.or(`id.eq.${buildingIdParam},gers_id.eq.${buildingIdParam}`)
    : query.eq("gers_id", buildingIdParam);

  const { data: row, error } = await builder.maybeSingle();

  if (error || !row) return null;
  const building = row as { id: string; gers_id: string | null };
  return {
    rowId: building.id,
    publicId: building.gers_id ?? building.id,
  };
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

  return supabase
    .from("campaign_addresses")
    .select(ADDRESS_SELECT)
    .eq("campaign_id", campaignId)
    .in("building_id", candidates);
}

function isStrongBuildingLink(link: BuildingAddressLinkRow): boolean {
  const matchType = (link.match_type ?? "").toLowerCase();
  if (matchType === "manual") return true;
  if (matchType === "containment_verified") return true;
  if (matchType === "point_on_surface") return true;
  if (matchType === "parcel_verified") return true;
  return (link.confidence ?? 0) >= 0.9 && matchType !== "proximity_fallback";
}

function chooseAddressLinksForDisplay(links: BuildingAddressLinkRow[]): BuildingAddressLinkRow[] {
  if (links.length <= 1) return links;

  const strongLinks = links.filter(isStrongBuildingLink);
  if (strongLinks.length > 0 && strongLinks.length < links.length) {
    return strongLinks;
  }

  return links;
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
    const supabaseAnon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    const {
      data: { user },
      error: userError,
    } = await supabaseAnon.auth.getUser(token);
    if (userError || !user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const canAccess = await ensureCampaignAccess(
      supabase,
      campaignId,
      user.id
    );
    if (!canAccess) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 });
    }

    const resolvedBuilding = await resolveBuilding(supabase, buildingIdParam);
    const buildingIdCandidates = Array.from(
      new Set(
        [buildingIdParam, resolvedBuilding?.rowId, resolvedBuilding?.publicId]
          .filter((value): value is string => Boolean(value))
          .map((value) => value.trim())
          .filter((value) => value.length > 0)
      )
    );

    if (resolvedBuilding) {
      const { data: links, error: linksError } = await supabase
        .from("building_address_links")
        .select("address_id, match_type, confidence, distance_meters")
        .eq("campaign_id", campaignId)
        .in("building_id", buildingIdCandidates);

      if (linksError) {
        console.error("[buildings/addresses] links error:", linksError);
        return NextResponse.json(
          { error: "Failed to fetch links", addresses: [] },
          { status: 500 }
        );
      }

      const displayLinks = chooseAddressLinksForDisplay((links ?? []) as BuildingAddressLinkRow[]);
      const addressIds = displayLinks
        .map((r) => r.address_id)
        .filter(Boolean);

      if (addressIds.length > 0) {
        const { data: addresses, error: addrError } = await supabase
          .from("campaign_addresses")
          .select(ADDRESS_SELECT)
          .eq("campaign_id", campaignId)
          .in("id", addressIds);

        if (addrError) {
          console.error("[buildings/addresses] campaign_addresses error:", addrError);
          return NextResponse.json(
            { error: "Failed to fetch addresses", addresses: [] },
            { status: 500 }
          );
        }

        return NextResponse.json({ addresses: addresses ?? [] });
      }
    }

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

    if ((goldAddresses ?? []).length > 0) {
      return NextResponse.json({ addresses: goldAddresses ?? [] });
    }

    if (!resolvedBuilding) {
      return NextResponse.json(
        { error: "Building not found", addresses: [] },
        { status: 404 }
      );
    }

    return NextResponse.json({ addresses: [] });
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
    let body: { address_id?: string };
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

    const supabaseAnon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    const {
      data: { user },
      error: userError,
    } = await supabaseAnon.auth.getUser(token);
    if (userError || !user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const canAccess = await ensureCampaignAccess(
      supabase,
      campaignId,
      user.id
    );
    if (!canAccess) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 });
    }

    const resolvedBuilding = await resolveBuilding(supabase, buildingIdParam);
    if (!resolvedBuilding) {
      return NextResponse.json({ error: "Building not found" }, { status: 404 });
    }

    const { error: insertError } = await supabase
      .from("building_address_links")
      .insert({
        building_id: resolvedBuilding.rowId,
        address_id: addressId,
        campaign_id: campaignId,
        match_type: "manual",
        confidence: 1,
        is_multi_unit: false,
        unit_count: 1,
      });

    if (insertError) {
      if (insertError.code === "23505") {
        return NextResponse.json(
          { error: "Address already linked to this building" },
          { status: 409 }
        );
      }
      console.error("[buildings/addresses] POST insert error:", insertError);
      return NextResponse.json(
        { error: "Failed to link address" },
        { status: 500 }
      );
    }

    return NextResponse.json({ linked: true, address_id: addressId });
  } catch (err) {
    console.error("[buildings/addresses] POST", err);
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

    const supabaseAnon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    const {
      data: { user },
      error: userError,
    } = await supabaseAnon.auth.getUser(token);
    if (userError || !user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const canAccess = await ensureCampaignAccess(
      supabase,
      campaignId,
      user.id
    );
    if (!canAccess) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 });
    }

    const resolvedBuilding = await resolveBuilding(supabase, buildingIdParam);
    if (!resolvedBuilding) {
      return NextResponse.json({ error: "Building not found" }, { status: 404 });
    }

    const { error: deleteError } = await supabase
      .from("building_address_links")
      .delete()
      .eq("building_id", resolvedBuilding.rowId)
      .eq("address_id", addressId)
      .eq("campaign_id", campaignId);

    if (deleteError) {
      console.error("[buildings/addresses] DELETE error:", deleteError);
      return NextResponse.json(
        { error: "Failed to unlink address" },
        { status: 500 }
      );
    }

    return NextResponse.json({ unlinked: true, address_id: addressId });
  } catch (err) {
    console.error("[buildings/addresses] DELETE", err);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}
