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
  if (!workspace) return false;

  const status = (workspace.subscription_status ?? "").toLowerCase();
  if (status === "inactive" || status === "canceled" || status === "past_due" || status === "unpaid") {
    return false;
  }

  if (status === "trialing") {
    if (!workspace.trial_ends_at) return true;
    const trialEnd = new Date(workspace.trial_ends_at);
    return Number.isNaN(trialEnd.getTime()) || trialEnd > new Date();
  }

  return true;
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

export async function resolveAccessContext(request: NextRequest): Promise<AccessContext | null> {
  const user = await resolveUserFromRequest(request);
  if (!user) return null;

  const { workspace, role } = await resolvePrimaryWorkspace(user.id);
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
  return {
    user_id: context.user.id,
    userId: context.user.id,
    role: context.role,
    name: context.workspace?.name ?? null,
    workspaceName: context.workspace?.name ?? null,
    industry: context.workspace?.industry ?? null,
    workspace_id: context.workspace?.id ?? null,
    workspaceId: context.workspace?.id ?? null,
    has_access: context.hasAccess,
    hasAccess: context.hasAccess,
    reason: context.reason,
  };
}
