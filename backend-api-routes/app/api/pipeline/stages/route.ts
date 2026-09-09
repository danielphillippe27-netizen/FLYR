import { NextRequest, NextResponse } from 'next/server';
import { cleanText, requireSalesProContext } from '@/lib/sales-pro/context';

export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const { data, error } = await context.admin
    .from('sales_pipeline_stages')
    .select('*')
    .eq('workspace_id', context.workspaceId)
    .order('position');
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ stages: data ?? [] });
}

export async function POST(request: NextRequest) {
  const context = await requireSalesProContext(request, { admin: true });
  if (context instanceof NextResponse) return context;
  const body = await request.json().catch(() => ({}));
  const name = cleanText(body.name);
  if (!name) return NextResponse.json({ error: 'Stage name is required.' }, { status: 400 });
  const stageKey = cleanText(body.stageKey) ?? name.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '');
  const { data: last } = await context.admin
    .from('sales_pipeline_stages')
    .select('position')
    .eq('workspace_id', context.workspaceId)
    .order('position', { ascending: false })
    .limit(1)
    .maybeSingle();
  const { data, error } = await context.admin
    .from('sales_pipeline_stages')
    .insert({
      workspace_id: context.workspaceId,
      stage_key: stageKey,
      name,
      color: cleanText(body.color) ?? '#64748B',
      position: Number.isFinite(Number(body.position)) ? Math.trunc(Number(body.position)) : Number(last?.position ?? 0) + 10,
      terminal_kind: body.terminalKind === 'won' || body.terminalKind === 'lost' ? body.terminalKind : null,
      created_by_user_id: context.userId,
    })
    .select('*')
    .single();
  if (error) return NextResponse.json({ error: error.message }, { status: 409 });
  return NextResponse.json({ stage: data }, { status: 201 });
}

export async function PATCH(request: NextRequest) {
  const context = await requireSalesProContext(request, { admin: true });
  if (context instanceof NextResponse) return context;
  const body = await request.json().catch(() => ({}));
  if (Array.isArray(body.order)) {
    const ids = body.order.filter((value: unknown): value is string => typeof value === 'string');
    const { data: existing } = await context.admin.from('sales_pipeline_stages').select('id').eq('workspace_id', context.workspaceId).in('id', ids);
    if ((existing ?? []).length !== ids.length) return NextResponse.json({ error: 'One or more stages are invalid.' }, { status: 400 });
    for (let index = 0; index < ids.length; index += 1) await context.admin.from('sales_pipeline_stages').update({ position: 100000 + index }).eq('id', ids[index]);
    for (let index = 0; index < ids.length; index += 1) await context.admin.from('sales_pipeline_stages').update({ position: (index + 1) * 10 }).eq('id', ids[index]);
    const { data } = await context.admin.from('sales_pipeline_stages').select('*').eq('workspace_id', context.workspaceId).order('position');
    return NextResponse.json({ stages: data ?? [] });
  }
  const id = cleanText(body.id);
  if (!id) return NextResponse.json({ error: 'Stage id is required.' }, { status: 400 });

  if (body.isArchived === true) {
    const { count } = await context.admin
      .from('sales_leads')
      .select('*', { count: 'exact', head: true })
      .eq('workspace_id', context.workspaceId)
      .eq('pipeline_stage_id', id);
    if ((count ?? 0) > 0) {
      return NextResponse.json({ error: 'Reassign leads before archiving this stage.', leadCount: count }, { status: 409 });
    }
  }

  const updates: Record<string, unknown> = {};
  if (cleanText(body.name)) updates.name = cleanText(body.name);
  if (cleanText(body.color)) updates.color = cleanText(body.color);
  if (Number.isFinite(Number(body.position))) updates.position = Math.trunc(Number(body.position));
  if (typeof body.isArchived === 'boolean') updates.is_archived = body.isArchived;
  if (body.terminalKind === null || body.terminalKind === 'won' || body.terminalKind === 'lost') updates.terminal_kind = body.terminalKind;
  const { data, error } = await context.admin
    .from('sales_pipeline_stages')
    .update(updates)
    .eq('workspace_id', context.workspaceId)
    .eq('id', id)
    .select('*')
    .single();
  if (error) return NextResponse.json({ error: error.message }, { status: 409 });
  return NextResponse.json({ stage: data });
}
