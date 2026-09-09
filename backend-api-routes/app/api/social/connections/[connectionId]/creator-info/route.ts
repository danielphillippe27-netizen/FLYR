import { NextRequest, NextResponse } from 'next/server';
import { requireSocialUser } from '@/lib/social/auth';
import { socialAccessToken } from '@/lib/social/publisher';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

type TikTokConnection = {
  id: string;
  platform: 'tiktok';
  external_account_id: string;
  access_token_encrypted: string;
  refresh_token_encrypted?: string | null;
  token_expires_at?: string | null;
  metadata?: Record<string, unknown>;
};

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ connectionId: string }> },
) {
  const context = await requireSocialUser(request);
  if (!context) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { connectionId } = await params;
  const { data: connection, error: connectionError } = await context.admin
    .from('social_connections')
    .select('id,platform,external_account_id,access_token_encrypted,refresh_token_encrypted,token_expires_at,metadata')
    .eq('id', connectionId)
    .eq('social_workspace_id', context.socialWorkspaceId)
    .eq('platform', 'tiktok')
    .maybeSingle();

  if (connectionError) return NextResponse.json({ error: connectionError.message }, { status: 500 });
  if (!connection) return NextResponse.json({ error: 'TikTok connection not found' }, { status: 404 });

  try {
    const token = await socialAccessToken(connection as TikTokConnection, context.admin);
    const response = await fetch('https://open.tiktokapis.com/v2/post/publish/creator_info/query/', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json; charset=UTF-8',
      },
      cache: 'no-store',
    });
    const payload = await response.json();
    if (!response.ok || payload.error?.code !== 'ok') {
      return NextResponse.json({ error: payload.error?.message || 'TikTok creator information is unavailable' }, { status: response.status || 502 });
    }

    const creator = payload.data || {};
    return NextResponse.json({
      creatorInfo: {
        username: creator.creator_username || null,
        nickname: creator.creator_nickname || null,
        avatarUrl: creator.creator_avatar_url || null,
        privacyLevelOptions: Array.isArray(creator.privacy_level_options) ? creator.privacy_level_options : [],
        commentsDisabled: creator.comment_disabled === true,
        duetDisabled: creator.duet_disabled === true,
        stitchDisabled: creator.stitch_disabled === true,
        maxVideoDurationSeconds: Number(creator.max_video_post_duration_sec || 0),
      },
    }, { headers: { 'Cache-Control': 'no-store' } });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'TikTok creator information is unavailable' }, { status: 502 });
  }
}
