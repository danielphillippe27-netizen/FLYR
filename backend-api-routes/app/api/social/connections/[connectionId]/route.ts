import { NextRequest, NextResponse } from 'next/server';
import { requireSocialUser } from '@/lib/social/auth';

export async function DELETE(request: NextRequest, { params }: { params: Promise<{ connectionId: string }> }) {
  const context = await requireSocialUser(request);
  if (!context) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const { connectionId } = await params;
  const { error } = await context.admin.from('social_connections').delete().eq('id', connectionId).eq('social_workspace_id', context.socialWorkspaceId);
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ ok: true });
}
