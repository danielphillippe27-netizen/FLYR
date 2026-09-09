import { NextRequest, NextResponse } from 'next/server';
import { requireSocialUser } from '@/lib/social/auth';

export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest) {
  const context = await requireSocialUser(request);
  if (!context) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const [{ data: posts, error: postsError }, { data: metrics, error: metricsError }] = await Promise.all([
    context.admin.from('social_posts').select('id,status,created_at,social_post_targets(platform,status)').eq('social_workspace_id', context.socialWorkspaceId).gte('created_at', new Date(Date.now() - 30 * 86_400_000).toISOString()),
    context.admin.from('social_post_metrics').select('impressions,reach,views,likes,comments,shares,saves,watch_time_seconds').eq('social_workspace_id', context.socialWorkspaceId).gte('captured_at', new Date(Date.now() - 30 * 86_400_000).toISOString()),
  ]);
  if (postsError || metricsError) return NextResponse.json({ error: postsError?.message || metricsError?.message }, { status: 500 });
  const totals = (metrics || []).reduce((sum, row) => ({ impressions: sum.impressions + Number(row.impressions || 0), reach: sum.reach + Number(row.reach || 0), views: sum.views + Number(row.views || 0), likes: sum.likes + Number(row.likes || 0), comments: sum.comments + Number(row.comments || 0), shares: sum.shares + Number(row.shares || 0), saves: sum.saves + Number(row.saves || 0) }), { impressions: 0, reach: 0, views: 0, likes: 0, comments: 0, shares: 0, saves: 0 });
  return NextResponse.json({ periodDays: 30, totals, posts: { total: (posts || []).length, published: (posts || []).filter((post) => post.status === 'published').length, scheduled: (posts || []).filter((post) => post.status === 'scheduled').length, failed: (posts || []).filter((post) => post.status === 'failed' || post.status === 'partial_failed').length } });
}

