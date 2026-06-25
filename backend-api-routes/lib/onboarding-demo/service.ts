import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import {
  getSupabaseServiceRoleKey,
  getSupabaseUrl,
} from "@/lib/supabase/env";

export type DemoRolePath = "solo_owner" | "team_owner" | "member";

type AccessWorkspace = {
  id: string;
  owner_id?: string | null;
};

type AccessContextLike = {
  user: { id: string };
  workspace: AccessWorkspace | null;
  role: string | null;
};

export type DemoStatePayload = {
  workspace_id: string | null;
  workspaceId: string | null;
  user_id: string;
  userId: string;
  role_path: DemoRolePath;
  rolePath: DemoRolePath;
  seeded_campaign_id: string | null;
  seededCampaignId: string | null;
  dismissed_at: string | null;
  dismissedAt: string | null;
  completed_checklist_items: string[];
  completedChecklistItems: string[];
  has_assigned_work: boolean;
  hasAssignedWork: boolean;
  can_seed: boolean;
  canSeed: boolean;
  seed_skipped_reason: string | null;
  seedSkippedReason: string | null;
};

export type DemoSeedPayload = {
  seeded: boolean;
  skipped: boolean;
  reason: string | null;
  campaign_id: string | null;
  campaignId: string | null;
  state: DemoStatePayload;
};

const STARTER_CAMPAIGN_NAME = "Sugar House Starter Farm";
const DEMO_TAG = "onboarding_demo_starter";
const DEMO_MARKER = "[onboarding-demo:sugar-house-starter-farm]";

const STARTER_POLYGON = {
  type: "Polygon",
  coordinates: [[
    [-111.86485, 40.72745],
    [-111.84785, 40.72745],
    [-111.84785, 40.71415],
    [-111.86485, 40.71415],
    [-111.86485, 40.72745],
  ]],
};

const STARTER_ADDRESSES = [
  ["1111 E Hollywood Ave, Salt Lake City, UT 84105", "84105", -111.86091, 40.72471],
  ["1128 E Hollywood Ave, Salt Lake City, UT 84105", "84105", -111.85951, 40.72468],
  ["1164 E Hollywood Ave, Salt Lake City, UT 84105", "84105", -111.85792, 40.72466],
  ["1198 E Hollywood Ave, Salt Lake City, UT 84105", "84105", -111.85632, 40.72464],
  ["1135 E Ramona Ave, Salt Lake City, UT 84105", "84105", -111.85913, 40.72236],
  ["1177 E Ramona Ave, Salt Lake City, UT 84105", "84105", -111.85715, 40.72234],
  ["1215 E Ramona Ave, Salt Lake City, UT 84105", "84105", -111.85532, 40.72232],
  ["1136 E Wilson Ave, Salt Lake City, UT 84105", "84105", -111.85894, 40.71998],
  ["1174 E Wilson Ave, Salt Lake City, UT 84105", "84105", -111.85721, 40.71995],
  ["1212 E Wilson Ave, Salt Lake City, UT 84105", "84105", -111.85542, 40.71992],
  ["1117 E Garfield Ave, Salt Lake City, UT 84105", "84105", -111.86069, 40.71755],
  ["1169 E Garfield Ave, Salt Lake City, UT 84105", "84105", -111.85808, 40.71752],
  ["1219 E Garfield Ave, Salt Lake City, UT 84105", "84105", -111.85572, 40.71749],
  ["1265 E Garfield Ave, Salt Lake City, UT 84105", "84105", -111.85338, 40.71745],
] as const;

const STATUS_PATTERN = [
  "delivered",
  "no_answer",
  "talked",
  "future_seller",
  "hot_lead",
  "appointment",
  "delivered",
  "talked",
] as const;

function adminClient() {
  return createClient(getSupabaseUrl(), getSupabaseServiceRoleKey(), {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

function nowIso(offsetHours = 0): string {
  return new Date(Date.now() + offsetHours * 60 * 60 * 1000).toISOString();
}

function formatError(error: unknown): string {
  if (!error) return "Unknown error";
  if (error instanceof Error) return error.message;
  if (typeof error === "string") return error;
  const candidate = error as { message?: string; details?: string | null; hint?: string | null; code?: string | null };
  return [candidate.message, candidate.details, candidate.hint, candidate.code].filter(Boolean).join(" | ") || "Unknown error";
}

function isMissingColumnError(error: unknown, column: string): boolean {
  const message = formatError(error).toLowerCase();
  return (
    message.includes(`could not find the '${column}' column`) ||
    message.includes(`column ${column}`) ||
    message.includes(`${column} does not exist`) ||
    (message.includes("schema cache") && message.includes(column.toLowerCase()))
  );
}

function isMissingRelationError(error: unknown): boolean {
  const message = formatError(error).toLowerCase();
  return message.includes("does not exist") || message.includes("could not find") || message.includes("schema cache");
}

function removeMissingColumn(payload: Record<string, unknown>, error: unknown): boolean {
  for (const column of Object.keys(payload)) {
    if (isMissingColumnError(error, column)) {
      delete payload[column];
      return true;
    }
  }
  return false;
}

function roleRank(role: string | null | undefined): number {
  if (role === "owner") return 0;
  if (role === "admin") return 1;
  if (role === "member") return 2;
  return 3;
}

function canSeed(role: string | null | undefined): boolean {
  return role === "owner" || role === "admin";
}

async function inferRolePath(
  supabase: SupabaseClient,
  workspaceId: string | null,
  userId: string,
  role: string | null
): Promise<DemoRolePath> {
  if (!canSeed(role)) return "member";
  if (!workspaceId) return "solo_owner";

  const { count } = await supabase
    .from("workspace_members")
    .select("user_id", { count: "exact", head: true })
    .eq("workspace_id", workspaceId)
    .neq("user_id", userId);

  return (count ?? 0) > 0 ? "team_owner" : "solo_owner";
}

async function hasAssignedWork(supabase: SupabaseClient, workspaceId: string | null, userId: string): Promise<boolean> {
  if (!workspaceId) return false;

  const assignmentTables = ["route_assignments", "campaign_assignments"] as const;
  for (const table of assignmentTables) {
    try {
      const { count, error } = await supabase
        .from(table)
        .select("id", { count: "exact", head: true })
        .eq("workspace_id", workspaceId)
        .eq("assigned_to_user_id", userId);
      if (error) {
        if (isMissingRelationError(error)) continue;
        continue;
      }
      if ((count ?? 0) > 0) return true;
    } catch {}
  }

  return false;
}

async function getCampaignCount(supabase: SupabaseClient, workspaceId: string): Promise<number> {
  const { count, error } = await supabase
    .from("campaigns")
    .select("id", { count: "exact", head: true })
    .eq("workspace_id", workspaceId);

  if (error) throw new Error(formatError(error));
  return count ?? 0;
}

async function findStarterCampaign(supabase: SupabaseClient, workspaceId: string): Promise<string | null> {
  const { data, error } = await supabase
    .from("campaigns")
    .select("id,description,tags,name,title")
    .eq("workspace_id", workspaceId)
    .or(`description.ilike.%${DEMO_MARKER}%,tags.ilike.%${DEMO_TAG}%,name.eq.${STARTER_CAMPAIGN_NAME},title.eq.${STARTER_CAMPAIGN_NAME}`)
    .order("created_at", { ascending: true })
    .limit(1);

  if (error) return null;
  const row = Array.isArray(data) ? data[0] as { id?: string } | undefined : undefined;
  return row?.id ?? null;
}

async function upsertState(
  supabase: SupabaseClient,
  context: AccessContextLike,
  rolePath: DemoRolePath,
  patch: Record<string, unknown> = {}
) {
  if (!context.workspace?.id) return null;
  const payload = {
    workspace_id: context.workspace.id,
    user_id: context.user.id,
    role_path: rolePath,
    ...patch,
  };
  const { data, error } = await supabase
    .from("onboarding_demo_states")
    .upsert(payload, { onConflict: "workspace_id,user_id" })
    .select()
    .single();
  if (error) throw new Error(formatError(error));
  return data as Record<string, unknown>;
}

async function loadRawState(supabase: SupabaseClient, workspaceId: string, userId: string) {
  const { data, error } = await supabase
    .from("onboarding_demo_states")
    .select("*")
    .eq("workspace_id", workspaceId)
    .eq("user_id", userId)
    .maybeSingle();
  if (error) throw new Error(formatError(error));
  return data as Record<string, unknown> | null;
}

function toPayload(
  raw: Record<string, unknown> | null,
  context: AccessContextLike,
  rolePath: DemoRolePath,
  assignedWork: boolean,
  seedSkippedReason: string | null = null
): DemoStatePayload {
  const workspaceId = context.workspace?.id ?? null;
  const completed = Array.isArray(raw?.completed_checklist_items)
    ? (raw?.completed_checklist_items as unknown[]).filter((item): item is string => typeof item === "string")
    : [];
  const seededCampaignId = typeof raw?.seeded_campaign_id === "string" ? raw.seeded_campaign_id : null;
  const dismissedAt = typeof raw?.dismissed_at === "string" ? raw.dismissed_at : null;

  return {
    workspace_id: workspaceId,
    workspaceId,
    user_id: context.user.id,
    userId: context.user.id,
    role_path: rolePath,
    rolePath,
    seeded_campaign_id: seededCampaignId,
    seededCampaignId,
    dismissed_at: dismissedAt,
    dismissedAt,
    completed_checklist_items: completed,
    completedChecklistItems: completed,
    has_assigned_work: assignedWork,
    hasAssignedWork: assignedWork,
    can_seed: canSeed(context.role),
    canSeed: canSeed(context.role),
    seed_skipped_reason: seedSkippedReason,
    seedSkippedReason,
  };
}

export async function loadDemoState(context: AccessContextLike): Promise<DemoStatePayload> {
  const supabase = adminClient();
  const rolePath = await inferRolePath(supabase, context.workspace?.id ?? null, context.user.id, context.role);
  const assigned = await hasAssignedWork(supabase, context.workspace?.id ?? null, context.user.id);
  if (!context.workspace?.id) {
    return toPayload(null, context, rolePath, assigned, "no-workspace");
  }

  let raw = await loadRawState(supabase, context.workspace.id, context.user.id);
  if (!raw) {
    raw = await upsertState(supabase, context, rolePath);
  } else if (raw.role_path !== rolePath) {
    raw = await upsertState(supabase, context, rolePath, {
      completed_checklist_items: raw.completed_checklist_items ?? [],
      seeded_campaign_id: raw.seeded_campaign_id ?? null,
      dismissed_at: raw.dismissed_at ?? null,
    });
  }

  return toPayload(raw, context, rolePath, assigned);
}

export async function patchDemoState(
  context: AccessContextLike,
  patch: { dismissed?: boolean; completedChecklistItems?: string[]; completed_checklist_items?: string[] }
): Promise<DemoStatePayload> {
  const supabase = adminClient();
  if (!context.workspace?.id) {
    throw new Error("Workspace required.");
  }

  const rolePath = await inferRolePath(supabase, context.workspace.id, context.user.id, context.role);
  const updates: Record<string, unknown> = { role_path: rolePath };

  if (typeof patch.dismissed === "boolean") {
    updates.dismissed_at = patch.dismissed ? nowIso() : null;
  }

  const completed = patch.completedChecklistItems ?? patch.completed_checklist_items;
  if (Array.isArray(completed)) {
    updates.completed_checklist_items = Array.from(new Set(completed.filter((item) => typeof item === "string" && item.trim()).map((item) => item.trim())));
  }

  const raw = await upsertState(supabase, context, rolePath, updates);
  const assigned = await hasAssignedWork(supabase, context.workspace.id, context.user.id);
  return toPayload(raw, context, rolePath, assigned);
}

async function insertCampaign(supabase: SupabaseClient, context: AccessContextLike, workspaceId: string) {
  const payload: Record<string, unknown> = {
    owner_id: context.workspace?.owner_id ?? context.user.id,
    workspace_id: workspaceId,
    name: STARTER_CAMPAIGN_NAME,
    title: STARTER_CAMPAIGN_NAME,
    description: `${DEMO_MARKER}\nEditable starter data for learning campaign maps, statuses, leads, QR interest, and sessions.`,
    tags: DEMO_TAG,
    type: "flyer",
    address_source: "map",
    region: "Salt Lake City / Sugar House, Utah",
    bbox: [-111.86485, 40.71415, -111.84785, 40.72745],
    territory_boundary: STARTER_POLYGON,
    total_flyers: STARTER_ADDRESSES.length,
    scans: 23,
    conversions: 4,
    status: "active",
    provision_status: "ready",
    provision_phase: "ready",
    addresses_ready_at: nowIso(),
    map_ready_at: nowIso(),
    map_mode: "standard_pins",
  };

  for (;;) {
    const { data, error } = await supabase.from("campaigns").insert(payload).select("id").single();
    if (!error && data?.id) return data.id as string;
    if (!removeMissingColumn(payload, error)) {
      throw new Error(formatError(error));
    }
  }
}

async function ensureAddresses(supabase: SupabaseClient, campaignId: string) {
  const { count } = await supabase
    .from("campaign_addresses")
    .select("id", { count: "exact", head: true })
    .eq("campaign_id", campaignId);
  if ((count ?? 0) > 0) return;

  const rpcAddresses = STARTER_ADDRESSES.map(([formatted, postalCode, lon, lat], index) => ({
    formatted,
    postal_code: postalCode,
    source: "onboarding_demo",
    seq: index + 1,
    visited: index < STATUS_PATTERN.length,
    lon,
    lat,
  }));

  const rpc = await supabase.rpc("add_campaign_addresses", {
    p_campaign_id: campaignId,
    p_addresses: rpcAddresses,
  });
  if (!rpc.error) return;

  const rows = STARTER_ADDRESSES.map(([formatted, postalCode, lon, lat], index) => ({
    campaign_id: campaignId,
    formatted,
    postal_code: postalCode,
    source: "onboarding_demo",
    seq: index + 1,
    visited: index < STATUS_PATTERN.length,
    geom: `POINT(${lon} ${lat})`,
  }));

  const { error } = await supabase.from("campaign_addresses").insert(rows);
  if (!error) return;

  const withoutGeom = rows.map(({ geom: _geom, ...row }) => row);
  const fallback = await supabase.from("campaign_addresses").insert(withoutGeom);
  if (fallback.error) throw new Error(formatError(fallback.error));
}

async function fetchStarterAddresses(supabase: SupabaseClient, campaignId: string) {
  const { data, error } = await supabase
    .from("campaign_addresses")
    .select("id,formatted")
    .eq("campaign_id", campaignId)
    .order("seq", { ascending: true });
  if (error) throw new Error(formatError(error));
  return (data ?? []) as { id: string; formatted: string }[];
}

async function ensureStatuses(supabase: SupabaseClient, campaignId: string, userId: string, addresses: { id: string }[]) {
  const statusRows = addresses.slice(0, STATUS_PATTERN.length).map((address, index) => ({
    campaign_id: campaignId,
    campaign_address_id: address.id,
    user_id: userId,
    status: STATUS_PATTERN[index],
    last_visited_at: nowIso(-(48 - index * 4)),
    notes: index === 4 ? "Asked for a valuation follow-up." : null,
    visit_count: index === 5 ? 2 : 1,
  }));
  if (!statusRows.length) return;

  let { error } = await supabase
    .from("address_statuses")
    .upsert(statusRows, { onConflict: "campaign_address_id" });
  if (!error) return;

  const legacyRows = statusRows.map(({ campaign_address_id, ...row }) => ({
    ...row,
    address_id: campaign_address_id,
  }));
  const legacy = await supabase
    .from("address_statuses")
    .upsert(legacyRows, { onConflict: "address_id,campaign_id" });
  if (legacy.error) throw new Error(formatError(legacy.error));
}

async function ensureContacts(supabase: SupabaseClient, campaignId: string, workspaceId: string, userId: string, addresses: { id: string; formatted: string }[]) {
  const { count } = await supabase
    .from("contacts")
    .select("id", { count: "exact", head: true })
    .eq("campaign_id", campaignId);
  if ((count ?? 0) > 0) return;

  const contacts = [
    {
      user_id: userId,
      workspace_id: workspaceId,
      campaign_id: campaignId,
      address_id: addresses[4]?.id,
      full_name: "Maya Jensen",
      phone: "+1 801-555-0142",
      email: "maya.jensen@example.com",
      address: addresses[4]?.formatted ?? "Sugar House, Salt Lake City, UT",
      status: "hot",
      notes: "Sample hot lead from the starter farm. Interested in a spring listing estimate.",
      last_contacted: nowIso(-18),
      reminder_date: nowIso(48),
    },
    {
      user_id: userId,
      workspace_id: workspaceId,
      campaign_id: campaignId,
      address_id: addresses[5]?.id,
      full_name: "Chris Navarro",
      phone: "+1 801-555-0188",
      address: addresses[5]?.formatted ?? "Sugar House, Salt Lake City, UT",
      status: "warm",
      notes: "Sample future seller. Follow up after the weekend.",
      last_contacted: nowIso(-28),
      reminder_date: nowIso(72),
    },
    {
      user_id: userId,
      workspace_id: workspaceId,
      campaign_id: campaignId,
      address_id: addresses[2]?.id,
      full_name: "QR Scan Interest",
      address: addresses[2]?.formatted ?? "Sugar House, Salt Lake City, UT",
      status: "warm",
      notes: "Sample lead representing QR activity on a printed flyer.",
      last_contacted: nowIso(-6),
    },
  ];

  let payload = contacts.map((row) => ({ ...row }));
  for (;;) {
    const { error } = await supabase.from("contacts").insert(payload);
    if (!error) return;
    let removed = false;
    payload = payload.map((row) => {
      const copy: Record<string, unknown> = { ...row };
      if (removeMissingColumn(copy, error)) removed = true;
      return copy as typeof row;
    });
    if (!removed) throw new Error(formatError(error));
  }
}

async function ensureSessions(supabase: SupabaseClient, campaignId: string, workspaceId: string, userId: string) {
  const { count } = await supabase
    .from("sessions")
    .select("id", { count: "exact", head: true })
    .eq("campaign_id", campaignId);
  if ((count ?? 0) > 0) return;

  const path = JSON.stringify({
    type: "LineString",
    coordinates: [
      [-111.86091, 40.72471],
      [-111.85894, 40.71998],
      [-111.85572, 40.71749],
    ],
  });
  const sessions = [
    {
      user_id: userId,
      workspace_id: workspaceId,
      campaign_id: campaignId,
      start_time: nowIso(-44),
      end_time: nowIso(-43),
      distance_meters: 1260,
      goal_type: "flyers",
      goal_amount: 40,
      path_geojson: path,
      doors_hit: 8,
      completed_count: 8,
      flyers_delivered: 8,
      conversations: 3,
      leads_created: 2,
      active_seconds: 3120,
      session_mode: "flyer",
      notes: "Sample completed starter session.",
    },
    {
      user_id: userId,
      workspace_id: workspaceId,
      campaign_id: campaignId,
      start_time: nowIso(-20),
      end_time: nowIso(-19),
      distance_meters: 920,
      goal_type: "knocks",
      goal_amount: 20,
      path_geojson: path,
      doors_hit: 6,
      completed_count: 6,
      flyers_delivered: 4,
      conversations: 2,
      leads_created: 1,
      active_seconds: 2460,
      session_mode: "door_knocking",
      notes: "Sample follow-up door knock.",
    },
  ];

  let payload = sessions.map((row) => ({ ...row }));
  for (;;) {
    const { error } = await supabase.from("sessions").insert(payload);
    if (!error) return;
    let removed = false;
    payload = payload.map((row) => {
      const copy: Record<string, unknown> = { ...row };
      if (removeMissingColumn(copy, error)) removed = true;
      return copy as typeof row;
    });
    if (!removed) throw new Error(formatError(error));
  }
}

async function seedStarterCampaign(supabase: SupabaseClient, context: AccessContextLike, workspaceId: string): Promise<string> {
  const existingStarter = await findStarterCampaign(supabase, workspaceId);
  const campaignId = existingStarter ?? await insertCampaign(supabase, context, workspaceId);

  await ensureAddresses(supabase, campaignId);
  const addresses = await fetchStarterAddresses(supabase, campaignId);
  await ensureStatuses(supabase, campaignId, context.user.id, addresses);
  await ensureContacts(supabase, campaignId, workspaceId, context.user.id, addresses);
  await ensureSessions(supabase, campaignId, workspaceId, context.user.id);

  return campaignId;
}

export async function seedDemo(context: AccessContextLike): Promise<DemoSeedPayload> {
  const supabase = adminClient();
  const rolePath = await inferRolePath(supabase, context.workspace?.id ?? null, context.user.id, context.role);
  if (!context.workspace?.id) {
    throw new Error("Workspace required.");
  }
  if (!canSeed(context.role)) {
    const state = await loadDemoState(context);
    return { seeded: false, skipped: true, reason: "forbidden", campaign_id: null, campaignId: null, state };
  }

  const workspaceId = context.workspace.id;
  const existingState = await loadRawState(supabase, workspaceId, context.user.id);
  if (typeof existingState?.seeded_campaign_id === "string") {
    const state = toPayload(existingState, context, rolePath, await hasAssignedWork(supabase, workspaceId, context.user.id));
    return {
      seeded: false,
      skipped: false,
      reason: "already_seeded",
      campaign_id: existingState.seeded_campaign_id,
      campaignId: existingState.seeded_campaign_id,
      state,
    };
  }

  const starterCampaignId = await findStarterCampaign(supabase, workspaceId);
  if (starterCampaignId) {
    const raw = await upsertState(supabase, context, rolePath, { seeded_campaign_id: starterCampaignId });
    const state = toPayload(raw, context, rolePath, await hasAssignedWork(supabase, workspaceId, context.user.id));
    return { seeded: false, skipped: false, reason: "starter_exists", campaign_id: starterCampaignId, campaignId: starterCampaignId, state };
  }

  const campaignCount = await getCampaignCount(supabase, workspaceId);
  if (campaignCount > 0) {
    const raw = await upsertState(supabase, context, rolePath);
    const state = toPayload(raw, context, rolePath, await hasAssignedWork(supabase, workspaceId, context.user.id), "workspace_has_campaigns");
    return { seeded: false, skipped: true, reason: "workspace_has_campaigns", campaign_id: null, campaignId: null, state };
  }

  const campaignId = await seedStarterCampaign(supabase, context, workspaceId);
  const raw = await upsertState(supabase, context, rolePath, { seeded_campaign_id: campaignId });
  const state = toPayload(raw, context, rolePath, await hasAssignedWork(supabase, workspaceId, context.user.id));
  return { seeded: true, skipped: false, reason: null, campaign_id: campaignId, campaignId, state };
}
