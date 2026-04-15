import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;
const SUPABASE_ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

function adminClient() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
}

function anonClient() {
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
}

type CreateFarmBody = {
  name?: string;
  description?: string;
  polygon?: string;
  start_date?: string;
  end_date?: string;
  frequency?: number;
  touches_per_interval?: number | null;
  touches_interval?: string | null;
  goal_type?: string | null;
  goal_target?: number | null;
  cycle_completion_window_days?: number | null;
  touch_types?: string[] | null;
  annual_budget_cents?: number | null;
  workspace_id?: string | null;
  area_label?: string | null;
  home_limit?: number | null;
  address_count?: number | null;
};

type GeoJSONPolygon = {
  type: "Polygon";
  coordinates: number[][][];
};

function formatError(error: unknown): string {
  if (!error) return "Unknown error";
  if (typeof error === "string") return error;
  if (error instanceof Error) return error.message;
  const candidate = error as { message?: string; details?: string | null; hint?: string | null };
  return [candidate.message, candidate.details, candidate.hint].filter(Boolean).join(" | ") || "Unknown error";
}

function isMissingFarmColumnError(error: unknown, column: string): boolean {
  const message = formatError(error).toLowerCase();
  return (
    message.includes(`could not find the '${column}' column`) ||
    message.includes(`column farms.${column}`) ||
    message.includes(`${column} does not exist`)
  );
}

function parseFarmPolygon(rawPolygon: string | undefined): GeoJSONPolygon | null {
  if (!rawPolygon?.trim()) return null;

  try {
    const parsed = JSON.parse(rawPolygon) as GeoJSONPolygon;
    if (parsed?.type === "Polygon" && Array.isArray(parsed.coordinates)) {
      return parsed;
    }
  } catch {}

  return null;
}

function computeBBox(polygon: GeoJSONPolygon): [number, number, number, number] {
  const ring = polygon.coordinates[0] ?? [];
  let minLon = Infinity;
  let minLat = Infinity;
  let maxLon = -Infinity;
  let maxLat = -Infinity;

  for (const point of ring) {
    const [lon, lat] = point;
    if (!Number.isFinite(lon) || !Number.isFinite(lat)) continue;
    minLon = Math.min(minLon, lon);
    minLat = Math.min(minLat, lat);
    maxLon = Math.max(maxLon, lon);
    maxLat = Math.max(maxLat, lat);
  }

  if (!Number.isFinite(minLon) || !Number.isFinite(minLat) || !Number.isFinite(maxLon) || !Number.isFinite(maxLat)) {
    return [0, 0, 0, 0];
  }

  return [minLon, minLat, maxLon, maxLat];
}

async function resolveWorkspaceId(admin: ReturnType<typeof adminClient>, userId: string, requestedWorkspaceId?: string | null) {
  if (requestedWorkspaceId?.trim()) {
    const { data: membership } = await admin
      .from("workspace_members")
      .select("workspace_id")
      .eq("workspace_id", requestedWorkspaceId.trim())
      .eq("user_id", userId)
      .maybeSingle();
    if (membership?.workspace_id) return membership.workspace_id as string;
  }

  const { data: memberships } = await admin
    .from("workspace_members")
    .select("workspace_id")
    .eq("user_id", userId)
    .limit(1);

  return Array.isArray(memberships) && memberships[0]?.workspace_id ? memberships[0].workspace_id as string : null;
}

function buildFarmCampaignDescription(farmId: string, farmDescription?: string | null): string {
  const marker = `[farm:${farmId}]`;
  const description = farmDescription?.trim();
  return description ? `${marker}\n${description}` : marker;
}

async function persistLinkedCampaignIdIfPossible(
  admin: ReturnType<typeof adminClient>,
  farmId: string,
  campaignId: string
) {
  const { error } = await admin
    .from("farms")
    .update({ linked_campaign_id: campaignId })
    .eq("id", farmId);

  if (error && !isMissingFarmColumnError(error, "linked_campaign_id")) {
    throw new Error(formatError(error));
  }
}

export async function POST(request: Request): Promise<Response> {
  const admin = adminClient();

  const authHeader = request.headers.get("authorization");
  const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
  if (!token) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const {
    data: { user },
    error: userError,
  } = await anonClient().auth.getUser(token);

  if (userError || !user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  let body: CreateFarmBody;
  try {
    body = (await request.json()) as CreateFarmBody;
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const polygon = parseFarmPolygon(body.polygon);
  if (!body.name?.trim() || !polygon || !body.start_date || !body.end_date || !body.frequency) {
    return NextResponse.json(
      { error: "name, polygon, start_date, end_date, and frequency are required" },
      { status: 400 }
    );
  }

  const workspaceId = await resolveWorkspaceId(admin, user.id, body.workspace_id);
  const bbox = computeBBox(polygon);
  const boundedHomeLimit = Math.min(5000, Math.max(1, Number(body.home_limit ?? 5000) || 5000));

  const farmInsert: Record<string, unknown> = {
    owner_id: user.id,
    workspace_id: workspaceId,
    name: body.name.trim(),
    description: body.description?.trim() || null,
    polygon: JSON.stringify(polygon),
    start_date: body.start_date,
    end_date: body.end_date,
    frequency: body.frequency,
    is_active: true,
    touches_per_interval: body.touches_per_interval ?? body.frequency,
    touches_interval: body.touches_interval ?? "month",
    goal_type: body.goal_type ?? ((body.touches_interval ?? "month") === "year" ? "touches_per_year" : "touches_per_cycle"),
    goal_target: body.goal_target ?? body.touches_per_interval ?? body.frequency,
    cycle_completion_window_days: body.cycle_completion_window_days ?? null,
    touch_types: body.touch_types ?? [],
    annual_budget_cents: body.annual_budget_cents ?? null,
    area_label: body.area_label ?? null,
    home_limit: boundedHomeLimit,
    address_count: body.address_count ?? 0,
  };

  const removableColumns = [
    "workspace_id",
    "description",
    "is_active",
    "touches_per_interval",
    "touches_interval",
    "goal_type",
    "goal_target",
    "cycle_completion_window_days",
    "touch_types",
    "annual_budget_cents",
    "home_limit",
    "address_count",
  ] as const;

  let { data: farm, error: farmError } = await admin
    .from("farms")
    .insert(farmInsert)
    .select()
    .single();

  while (farmError) {
    const missingColumn = removableColumns.find(
      (column) => column in farmInsert && isMissingFarmColumnError(farmError, column)
    );
    if (!missingColumn) break;
    delete farmInsert[missingColumn];
    const retry = await admin.from("farms").insert(farmInsert).select().single();
    farm = retry.data;
    farmError = retry.error;
  }

  if (farmError || !farm) {
    return NextResponse.json(
      { error: farmError ? formatError(farmError) : "Failed to create farm" },
      { status: 500 }
    );
  }

  const { data: campaign, error: campaignError } = await admin
    .from("campaigns")
    .insert({
      owner_id: user.id,
      workspace_id: workspaceId,
      name: body.name.trim(),
      title: body.name.trim(),
      description: buildFarmCampaignDescription((farm as { id: string }).id, body.description),
      type: "flyer",
      address_source: "map",
      bbox,
      territory_boundary: polygon,
      total_flyers: 0,
      scans: 0,
      conversions: 0,
      status: "draft",
    })
    .select("id")
    .single();

  if (campaignError || !campaign) {
    return NextResponse.json(
      { error: campaignError ? formatError(campaignError) : "Failed to create linked campaign" },
      { status: 500 }
    );
  }

  try {
    await persistLinkedCampaignIdIfPossible(admin, (farm as { id: string }).id, campaign.id as string);
  } catch (error) {
    return NextResponse.json({ error: formatError(error) }, { status: 500 });
  }

  return NextResponse.json({
    ...farm,
    linked_campaign_id: campaign.id,
  });
}
