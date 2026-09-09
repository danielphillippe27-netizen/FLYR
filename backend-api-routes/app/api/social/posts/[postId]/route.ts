import { NextRequest, NextResponse } from 'next/server';
import { requireSocialUser } from '@/lib/social/auth';

export const runtime = 'nodejs';

async function ownedPost(request: NextRequest, postId: string) {
  const context = await requireSocialUser(request);
  if (!context) return { response: NextResponse.json({ error: 'Unauthorized' }, { status: 401 }) };
  const { data: post, error } = await context.admin.from('social_posts').select('id,status,scheduled_for').eq('id', postId).eq('social_workspace_id', context.socialWorkspaceId).maybeSingle();
  if (error) return { response: NextResponse.json({ error: error.message }, { status: 500 }) };
  if (!post) return { response: NextResponse.json({ error: 'Post not found' }, { status: 404 }) };
  return { context, post };
}

export async function PATCH(request: NextRequest, { params }: { params: Promise<{ postId: string }> }) {
  const { postId } = await params;
  const result = await ownedPost(request, postId);
  if ('response' in result) return result.response;
  const body = await request.json().catch(() => ({}));
  const action = String(body.action || '');
  if (action === 'cancel') {
    if (!['draft', 'scheduled', 'publishing', 'partial_failed', 'failed'].includes(result.post.status)) return NextResponse.json({ error: 'This post can no longer be cancelled' }, { status: 409 });
    await Promise.all([
      result.context.admin.from('social_posts').update({ status: 'cancelled', updated_at: new Date().toISOString() }).eq('id', postId),
      result.context.admin.from('social_post_targets').update({ status: 'cancelled', next_attempt_at: null, updated_at: new Date().toISOString() }).eq('post_id', postId).in('status', ['pending', 'uploading', 'processing', 'failed']),
    ]);
    return NextResponse.json({ status: 'cancelled' });
  }
  if (action === 'retry') {
    const { data: targets } = await result.context.admin.from('social_post_targets').select('id').eq('post_id', postId).eq('status', 'failed').lt('attempt_count', 5);
    if (!targets?.length) return NextResponse.json({ error: 'No failed targets are eligible for retry' }, { status: 409 });
    await Promise.all([
      result.context.admin.from('social_post_targets').update({ status: 'pending', next_attempt_at: new Date().toISOString(), last_error: null, updated_at: new Date().toISOString() }).eq('post_id', postId).eq('status', 'failed').lt('attempt_count', 5),
      result.context.admin.from('social_posts').update({ status: 'publishing', scheduled_for: new Date().toISOString(), last_error: null, updated_at: new Date().toISOString() }).eq('id', postId),
    ]);
    return NextResponse.json({ status: 'publishing', targets: targets.length });
  }
  if (action === 'reschedule') {
    const scheduledFor = new Date(body.scheduledFor);
    if (Number.isNaN(scheduledFor.getTime()) || scheduledFor <= new Date()) return NextResponse.json({ error: 'Choose a future schedule time' }, { status: 400 });
    if (!['draft', 'scheduled', 'failed', 'partial_failed'].includes(result.post.status)) return NextResponse.json({ error: 'This post cannot be rescheduled' }, { status: 409 });
    await Promise.all([
      result.context.admin.from('social_posts').update({ status: 'scheduled', scheduled_for: scheduledFor.toISOString(), timezone: String(body.timezone || '').slice(0, 100) || null, last_error: null, updated_at: new Date().toISOString() }).eq('id', postId),
      result.context.admin.from('social_post_targets').update({ status: 'pending', next_attempt_at: null, last_error: null, updated_at: new Date().toISOString() }).eq('post_id', postId).in('status', ['failed', 'cancelled']),
    ]);
    return NextResponse.json({ status: 'scheduled', scheduledFor: scheduledFor.toISOString() });
  }
  return NextResponse.json({ error: 'Unsupported calendar action' }, { status: 400 });
}

export async function DELETE(request: NextRequest, { params }: { params: Promise<{ postId: string }> }) {
  const { postId } = await params;
  const result = await ownedPost(request, postId);
  if ('response' in result) return result.response;
  if (!['draft', 'cancelled'].includes(result.post.status)) return NextResponse.json({ error: 'Only drafts or cancelled posts can be deleted' }, { status: 409 });
  const { error } = await result.context.admin.from('social_posts').delete().eq('id', postId);
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return new NextResponse(null, { status: 204 });
}
