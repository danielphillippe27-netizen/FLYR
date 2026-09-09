import { NextRequest, NextResponse } from 'next/server';
import { requireSocialUser } from '@/lib/social/auth';
import { SOCIAL_PLATFORMS, type SocialPlatform } from '@/lib/social/platforms';
import { validateSocialTargets } from '@/lib/social/post-validation';

const CONTENT_TYPES = new Set(['feed', 'carousel', 'reel', 'story', 'short', 'tiktok_video', 'tiktok_photo']);

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';
export const maxDuration = 300;

export async function GET(request: NextRequest) {
  const context = await requireSocialUser(request);
  if (!context) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const { data, error } = await context.admin.from('social_posts').select('id,caption,title,content_type,status,scheduled_for,published_at,last_error,created_at,social_post_targets(id,connection_id,platform,format,caption,title,settings,status,external_url,last_error)').eq('social_workspace_id', context.socialWorkspaceId).order('created_at', { ascending: false }).limit(100);
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ posts: data ?? [], socialWorkspace: context.socialWorkspace });
}

export async function POST(request: NextRequest) {
  const context = await requireSocialUser(request);
  if (!context) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const body = await request.json().catch(() => ({}));
  if (body.socialWorkspaceId && body.socialWorkspaceId !== context.socialWorkspaceId) return NextResponse.json({ error: 'Workspace access denied' }, { status: 403 });
  const assetIds = Array.from(new Set((Array.isArray(body.assetIds) ? body.assetIds : []).filter((value: unknown): value is string => typeof value === 'string' && !!value)));
  const contentType = typeof body.contentType === 'string' && CONTENT_TYPES.has(body.contentType) ? body.contentType : 'feed';
  const mode = body.mode === 'draft' || body.mode === 'schedule' || body.mode === 'publish' ? body.mode : 'draft';
  const requestedTargets = Array.isArray(body.targets) ? body.targets.filter((target: unknown): target is Record<string, unknown> => !!target && typeof target === 'object') : [];
  const legacyPlatforms = Array.from(new Set((Array.isArray(body.platforms) ? body.platforms : []).filter((value: unknown): value is SocialPlatform => typeof value === 'string' && SOCIAL_PLATFORMS.includes(value as SocialPlatform))));
  if (!requestedTargets.length && !legacyPlatforms.length) return NextResponse.json({ error: 'Choose at least one connected account' }, { status: 400 });
  const scheduledFor = mode === 'schedule' ? new Date(body.scheduledFor) : null;
  if (mode === 'schedule' && (!scheduledFor || Number.isNaN(scheduledFor.getTime()) || scheduledFor <= new Date())) return NextResponse.json({ error: 'Choose a future schedule time' }, { status: 400 });

  const connectionIds = requestedTargets.map((target) => String(target.connectionId || '')).filter(Boolean);
  const assetsRequest = assetIds.length
    ? context.admin.from('social_media_assets').select('id,mime_type,duration_seconds').eq('social_workspace_id', context.socialWorkspaceId).in('id', assetIds)
    : Promise.resolve({ data: [] as Array<{ id: string; mime_type: string; duration_seconds: number | null }>, error: null });
  const [{ data: availableConnections, error: connectionError }, { data: assets, error: assetError }] = await Promise.all([
    context.admin.from('social_connections').select('id,platform').eq('social_workspace_id', context.socialWorkspaceId).eq('status', 'active'),
    assetsRequest,
  ]);
  if (connectionError || assetError) return NextResponse.json({ error: connectionError?.message || assetError?.message }, { status: 500 });
  if ((assets || []).length !== assetIds.length) return NextResponse.json({ error: 'One or more media files were not found' }, { status: 400 });
  const connectionById = new Map((availableConnections || []).map((connection) => [connection.id, connection]));
  const normalizedTargets = requestedTargets.length
    ? requestedTargets.map((target) => {
        const connection = connectionById.get(String(target.connectionId || ''));
        return connection ? {
          connection,
          format: String(target.format || body.contentType || 'feed').slice(0, 50),
          caption: String(target.caption ?? body.caption ?? '').trim(),
          title: String(target.title ?? body.title ?? '').trim() || null,
          settings: target.settings && typeof target.settings === 'object' ? target.settings : {},
        } : null;
      }).filter(Boolean)
    : legacyPlatforms.map((platform) => {
        const connection = (availableConnections || []).find((item) => item.platform === platform);
        return connection ? { connection, format: contentType, caption: String(body.caption || '').trim(), title: String(body.title || '').trim() || null, settings: {} } : null;
      }).filter(Boolean);
  if (normalizedTargets.length !== (requestedTargets.length || legacyPlatforms.length) || connectionIds.some((id) => !connectionById.has(id))) return NextResponse.json({ error: 'Reconnect any selected account before publishing' }, { status: 409 });
  const validationError = validateSocialTargets(
    normalizedTargets.map((target) => ({
      platform: target!.connection.platform as SocialPlatform,
      format: target!.format,
      caption: target!.caption,
      title: target!.title,
      settings: target!.settings as Record<string, unknown>,
    })),
    assets || [],
    mode,
  );
  if (validationError) return NextResponse.json({ error: validationError }, { status: 400 });

  const initialStatus = mode === 'draft' ? 'draft' : mode === 'schedule' ? 'scheduled' : 'publishing';
  const { data: post, error: postError } = await context.admin.from('social_posts').insert({ social_workspace_id: context.socialWorkspaceId, user_id: context.user.id, caption: String(body.caption || normalizedTargets[0]?.caption || '').trim(), title: String(body.title || normalizedTargets[0]?.title || '').trim() || null, content_type: contentType, status: initialStatus, scheduled_for: scheduledFor?.toISOString() || (mode === 'publish' ? new Date().toISOString() : null), claimed_at: null, timezone: typeof body.timezone === 'string' ? body.timezone.slice(0, 100) : null }).select('id,status').single();
  if (postError || !post) return NextResponse.json({ error: postError?.message || 'Could not create post' }, { status: 500 });
  const assetsInsertRequest = assetIds.length
    ? context.admin.from('social_post_assets').insert(assetIds.map((assetId, position) => ({ post_id: post.id, asset_id: assetId, position })))
    : Promise.resolve({ error: null });
  const [{ error: assetsInsertError }, { error: targetsInsertError }] = await Promise.all([
    assetsInsertRequest,
    context.admin.from('social_post_targets').insert(normalizedTargets.map((target) => ({ post_id: post.id, connection_id: target!.connection.id, platform: target!.connection.platform, format: target!.format, caption: target!.caption, title: target!.title, settings: target!.settings, idempotency_key: `${post.id}:${target!.connection.id}` }))),
  ]);
  if (assetsInsertError || targetsInsertError) {
    // Post assets and targets cascade from the post. Removing the incomplete
    // parent keeps the queue from retaining a post that can never publish.
    await context.admin.from('social_posts').delete().eq('id', post.id).eq('social_workspace_id', context.socialWorkspaceId);
    return NextResponse.json({ error: assetsInsertError?.message || targetsInsertError?.message }, { status: 500 });
  }

  return NextResponse.json({ post, queued: mode === 'publish' }, { status: 201 });
}
