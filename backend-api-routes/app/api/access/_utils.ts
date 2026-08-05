import { createClient } from "@supabase/supabase-js";
import { type NextRequest } from "next/server";
import { resolveUserFromRequest, type RequestUser } from "@/app/api/_utils/request-user";
import {
  getSupabaseServiceRoleKey,
  getSupabaseUrl,
} from "@/lib/supabase/env";

type WorkspaceMembership = {
  workspace_id: string;
  role?: string | null;
  created_at?: string | null;
};

type WorkspaceRow = {
  id: string;
  name?: string | null;
  industry?: string | null;
  owner_id?: string | null;
  subscription_status?: string | null;
  trial_ends_at?: string | null;
  created_at?: string | null;
};

type ResolveAccessContextOptions = {
  workspaceId?: string | null;
};

export type AccessContext = {
  user: RequestUser;
  workspace: WorkspaceRow | null;
  role: string | null;
  hasAccess: boolean;
  reason: string | null;
};

export type AccessStatePayload = {
  user_id: string;
  userId: string;
  role: string | null;
  name: string | null;
  workspaceName: string | null;
  industry: string | null;
  workspace_id: string | null;
  workspaceId: string | null;
  accessLevel: string | null;
  dashboardMode: string | null;
  salespersonId: string | null;
  salesperson: { id: string } | null;
  isSalesperson: boolean;
  canUseSalespersonDashboard: boolean;
  has_access: boolean;
  hasAccess: boolean;
  reason: string | null;
};

function adminClient() {
  return createClient(getSupabaseUrl(), getSupabaseServiceRoleKey(), {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

function roleRank(role: string | null | undefined): number {
  if (role === "owner") return 0;
  if (role === "admin") return 1;
  if (role === "member") return 2;
  return 3;
}

function workspaceHasAccess(workspace: WorkspaceRow | null): boolean {
  return !!workspace;
}

function envList(name: string): string[] {
  return (process.env[name] ?? "")
    .split(/\\n|[\n,]/)
    .map((value) => value.trim())
    .filter(Boolean);
}

function normalizedEmail(email: string | null | undefined): string | null {
  return email?.trim().toLowerCase() || null;
}

function canUseSalespersonDashboard(context: AccessContext): boolean {
  if (!context.workspace?.id || !context.hasAccess) return false;

  const allowedWorkspaceIds = new Set(envList("DIALER_ENABLED_WORKSPACE_IDS"));
  const allowedEmails = new Set(
    envList("DIALER_ENABLED_EMAILS").map((value) => value.toLowerCase())
  );

  if (allowedWorkspaceIds.size === 0 && allowedEmails.size === 0) {
    return false;
  }

  const email = normalizedEmail(context.user.email);
  return allowedWorkspaceIds.has(context.workspace.id) || (email ? allowedEmails.has(email) : false);
}

async function resolvePrimaryWorkspace(userId: string): Promise<{ workspace: WorkspaceRow | null; role: string | null }> {
  const admin = adminClient();

  const { data: ownedWorkspace } = await admin
    .from("workspaces")
    .select("id,name,industry,owner_id,subscription_status,trial_ends_at,created_at")
    .eq("owner_id", userId)
    .order("created_at", { ascending: true })
    .limit(1)
    .maybeSingle();

  const primaryOwnedWorkspace = (ownedWorkspace as WorkspaceRow | null) ?? null;
  if (primaryOwnedWorkspace?.id) {
    return { workspace: primaryOwnedWorkspace, role: "owner" };
  }

  const { data: memberships } = await admin
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

  const primaryMembership = sorted[0];
  if (!primaryMembership?.workspace_id) {
    return { workspace: null, role: null };
  }

  const { data: workspace } = await admin
    .from("workspaces")
    .select("id,name,industry,owner_id,subscription_status,trial_ends_at,created_at")
    .eq("id", primaryMembership.workspace_id)
    .maybeSingle();

  return {
    workspace: (workspace as WorkspaceRow | null) ?? null,
    role: primaryMembership.role ?? "member",
  };
}

async function resolveRequestedWorkspace(
  userId: string,
  workspaceId: string
): Promise<{ workspace: WorkspaceRow | null; role: string | null }> {
  const admin = adminClient();

  const { data: workspace } = await admin
    .from("workspaces")
    .select("id,name,industry,owner_id,subscription_status,trial_ends_at,created_at")
    .eq("id", workspaceId)
    .maybeSingle();

  const requestedWorkspace = (workspace as WorkspaceRow | null) ?? null;
  if (!requestedWorkspace?.id) {
    return { workspace: null, role: null };
  }

  if (requestedWorkspace.owner_id === userId) {
    return { workspace: requestedWorkspace, role: "owner" };
  }

  const { data: membership } = await admin
    .from("workspace_members")
    .select("workspace_id,role,created_at")
    .eq("workspace_id", workspaceId)
    .eq("user_id", userId)
    .maybeSingle();

  const requestedMembership = membership as WorkspaceMembership | null;
  if (!requestedMembership?.workspace_id) {
    return { workspace: null, role: null };
  }

  return {
    workspace: requestedWorkspace,
    role: requestedMembership.role ?? "member",
  };
}

export async function resolveAccessContext(
  request: NextRequest,
  options?: ResolveAccessContextOptions
): Promise<AccessContext | null> {
  const user = await resolveUserFromRequest(request);
  if (!user) return null;

  const requestedWorkspaceId = options?.workspaceId?.trim();
  const { workspace, role } = requestedWorkspaceId
    ? await resolveRequestedWorkspace(user.id, requestedWorkspaceId)
    : await resolvePrimaryWorkspace(user.id);
  const hasAccess = workspaceHasAccess(workspace);
  return {
    user,
    workspace,
    role,
    hasAccess,
    reason: hasAccess ? null : workspace ? "member-inactive" : "no-workspace",
  };
}

export function toAccessStatePayload(context: AccessContext): AccessStatePayload {
  const salespersonDashboardEnabled = canUseSalespersonDashboard(context);
  const salespersonId = salespersonDashboardEnabled ? context.user.id : null;

  return {
    user_id: context.user.id,
    userId: context.user.id,
    role: context.role,
    name: context.workspace?.name ?? null,
    workspaceName: context.workspace?.name ?? null,
    industry: context.workspace?.industry ?? null,
    workspace_id: context.workspace?.id ?? null,
    workspaceId: context.workspace?.id ?? null,
    accessLevel: salespersonDashboardEnabled ? "salesperson" : context.role,
    dashboardMode: salespersonDashboardEnabled ? "salesperson" : null,
    salespersonId,
    salesperson: salespersonId ? { id: salespersonId } : null,
    isSalesperson: salespersonDashboardEnabled,
    canUseSalespersonDashboard: salespersonDashboardEnabled,
    has_access: context.hasAccess,
    hasAccess: context.hasAccess,
    reason: context.reason,
  };
}
