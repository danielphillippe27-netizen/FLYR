import { requirePersonalReferences } from '@/lib/sales-pro/personal-references';
import type { SupabaseClient } from '@supabase/supabase-js';

export async function triggerSalesAutomations(admin: SupabaseClient, input: {
  workspaceId: string; triggerType: 'stage_entry' | 'missed_call' | 'inbound_reply' | 'no_reply' | 'meeting_booked' | 'meeting_completed' | 'task_completed';
  leadId?: string | null; contactId?: string | null; ownerUserId?: string | null; context?: Record<string, unknown>;
}) {
  if (!input.leadId || !input.ownerUserId) return [];
  await requirePersonalReferences(admin, input.workspaceId, input.ownerUserId, { leadId: input.leadId, contactId: input.contactId });
  const { data: definitions } = await admin.from('sales_automation_definitions').select('*')
    .eq('workspace_id', input.workspaceId).eq('created_by_user_id', input.ownerUserId).eq('trigger_type', input.triggerType).eq('is_enabled', true);
  const created: string[] = [];
  for (const definition of definitions ?? []) {
    const config = (definition.trigger_config ?? {}) as Record<string, unknown>;
    if (input.triggerType === 'stage_entry' && config.stageId && config.stageId !== input.context?.stageId) continue;
    const delayMinutes = input.triggerType === 'no_reply' ? Math.max(1, Number(config.durationMinutes ?? config.delayMinutes ?? 1440)) : 0;
    const now = new Date(Date.now() + delayMinutes * 60_000).toISOString();
    const enrollment = await admin.from('sales_sequence_enrollments').insert({ workspace_id: input.workspaceId, automation_id: definition.id, automation_version: definition.active_version, sales_lead_id: input.leadId, sales_contact_id: input.contactId ?? null, owner_user_id: input.ownerUserId ?? null, status: 'active', current_step: 0, next_run_at: now, state: { trigger: input.triggerType, ...input.context } }).select('id').single();
    if (enrollment.error) continue;
    await admin.from('sales_automation_executions').insert({ workspace_id: input.workspaceId, enrollment_id: enrollment.data.id, step_index: 0, idempotency_key: `${enrollment.data.id}:0`, scheduled_for: now });
    created.push(enrollment.data.id);
  }
  return created;
}
