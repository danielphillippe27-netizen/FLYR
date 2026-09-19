import { simpleParser } from 'mailparser';
import type { SupabaseClient } from '@supabase/supabase-js';
import { appendCommunication } from '@/lib/sales-pro/communications';
import {
  iCloudAuthenticationEmailAddress,
  iCloudConnection,
  iCloudImap,
  type ICloudEmailConnection,
} from '@/lib/email/icloud-client';

function normalizedAddress(value: string | undefined | null) {
  return value?.trim().toLowerCase() || null;
}

function parsedAddresses(value: unknown): string[] {
  if (!value || typeof value !== 'object' || !('value' in value)) return [];
  const addresses = (value as { value?: Array<{ address?: string }> }).value ?? [];
  return addresses.map((item) => normalizedAddress(item.address)).filter((item): item is string => !!item);
}

export async function syncICloudInbox(admin: SupabaseClient, workspaceId: string, userId: string) {
  const connection = await iCloudConnection(admin, workspaceId, userId);
  if (!connection?.is_active) return 0;
  return syncConnection(admin, connection);
}

export async function syncConnection(admin: SupabaseClient, connection: ICloudEmailConnection) {
  const client = iCloudImap(connection);
  let imported = 0;
  let highestUID = connection.last_uid ?? 0;
  try {
    await client.connect();
    const mailbox = await client.mailboxOpen('INBOX', { readOnly: true });
    if (!mailbox.exists) return 0;
    if (connection.last_uid && mailbox.uidNext && connection.last_uid >= mailbox.uidNext - 1) {
      await admin.from('email_connections').update({
        last_synced_at: new Date().toISOString(), updated_at: new Date().toISOString(), sync_error: null,
      }).eq('id', connection.id);
      return 0;
    }
    const range = connection.last_uid
      ? `${connection.last_uid + 1}:*`
      : `${Math.max(1, mailbox.exists - 49)}:*`;
    for await (const message of client.fetch(range, { uid: true, source: true }, { uid: !!connection.last_uid })) {
      if (!message.source || !message.uid) continue;
      highestUID = Math.max(highestUID, message.uid);
      const parsed = await simpleParser(message.source);
      const fromEmail = normalizedAddress(parsed.from?.value[0]?.address);
      const recipients = [parsed.to, parsed.cc, parsed.bcc]
        .flatMap((value) => Array.isArray(value) ? value.flatMap(parsedAddresses) : parsedAddresses(value));
      const mailboxAddress = connection.email_address.toLowerCase();
      const deliveryHeaders = parsed.headerLines
        .filter((header) => ['delivered-to', 'x-original-to', 'envelope-to'].includes(header.key.toLowerCase()))
        .map((header) => header.line.toLowerCase());
      const isAddressedToMailbox = recipients.includes(mailboxAddress)
        || deliveryHeaders.some((header) => header.includes(mailboxAddress));
      if (!isAddressedToMailbox) continue;
      if (!fromEmail
        || fromEmail === mailboxAddress
        || fromEmail === iCloudAuthenticationEmailAddress(connection)) continue;
      const { data: contact } = await admin.from('sales_contacts').select('id')
        .eq('workspace_id', connection.workspace_id).eq('owner_user_id', connection.user_id).eq('email_normalized', fromEmail).is('merged_into_id', null).maybeSingle();
      const { data: lead } = contact ? await admin.from('sales_leads').select('id')
        .eq('workspace_id', connection.workspace_id).eq('assigned_user_id', connection.user_id).eq('sales_contact_id', contact.id)
        .order('updated_at', { ascending: false }).limit(1).maybeSingle() : { data: null };
      const legacyId = parsed.messageId ?? `icloud-uid-${message.uid}`;
      const { data: prior, error: priorError } = await admin.from('communication_events').select('id')
        .eq('workspace_id', connection.workspace_id).eq('actor_user_id', connection.user_id)
        .eq('provider', 'icloud').eq('provider_event_id', legacyId).eq('direction', 'inbound').maybeSingle();
      if (priorError) throw priorError;
      if (prior) continue;
      await appendCommunication(admin, {
        workspaceId: connection.workspace_id,
        contactId: contact?.id ?? null,
        leadId: lead?.id ?? null,
        actorUserId: connection.user_id,
        channel: 'email', direction: 'inbound', eventKind: 'email_received', provider: 'icloud',
        providerEventId: `mailbox:${connection.id}:${parsed.messageId ?? `icloud-uid-${message.uid}`}`,
        providerThreadId: parsed.inReplyTo ?? parsed.messageId ?? null,
        subject: parsed.subject ?? null,
        body: parsed.text ?? parsed.html?.toString() ?? '',
        fromAddress: fromEmail,
        toAddresses: [connection.email_address],
        status: 'received', occurredAt: parsed.date?.toISOString(),
        metadata: { messageId: parsed.messageId ?? null, inReplyTo: parsed.inReplyTo ?? null, icloudUid: message.uid },
      });
      imported += 1;
    }
    await admin.from('email_connections').update({
      last_uid: highestUID || connection.last_uid,
      last_synced_at: new Date().toISOString(), updated_at: new Date().toISOString(), sync_error: null,
    }).eq('id', connection.id);
    return imported;
  } catch (error) {
    await admin.from('email_connections').update({
      sync_error: error instanceof Error ? error.message.slice(0, 500) : 'iCloud sync failed',
      updated_at: new Date().toISOString(),
    }).eq('id', connection.id);
    throw error;
  } finally {
    if (client.usable) await client.logout().catch(() => undefined);
  }
}
