import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

type WorkspaceMembership = {
  workspace_id: string;
  role?: string | null;
  created_at?: string | null;
};

type WorkspaceBilling = {
  id: string;
  subscription_status?: string | null;
  trial_ends_at?: string | null;
};

function roleRank(role: string | null | undefined): number {
  if (role === "owner") return 0;
  if (role === "admin") return 1;
  if (role === "member") return 2;
  return 3;
}

function workspaceHasAccess(workspace: WorkspaceBilling | null): boolean {
  if (!workspace) return false;
  const status = (workspace.subscription_status ?? "").toLowerCase();
  if (status === "active") return true;
  if (status !== "trialing") return false;
  if (!workspace.trial_ends_at) return true;
  const trialEnd = new Date(workspace.trial_ends_at);
  return !Number.isNaN(trialEnd.getTime()) && trialEnd > new Date();
}

async function resolvePrimaryWorkspaceBilling(
  supabaseAdmin: any,
  userId: string
): Promise<WorkspaceBilling | null> {
  const { data: ownedWorkspace } = await supabaseAdmin
    .from("workspaces")
    .select("id,subscription_status,trial_ends_at")
    .eq("owner_id", userId)
    .order("created_at", { ascending: true })
    .limit(1)
    .maybeSingle();

  const primaryOwnedWorkspace = (ownedWorkspace as WorkspaceBilling | null) ?? null;
  if (primaryOwnedWorkspace?.id) return primaryOwnedWorkspace;

  const { data: memberships } = await supabaseAdmin
    .from("workspace_members")
    .select("workspace_id,role,created_at")
    .eq("user_id", userId);

  const sorted = ((memberships ?? []) as WorkspaceMembership[])
    .filter((row) => !!row.workspace_id)
    .sort((a, b) => {
      const byRole = roleRank(a.role) - roleRank(b.role);
      if (byRole !== 0) return byRole;
      const aTime = a.created_at ? new Date(a.created_at).getTime() : 0;
      const bTime = b.created_at ? new Date(b.created_at).getTime() : 0;
      return aTime - bTime;
    });

  const primaryWorkspaceId = sorted[0]?.workspace_id;
  if (!primaryWorkspaceId) return null;

  const { data: workspace } = await supabaseAdmin
    .from("workspaces")
    .select("id,subscription_status,trial_ends_at")
    .eq("id", primaryWorkspaceId)
    .maybeSingle();

  return (workspace as WorkspaceBilling | null) ?? null;
}

/** GET /api/billing/entitlement — Always return an entitlement (create default free row if none). */
export async function GET(request: Request) {
  try {
    const authHeader = request.headers.get("authorization");
    const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
    if (!token) {
      return NextResponse.json(
        { plan: "free", is_active: false, source: "none", current_period_end: null },
        { status: 200 }
      );
    }

    const supabaseAnon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    const {
      data: { user },
      error: userError,
    } = await supabaseAnon.auth.getUser(token);
    if (userError || !user) {
      return NextResponse.json(
        { plan: "free", is_active: false, source: "none", current_period_end: null },
        { status: 200 }
      );
    }

    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { data: existing, error: selectError } = await supabaseAdmin
      .from("entitlements")
      .select("plan, is_active, source, current_period_end, updated_at")
      .eq("user_id", user.id)
      .maybeSingle();

    if (selectError) {
      console.error("[billing/entitlement] select error:", selectError);
      return NextResponse.json(
        { plan: "free", is_active: false, source: "none", current_period_end: null },
        { status: 200 }
      );
    }

    if (existing) {
      const workspace = await resolvePrimaryWorkspaceBilling(supabaseAdmin, user.id);
      return NextResponse.json({
        plan: existing.plan,
        is_active: workspace ? workspaceHasAccess(workspace) : existing.is_active,
        source: existing.source,
        current_period_end: existing.current_period_end ?? null,
      });
    }

    // No row: create default free row and return it
    const { data: inserted, error: insertError } = await supabaseAdmin
      .from("entitlements")
      .insert({
        user_id: user.id,
        plan: "free",
        is_active: false,
        source: "none",
        current_period_end: null,
        updated_at: new Date().toISOString(),
      })
      .select("plan, is_active, source, current_period_end")
      .single();

    if (insertError || !inserted) {
      console.error("[billing/entitlement] insert error:", insertError);
      return NextResponse.json(
        { plan: "free", is_active: false, source: "none", current_period_end: null },
        { status: 200 }
      );
    }

    const workspace = await resolvePrimaryWorkspaceBilling(supabaseAdmin, user.id);
    return NextResponse.json({
      plan: inserted.plan,
      is_active: workspace ? workspaceHasAccess(workspace) : inserted.is_active,
      source: inserted.source,
      current_period_end: inserted.current_period_end ?? null,
    });
  } catch (err) {
    console.error("[billing/entitlement]", err);
    return NextResponse.json(
      { plan: "free", is_active: false, source: "none", current_period_end: null },
      { status: 200 }
    );
  }
}
