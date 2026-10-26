import { normalizePhoneNumber } from './phone';

export type ActivityLogItem = {
  id: string; timelineKind: string; channel: string; subject: string;
  body: string | null; note: string | null; status: string | null; direction: string | null;
  occurred_at: string; at: string; activity_type: string;
};
type Row = Record<string, any>;
const text = (value: unknown) => typeof value === 'string' && value.trim() ? value.trim() : null;
const human = (value: unknown) => (text(value) ?? '').replaceAll('_', ' ');

export function mergeActivityLogs(sources: Record<string, Row[]>): ActivityLogItem[] {
  const result: ActivityLogItem[] = [];
  const calls = sources.calls ?? [];
  const messages = sources.messages ?? [];
  const callProviderIds = new Set(calls.flatMap(row => [row.id, row.provider_call_id, row.call_request_id, row.provider_call_control_id]).filter(Boolean));
  const messageProviderIds = new Set(messages.flatMap(row => [row.id, row.provider_message_id]).filter(Boolean));
  function add(kind: string, row: Row, channel: string, subject: string, at: unknown, body?: unknown) {
    if (!text(at) || !Number.isFinite(Date.parse(String(at)))) return;
    result.push({ id: `${kind}:${row.id}`, timelineKind: kind, channel, subject,
      body: text(body), note: text(body), status: text(row.status), direction: text(row.direction),
      occurred_at: String(at), at: String(at), activity_type: text(row.activity_type) ?? kind });
  }
  for (const row of calls) {
    const seconds = row.duration_seconds ?? (row.answered_at && row.ended_at ? Math.max(0, Math.round((Date.parse(row.ended_at) - Date.parse(row.answered_at)) / 1000)) : 0);
    const duration = seconds > 0 ? ` · ${Math.floor(seconds / 60)}m ${seconds % 60}s` : '';
    add('call', row, 'call', `${row.direction === 'inbound' ? 'Incoming' : 'Outgoing'} call · ${human(row.disposition || row.status)}${duration}`, row.started_at ?? row.created_at, row.disposition_note);
  }
  for (const row of messages) add('text', row, 'sms', `${row.direction === 'inbound' ? 'Text received' : 'Text sent'}${row.status ? ` · ${human(row.status)}` : ''}`, row.sent_at ?? row.received_at ?? row.created_at, row.body);
  for (const row of sources.communications ?? []) {
    if (row.channel === 'call' && callProviderIds.has(row.provider_event_id)) continue;
    if (row.channel === 'sms' && messageProviderIds.has(row.provider_event_id)) continue;
    add('communication', row, row.channel ?? 'note', row.subject || (row.channel === 'email' ? `Email ${row.direction === 'inbound' ? 'received' : 'sent'}` : row.channel === 'sms' ? `Text ${row.direction === 'inbound' ? 'received' : 'sent'}` : human(row.event_kind || row.channel)), row.occurred_at ?? row.created_at, row.body);
  }
  for (const row of sources.activities ?? []) {
    // Sending writes both a communication and an activity receipt. Show one event.
    const channel = row.activity_type === 'text' ? 'sms' : row.activity_type;
    if (['email', 'sms'].includes(channel) && (sources.communications ?? []).some(event => event.channel === channel && event.occurred_at === row.occurred_at)) continue;
    add('activity', row, ['call', 'email', 'sms', 'meeting'].includes(channel) ? channel : 'note', row.activity_type === 'call' ? 'Call disposition saved' : human(row.activity_type), row.occurred_at ?? row.created_at, row.note);
  }
  for (const row of sources.legacyActivities ?? []) add('contact_activity', row, row.type === 'text' ? 'sms' : row.type ?? 'note', human(row.type || 'Note'), row.timestamp ?? row.created_at, row.note);
  for (const row of sources.tasks ?? []) {
    add('task_created', row, 'task', `Follow-up created: ${row.title}`, row.created_at, row.notes);
    if (row.completed_at) add('task_completed', row, 'task', `Follow-up completed: ${row.title}`, row.completed_at, row.notes);
  }
  for (const row of sources.calendar ?? []) {
    add('calendar_created', row, row.event_type === 'follow_up' ? 'task' : 'meeting', `${row.event_type === 'follow_up' ? 'Follow-up' : 'Meeting'} scheduled: ${row.title}`, row.created_at, [row.start_at ? `Scheduled for ${row.start_at}` : '', row.notes].filter(Boolean).join('\n'));
    if (row.deleted_at) add('calendar_closed', row, 'task', `Closed: ${row.title}`, row.deleted_at);
  }
  for (const row of sources.bookings ?? []) add('meeting', row, 'meeting', `Meeting ${human(row.outcome || 'booked')}`, row.created_at, `${row.guest_name ?? ''}${row.starts_at ? ` · ${row.starts_at}` : ''}`);
  for (const row of sources.campaigns ?? []) add('campaign', row, 'note', 'Added to campaign', row.created_at, row.name);
  return result.sort((a, b) => Date.parse(b.at) - Date.parse(a.at) || b.id.localeCompare(a.id));
}

/** All raw and canonical events are read under both workspace and personal ownership. */
export async function loadActivityLogs(context: { admin: any; workspaceId: string; userId: string }, references: { leadId?: string | null; contactId?: string | null }, limit: number, offset: number) {
  const { admin, workspaceId, userId } = context;
  let leadQuery = admin.from('sales_leads').select('id,sales_contact_id,legacy_contact_id,converted_contact_id,phone,phone_e164')
    .eq('workspace_id', workspaceId).eq('assigned_user_id', userId);
  leadQuery = references.leadId ? leadQuery.eq('id', references.leadId) : leadQuery.eq('sales_contact_id', references.contactId);
  const leadResult = await leadQuery.limit(200);
  if (leadResult.error) throw leadResult.error;
  const leads = leadResult.data ?? [];
  const leadIds = leads.map((row: Row) => row.id);
  const contactIds = [...new Set([references.contactId, ...leads.map((row: Row) => row.sales_contact_id)].filter(Boolean))];
  const contactResult = contactIds.length ? await admin.from('sales_contacts').select('id,phone').eq('workspace_id', workspaceId).eq('owner_user_id', userId).in('id', contactIds) : { data: [], error: null };
  if (contactResult.error) throw contactResult.error;
  const phones = [...new Set<string>([...leads, ...(contactResult.data ?? [])].map((row: Row) => normalizePhoneNumber(row.phone_e164 || row.phone).e164).filter(Boolean))];
  const legacyIds = [...new Set(leads.flatMap((row: Row) => [row.legacy_contact_id, row.converted_contact_id]).filter(Boolean))];
  const personalLegacy = legacyIds.length ? await admin.from('contacts').select('id').eq('workspace_id', workspaceId).eq('user_id', userId).in('id', legacyIds) : { data: [], error: null };
  if (personalLegacy.error) throw personalLegacy.error;
  const ownedLegacyIds = (personalLegacy.data ?? []).map((row: Row) => row.id);
  const clauses = (leadColumn: string, contactColumn: string, ids = contactIds) => [
    ...(leadIds.length ? [`${leadColumn}.in.(${leadIds.join(',')})`] : []),
    ...(ids.length ? [`${contactColumn}.in.(${ids.join(',')})`] : []),
  ];
  const filter = (query: any, parts: string[]) => parts.length ? query.or(parts.join(',')) : null;
  const cap = offset + limit + 1;
  const linked = (table: string, owner: string, date: string) => filter(admin.from(table).select('*').eq('workspace_id', workspaceId).eq(owner, userId).order(date, { ascending: false }).limit(cap), clauses('sales_lead_id', 'sales_contact_id'));
  const callClauses = [...clauses('sales_lead_id', 'contact_id', ownedLegacyIds), ...phones.flatMap(phone => [`and(direction.eq.outbound,to_number_e164.eq.${phone})`, `and(direction.eq.inbound,from_number_e164.eq.${phone})`])];
  const smsClauses = [...(ownedLegacyIds.length ? [`contact_id.in.(${ownedLegacyIds.join(',')})`] : []), ...phones.flatMap(phone => [`and(direction.eq.outbound,to_number_e164.eq.${phone})`, `and(direction.eq.inbound,from_number_e164.eq.${phone})`])];
  const queries: Record<string, any> = {
    calls: filter(admin.from('dialer_calls').select('*').eq('workspace_id', workspaceId).eq('user_id', userId).order('created_at', { ascending: false }).limit(cap), callClauses),
    messages: filter(admin.from('dialer_messages').select('*').eq('workspace_id', workspaceId).eq('sender_user_id', userId).order('created_at', { ascending: false }).limit(cap), smsClauses),
    activities: linked('sales_activities', 'actor_user_id', 'occurred_at'),
    communications: linked('communication_events', 'actor_user_id', 'occurred_at'),
    tasks: linked('sales_tasks', 'assigned_user_id', 'created_at'),
    bookings: linked('sales_bookings', 'assigned_user_id', 'created_at'),
    calendar: filter(admin.from('calendar_events').select('*').eq('workspace_id', workspaceId).eq('user_id', userId).order('created_at', { ascending: false }).limit(cap), [...(leadIds.length ? [`and(source_kind.eq.sales_lead_follow_up,source_id.in.(${leadIds.join(',')}))`] : []), ...([...ownedLegacyIds, ...contactIds].length ? [`contact_id.in.(${[...ownedLegacyIds, ...contactIds].join(',')})`] : [])]),
    legacyActivities: ownedLegacyIds.length ? admin.from('contact_activities').select('*').eq('communication_owner_user_id', userId).in('contact_id', ownedLegacyIds).order('timestamp', { ascending: false }).limit(cap) : null,
  };
  const entries = await Promise.all(Object.entries(queries).map(async ([key, query]) => {
    if (!query) return [key, []] as const;
    const result = await query;
    if (result.error) throw new Error(`Unable to load ${key} activity: ${result.error.message}`);
    return [key, result.data ?? []] as const;
  }));
  const memberships = contactIds.length ? await admin.from('sales_contact_campaigns').select('created_at,campaign_id').eq('workspace_id', workspaceId).in('sales_contact_id', contactIds).order('created_at', { ascending: false }).limit(cap) : { data: [], error: null };
  if (memberships.error) throw memberships.error;
  const campaignIds = (memberships.data ?? []).map((row: Row) => row.campaign_id);
  const campaigns = campaignIds.length ? await admin.from('campaigns').select('id,name,title').eq('workspace_id', workspaceId).eq('owner_id', userId).in('id', campaignIds) : { data: [], error: null };
  if (campaigns.error) throw campaigns.error;
  entries.push(['campaigns', (memberships.data ?? []).flatMap((row: Row) => {
    const campaign = (campaigns.data ?? []).find((item: Row) => item.id === row.campaign_id);
    return campaign ? [{ ...row, id: `${row.campaign_id}:${row.created_at}`, name: campaign.name ?? campaign.title }] : [];
  })]);
  const merged = mergeActivityLogs(Object.fromEntries(entries));
  return { timeline: merged.slice(offset, offset + limit), hasMore: merged.length > offset + limit };
}
