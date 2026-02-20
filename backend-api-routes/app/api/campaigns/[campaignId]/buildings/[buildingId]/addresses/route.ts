import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

type RouteContext = { params: Promise<{ campaignId: string; buildingId: string }> };

/**
 * Resolve path param buildingId (GERS ID string or buildings.id UUID string) to buildings.id UUID.
 * building_address_links.building_id references buildings(id), so we need the internal UUID.
 */
async function resolveBuildingId(
  supabase: ReturnType<typeof createClient>,
  buildingIdParam: string
): Promise<string | null> {
  const uuidMatch = buildingIdParam.match(
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
  );
  if (!uuidMatch) return null;

  const { data: row, error } = await supabase
    .from("buildings")
    .select("id")
    .or(`id.eq.${buildingIdParam},gers_id.eq.${buildingIdParam}`)
    .limit(1)
    .maybeSingle();

  if (error || !row) return null;
  return (row as { id: string }).id;
}

function getAuthUser(request: Request) {
  const authHeader = request.headers.get("authorization");
  const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
  return token;
}

/** Ensure the campaign exists and is owned by the given user (when using service role). */
async function ensureCampaignOwnership(
  supabase: ReturnType<typeof createClient>,
  campaignId: string,
  userId: string
): Promise<boolean> {
  const { data, error } = await supabase
    .from("campaigns")
    .select("id")
    .eq("id", campaignId)
    .eq("owner_id", userId)
    .maybeSingle();
  return !error && data != null;
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
    const canAccess = await ensureCampaignOwnership(
      supabase,
      campaignId,
      user.id
    );
    if (!canAccess) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 });
    }

    const buildingUuid = await resolveBuildingId(supabase, buildingIdParam);
    if (!buildingUuid) {
      return NextResponse.json(
        { error: "Building not found", addresses: [] },
        { status: 404 }
      );
    }

    const { data: links, error: linksError } = await supabase
      .from("building_address_links")
      .select("address_id")
      .eq("campaign_id", campaignId)
      .eq("building_id", buildingUuid);

    if (linksError) {
      console.error("[buildings/addresses] links error:", linksError);
      return NextResponse.json(
        { error: "Failed to fetch links", addresses: [] },
        { status: 500 }
      );
    }

    const addressIds = (links ?? [])
      .map((r) => (r as { address_id: string }).address_id)
      .filter(Boolean);
    if (addressIds.length === 0) {
      return NextResponse.json({ addresses: [] });
    }

    const { data: addresses, error: addrError } = await supabase
      .from("campaign_addresses")
      .select(
        "id, house_number, street_name, formatted, locality, region, postal_code, gers_id, building_gers_id, scans, last_scanned_at, qr_code_base64, contact_name, lead_status, product_interest, follow_up_date, raw_transcript, ai_summary"
      )
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
    const canAccess = await ensureCampaignOwnership(
      supabase,
      campaignId,
      user.id
    );
    if (!canAccess) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 });
    }

    const buildingUuid = await resolveBuildingId(supabase, buildingIdParam);
    if (!buildingUuid) {
      return NextResponse.json({ error: "Building not found" }, { status: 404 });
    }

    const { error: insertError } = await supabase
      .from("building_address_links")
      .insert({
        building_id: buildingUuid,
        address_id: addressId,
        campaign_id: campaignId,
        method: "MANUAL",
        is_primary: false,
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
    const canAccess = await ensureCampaignOwnership(
      supabase,
      campaignId,
      user.id
    );
    if (!canAccess) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 });
    }

    const buildingUuid = await resolveBuildingId(supabase, buildingIdParam);
    if (!buildingUuid) {
      return NextResponse.json({ error: "Building not found" }, { status: 404 });
    }

    const { error: deleteError } = await supabase
      .from("building_address_links")
      .delete()
      .eq("building_id", buildingUuid)
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
