import { requirePersonalReferences } from '@/lib/sales-pro/personal-references';
import { NextRequest, NextResponse } from 'next/server';
import { appendCommunication, sendManagedEmail, sendManagedSms } from '@/lib/sales-pro/communications';
import { clampLimit, cleanText, decodeCursor, encodeCursor, requireSalesProContext } from '@/lib/sales-pro/context';
import { notifySalesUser } from '@/lib/sales-pro/notifications';

export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const limit = clampLimit(request.nextUrl.searchParams.get('limit'), 50, 100);
  const cursor = decodeCursor(request.nextUrl.searchParams.get('cursor'));
  const channel = cleanText(request.nextUrl.searchParams.get('channel'));
  const status = cleanText(request.nextUrl.searchParams.get('status')) ?? 'open';
  const assignee = cleanText(request.nextUrl.searchParams.get('assignee'));
  let query = context.admin.from('communication_threads')
    .select('*,sales_contacts(id,name,email,phone),sales_leads(id,name,email,phone),communication_events(*)')
    .eq('workspace_id', context.workspaceId).eq('assigned_user_id', context.userId)
    .eq('sales_contacts.owner_user_id', context.userId).eq('sales_contacts.workspace_id', context.workspaceId)
    .eq('sales_leads.assigned_user_id', context.userId).eq('sales_leads.workspace_id', context.workspaceId)
    .order('latest_event_at', { ascending: false })
    .order('id', { ascending: false })
    .limit(limit + 1);
  if (status !== 'all') query = query.eq('status', status);
  if (channel && channel !== 'all') query = query.eq('latest_channel', channel);
  if (assignee === 'me') query = query.eq('assigned_user_id', context.userId);
  else if (assignee === 'unassigned') query = query.is('assigned_user_id', null);
  else if (assignee) query = query.eq('assigned_user_id', assignee);
  if (cursor) query = query.or(`latest_event_at.lt.${cursor.date},and(latest_event_at.eq.${cursor.date},id.lt.${cursor.id})`);
  const { data, error } = await query;
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  const rows = data ?? [];
  const hasMore = rows.length > limit;
  const threads = rows.slice(0, limit).map((thread) => ({
    ...thread,
    communication_events: [...(thread.communication_events ?? [])].filter((event) => event.actor_user_id === context.userId && event.workspace_id === context.workspaceId).sort((a, b) => String(a.occurred_at).localeCompare(String(b.occurred_at))),
  }));
  const last = threads.at(-1);
  return NextResponse.json({ threads, nextCursor: hasMore && last ? encodeCursor(last.latest_event_at, last.id) : null });
}

export async function POST(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const body = await request.json().catch(() => ({}));
  const channel = cleanText(body.channel);
  const message = cleanText(body.body);
  const to = cleanText(body.to);
  if (!message || !to || (channel !== 'sms' && channel !== 'email')) {
    return NextResponse.json({ error: 'channel, to, and body are required.' }, { status: 400 });
  }
  try {
    const common = { admin: context.admin, workspaceId: context.workspaceId, userId: context.userId, senderEmail: context.email, contactId: cleanText(body.contactId), leadId: cleanText(body.leadId), to, body: message };
    const threadId = cleanText(body.threadId);
    if (threadId) {
      const { data: ownedThread, error } = await context.admin.from('communication_threads').select('id')
        .eq('workspace_id', context.workspaceId).eq('assigned_user_id', context.userId).eq('id', threadId).maybeSingle();
      if (error) throw error;
      if (!ownedThread) return NextResponse.json({ error: 'Conversation not found.' }, { status: 404 });
    }
    const { data: lastInbound } = threadId ? await context.admin.from('communication_events').select('provider_thread_id,metadata').eq('workspace_id', context.workspaceId).eq('thread_id', threadId).eq('actor_user_id', context.userId).eq('channel', 'email').eq('direction', 'inbound').order('occurred_at', { ascending: false }).limit(1).maybeSingle() : { data: null };
    const inReplyTo = lastInbound?.metadata?.messageId ?? lastInbound?.provider_thread_id ?? null;
    const result = channel === 'email'
      ? await sendManagedEmail({ ...common, subject: cleanText(body.subject) ?? 'WolfGrid follow-up', inReplyTo })
      : await sendManagedSms(common);
    return NextResponse.json(result, { status: 201 });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Reply failed.' }, { status: 502 });
  }
}

export async function PATCH(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const body = await request.json().catch(() => ({}));
  const id = cleanText(body.id);
  if (!id) return NextResponse.json({ error: 'Thread id is required.' }, { status: 400 });
  try { await requirePersonalReferences(context.admin, context.workspaceId, context.userId, { contactId: cleanText(body.contactId), leadId: cleanText(body.leadId) }); }
  catch { return NextResponse.json({ error: 'Linked record not found.' }, { status: 404 }); }
  const updates: Record<string, unknown> = {};
  if (['open', 'done', 'archived'].includes(body.status)) updates.status = body.status;
  if ('assignedUserId' in body && body.assignedUserId !== context.userId) return NextResponse.json({ error: 'Personal conversations cannot be reassigned.' }, { status: 403 });
  if ('contactId' in body) updates.sales_contact_id = cleanText(body.contactId);
  if ('leadId' in body) updates.sales_lead_id = cleanText(body.leadId);
  if (body.read === true) updates.last_read_at = new Date().toISOString();
  if (body.needsResponse === false) updates.needs_response = false;
  const { data, error } = await context.admin.from('communication_threads').update(updates)
    .eq('workspace_id', context.workspaceId).eq('assigned_user_id', context.userId).eq('id', id).select('*').single();
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  if (cleanText(body.assignedUserId)) await notifySalesUser(context.admin, { workspaceId: context.workspaceId, userId: cleanText(body.assignedUserId), type: 'inbox_assignment', title: 'Conversation assigned to you', body: data.subject ?? 'Open WolfGrid Sales to respond.', data: { threadId: id } });
  if (body.read === true) await context.admin.from('communication_events').update({ read_at: new Date().toISOString() }).eq('workspace_id', context.workspaceId).eq('actor_user_id', context.userId).eq('thread_id', id).is('read_at', null);
  await appendCommunication(context.admin, {
    workspaceId: context.workspaceId, contactId: data.sales_contact_id, leadId: data.sales_lead_id,
    actorUserId: context.userId, channel: 'notification', direction: 'internal', eventKind: 'thread_updated',
    body: cleanText(body.note) ?? 'Conversation updated.', metadata: { threadId: id, updates },
  });
  return NextResponse.json({ thread: data });
}
