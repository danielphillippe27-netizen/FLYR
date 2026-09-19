import { requirePersonalReferences } from '@/lib/sales-pro/personal-references';
import { NextRequest, NextResponse } from 'next/server';
import { cleanText, requireSalesProContext } from '@/lib/sales-pro/context';
import { triggerSalesAutomations } from '@/lib/sales-pro/automation-trigger';

export async function GET(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const from = cleanText(request.nextUrl.searchParams.get('from')) ?? new Date(Date.now() - 30 * 86400_000).toISOString();
  const { data, error } = await context.admin.from('sales_bookings').select('*,sales_contacts(*),sales_leads(*)').eq('workspace_id', context.workspaceId).eq('assigned_user_id', context.userId).eq('sales_contacts.owner_user_id', context.userId).eq('sales_contacts.workspace_id', context.workspaceId).eq('sales_leads.assigned_user_id', context.userId).eq('sales_leads.workspace_id', context.workspaceId).gte('ends_at', from).order('starts_at');
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ bookings: data ?? [] });
}

export async function PATCH(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const body = await request.json().catch(() => ({})); const id = cleanText(body.id);
  const outcome = cleanText(body.outcome);
  if (!id || !['held', 'no_show', 'rescheduled', 'cancelled'].includes(outcome ?? '')) return NextResponse.json({ error: 'Booking id and outcome are required.' }, { status: 400 });
  const { data: existing } = await context.admin.from('sales_bookings').select('*').eq('workspace_id', context.workspaceId).eq('assigned_user_id', context.userId).eq('id', id).single();
  if (!existing) return NextResponse.json({ error: 'Booking not found.' }, { status: 404 });
  try { await requirePersonalReferences(context.admin, context.workspaceId, context.userId, { contactId: existing.sales_contact_id, leadId: existing.sales_lead_id }); }
  catch { return NextResponse.json({ error: 'Linked record not found.' }, { status: 404 }); }
  let nextTaskId: string | null = null;
  const nextTaskTitle = cleanText(body.nextTaskTitle);
  if (nextTaskTitle) {
    const task = await context.admin.from('sales_tasks').insert({ workspace_id: context.workspaceId, sales_lead_id: existing.sales_lead_id, sales_contact_id: existing.sales_contact_id, assigned_user_id: existing.assigned_user_id, task_type: cleanText(body.nextTaskType) ?? 'follow_up', title: nextTaskTitle, status: 'open', due_at: cleanText(body.nextTaskDueAt), notes: cleanText(body.notes), metadata: { bookingId: id } }).select('id').single();
    if (task.error) return NextResponse.json({ error: task.error.message }, { status: 400 });
    nextTaskId = task.data.id;
  }
  const status = outcome === 'held' ? 'completed' : outcome;
  const { data, error } = await context.admin.from('sales_bookings').update({ outcome, status, notes: cleanText(body.notes), next_task_id: nextTaskId }).eq('id', id).eq('workspace_id', context.workspaceId).eq('assigned_user_id', context.userId).select('*').single();
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  await context.admin.from('sales_activities').insert({ workspace_id: context.workspaceId, sales_lead_id: existing.sales_lead_id, sales_contact_id: existing.sales_contact_id, sales_task_id: nextTaskId, actor_user_id: context.userId, activity_type: 'meeting_outcome', note: cleanText(body.notes) ?? `Meeting outcome: ${outcome}`, metadata: { bookingId: id, outcome } });
  if (existing.sales_lead_id) await triggerSalesAutomations(context.admin, { workspaceId: context.workspaceId, triggerType: 'meeting_completed', leadId: existing.sales_lead_id, contactId: existing.sales_contact_id, ownerUserId: existing.assigned_user_id, context: { bookingId: id, outcome } });
  return NextResponse.json({ booking: data });
}
