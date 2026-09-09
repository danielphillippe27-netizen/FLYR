import { NextRequest, NextResponse } from 'next/server';
import { cleanText, requireSalesProContext } from '@/lib/sales-pro/context';

export async function POST(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const body = await request.json().catch(() => ({}));
  const automationId = cleanText(body.automationId); const leadId = cleanText(body.leadId);
  if (!automationId || !leadId) return NextResponse.json({ error: 'automationId and leadId are required.' }, { status: 400 });
  const { data: automation } = await context.admin.from('sales_automation_definitions').select('id,active_version,is_enabled').eq('workspace_id', context.workspaceId).eq('id', automationId).single();
  if (!automation?.is_enabled) return NextResponse.json({ error: 'Automation is not enabled.' }, { status: 409 });
  const now = new Date().toISOString();
  const { data, error } = await context.admin.from('sales_sequence_enrollments').insert({ workspace_id: context.workspaceId, automation_id: automationId, automation_version: automation.active_version, sales_lead_id: leadId, sales_contact_id: cleanText(body.contactId), owner_user_id: cleanText(body.ownerUserId) ?? context.userId, status: 'active', current_step: 0, next_run_at: now }).select('*').single();
  if (error) return NextResponse.json({ error: error.message }, { status: 409 });
  await context.admin.from('sales_automation_executions').insert({ workspace_id: context.workspaceId, enrollment_id: data.id, step_index: 0, idempotency_key: `${data.id}:0`, scheduled_for: now });
  return NextResponse.json({ enrollment: data }, { status: 201 });
}

export async function PATCH(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const body = await request.json().catch(() => ({})); const id = cleanText(body.id);
  if (!id || !['active', 'paused', 'stopped'].includes(body.status)) return NextResponse.json({ error: 'A valid enrollment id and status are required.' }, { status: 400 });
  const { data, error } = await context.admin.from('sales_sequence_enrollments').update({ status: body.status, stop_reason: body.status === 'stopped' ? cleanText(body.reason) ?? 'manual' : null }).eq('workspace_id', context.workspaceId).eq('id', id).select('*').single();
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ enrollment: data });
}
