import type { SupabaseClient } from '@supabase/supabase-js';

const PAGE_SIZE = 1000;
const FAILED = new Set(['failed', 'rejected', 'canceled', 'cancelled', 'undelivered', 'draft', 'scheduled', 'pending']);

export function containsDemoLink(body: string | null | undefined): boolean {
  const links: string[] = body?.match(/https?:\/\/[^\s<>"']+/gi) ?? [];
  return links.some((candidate) => {
    try {
      const url = new URL(candidate.replace(/[),.!;]+$/, ''));
      return ['wolfgrid.app', 'www.wolfgrid.app'].includes(url.hostname.toLowerCase())
        && /^\/(demo100|demo-1|demo-2|d\/[^/]+)\/?$/.test(url.pathname);
    } catch { return false; }
  });
}

type Row = Record<string, any>;
export function countPersonalOutreach(canonical: Row[], messages: Row[], followups: Row[], emails: Row[], inbound: Row[] = []) {
  const received = new Set<string>();
  for (const [source, rows] of [['canonical', canonical], ['inbound', inbound]] as const) {
    for (const row of rows) {
      if (source === 'canonical' && (row.direction !== 'inbound' || row.channel !== 'sms')) continue;
      if (FAILED.has(String(row.status ?? '').toLowerCase())) continue;
      const providerId = source === 'canonical' ? row.metadata?.providerMessageId ?? row.provider_event_id : row.provider_message_id ?? row.twilio_message_sid;
      const provider = row.provider ?? row.telecom_provider ?? (row.twilio_message_sid ? 'twilio' : 'telnyx');
      received.add(providerId ? `${provider}:${providerId}` : `${source}:${row.id}`);
    }
  }
  const sent = new Map<string, { channel: string; demo: boolean }>();
  for (const [source, rows] of [['canonical', canonical], ['messages', messages], ['followups', followups], ['emails', emails]] as const) {
    for (const row of rows) {
      if (FAILED.has(String(row.status ?? '').toLowerCase())) continue;
      if (source === 'canonical' && row.direction !== 'outbound') continue;
      if (source === 'messages' && row.direction !== 'outbound') continue;
      const channel = source === 'canonical' ? row.channel : source === 'emails' ? 'email' : 'sms';
      if (!['email', 'sms'].includes(channel)) continue;
      const providerId = source === 'canonical'
        ? row.metadata?.providerMessageId ?? row.provider_event_id
        : row.provider_message_id ?? row.twilio_message_sid;
      const provider = row.provider ?? row.telecom_provider ?? (row.twilio_message_sid ? 'twilio' : 'telnyx');
      const key = providerId ? `${channel}:${provider}:${providerId}` : `${source}:${row.id}`;
      const demo = row.event_kind === 'demo_sent' || containsDemoLink(row.body ?? row.note);
      sent.set(key, { channel, demo: demo || sent.get(key)?.demo === true });
    }
  }
  return {
    inboundMessages: received.size,
    outboundMessages: [...sent.values()].filter(row => row.channel === 'sms').length,
    emails: [...sent.values()].filter(row => row.channel === 'email').length,
    demosSent: [...sent.values()].filter(row => row.demo).length,
  };
}

export async function loadPersonalOutreach(admin: SupabaseClient, params: {
  userId: string; workspaceId: string; start: string; end: string;
}) {
  async function rows(table: string, owner: string, time: string, select: string) {
    const result: Row[] = [];
    for (let offset = 0; ; offset += PAGE_SIZE) {
      let query = admin.from(table).select(select).eq(owner, params.userId)
        .gte(time, params.start).lt(time, params.end).order('id').range(offset, offset + PAGE_SIZE - 1);
      if (table === 'contact_activities') {
        query = query.eq('type', 'email').eq('contacts.workspace_id', params.workspaceId);
      } else {
        query = query.eq('workspace_id', params.workspaceId);
      }
      if (table === 'dialer_messages') query = query.eq('direction', 'outbound');
      const { data, error } = await query;
      if (error) throw error; // Do not turn an unavailable personal metric into a workspace fallback or false zero.
      const page = (data ?? []) as unknown as Row[];
      result.push(...page);
      if (page.length < PAGE_SIZE) return result;
    }
  }
  const [canonical, messages, followups, inbound, emails] = await Promise.all([
    rows('communication_events', 'actor_user_id', 'occurred_at', 'id,channel,direction,event_kind,status,provider,provider_event_id,body,metadata'),
    rows('dialer_messages', 'sender_user_id', 'created_at', 'id,direction,status,provider,provider_message_id,body'),
    rows('dialer_sms_followups', 'user_id', 'created_at', 'id,status,telecom_provider,provider_message_id,twilio_message_sid,body'),
    rows('dialer_inbound_messages', 'owner_user_id', 'received_at', 'id,telecom_provider,provider_message_id,twilio_message_sid'),
    rows('contact_activities', 'communication_owner_user_id', 'timestamp', 'id,note,contacts!inner(workspace_id)'),
  ]);
  return countPersonalOutreach(canonical, messages, followups, emails, inbound);
}
