import { createHmac, createHash, timingSafeEqual } from 'crypto';
import { NextRequest, NextResponse } from 'next/server';
import { createAdminClient } from '@/lib/supabase/server';
import { appendCommunication } from '@/lib/sales-pro/communications';

export const runtime = 'nodejs';

export async function GET(request: NextRequest) {
  const mode = request.nextUrl.searchParams.get('hub.mode');
  const token = request.nextUrl.searchParams.get('hub.verify_token');
  const challenge = request.nextUrl.searchParams.get('hub.challenge');
  if (mode === 'subscribe' && token && token === process.env.META_WEBHOOK_VERIFY_TOKEN && challenge) return new NextResponse(challenge);
  return NextResponse.json({ error: 'Verification failed' }, { status: 403 });
}

export async function POST(request: NextRequest) {
  const raw = await request.text();
  const secret = process.env.META_APP_SECRET;
  const supplied = request.headers.get('x-hub-signature-256') || '';
  const expected = secret ? `sha256=${createHmac('sha256', secret).update(raw).digest('hex')}` : '';
  if (!secret || supplied.length !== expected.length || !timingSafeEqual(Buffer.from(supplied), Buffer.from(expected))) return NextResponse.json({ error: 'Invalid signature' }, { status: 401 });
  const payload = JSON.parse(raw);
  const admin = createAdminClient();
  const eventKey = createHash('sha256').update(raw).digest('hex');
  const { error: eventError } = await admin.from('social_webhook_events').insert({ platform: payload.object === 'instagram' ? 'instagram' : 'facebook', event_key: eventKey, payload });
  if (eventError?.code === '23505') return NextResponse.json({ received: true, duplicate: true });
  if (eventError) return NextResponse.json({ error: eventError.message }, { status: 500 });
  try {
    for (const entry of payload.entry || []) await normalizeEntry(admin, payload.object === 'instagram' ? 'instagram' : 'facebook', entry);
    await admin.from('social_webhook_events').update({ processed_at: new Date().toISOString() }).eq('event_key', eventKey);
  } catch (error) {
    await admin.from('social_webhook_events').update({ error: error instanceof Error ? error.message : 'Normalization failed' }).eq('event_key', eventKey);
  }
  return NextResponse.json({ received: true });
}

async function normalizeEntry(admin: ReturnType<typeof createAdminClient>, platform: 'facebook' | 'instagram', entry: any) {
  const { data: connections } = await admin.from('social_connections').select('id,social_workspace_id,user_id').eq('platform', platform).eq('external_account_id', String(entry.id));
  for (const connection of connections || []) {
    for (const event of entry.messaging || []) {
      if (!event.message?.mid || !event.sender?.id) continue;
      if (event.message.is_echo === true) continue;
      await upsertInteraction(admin, connection, platform, { externalId: event.message.mid, senderId: event.sender.id, senderName: event.sender.name, body: event.message.text || '', kind: 'message', threadId: event.sender.id, occurredAt: new Date(Number(event.timestamp || Date.now())).toISOString(), raw: event });
    }
    for (const change of entry.changes || []) {
      const value = change.value || {};
      const externalId = String(value.comment_id || value.id || ''); const senderId = String(value.from?.id || value.sender_id || '');
      if (!externalId || !senderId || !(value.message || value.text)) continue;
      await upsertInteraction(admin, connection, platform, { externalId, senderId, senderName: value.from?.name || value.username, body: value.message || value.text, kind: 'comment', threadId: String(value.parent_id || value.post_id || externalId), occurredAt: value.created_time ? new Date(Number(value.created_time) * 1000).toISOString() : new Date().toISOString(), raw: change });
    }
  }
}

async function upsertInteraction(admin: ReturnType<typeof createAdminClient>, connection: any, platform: string, event: { externalId: string; senderId: string; senderName?: string; body: string; kind: string; threadId: string; occurredAt: string; raw: unknown }) {
  const { data: contact } = await admin.from('social_contacts').upsert({ social_workspace_id: connection.social_workspace_id, connection_id: connection.id, platform, external_id: event.senderId, display_name: event.senderName || null, username: event.senderName || null, updated_at: new Date().toISOString() }, { onConflict: 'social_workspace_id,platform,external_id' }).select('id').single();
  const { data: thread } = await admin.from('social_threads').upsert({ social_workspace_id: connection.social_workspace_id, connection_id: connection.id, contact_id: contact?.id || null, platform, kind: event.kind, external_id: event.threadId, last_message_at: event.occurredAt, unread_count: 1, needs_reply: true, metadata: event.kind === 'message' ? { recipientId: event.senderId } : {}, updated_at: new Date().toISOString() }, { onConflict: 'connection_id,external_id' }).select('id').single();
  await admin.from('social_interactions').upsert({ social_workspace_id: connection.social_workspace_id, user_id: connection.user_id, connection_id: connection.id, thread_id: thread?.id || null, contact_id: contact?.id || null, platform, kind: event.kind, external_id: event.externalId, sender_external_id: event.senderId, sender_name: event.senderName || null, body: event.body, direction: 'inbound', status: 'received', needs_reply: true, occurred_at: event.occurredAt, raw_payload: event.raw }, { onConflict: 'platform,connection_id,external_id' });
  const { data: membership } = await admin.from('workspace_members').select('workspace_id').eq('user_id', connection.user_id).order('created_at').limit(1).maybeSingle();
  const { data: socialContact } = contact ? await admin.from('social_contacts').select('sales_lead_id').eq('id', contact.id).maybeSingle() : { data: null };
  const { data: salesLead } = socialContact?.sales_lead_id ? await admin.from('sales_leads').select('id,sales_contact_id').eq('id', socialContact.sales_lead_id).maybeSingle() : { data: null };
  if (membership?.workspace_id) await appendCommunication(admin, { workspaceId: membership.workspace_id, contactId: salesLead?.sales_contact_id ?? null, leadId: salesLead?.id ?? null, actorUserId: connection.user_id, channel: 'social', direction: 'inbound', eventKind: `${platform}_${event.kind}`, provider: platform, providerEventId: event.externalId, providerThreadId: event.threadId, body: event.body, fromAddress: event.senderName ?? event.senderId, status: 'received', occurredAt: event.occurredAt, metadata: { socialThreadId: thread?.id, socialContactId: contact?.id } });
}
