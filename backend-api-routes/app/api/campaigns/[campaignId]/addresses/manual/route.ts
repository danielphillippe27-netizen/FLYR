import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import { StableLinkerService } from "@/lib/services/StableLinkerService";
import { resolveCampaignBuilding } from "@/app/api/campaigns/_utils/resolve-campaign-building";

const SUPABASE_URL = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

type RouteContext = { params: Promise<{ campaignId: string }> };

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

function optionalUUID(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(trimmed)
    ? trimmed
    : null;
}

function pointGeoJSON(longitude: number, latitude: number) {
  return { type: "Point", coordinates: [longitude, latitude] as [number, number] };
}

const ADDRESS_SELECT =
  "id, formatted, house_number, street_name, locality, region, postal_code, building_id, building_gers_id, match_source, confidence, source";

export async function POST(request: Request, context: RouteContext): Promise<Response> {
  try {
    const token = getAuthToken(request);
    if (!token) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const body = await request.json().catch(() => null);
    if (!body || typeof body !== "object") {
      return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
    }

    const { campaignId } = await context.params;
    const longitude = (body as { longitude?: unknown }).longitude;
    const latitude = (body as { latitude?: unknown }).latitude;
    const formatted = String((body as { formatted?: unknown }).formatted ?? "").trim();
    const requestedAddressId =
      optionalUUID((body as { address_id?: unknown }).address_id) ??
      optionalUUID((body as { id?: unknown }).id);

    if (!isFiniteNumber(longitude) || !isFiniteNumber(latitude)) {
      return NextResponse.json(
        { error: "longitude and latitude are required numbers" },
        { status: 400 }
      );
    }
    if (!formatted) {
      return NextResponse.json({ error: "formatted is required" }, { status: 400 });
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
    const canAccess = await ensureCampaignAccess(supabase, campaignId, user.id);
    if (!canAccess) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 });
    }

    const requestedBuildingId = String(
      (body as { building_id?: unknown }).building_id ?? ""
    ).trim();
    const addressProvenance = String(
      (body as { address_provenance?: unknown }).address_provenance ?? ""
    ).trim();
    const isReverseGeocodeConfirmed = addressProvenance === "mapbox_reverse_geocode";
    const linkTarget = requestedBuildingId
      ? await resolveCampaignBuilding(supabase, campaignId, requestedBuildingId)
      : null;

    if (requestedBuildingId && !linkTarget) {
      return NextResponse.json(
        { error: "Linked building not found" },
        { status: 404 }
      );
    }

    const confidence = isReverseGeocodeConfirmed ? 0.65 : 1;
    const addressInsert: Record<string, unknown> = {
      ...(requestedAddressId ? { id: requestedAddressId } : {}),
      campaign_id: campaignId,
      house_number: String((body as { house_number?: unknown }).house_number ?? "").trim() || null,
      street_name: String((body as { street_name?: unknown }).street_name ?? "").trim() || null,
      locality: String((body as { locality?: unknown }).locality ?? "").trim() || null,
      region: String((body as { region?: unknown }).region ?? "").trim() || null,
      postal_code: String((body as { postal_code?: unknown }).postal_code ?? "").trim() || null,
      country: String((body as { country?: unknown }).country ?? "").trim() || null,
      formatted,
      source: "manual",
      building_gers_id: null,
      ...(isReverseGeocodeConfirmed ? { confidence } : {}),
      geom: JSON.stringify(pointGeoJSON(longitude, latitude)),
    };
    const addressMutation = requestedAddressId
      ? supabase
          .from("campaign_addresses")
          .upsert(addressInsert, { onConflict: "id" })
      : supabase
          .from("campaign_addresses")
          .insert(addressInsert);

    const { data: insertedAddress, error: insertError } = await addressMutation
      .select(ADDRESS_SELECT)
      .single();

    if (insertError || !insertedAddress) {
      console.error("[manual-address] insert error:", insertError);
      return NextResponse.json(
        { error: "Failed to create manual address" },
        { status: 500 }
      );
    }

    let responseAddress = insertedAddress;

    if (linkTarget) {
      try {
        const linker = new StableLinkerService(supabase);
        const addressId = (insertedAddress as { id: string }).id;
        const coordinate = [longitude, latitude] as [number, number];
        if (linkTarget.rowId) {
          await linker.assignAddressToBuilding({
            campaignId,
            addressId,
            buildingRowId: linkTarget.rowId,
            buildingPublicId: linkTarget.publicId,
            assignedBy: user.id,
            coordinate,
            confidence,
          });
        } else {
          await linker.assignAddressToExternalBuilding({
            campaignId,
            addressId,
            buildingPublicId: linkTarget.publicId,
            assignedBy: user.id,
            coordinate,
            confidence,
          });
        }

        const { data: linkedAddress, error: linkedAddressError } = await supabase
          .from("campaign_addresses")
          .select(ADDRESS_SELECT)
          .eq("campaign_id", campaignId)
          .eq("id", addressId)
          .maybeSingle();

        if (linkedAddressError) {
          console.warn("[manual-address] linked address refresh warning:", linkedAddressError);
        } else if (linkedAddress) {
          responseAddress = linkedAddress;
        }
      } catch (linkError) {
        console.error("[manual-address] link error:", linkError);
        return NextResponse.json(
          { error: "Address created but failed to link it to the building" },
          { status: 500 }
        );
      }
    }

    return NextResponse.json({
      address: responseAddress,
      linked_building_id: linkTarget?.publicId ?? null,
    });
  } catch (error) {
    console.error("[manual-address] POST error:", error);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}
