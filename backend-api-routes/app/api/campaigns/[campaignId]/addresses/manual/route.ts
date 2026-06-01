import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import { StableLinkerService } from "@/lib/services/StableLinkerService";
import { invalidateCampaignMapBundle } from "@/lib/services/CampaignMapBundleInvalidation";
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

function pointEWKT(longitude: number, latitude: number): string {
  return `SRID=4326;POINT(${longitude} ${latitude})`;
}

function isMissingColumnError(error: { code?: string; message?: string } | null, column: string): boolean {
  const message = error?.message?.toLowerCase() ?? "";
  return (
    (error?.code === "PGRST204" || error?.code === "42703") &&
    message.includes(column.toLowerCase())
  );
}

function isGeometryWriteError(error: { code?: string; message?: string } | null): boolean {
  const message = error?.message?.toLowerCase() ?? "";
  return (
    message.includes("geom") ||
    message.includes("geometry") ||
    message.includes("parse error") ||
    message.includes("invalid input syntax")
  );
}

function isMatchSourceConstraintError(error: { code?: string; message?: string } | null): boolean {
  const message = error?.message?.toLowerCase() ?? "";
  return (
    error?.code === "23514" &&
    (message.includes("match_source") || message.includes("campaign_addresses_match_source_check"))
  );
}

async function writeManualAddress(
  supabase: any,
  values: Record<string, unknown>,
  mode: "insert" | "upsert"
) {
  const writeValues = { ...values };
  let selectColumns = ADDRESS_SELECT;

  const write = async (payload: Record<string, unknown>) => {
    const mutation = mode === "upsert"
      ? supabase.from("campaign_addresses").upsert(payload, { onConflict: "id" })
      : supabase.from("campaign_addresses").insert(payload);

    return mutation
      .select(selectColumns)
      .single();
  };

  while (true) {
    const result = await write(writeValues);
    if (!result.error) {
      return result;
    }

    if ("geom" in writeValues && isGeometryWriteError(result.error)) {
      delete writeValues.geom;
      console.warn(`[manual-address] campaign_addresses.geom rejected; retrying ${mode} without geom`);
      continue;
    }

    const optionalColumn = [
      "country",
      "source",
      "building_id",
      "building_gers_id",
      "match_source",
      "confidence",
    ].find((column) => isMissingColumnError(result.error, column));

    if (optionalColumn) {
      delete writeValues[optionalColumn];
      selectColumns = selectColumns
        .split(",")
        .map((column) => column.trim())
        .filter((column) => column !== optionalColumn)
        .join(", ");
      console.warn(`[manual-address] campaign_addresses.${optionalColumn} missing; retrying ${mode} without it`);
      continue;
    }

    return result;
  }
}

const ADDRESS_SELECT =
  "id, formatted, house_number, street_name, locality, region, postal_code, building_id, building_gers_id, match_source, confidence, source";

type DuplicateAddressRow = {
  id: string;
  formatted: string | null;
  house_number: string | null;
  street_name: string | null;
  locality: string | null;
  region: string | null;
  postal_code: string | null;
  building_id?: string | null;
  building_gers_id?: string | null;
  match_source?: string | null;
  confidence?: number | null;
  source?: string | null;
};

type NormalizedAddressIdentity = {
  primary: string;
  postalCode: string | null;
};

function normalizedHouseNumber(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim().toLowerCase().replace(/\s+/g, "");
  return normalized.length > 0 ? normalized : null;
}

function normalizedPostalCode(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const normalized = value.toUpperCase().replace(/[^A-Z0-9]/g, "");
  return normalized.length > 0 ? normalized : null;
}

function normalizedStreetName(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const words = value
    .toLowerCase()
    .replace(/[.,]/g, " ")
    .split(/[^a-z0-9]+/)
    .filter(Boolean)
    .map((word) => {
      switch (word) {
        case "st":
        case "str":
          return "street";
        case "rd":
          return "road";
        case "ave":
        case "av":
          return "avenue";
        case "blvd":
          return "boulevard";
        case "dr":
          return "drive";
        case "ct":
          return "court";
        case "cres":
          return "crescent";
        case "ln":
          return "lane";
        case "pl":
          return "place";
        case "trl":
          return "trail";
        case "pkwy":
          return "parkway";
        case "hwy":
          return "highway";
        default:
          return word;
      }
    });

  const normalized = words.join(" ");
  return normalized.length > 0 ? normalized : null;
}

function parsedAddressParts(formatted: unknown): {
  houseNumber: string | null;
  streetName: string | null;
  postalCode: string | null;
} {
  if (typeof formatted !== "string") {
    return { houseNumber: null, streetName: null, postalCode: null };
  }
  const trimmed = formatted.trim();
  if (!trimmed) {
    return { houseNumber: null, streetName: null, postalCode: null };
  }

  const firstAddressLine = trimmed.split(",", 1)[0]?.trim() ?? trimmed;
  const tokens = firstAddressLine.split(/\s+/).filter(Boolean);
  const houseNumber = normalizedHouseNumber(tokens[0]);
  const streetName = tokens.length > 1 ? normalizedStreetName(tokens.slice(1).join(" ")) : null;
  const postalCode = trimmed
    .split(/[^A-Za-z0-9]+/)
    .filter(Boolean)
    .reverse()
    .map(normalizedPostalCode)
    .find((value): value is string =>
      Boolean(value && value.length >= 4 && value.length <= 10 && /\d/.test(value))
    ) ?? null;

  return { houseNumber, streetName, postalCode };
}

function normalizedAddressIdentityParts(input: {
  house_number?: unknown;
  street_name?: unknown;
  postal_code?: unknown;
  formatted?: unknown;
}): NormalizedAddressIdentity | null {
  const parsed = parsedAddressParts(input.formatted);
  const house = normalizedHouseNumber(input.house_number) ?? parsed.houseNumber;
  const street = normalizedStreetName(input.street_name) ?? parsed.streetName;
  if (!house || !street) return null;

  return {
    primary: `${house}|${street}`,
    postalCode: normalizedPostalCode(input.postal_code) ?? parsed.postalCode,
  };
}

function addressIdentitiesMatch(
  lhs: NormalizedAddressIdentity | null,
  rhs: NormalizedAddressIdentity | null
): boolean {
  if (!lhs || !rhs) return false;
  if (lhs.primary !== rhs.primary) return false;
  if (lhs.postalCode && rhs.postalCode) {
    return lhs.postalCode === rhs.postalCode;
  }
  return true;
}

function duplicateAddressSortScore(row: DuplicateAddressRow): number {
  const source = row.source?.trim().toLowerCase();
  const sourceScore = source === "manual" ? 10 : 0;
  const linkScore = row.building_id || row.building_gers_id ? 0 : 1;
  return sourceScore + linkScore;
}

async function findExistingReverseGeocodedAddress(
  supabase: any,
  campaignId: string,
  input: {
    formatted: string;
    house_number: string | null;
    street_name: string | null;
    postal_code: string | null;
  }
): Promise<DuplicateAddressRow | null> {
  const targetIdentity = normalizedAddressIdentityParts(input);
  if (!targetIdentity) return null;

  const { data, error } = await supabase
    .from("campaign_addresses")
    .select(ADDRESS_SELECT)
    .eq("campaign_id", campaignId);

  if (error) {
    console.warn("[manual-address] duplicate lookup skipped:", error);
    return null;
  }

  const matches = ((data ?? []) as DuplicateAddressRow[])
    .filter((row) => addressIdentitiesMatch(
      targetIdentity,
      normalizedAddressIdentityParts({
        house_number: row.house_number,
        street_name: row.street_name,
        postal_code: row.postal_code,
        formatted: row.formatted,
      })
    ))
    .sort((lhs, rhs) => {
      const scoreDelta = duplicateAddressSortScore(lhs) - duplicateAddressSortScore(rhs);
      if (scoreDelta !== 0) return scoreDelta;
      return String(lhs.formatted ?? "").localeCompare(String(rhs.formatted ?? ""), undefined, { numeric: true });
    });

  return matches[0] ?? null;
}

async function attachAddressToBuilding(input: {
  supabase: any;
  campaignId: string;
  address: Record<string, unknown>;
  linkTarget: Awaited<ReturnType<typeof resolveCampaignBuilding>> | null;
  userId: string;
  longitude: number;
  latitude: number;
  confidence: number;
}): Promise<{ responseAddress: Record<string, unknown>; linkWarning: string | null }> {
  const { supabase, campaignId, address, linkTarget, userId, longitude, latitude, confidence } = input;
  let responseAddress = address;
  let linkWarning: string | null = null;

  if (!linkTarget) {
    return { responseAddress, linkWarning };
  }

  const addressId = String(address.id ?? "").trim();
  if (!addressId) {
    return { responseAddress, linkWarning: "address_id_missing" };
  }

  try {
    const linker = new StableLinkerService(supabase);
    const coordinate = [longitude, latitude] as [number, number];
    if (linkTarget.rowId) {
      await linker.assignAddressToBuilding({
        campaignId,
        addressId,
        buildingRowId: linkTarget.rowId,
        buildingPublicId: linkTarget.publicId,
        assignedBy: userId,
        coordinate,
        confidence,
      });
    } else {
      await linker.assignAddressToExternalBuilding({
        campaignId,
        addressId,
        buildingPublicId: linkTarget.publicId,
        assignedBy: userId,
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
    const linkPatch: Record<string, unknown> = {
      building_gers_id: linkTarget.publicId,
      match_source: "manual",
      confidence,
    };
    if (linkTarget.rowId) {
      linkPatch.building_id = linkTarget.rowId;
    }

    let patchResult = await supabase
      .from("campaign_addresses")
      .update(linkPatch)
      .eq("campaign_id", campaignId)
      .eq("id", addressId)
      .select(ADDRESS_SELECT)
      .maybeSingle();

    if (
      patchResult.error &&
      (isMissingColumnError(patchResult.error, "match_source") ||
        isMatchSourceConstraintError(patchResult.error))
    ) {
      delete linkPatch.match_source;
      patchResult = await supabase
        .from("campaign_addresses")
        .update(linkPatch)
        .eq("campaign_id", campaignId)
        .eq("id", addressId)
        .select(ADDRESS_SELECT)
        .maybeSingle();
    }

    if (patchResult.error && isMissingColumnError(patchResult.error, "confidence")) {
      delete linkPatch.confidence;
      patchResult = await supabase
        .from("campaign_addresses")
        .update(linkPatch)
        .eq("campaign_id", campaignId)
        .eq("id", addressId)
        .select(ADDRESS_SELECT)
        .maybeSingle();
    }

    if (patchResult.error) {
      linkWarning = "link_not_confirmed";
      console.warn("[manual-address] fallback link patch warning:", patchResult.error);
    } else if (patchResult.data) {
      responseAddress = patchResult.data;
      linkWarning = "link_table_not_confirmed";
    }
  }

  return { responseAddress, linkWarning };
}

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
    const userConfirmed = (body as { user_confirmed?: unknown }).user_confirmed !== false;
    const isReverseGeocodeConfirmed =
      userConfirmed && addressProvenance.toLowerCase().includes("reverse_geocode");
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
    const houseNumber = String((body as { house_number?: unknown }).house_number ?? "").trim() || null;
    const streetName = String((body as { street_name?: unknown }).street_name ?? "").trim() || null;
    const locality = String((body as { locality?: unknown }).locality ?? "").trim() || null;
    const region = String((body as { region?: unknown }).region ?? "").trim() || null;
    const postalCode = String((body as { postal_code?: unknown }).postal_code ?? "").trim() || null;
    const country = String((body as { country?: unknown }).country ?? "").trim() || null;

    if (isReverseGeocodeConfirmed) {
      const existingAddress = await findExistingReverseGeocodedAddress(
        supabase,
        campaignId,
        {
          formatted,
          house_number: houseNumber,
          street_name: streetName,
          postal_code: postalCode,
        }
      );

      if (existingAddress) {
        const { responseAddress, linkWarning } = await attachAddressToBuilding({
          supabase,
          campaignId,
          address: existingAddress as unknown as Record<string, unknown>,
          linkTarget,
          userId: user.id,
          longitude,
          latitude,
          confidence,
        });

        await invalidateCampaignMapBundle(supabase, campaignId);

        return NextResponse.json({
          address: responseAddress,
          linked_building_id: linkTarget?.publicId ?? null,
          link_warning: linkWarning,
          resolved_existing_address: true,
        });
      }
    }

    const addressInsert: Record<string, unknown> = {
      ...(requestedAddressId ? { id: requestedAddressId } : {}),
      campaign_id: campaignId,
      house_number: houseNumber,
      street_name: streetName,
      locality,
      region,
      postal_code: postalCode,
      country,
      formatted,
      source: "manual",
      building_gers_id: null,
      ...(isReverseGeocodeConfirmed ? { confidence } : {}),
      geom: pointEWKT(longitude, latitude),
    };
    const { data: insertedAddress, error: insertError } = requestedAddressId
      ? await writeManualAddress(supabase, addressInsert, "upsert")
      : await writeManualAddress(supabase, addressInsert, "insert");

    if (insertError || !insertedAddress) {
      console.error("[manual-address] insert error:", insertError);
      return NextResponse.json(
        { error: "Failed to create manual address" },
        { status: 500 }
      );
    }

    const { responseAddress, linkWarning } = await attachAddressToBuilding({
      supabase,
      campaignId,
      address: insertedAddress as Record<string, unknown>,
      linkTarget,
      userId: user.id,
      longitude,
      latitude,
      confidence,
    });

    await invalidateCampaignMapBundle(supabase, campaignId);

    return NextResponse.json({
      address: responseAddress,
      linked_building_id: linkTarget?.publicId ?? null,
      link_warning: linkWarning,
    });
  } catch (error) {
    console.error("[manual-address] POST error:", error);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}
