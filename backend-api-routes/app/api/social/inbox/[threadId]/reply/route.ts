import { NextRequest, NextResponse } from 'next/server';
import { requireSocialUser } from '@/lib/social/auth';
import { metaApiVersion } from '@/lib/social/platforms';
import { isExpiredProviderAuthorization } from '@/lib/social/meta';
import { socialAccessToken } from '@/lib/social/publisher';

export async function POST(request: NextRequest, { params }: { params: Promise<{ threadId: string }> }) {
  const context = await requireSocialUser(request);
  if (!context) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const { threadId } = await params;
  const body = await request.json().catch(() => ({}));
  const message = typeof body.body === 'string' ? body.body.trim().slice(0, 5000) : '';
  if (!message) return NextResponse.json({ error: 'Reply cannot be empty' }, { status: 400 });
  const { data: thread, error } = await context.admin.from('social_threads').select('id,platform,kind,external_id,connection_id,contact_id,metadata,social_connections!inner(id,user_id,platform,external_account_id,access_token_encrypted,refresh_token_encrypted,token_expires_at,metadata)').eq('id', threadId).eq('social_workspace_id', context.socialWorkspaceId).eq('social_connections.user_id', context.user.id).single();
  if (error || !thread) return NextResponse.json({ error: 'Conversation not found' }, { status: 404 });
  if (thread.platform === 'tiktok') return NextResponse.json({ error: 'TikTok comments and DMs are unavailable through the Content Posting API.' }, { status: 422 });
  if (thread.platform === 'linkedin') return NextResponse.json({ error: 'LinkedIn messaging is unavailable through WolfSocial’s approved posting APIs.' }, { status: 422 });
  if (thread.platform === 'youtube' && thread.kind === 'message') return NextResponse.json({ error: 'YouTube does not support direct messages.' }, { status: 422 });
  const connection = Array.isArray(thread.social_connections) ? thread.social_connections[0] : thread.social_connections;
  if (!connection) return NextResponse.json({ error: 'Connection is unavailable' }, { status: 409 });
  if (thread.platform === 'instagram' && Buffer.byteLength(message, 'utf8') > 1000) return NextResponse.json({ error: 'Instagram messages must be 1,000 UTF-8 bytes or less' }, { status: 400 });
  let token: string;
  try {
    token = await socialAccessToken(connection as Parameters<typeof socialAccessToken>[0], context.admin);
  } catch (tokenError) {
    return NextResponse.json({ error: tokenError instanceof Error ? tokenError.message : 'Connection authorization expired' }, { status: 401 });
  }
  let externalId = '';
  if (thread.platform === 'youtube') {
    const parentId = String((thread.metadata as Record<string, unknown> | null)?.replyParentId || thread.external_id);
    const response = await fetch('https://www.googleapis.com/youtube/v3/comments?part=snippet', { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ snippet: { parentId, textOriginal: message } }) });
    const payload = await response.json();
    if (!response.ok || !payload.id) return NextResponse.json({ error: payload.error?.message || 'YouTube reply failed' }, { status: 502 });
    externalId = payload.id;
  } else if (thread.kind === 'comment') {
    const graphHost = thread.platform === 'instagram' ? 'graph.instagram.com' : 'graph.facebook.com';
    const response = await fetch(`https://${graphHost}/${metaApiVersion()}/${encodeURIComponent(thread.external_id)}/replies`, { method: 'POST', body: new URLSearchParams({ message, access_token: token }) });
    const payload = await response.json();
    if (!response.ok || !payload.id) {
      if (isExpiredProviderAuthorization(payload)) {
        await context.admin.from('social_connections').update({ status: 'expired', last_error: 'Authorization expired. Reconnect this account to continue.', updated_at: new Date().toISOString() }).eq('id', connection.id);
        return NextResponse.json({ error: 'Authorization expired. Reconnect this account to continue.' }, { status: 401 });
      }
      return NextResponse.json({ error: payload.error?.message || 'Meta reply failed' }, { status: 502 });
    }
    externalId = payload.id;
  } else {
    const recipientId = String((thread.metadata as Record<string, unknown> | null)?.recipientId || '');
    if (!recipientId) return NextResponse.json({ error: 'Message recipient is unavailable' }, { status: 409 });
    const graphHost = thread.platform === 'instagram' ? 'graph.instagram.com' : 'graph.facebook.com';
    const response = await fetch(`https://${graphHost}/${metaApiVersion()}/${connection.external_account_id}/messages`, { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ recipient: { id: recipientId }, ...(thread.platform === 'facebook' ? { messaging_type: 'RESPONSE' } : {}), message: { text: message } }) });
    const payload = await response.json();
    if (!response.ok || !(payload.message_id || payload.recipient_id)) {
      if (isExpiredProviderAuthorization(payload)) {
        await context.admin.from('social_connections').update({ status: 'expired', last_error: 'Authorization expired. Reconnect this account to continue.', updated_at: new Date().toISOString() }).eq('id', connection.id);
        return NextResponse.json({ error: 'Authorization expired. Reconnect this account to continue.' }, { status: 401 });
      }
      return NextResponse.json({ error: payload.error?.message || 'Meta message failed' }, { status: 502 });
    }
    externalId = payload.message_id || `${payload.recipient_id}:${Date.now()}`;
  }
  const occurredAt = new Date().toISOString();
  const { data: interaction, error: insertError } = await context.admin.from('social_interactions').insert({ social_workspace_id: context.socialWorkspaceId, user_id: context.user.id, connection_id: thread.connection_id, thread_id: thread.id, contact_id: thread.contact_id, platform: thread.platform, kind: 'reply', external_id: externalId, external_parent_id: thread.external_id, body: message, direction: 'outbound', status: 'sent', needs_reply: false, occurred_at: occurredAt }).select('id,body,direction,status,occurred_at').single();
  if (insertError) return NextResponse.json({ error: insertError.message }, { status: 500 });
  await context.admin.from('social_threads').update({ needs_reply: false, unread_count: 0, last_message_at: occurredAt, updated_at: occurredAt }).eq('id', thread.id);
  return NextResponse.json({ interaction }, { status: 201 });
}
