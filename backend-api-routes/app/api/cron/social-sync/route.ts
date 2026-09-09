import { NextRequest, NextResponse } from 'next/server';
import { createAdminClient } from '@/lib/supabase/server';
import { reconcileSocialPostStatus, socialAccessToken } from '@/lib/social/publisher';
import { metaApiVersion } from '@/lib/social/platforms';

export const runtime = 'nodejs';
export const maxDuration = 300;

type ProcessingTarget = {
  id: string;
  post_id: string;
  status: 'processing' | 'published';
  social_workspace_id?: string;
  platform: 'facebook' | 'tiktok' | 'youtube';
  external_publish_id?: string | null;
  external_post_id?: string | null;
  social_connections: {
    id: string;
    user_id: string;
    platform: 'facebook' | 'tiktok' | 'youtube';
    external_account_id: string;
    access_token_encrypted: string;
    refresh_token_encrypted?: string | null;
    token_expires_at?: string | null;
    metadata?: Record<string, unknown>;
  };
  social_posts: { social_workspace_id: string };
};

async function syncTikTok(target: ProcessingTarget, token: string) {
  if (!target.external_publish_id) throw new Error('TikTok publish id is missing');
  const response = await fetch('https://open.tiktokapis.com/v2/post/publish/status/fetch/', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify({ publish_id: target.external_publish_id }),
  });
  const payload = await response.json();
  if (!response.ok || payload.error?.code !== 'ok') throw new Error(payload.error?.message || 'TikTok status check failed');
  const status = String(payload.data?.status || 'PROCESSING');
  if (status === 'PUBLISH_COMPLETE' || status === 'SEND_TO_USER_INBOX') {
    return { status: 'published', externalPostId: payload.data?.publicly_available_post_id?.[0] || null, payload };
  }
  if (status === 'FAILED') throw new Error(payload.data?.fail_reason || 'TikTok processing failed');
  return { status: 'processing', externalPostId: null, payload };
}

async function syncFacebook(target: ProcessingTarget, token: string) {
  if (!target.external_post_id) throw new Error('Facebook video id is missing');
  const url = new URL(`https://graph.facebook.com/${metaApiVersion()}/${target.external_post_id}`);
  url.searchParams.set('fields', 'status');
  const response = await fetch(url, { headers: { Authorization: `Bearer ${token}` }, cache: 'no-store' });
  const payload = await response.json();
  if (!response.ok || payload.error) throw new Error(payload.error?.message || 'Facebook video status check failed');
  const status = payload.status || {};
  const videoStatus = String(status.video_status || '').toLowerCase();
  const processingStatus = String(status.processing_phase?.status || '').toLowerCase();
  const publishingStatus = String(status.publishing_phase?.status || '').toLowerCase();
  const phaseError = status.processing_phase?.error || status.publishing_phase?.error || status.uploading_phase?.error;
  if (videoStatus === 'error' || processingStatus === 'error' || publishingStatus === 'error') {
    throw new Error(phaseError?.message || phaseError?.error_user_msg || 'Facebook video processing failed');
  }
  const ready = videoStatus === 'ready' && (!publishingStatus || ['complete', 'published'].includes(publishingStatus));
  return { status: ready ? 'published' : 'processing', payload };
}

async function syncYouTube(target: ProcessingTarget, token: string) {
  if (!target.external_post_id) throw new Error('YouTube video id is missing');
  const url = new URL('https://www.googleapis.com/youtube/v3/videos');
  url.searchParams.set('part', 'processingDetails,status,statistics');
  url.searchParams.set('id', target.external_post_id);
  const response = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  const payload = await response.json();
  if (!response.ok) throw new Error(payload.error?.message || 'YouTube status check failed');
  const video = payload.items?.[0];
  if (!video) throw new Error('YouTube video is no longer available');
  const processing = String(video.processingDetails?.processingStatus || 'processing');
  if (processing === 'failed' || video.status?.uploadStatus === 'rejected') {
    throw new Error(video.processingDetails?.processingFailureReason || video.status?.rejectionReason || 'YouTube processing failed');
  }
  return { status: processing === 'succeeded' ? 'published' : 'processing', statistics: video.statistics || {}, payload: video };
}

async function syncYouTubeComments(target: ProcessingTarget, token: string, admin: ReturnType<typeof createAdminClient>) {
  if (!target.external_post_id) return 0;
  const url = new URL('https://www.googleapis.com/youtube/v3/commentThreads');
  url.searchParams.set('part', 'snippet,replies');
  url.searchParams.set('videoId', target.external_post_id);
  url.searchParams.set('maxResults', '100');
  url.searchParams.set('order', 'time');
  const response = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  const payload = await response.json();
  if (!response.ok) {
    if (payload.error?.errors?.some((item: { reason?: string }) => item.reason === 'commentsDisabled')) return 0;
    throw new Error(payload.error?.message || 'YouTube comments could not be synchronized');
  }
  let normalized = 0;
  for (const item of payload.items || []) {
    const comments = [item.snippet?.topLevelComment, ...(item.replies?.comments || [])].filter(Boolean);
    const replyParentId = String(item.snippet?.topLevelComment?.id || '');
    for (const comment of comments) {
      const snippet = comment.snippet || {};
      const authorId = String(snippet.authorChannelId?.value || snippet.authorDisplayName || 'youtube-viewer');
      const outbound = authorId === target.social_connections.external_account_id;
      const { data: contact } = await admin.from('social_contacts').upsert({
        social_workspace_id: target.social_posts.social_workspace_id,
        connection_id: target.social_connections.id,
        platform: 'youtube',
        external_id: authorId,
        display_name: snippet.authorDisplayName || null,
        avatar_url: snippet.authorProfileImageUrl || null,
        updated_at: new Date().toISOString(),
      }, { onConflict: 'social_workspace_id,platform,external_id' }).select('id').single();
      const { data: thread } = await admin.from('social_threads').upsert({
        social_workspace_id: target.social_posts.social_workspace_id,
        connection_id: target.social_connections.id,
        contact_id: contact?.id || null,
        platform: 'youtube',
        kind: 'comment',
        external_id: String(item.id),
        subject: 'YouTube Short comment',
        metadata: { replyParentId },
        last_message_at: snippet.publishedAt || new Date().toISOString(),
        unread_count: outbound ? 0 : 1,
        needs_reply: !outbound,
        updated_at: new Date().toISOString(),
      }, { onConflict: 'connection_id,external_id' }).select('id').single();
      await admin.from('social_interactions').upsert({
        social_workspace_id: target.social_posts.social_workspace_id,
        user_id: target.social_connections.user_id,
        connection_id: target.social_connections.id,
        thread_id: thread?.id || null,
        contact_id: contact?.id || null,
        platform: 'youtube',
        kind: comment.id === item.snippet?.topLevelComment?.id ? 'comment' : 'reply',
        external_id: String(comment.id),
        external_parent_id: snippet.parentId || (String(comment.id) !== replyParentId ? replyParentId : null),
        external_post_id: target.external_post_id,
        sender_external_id: authorId,
        sender_name: snippet.authorDisplayName || null,
        body: snippet.textOriginal || snippet.textDisplay || '',
        direction: outbound ? 'outbound' : 'inbound',
        status: outbound ? 'sent' : 'received',
        needs_reply: !outbound,
        occurred_at: snippet.publishedAt || new Date().toISOString(),
        raw_payload: comment,
      }, { onConflict: 'platform,connection_id,external_id' });
      normalized += 1;
    }
  }
  return normalized;
}

export async function GET(request: NextRequest) {
  if (!process.env.CRON_SECRET || request.headers.get('authorization') !== `Bearer ${process.env.CRON_SECRET}`) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  const admin = createAdminClient();
  const targetFields = 'id,post_id,status,platform,external_publish_id,external_post_id,social_connections(id,user_id,platform,external_account_id,access_token_encrypted,refresh_token_encrypted,token_expires_at,metadata),social_posts(social_workspace_id)';
  const [{ data: processing, error: processingError }, { data: publishedYouTube, error: publishedError }] = await Promise.all([
    admin.from('social_post_targets').select(targetFields).eq('status', 'processing').in('platform', ['facebook', 'tiktok', 'youtube']).order('updated_at', { ascending: true }).limit(30),
    admin.from('social_post_targets').select(targetFields).eq('status', 'published').eq('platform', 'youtube').order('updated_at', { ascending: false }).limit(20),
  ]);
  if (processingError || publishedError) return NextResponse.json({ error: processingError?.message || publishedError?.message }, { status: 500 });
  const data = [...(processing || []), ...(publishedYouTube || [])];

  const results: Array<Record<string, unknown>> = [];
  for (const rawTarget of data || []) {
    const target = rawTarget as unknown as ProcessingTarget;
    try {
      const token = await socialAccessToken(target.social_connections, admin);
      const result = target.platform === 'facebook'
        ? await syncFacebook(target, token)
        : target.platform === 'tiktok'
          ? await syncTikTok(target, token)
          : await syncYouTube(target, token);
      const update: Record<string, unknown> = { status: result.status, last_error: null, updated_at: new Date().toISOString() };
      if ('externalPostId' in result && result.externalPostId) update.external_post_id = result.externalPostId;
      if (result.status === 'published' && !target.external_post_id && target.platform === 'tiktok') update.external_url = 'https://www.tiktok.com/';
      await admin.from('social_post_targets').update(update).eq('id', target.id);
      if (target.platform === 'youtube' && 'statistics' in result) {
        const statistics = result.statistics as Record<string, string | undefined>;
        await admin.from('social_post_metrics').insert({
          social_workspace_id: target.social_posts.social_workspace_id,
          target_id: target.id,
          views: Number(statistics.viewCount || 0),
          likes: Number(statistics.likeCount || 0),
          comments: Number(statistics.commentCount || 0),
          raw_payload: result.payload,
        });
        const comments = await syncYouTubeComments(target, token, admin);
        results.push({ id: target.id, status: result.status, comments });
      } else {
        results.push({ id: target.id, status: result.status });
      }
      await reconcileSocialPostStatus(target.post_id, admin);
    } catch (syncError) {
      const message = syncError instanceof Error ? syncError.message : 'Status sync failed';
      if (target.status === 'published') {
        results.push({ id: target.id, status: 'published', syncError: message });
        continue;
      }
      await admin.from('social_post_targets').update({ status: 'failed', last_error: message, updated_at: new Date().toISOString() }).eq('id', target.id);
      await reconcileSocialPostStatus(target.post_id, admin);
      results.push({ id: target.id, status: 'failed', error: message });
    }
  }
  return NextResponse.json({ checked: data.length, results });
}
