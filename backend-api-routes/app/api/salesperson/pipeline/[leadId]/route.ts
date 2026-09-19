import { NextRequest, NextResponse } from 'next/server';
import {
  decorateLeadsWithMembers,
  loadPipelineMembers,
  parsePipelineUpdate,
  PIPELINE_LEAD_SELECT,
  resolvePipelineContext,
} from '../_lib';
import { pipelineStageLabel, pipelineTaskTypeLabel } from '@/lib/sales-pipeline/constants';
import type { SalesLead } from '@/types/database';
import { triggerSalesAutomations } from '@/lib/sales-pro/automation-trigger';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

async function loadAccessibleLead(
  context: Exclude<Awaited<ReturnType<typeof resolvePipelineContext>>, NextResponse>,
  leadId: string
) {
  const { admin, requestUser, salesperson, isFounder, workspaceId } = context;
  if (!workspaceId) return null;

  let query = admin
    .from('sales_leads')
    .select(PIPELINE_LEAD_SELECT)
    .eq('workspace_id', workspaceId)
    .eq('id', leadId)
    .limit(1);

  query = query.eq('assigned_user_id', requestUser.id);

  const { data, error } = await query.maybeSingle();
  if (error) throw new Error(error.message);
  return (data as SalesLead | null) ?? null;
}

function changeSummary(before: SalesLead, updates: Record<string, unknown>): string | null {
  if (typeof updates.pipeline_stage === 'string' && updates.pipeline_stage !== before.pipeline_stage) {
    return `Stage changed to ${pipelineStageLabel(updates.pipeline_stage)}.`;
  }
  if (typeof updates.next_task_title === 'string' && updates.next_task_title !== before.next_task_title) {
    return `Next task updated: ${updates.next_task_title}`;
  }
  if (typeof updates.next_task_type === 'string' && updates.next_task_type !== before.next_task_type) {
    return `Task type changed to ${pipelineTaskTypeLabel(updates.next_task_type)}.`;
  }
  if (typeof updates.pipeline_priority === 'string' && updates.pipeline_priority !== before.pipeline_priority) {
    return `Priority changed to ${updates.pipeline_priority}.`;
  }
  return null;
}

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ leadId: string }> }
) {
  const { leadId } = await params;
  const context = await resolvePipelineContext(request);
  if (context instanceof NextResponse) return context;

  try {
    const before = await loadAccessibleLead(context, leadId);
    if (!before) return NextResponse.json({ error: 'Lead not found.' }, { status: 404 });

    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    const updates = parsePipelineUpdate(body);
    const requestedStageId = typeof body.pipelineStageId === 'string' ? body.pipelineStageId : typeof body.pipeline_stage_id === 'string' ? body.pipeline_stage_id : null;
    let requestedStage: { id: string; name: string; stage_key: string } | null = null;
    if (requestedStageId) {
      const stageResult = await context.admin.from('sales_pipeline_stages').select('id,name,stage_key')
        .eq('workspace_id', before.workspace_id).eq('id', requestedStageId).eq('is_archived', false).maybeSingle();
      if (!stageResult.data) return NextResponse.json({ error: 'Pipeline stage not found.' }, { status: 400 });
      requestedStage = stageResult.data;
      updates.pipeline_stage_id = requestedStage.id;
      updates.pipeline_stage = requestedStage.stage_key === 'won' || requestedStage.stage_key === 'lost'
        ? requestedStage.stage_key
        : requestedStage.stage_key === 'proposal' ? 'closing'
          : requestedStage.stage_key === 'conversation' || requestedStage.stage_key === 'meeting_booked' ? 'connected'
            : requestedStage.stage_key === 'contacted' ? 'attempting_contact' : 'new_lead';
    }
    if (Object.keys(updates).length === 0) {
      return NextResponse.json({ lead: before });
    }

    const { data, error } = await context.admin
      .from('sales_leads')
      .update(updates)
      .eq('id', before.id)
      .eq('workspace_id', before.workspace_id)
      .select(PIPELINE_LEAD_SELECT)
      .single();

    if (error) throw new Error(error.message);

    const summary = requestedStage ? `Stage changed to ${requestedStage.name}.` : changeSummary(before, updates);
    if (summary) {
      await context.admin.from('sales_activities').insert({
        sales_lead_id: before.id,
        workspace_id: before.workspace_id,
        actor_user_id: context.requestUser.id,
        activity_type:
          typeof updates.pipeline_stage === 'string' && updates.pipeline_stage !== before.pipeline_stage
            ? 'stage_change'
            : 'task_change',
        note: summary,
        occurred_at: new Date().toISOString(),
        metadata: {
          title: summary,
          legacySalespersonId: before.assigned_salesperson_id ?? context.salesperson?.id ?? null,
          before,
          updates,
        },
      });
      if (requestedStage) await triggerSalesAutomations(context.admin, { workspaceId: before.workspace_id, triggerType: 'stage_entry', leadId: before.id, contactId: (before as SalesLead & { sales_contact_id?: string }).sales_contact_id, ownerUserId: before.assigned_user_id, context: { stageId: requestedStage.id, stageKey: requestedStage.stage_key } });
    }

    const members = await loadPipelineMembers(context.admin, before.workspace_id);
    const [lead] = decorateLeadsWithMembers([data as SalesLead], members);
    return NextResponse.json({ lead });
  } catch (error) {
    console.error('[api/salesperson/pipeline lead] PATCH error:', error);
    return NextResponse.json(
      { error: error instanceof Error ? error.message : 'Failed to update pipeline lead.' },
      { status: 500 }
    );
  }
}
