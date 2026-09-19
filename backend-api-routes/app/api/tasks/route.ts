import { requirePersonalReferences } from '@/lib/sales-pro/personal-references';
import { NextRequest, NextResponse } from 'next/server';
import { clampLimit, cleanText, requireSalesProContext } from '@/lib/sales-pro/context';
import { triggerSalesAutomations } from '@/lib/sales-pro/automation-trigger';

export async function GET(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const status = cleanText(request.nextUrl.searchParams.get('status')) ?? 'open';
  let query = context.admin.from('sales_tasks').select('*,sales_leads(id,name,phone,email),sales_contacts(id,name,phone,email)').eq('workspace_id', context.workspaceId).eq('assigned_user_id', context.userId).eq('sales_contacts.owner_user_id', context.userId).eq('sales_contacts.workspace_id', context.workspaceId).eq('sales_leads.assigned_user_id', context.userId).eq('sales_leads.workspace_id', context.workspaceId).order('due_at', { ascending: true }).limit(clampLimit(request.nextUrl.searchParams.get('limit'), 100, 300));
  if (status !== 'all') query = query.eq('status', status);
  const { data, error } = await query;
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ tasks: data ?? [] });
}

export async function POST(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const body = await request.json().catch(() => ({}));
  const title = cleanText(body.title);
  if (!title) return NextResponse.json({ error: 'Task title is required.' }, { status: 400 });
  const dueAt = cleanText(body.dueAt);
  if (dueAt && Number.isNaN(Date.parse(dueAt))) return NextResponse.json({ error: 'dueAt must be an ISO date.' }, { status: 400 });
  try { await requirePersonalReferences(context.admin, context.workspaceId, context.userId, { contactId: cleanText(body.contactId), leadId: cleanText(body.leadId) }); }
  catch { return NextResponse.json({ error: 'Linked record not found.' }, { status: 404 }); }
  const { data, error } = await context.admin.from('sales_tasks').insert({
    workspace_id: context.workspaceId, sales_lead_id: cleanText(body.leadId), sales_contact_id: cleanText(body.contactId),
    assigned_user_id: context.userId, task_type: cleanText(body.taskType) ?? 'follow_up',
    title, status: 'open', due_at: dueAt, notes: cleanText(body.notes), metadata: typeof body.metadata === 'object' && body.metadata ? body.metadata : {},
  }).select('*').single();
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ task: data }, { status: 201 });
}

export async function PATCH(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const body = await request.json().catch(() => ({}));
  const id = cleanText(body.id);
  if (!id) return NextResponse.json({ error: 'Task id is required.' }, { status: 400 });
  const { data: existing, error: lookupError } = await context.admin.from('sales_tasks').select('sales_contact_id,sales_lead_id')
    .eq('workspace_id', context.workspaceId).eq('assigned_user_id', context.userId).eq('id', id).maybeSingle();
  if (lookupError) return NextResponse.json({ error: 'Unable to load task.' }, { status: 500 });
  if (!existing) return NextResponse.json({ error: 'Task not found.' }, { status: 404 });
  try { await requirePersonalReferences(context.admin, context.workspaceId, context.userId, { contactId: existing.sales_contact_id, leadId: existing.sales_lead_id }); }
  catch { return NextResponse.json({ error: 'Linked record not found.' }, { status: 404 }); }
  const updates: Record<string, unknown> = {};
  if (cleanText(body.title)) updates.title = cleanText(body.title);
  if ('dueAt' in body) updates.due_at = cleanText(body.dueAt);
  if (body.status === 'open' || body.status === 'completed' || body.status === 'dismissed') {
    updates.status = body.status; updates.completed_at = body.status === 'completed' ? new Date().toISOString() : null;
  }
  const { data, error } = await context.admin.from('sales_tasks').update(updates).eq('workspace_id', context.workspaceId).eq('assigned_user_id', context.userId).eq('id', id).select('*').single();
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  if (body.status === 'completed' && data.sales_lead_id) await triggerSalesAutomations(context.admin, { workspaceId: context.workspaceId, triggerType: 'task_completed', leadId: data.sales_lead_id, contactId: data.sales_contact_id, ownerUserId: data.assigned_user_id, context: { taskId: data.id } });
  return NextResponse.json({ task: data });
}
