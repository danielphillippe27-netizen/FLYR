import { NextRequest, NextResponse } from 'next/server';
import { cleanText, requireSalesProContext } from '@/lib/sales-pro/context';

const TRIGGERS = new Set(['stage_entry', 'missed_call', 'inbound_reply', 'no_reply', 'meeting_booked', 'meeting_completed', 'task_completed']);
const ACTIONS = new Set(['delay', 'sms', 'email', 'call_task', 'task', 'notification', 'stage_update', 'assignment', 'enroll']);

export async function GET(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const { data, error } = await context.admin.from('sales_automation_definitions').select('*,sales_automation_versions(*)').eq('workspace_id', context.workspaceId).eq('created_by_user_id', context.userId).order('updated_at', { ascending: false });
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ automations: data ?? [] });
}

export async function POST(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const body = await request.json().catch(() => ({}));
  const name = cleanText(body.name); const triggerType = cleanText(body.triggerType); const steps = Array.isArray(body.steps) ? body.steps : [];
  if (!name || !triggerType || !TRIGGERS.has(triggerType)) return NextResponse.json({ error: 'A valid name and trigger are required.' }, { status: 400 });
  if (!steps.length || steps.some((step: Record<string, unknown>) => !ACTIONS.has(String(step.action ?? '')))) return NextResponse.json({ error: 'Every automation needs valid steps.' }, { status: 400 });
  const created = await context.admin.from('sales_automation_definitions').insert({ workspace_id: context.workspaceId, name, trigger_type: triggerType, trigger_config: body.triggerConfig ?? {}, is_enabled: body.isEnabled === true, active_version: 1, created_by_user_id: context.userId }).select('*').single();
  if (created.error) return NextResponse.json({ error: created.error.message }, { status: 400 });
  const version = await context.admin.from('sales_automation_versions').insert({ automation_id: created.data.id, version: 1, steps, published_by_user_id: context.userId }).select('*').single();
  if (version.error) { await context.admin.from('sales_automation_definitions').delete().eq('id', created.data.id); return NextResponse.json({ error: version.error.message }, { status: 400 }); }
  return NextResponse.json({ automation: created.data, version: version.data }, { status: 201 });
}

export async function PATCH(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const body = await request.json().catch(() => ({})); const id = cleanText(body.id);
  if (!id) return NextResponse.json({ error: 'Automation id is required.' }, { status: 400 });
  const { data: existing } = await context.admin.from('sales_automation_definitions').select('*').eq('workspace_id', context.workspaceId).eq('created_by_user_id', context.userId).eq('id', id).single();
  if (!existing) return NextResponse.json({ error: 'Automation not found.' }, { status: 404 });
  let nextVersion = existing.active_version;
  if (Array.isArray(body.steps)) {
    if (!body.steps.length || body.steps.some((step: Record<string, unknown>) => !ACTIONS.has(String(step.action ?? '')))) return NextResponse.json({ error: 'Every automation needs valid steps.' }, { status: 400 });
    nextVersion += 1;
    const version = await context.admin.from('sales_automation_versions').insert({ automation_id: id, version: nextVersion, steps: body.steps, published_by_user_id: context.userId });
    if (version.error) return NextResponse.json({ error: version.error.message }, { status: 400 });
  }
  const updates: Record<string, unknown> = { active_version: nextVersion };
  if (cleanText(body.name)) updates.name = cleanText(body.name);
  if (typeof body.isEnabled === 'boolean') updates.is_enabled = body.isEnabled;
  const { data, error } = await context.admin.from('sales_automation_definitions').update(updates).eq('workspace_id', context.workspaceId).eq('created_by_user_id', context.userId).eq('id', id).select('*').single();
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ automation: data });
}
