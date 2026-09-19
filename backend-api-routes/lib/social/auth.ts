import type { NextRequest } from 'next/server';
import { resolveUserFromRequest } from '@/app/api/_utils/request-user';
import { createAdminClient } from '@/lib/supabase/server';
import { resolveDashboardAccessLevel } from '@/app/api/_utils/workspace';
import { resolveSalespersonForUser } from '@/lib/dialer/salesperson-settings';

export async function requireSocialUser(request: NextRequest) {
  const user = await resolveUserFromRequest(request);
  if (!user) return null;
  const admin = createAdminClient();
  const access = await resolveDashboardAccessLevel(admin, user.id);
  const salesperson = await resolveSalespersonForUser(admin, {
    userId: user.id,
    email: user.email,
    workspaceId: access.workspaceId,
  });
  const requestedWorkspaceId = request.headers.get('x-social-workspace-id');
  let memberships = admin
    .from('social_workspace_members')
    .select('social_workspace_id,role,social_workspaces(id,name,slug,settings)')
    .eq('user_id', user.id)
    .order('created_at', { ascending: true });
  if (requestedWorkspaceId) memberships = memberships.eq('social_workspace_id', requestedWorkspaceId);
  let { data: membership, error } = await memberships.limit(1).maybeSingle();

  if (!membership && !requestedWorkspaceId) {
    const { data: workspaceId, error: ensureError } = await admin.rpc('ensure_social_workspace', {
      target_user: user.id,
      workspace_name: user.email ? `${user.email.split('@')[0]}'s WolfSocial` : 'My WolfSocial',
    });
    if (ensureError || !workspaceId) throw new Error(ensureError?.message || 'Could not create WolfSocial workspace');
    const retry = await admin
      .from('social_workspace_members')
      .select('social_workspace_id,role,social_workspaces(id,name,slug,settings)')
      .eq('user_id', user.id)
      .eq('social_workspace_id', workspaceId)
      .single();
    membership = retry.data;
    error = retry.error;
  }
  if (error || !membership) return null;
  const workspace = Array.isArray(membership.social_workspaces)
    ? membership.social_workspaces[0]
    : membership.social_workspaces;
  if (!workspace) return null;
  return {
    user,
    salesperson,
    admin,
    access,
    socialWorkspaceId: membership.social_workspace_id as string,
    socialRole: membership.role as 'owner' | 'admin' | 'member',
    socialWorkspace: workspace as { id: string; name: string; slug: string; settings: Record<string, unknown> },
  };
}

// Compatibility alias while legacy /api/social clients migrate to workspace headers.
export const requireSocialSalesperson = requireSocialUser;
