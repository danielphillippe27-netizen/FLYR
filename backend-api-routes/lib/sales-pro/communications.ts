import { requirePersonalReferences } from '@/lib/sales-pro/personal-references';
import { containsDemoLink } from '@/lib/salesperson/outreach-metrics';
import { Resend } from 'resend';
import type { SupabaseClient } from '@supabase/supabase-js';
import { sendTelnyxSms } from '@/lib/dialer/telnyx-messaging';
import { triggerSalesAutomations } from '@/lib/sales-pro/automation-trigger';
import { notifySalesUser } from '@/lib/sales-pro/notifications';
import { iCloudConnection, sendICloudEmail } from '@/lib/email/icloud-client';
import { brandedEmailContent } from '@/lib/email/signature';
import { demoEmailContent } from '@/lib/email/demo';
import { getSalespersonSmsFromNumber } from '@/lib/dialer/salesperson-settings';

type Admin = SupabaseClient;

type SalesMailbox = {
  address: string;
  forward_to: string | null;
};

function cleanEnv(name: string): string | null {
  const value = process.env[name]?.trim();
  return value || null;
}

function inboundEmailDomain(): string | null {
  return cleanEnv('RESEND_INBOUND_DOMAIN')?.toLowerCase() ?? null;
}

async function getOrCreateMailbox(
  admin: Admin,
  workspaceId: string,
  userId: string
): Promise<SalesMailbox | null> {
  const existing = await admin
    .from('sales_mailboxes')
    .select('address,forward_to')
    .eq('workspace_id', workspaceId)
    .eq('user_id', userId)
    .eq('is_active', true)
    .maybeSingle();
  if (existing.error) throw existing.error;
  if (existing.data?.address) return existing.data as SalesMailbox;

  // A verified receiving domain lets every salesperson receive replies without
  // requiring a separate setup step in the web app or the native app.
  if (!inboundEmailDomain()) return null;

  for (const suffixLength of [8, 12, 16]) {
    const localPart = `sales-${userId.replace(/-/g, '').slice(0, suffixLength)}`;
    const created = await admin
      .from('sales_mailboxes')
      .upsert(
        {
          workspace_id: workspaceId,
          user_id: userId,
          local_part: localPart,
          is_active: true,
        },
        { onConflict: 'workspace_id,user_id' }
      )
      .select('address,forward_to')
      .single();
    if (!created.error && created.data?.address) return created.data as SalesMailbox;
    if (created.error?.code !== '23505') throw created.error;
  }

  throw new Error('Unable to provision a unique WolfGrid reply mailbox.');
}

function validEmailAddress(value: string | null | undefined): string | null {
  const email = value?.trim().toLowerCase();
  return email && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? email : null;
}

export async function resolveSalesReplyAddress(
  admin: Admin,
  workspaceId: string,
  userId: string
): Promise<string | null> {
  const appleConnection = await iCloudConnection(admin, workspaceId, userId);
  const appleAddress = appleConnection?.is_active
    ? validEmailAddress(appleConnection.email_address)
    : null;
  if (appleAddress) return appleAddress;

  const configuredAddress = validEmailAddress(cleanEnv('MEETING_REPLY_TO_EMAIL'));
  if (configuredAddress) return configuredAddress;

  const mailbox = await getOrCreateMailbox(admin, workspaceId, userId);
  const managedAddress = validEmailAddress(mailbox?.address);
  const inboundDomain = inboundEmailDomain();
  return managedAddress && inboundDomain && managedAddress.endsWith(`@${inboundDomain}`)
    ? managedAddress
    : null;
}

export type CommunicationInput = {
  workspaceId: string;
  contactId?: string | null;
  leadId?: string | null;
  actorUserId?: string | null;
  channel: 'sms' | 'email' | 'call' | 'voicemail' | 'social' | 'notification';
  direction: 'inbound' | 'outbound' | 'internal';
  eventKind: string;
  provider?: string | null;
  providerEventId?: string | null;
  providerThreadId?: string | null;
  subject?: string | null;
  body?: string | null;
  fromAddress?: string | null;
  toAddresses?: string[];
  status?: string;
  occurredAt?: string;
  attachments?: unknown[];
  metadata?: Record<string, unknown>;
};

export async function appendCommunication(admin: Admin, input: CommunicationInput) {
  // Preserve the communication even when an older producer supplies an invalid
  // CRM link, but never attach it to or trigger automation for a foreign record.
  input = { ...input };
  for (const [table, ownerColumn, key] of [
    ['sales_contacts', 'owner_user_id', 'contactId'],
    ['sales_leads', 'assigned_user_id', 'leadId'],
  ] as const) {
    const id = input[key];
    if (!id) continue;
    if (!input.actorUserId) { input[key] = null; continue; }
    const { data, error } = await admin.from(table).select('id')
      .eq('workspace_id', input.workspaceId).eq(ownerColumn, input.actorUserId).eq('id', id).maybeSingle();
    if (error) throw error;
    if (!data) input[key] = null;
  }
  const now = input.occurredAt ?? new Date().toISOString();
  if (input.provider && input.providerEventId) {
    const existing = await admin.from('communication_events').select('*,communication_threads(id)')
      .eq('workspace_id', input.workspaceId).eq('provider', input.provider).eq('provider_event_id', input.providerEventId).maybeSingle();
    if (existing.error) throw existing.error;
    if (existing.data) {
      if (existing.data.actor_user_id !== (input.actorUserId ?? null)) throw new Error('Provider event belongs to a different communication owner.');
      return { threadId: existing.data.thread_id, event: existing.data };
    }
  }
  let threadQuery = admin
    .from('communication_threads')
    .select('id')
    .eq('workspace_id', input.workspaceId)
    .eq('status', 'open')
    .order('latest_event_at', { ascending: false })
    .limit(1);
  if (input.contactId) threadQuery = threadQuery.eq('sales_contact_id', input.contactId);
  else if (input.leadId) threadQuery = threadQuery.eq('sales_lead_id', input.leadId);
  else if (input.providerThreadId) threadQuery = threadQuery.contains('provider_thread_keys', { [input.provider ?? input.channel]: input.providerThreadId });
  else threadQuery = threadQuery.eq('id', '00000000-0000-0000-0000-000000000000');

  // Ownership is part of thread identity, even when two users share a contact.
  threadQuery = input.actorUserId
    ? threadQuery.eq('assigned_user_id', input.actorUserId)
    : threadQuery.is('assigned_user_id', null);
  let { data: thread, error: threadError } = await threadQuery.maybeSingle();
  if (threadError) throw threadError;
  if (!thread) {
    const created = await admin.from('communication_threads').insert({
      workspace_id: input.workspaceId,
      sales_contact_id: input.contactId ?? null,
      sales_lead_id: input.leadId ?? null,
      assigned_user_id: input.actorUserId ?? null,
      subject: input.subject ?? null,
      status: 'open',
      needs_response: input.direction === 'inbound',
      latest_channel: input.channel,
      latest_event_at: now,
      provider_thread_keys: input.providerThreadId ? { [input.provider ?? input.channel]: input.providerThreadId } : {},
    }).select('id').single();
    if (created.error) throw created.error;
    thread = created.data;
  }

  let inserted = await admin.from('communication_events').insert({
    workspace_id: input.workspaceId,
    thread_id: thread.id,
    sales_contact_id: input.contactId ?? null,
    sales_lead_id: input.leadId ?? null,
    actor_user_id: input.actorUserId ?? null,
    channel: input.channel,
    direction: input.direction,
    event_kind: input.direction === 'outbound' && ['email', 'sms'].includes(input.channel) && containsDemoLink(input.body) ? 'demo_sent' : input.eventKind,
    provider: input.provider ?? null,
    provider_event_id: input.providerEventId ?? null,
    provider_thread_id: input.providerThreadId ?? null,
    subject: input.subject ?? null,
    body: input.body ?? null,
    from_address: input.fromAddress ?? null,
    to_addresses: input.toAddresses ?? [],
    status: input.status ?? (input.direction === 'inbound' ? 'received' : 'queued'),
    occurred_at: now,
    attachments: input.attachments ?? [],
    metadata: input.metadata ?? {},
  }).select('*').single();
  if (inserted.error && input.provider && input.providerEventId && inserted.error.code === '23505') {
    inserted = await admin.from('communication_events').select('*').eq('workspace_id', input.workspaceId)
      .eq('provider', input.provider).eq('provider_event_id', input.providerEventId).single();
  }
  if (inserted.error) throw inserted.error;
  if (inserted.data.actor_user_id !== (input.actorUserId ?? null)) throw new Error('Provider event belongs to a different communication owner.');

  await admin.from('communication_threads').update({
    latest_channel: input.channel,
    latest_event_at: now,
    needs_response: input.direction === 'inbound',
    ...(input.subject ? { subject: input.subject } : {}),
  }).eq('id', thread.id);

  if (input.leadId) {
    await admin.from('sales_activities').insert({
      workspace_id: input.workspaceId,
      sales_lead_id: input.leadId,
      sales_contact_id: input.contactId ?? null,
      actor_user_id: input.actorUserId ?? null,
      activity_type: input.channel,
      note: [input.subject, input.body].filter(Boolean).join('\n'),
      occurred_at: now,
      metadata: { communicationEventId: inserted.data?.id ?? null, direction: input.direction },
    });
    await admin.from('sales_leads').update({ last_touch_at: now, last_touch_summary: `${input.direction} ${input.channel}` }).eq('id', input.leadId).eq('workspace_id', input.workspaceId).eq('assigned_user_id', input.actorUserId);
    if (input.direction === 'inbound') {
      await notifySalesUser(admin, { workspaceId: input.workspaceId, userId: input.actorUserId, type: input.channel === 'voicemail' ? 'voicemail' : input.channel === 'call' && input.status === 'missed' ? 'missed_call' : 'inbound_reply', title: input.channel === 'voicemail' ? 'New voicemail' : input.channel === 'call' ? 'Missed call' : `New ${input.channel} reply`, body: input.body, data: { threadId: thread.id, leadId: input.leadId, contactId: input.contactId } });
      await triggerSalesAutomations(admin, { workspaceId: input.workspaceId, triggerType: input.eventKind.includes('missed') || (input.channel === 'call' && input.status === 'missed') ? 'missed_call' : 'inbound_reply', leadId: input.leadId, contactId: input.contactId, ownerUserId: input.actorUserId, context: { communicationEventId: inserted.data?.id, channel: input.channel } });
    } else if (input.direction === 'outbound' && (input.channel === 'sms' || input.channel === 'email')) {
      await triggerSalesAutomations(admin, { workspaceId: input.workspaceId, triggerType: 'no_reply', leadId: input.leadId, contactId: input.contactId, ownerUserId: input.actorUserId, context: { communicationEventId: inserted.data?.id, channel: input.channel } });
    }
  }
  return { threadId: thread.id, event: inserted.data };
}

export async function sendManagedEmail(params: {
  admin: Admin; workspaceId: string; userId: string; contactId?: string | null; leadId?: string | null;
  to: string; subject: string; body: string; inReplyTo?: string | null; senderEmail?: string | null;
  demo?: { recipientName?: string | null; senderName?: string | null; senderAddress?: string | null; replyTo?: string | null };
}) {
  await requirePersonalReferences(params.admin, params.workspaceId, params.userId, params);
  let signatureSender = params.senderEmail?.trim() || null;
  if (!signatureSender) {
    const { data } = await params.admin.auth.admin.getUserById(params.userId);
    signatureSender = data.user?.email?.trim() || null;
  }
  const appleConnection = await iCloudConnection(params.admin, params.workspaceId, params.userId);
  if (appleConnection?.is_active) {
    const content = params.demo
      ? demoEmailContent({ ...params.demo, senderEmail: appleConnection.email_address })
      : brandedEmailContent(params.body, signatureSender ?? appleConnection.email_address);
    const sent = await sendICloudEmail(appleConnection, {
      to: params.to,
      subject: params.subject,
      body: content.text,
      html: content.html,
      inReplyTo: params.inReplyTo,
    });
    return appendCommunication(params.admin, {
      workspaceId: params.workspaceId, contactId: params.contactId, leadId: params.leadId, actorUserId: params.userId,
      channel: 'email', direction: 'outbound', eventKind: 'email_sent', provider: 'icloud', providerEventId: sent.messageId,
      subject: params.subject, body: params.demo ? content.text : params.body, fromAddress: appleConnection.email_address, toAddresses: [params.to],
      status: 'sent', providerThreadId: params.inReplyTo,
    });
  }
  const apiKey = process.env.RESEND_API_KEY?.trim();
  if (!apiKey) throw new Error('RESEND_API_KEY is not configured.');
  const mailbox = await getOrCreateMailbox(params.admin, params.workspaceId, params.userId);
  const fallback = process.env.RESEND_FROM_EMAIL?.trim();
  const demoSender = validEmailAddress(params.demo?.senderAddress);
  const from = demoSender ? `WolfGrid Sales <${demoSender}>` : mailbox?.address ? `WolfGrid Sales <${mailbox.address}>` : fallback;
  if (!from) throw new Error('A WolfGrid mailbox is not configured.');
  const resend = new Resend(apiKey);
  const fromAddress = demoSender ?? mailbox?.address ?? fallback?.match(/<([^>]+)>/)?.[1] ?? fallback!;
  const content = params.demo
    ? demoEmailContent({ ...params.demo, senderEmail: fromAddress })
    : brandedEmailContent(params.body, signatureSender ?? mailbox?.address ?? fallback);
  const sent = await resend.emails.send({ from, to: params.to, subject: params.subject, text: content.text, html: content.html, replyTo: validEmailAddress(params.demo?.replyTo) ?? mailbox?.address ?? undefined, headers: params.inReplyTo ? { 'In-Reply-To': params.inReplyTo, References: params.inReplyTo } : undefined });
  if (sent.error) throw new Error(sent.error.message);
  return appendCommunication(params.admin, {
    workspaceId: params.workspaceId, contactId: params.contactId, leadId: params.leadId, actorUserId: params.userId,
    channel: 'email', direction: 'outbound', eventKind: 'email_sent', provider: 'resend', providerEventId: sent.data?.id,
    subject: params.subject, body: params.demo ? content.text : params.body, fromAddress: demoSender ?? mailbox?.address ?? fallback ?? null, toAddresses: [params.to], status: 'sent', providerThreadId: params.inReplyTo,
  });
}

export async function sendManagedSms(params: {
  admin: Admin; workspaceId: string; userId: string; contactId?: string | null; leadId?: string | null;
  to: string; body: string; attachments?: Array<{ url: string; mimeType?: string; fileName?: string | null; storagePath?: string | null }>;
}) {
  await requirePersonalReferences(params.admin, params.workspaceId, params.userId, params);
  const senderNumber = await getSalespersonSmsFromNumber(params.admin, { userId: params.userId, workspaceId: params.workspaceId }, null);
  if (!senderNumber) throw Object.assign(new Error("A personal phone number must be assigned before texting."), { status: 409 });
  const sent = await sendTelnyxSms({ from: senderNumber, to: params.to, text: params.body, mediaUrls: params.attachments?.map((attachment) => attachment.url) });
  return appendCommunication(params.admin, {
    workspaceId: params.workspaceId, contactId: params.contactId, leadId: params.leadId, actorUserId: params.userId,
    channel: 'sms', direction: 'outbound', eventKind: 'sms_sent', provider: 'telnyx', providerEventId: sent?.id ?? null,
    body: params.body, fromAddress: sent?.from?.phone_number ?? senderNumber, toAddresses: [params.to], status: sent?.to?.[0]?.status ?? 'queued',
    attachments: params.attachments ?? [],
  });
}
