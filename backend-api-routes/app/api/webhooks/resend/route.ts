import { NextRequest, NextResponse } from 'next/server';
import { Resend, type WebhookEventPayload } from 'resend';
import { createAdminClient } from '@/lib/supabase/server';
import { appendCommunication } from '@/lib/sales-pro/communications';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function POST(request: NextRequest) {
  const apiKey = process.env.RESEND_API_KEY?.trim(); const secret = process.env.RESEND_WEBHOOK_SECRET?.trim();
  if (!apiKey || !secret) return NextResponse.json({ error: 'Resend webhook is not configured.' }, { status: 503 });
  const payload = await request.text(); const resend = new Resend(apiKey); let event: WebhookEventPayload;
  try {
    event = resend.webhooks.verify({ payload, webhookSecret: secret, headers: { id: request.headers.get('svix-id') ?? '', timestamp: request.headers.get('svix-timestamp') ?? '', signature: request.headers.get('svix-signature') ?? '' } });
  } catch {
    return NextResponse.json({ error: 'Invalid Resend webhook signature.' }, { status: 403 });
  }
  const admin = createAdminClient();
  if (event.type === 'email.received') {
    const received = await resend.emails.receiving.get(event.data.email_id);
    if (received.error || !received.data) return NextResponse.json({ error: received.error?.message ?? 'Inbound email could not be loaded.' }, { status: 502 });
    const mailboxAddresses = [...new Set((event.data.received_for?.length ? event.data.received_for : event.data.to ?? []).map(address => address.toLowerCase()))];
    for (const mailboxAddress of mailboxAddresses) {
    const { data: mailbox } = await admin.from('sales_mailboxes').select('*').eq('address', mailboxAddress).eq('is_active', true).maybeSingle();
    if (!mailbox?.user_id) continue;
    const fromEmail = received.data.from.match(/<([^>]+)>/)?.[1]?.toLowerCase() ?? received.data.from.toLowerCase();
    const { data: contact } = await admin.from('sales_contacts').select('id').eq('workspace_id', mailbox.workspace_id).eq('owner_user_id', mailbox.user_id).eq('email_normalized', fromEmail).is('merged_into_id', null).maybeSingle();
    const { data: lead } = contact ? await admin.from('sales_leads').select('id').eq('workspace_id', mailbox.workspace_id).eq('assigned_user_id', mailbox.user_id).eq('sales_contact_id', contact.id).order('updated_at', { ascending: false }).limit(1).maybeSingle() : { data: null };
    const { data: prior, error: priorError } = await admin.from('communication_events').select('id')
      .eq('workspace_id', mailbox.workspace_id).eq('actor_user_id', mailbox.user_id)
      .eq('provider', 'resend').eq('provider_event_id', event.data.email_id).eq('direction', 'inbound').maybeSingle();
    if (priorError) return NextResponse.json({ error: 'Inbound deduplication lookup failed.' }, { status: 500 });
    if (prior) continue;
    await appendCommunication(admin, { workspaceId: mailbox.workspace_id, contactId: contact?.id ?? null, leadId: lead?.id ?? null, actorUserId: mailbox.user_id, channel: 'email', direction: 'inbound', eventKind: 'email_received', provider: 'resend', providerEventId: `mailbox:${mailbox.id}:${event.data.email_id}`, providerThreadId: received.data.headers?.['in-reply-to'] ?? received.data.message_id, subject: received.data.subject, body: received.data.text ?? received.data.html ?? '', fromAddress: fromEmail, toAddresses: received.data.to, status: 'received', occurredAt: received.data.created_at, attachments: received.data.attachments, metadata: { messageId: received.data.message_id, inReplyTo: received.data.headers?.['in-reply-to'] ?? null } });
    if (mailbox.forward_to) await resend.emails.receiving.forward({ emailId: event.data.email_id, from: mailbox.address, to: mailbox.forward_to, passthrough: true }).catch(() => undefined);
    }
  } else if (event.type.startsWith('email.')) {
    const data = event.data as { email_id: string; to?: string[] };
    const status = event.type.replace('email.', '');
    const { data: sent, error: lookupError } = await admin.from('communication_events')
      .select('id,workspace_id,actor_user_id,sales_contact_id,metadata').eq('provider', 'resend')
      .eq('provider_event_id', data.email_id).eq('direction', 'outbound').maybeSingle();
    if (lookupError) return NextResponse.json({ error: 'Delivery owner lookup failed.' }, { status: 500 });
    if (!sent?.actor_user_id) return NextResponse.json({ ok: true, ignored: true, reason: 'outbound_message_not_found' });
    const { error: updateError } = await admin.from('communication_events')
      .update({ status, metadata: { ...(sent.metadata ?? {}), lastDeliveryEvent: event.type } })
      .eq('id', sent.id).eq('workspace_id', sent.workspace_id).eq('actor_user_id', sent.actor_user_id);
    if (updateError) return NextResponse.json({ error: 'Delivery update failed.' }, { status: 500 });
    if (['email.bounced', 'email.complained', 'email.suppressed'].includes(event.type) && sent.sales_contact_id) {
      const { data: contact } = await admin.from('sales_contacts').select('id,workspace_id')
        .eq('id', sent.sales_contact_id).eq('workspace_id', sent.workspace_id)
        .eq('owner_user_id', sent.actor_user_id).is('merged_into_id', null).maybeSingle();
      if (contact) await admin.from('sales_communication_preferences').upsert({ workspace_id: contact.workspace_id, sales_contact_id: contact.id, channel: 'email', status: event.type === 'email.complained' ? 'complained' : 'bounced', source: 'resend' }, { onConflict: 'sales_contact_id,channel' });
    }
  }
  return NextResponse.json({ ok: true });
}

export async function GET() {
  return NextResponse.json({ ok: true, provider: 'resend', events: ['email.received', 'email.delivered', 'email.bounced', 'email.failed', 'email.complained'] });
}
