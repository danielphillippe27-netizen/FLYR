import { NextRequest, NextResponse } from 'next/server';
import { requireSocialUser } from '@/lib/social/auth';

export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest) {
  const context = await requireSocialUser(request);
  if (!context) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  return NextResponse.json({ workspace: context.socialWorkspace, role: context.socialRole, canCreateLead: Boolean(context.salesperson || context.access.workspaceId) });
}

export async function PATCH(request: NextRequest) {
  const context = await requireSocialUser(request);
  if (!context) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  if (context.socialRole !== 'owner' && context.socialRole !== 'admin') return NextResponse.json({ error: 'Workspace admin access required' }, { status: 403 });
  const body = await request.json().catch(() => ({}));
  const name = typeof body.name === 'string' ? body.name.trim().slice(0, 80) : '';
  if (!name) return NextResponse.json({ error: 'Workspace name is required' }, { status: 400 });
  const { data, error } = await context.admin.from('social_workspaces').update({ name, updated_at: new Date().toISOString() }).eq('id', context.socialWorkspaceId).select('id,name,slug,settings').single();
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ workspace: data });
}

