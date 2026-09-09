import { requirePersonalReferences } from '@/lib/sales-pro/personal-references';
import { NextRequest, NextResponse } from 'next/server';
import { createAdminClient } from '@/lib/supabase/server';
import { appendCommunication, sendManagedEmail, sendManagedSms } from '@/lib/sales-pro/communications';
import { notifySalesUser } from '@/lib/sales-pro/notifications';
import { isInsideBusinessWindow } from '@/lib/sales-pro/scheduling';

export const runtime = 'nodejs';
export const maxDuration = 300;

type Step = { action?: string; delayMinutes?: number; title?: string; body?: string; subject?: string; stageId?: string; assignedUserId?: string; automationId?: string };

function retryAt(attempt: number) {
  return new Date(Date.now() + Math.min(24 * 60, 2 ** Math.max(0, attempt - 1) * 5) * 60_000).toISOString();
}

export async function GET(request: NextRequest) {
  if (!process.env.CRON_SECRET || request.headers.get('authorization') !== `Bearer ${process.env.CRON_SECRET}`) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  const admin = createAdminClient();
  const { data: overdue } = await admin.from('sales_tasks').select('id,workspace_id,assigned_user_id,title,metadata').eq('status', 'open').lt('due_at', new Date().toISOString()).limit(50);
  for (const task of overdue ?? []) {
    if (task.metadata?.overdueNotifiedAt) continue;
    await notifySalesUser(admin, { workspaceId: task.workspace_id, userId: task.assigned_user_id, type: 'overdue_follow_up', title: 'Follow-up overdue', body: task.title, data: { taskId: task.id } });
    await admin.from('sales_tasks').update({ metadata: { ...(task.metadata ?? {}), overdueNotifiedAt: new Date().toISOString() } }).eq('id', task.id);
  }
  const { data: claimed, error } = await admin.rpc('claim_due_sales_automation_executions', { batch_size: 25 });
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  const results: Array<{ id: string; status: string; error?: string }> = [];
  for (const execution of claimed ?? []) {
    try {
      const { data: enrollment } = await admin.from('sales_sequence_enrollments')
        .select('*,sales_leads(*),sales_contacts(*)').eq('id', execution.enrollment_id).single();
      if (!enrollment || enrollment.status !== 'active') throw new Error('Enrollment is no longer active.');
      const owner = enrollment.owner_user_id;
      if (!owner || enrollment.workspace_id !== execution.workspace_id) throw new Error('Automation owner or workspace is invalid.');
      await requirePersonalReferences(admin, enrollment.workspace_id, owner, { leadId: enrollment.sales_lead_id, contactId: enrollment.sales_contact_id });
      const { data: definition } = await admin.from('sales_automation_definitions').select('id')
        .eq('id', enrollment.automation_id).eq('workspace_id', enrollment.workspace_id).eq('created_by_user_id', owner).maybeSingle();
      if (!definition) throw new Error('Personal automation definition not found.');
      const lead = enrollment.sales_leads;
      const contact = enrollment.sales_contacts;
      const stopped = lead?.lead_state === 'dnc' || ['won', 'lost'].includes(lead?.pipeline_stage);
      const { count: replies } = await admin.from('communication_events').select('*', { count: 'exact', head: true })
        .eq('workspace_id', enrollment.workspace_id).eq('actor_user_id', owner).eq('sales_lead_id', enrollment.sales_lead_id).eq('direction', 'inbound').gt('occurred_at', enrollment.created_at);
      if (stopped || (replies ?? 0) > 0) {
        const reason = stopped ? 'terminal_or_dnc' : 'inbound_reply';
        await admin.from('sales_sequence_enrollments').update({ status: 'stopped', stop_reason: reason }).eq('id', enrollment.id);
        await admin.from('sales_automation_executions').update({ status: 'succeeded', completed_at: new Date().toISOString(), output: { stopped: reason } }).eq('id', execution.id);
        results.push({ id: execution.id, status: 'stopped' });
        continue;
      }
      const { data: version } = await admin.from('sales_automation_versions').select('steps')
        .eq('automation_id', enrollment.automation_id).eq('version', enrollment.automation_version).single();
      const steps = (Array.isArray(version?.steps) ? version.steps : []) as Step[];
      const step = steps[execution.step_index];
      if (!step) throw new Error('Published automation step is missing.');
      const common = { admin, workspaceId: enrollment.workspace_id, userId: owner, contactId: enrollment.sales_contact_id, leadId: enrollment.sales_lead_id };
      if (step.action === 'sms' || step.action === 'email') {
        const [{ data: settings }, { data: preference }] = await Promise.all([
          admin.from('sales_automation_settings').select('*').eq('workspace_id', enrollment.workspace_id).maybeSingle(),
          enrollment.sales_contact_id ? admin.from('sales_communication_preferences').select('status').eq('sales_contact_id', enrollment.sales_contact_id).eq('channel', step.action).maybeSingle() : Promise.resolve({ data: null }),
        ]);
        if (['unsubscribed', 'dnc', 'bounced', 'complained'].includes(preference?.status)) throw new Error(`Contact cannot receive ${step.action}: ${preference.status}.`);
        if (!isInsideBusinessWindow(new Date(), { timezone: settings?.timezone ?? 'America/Toronto', weekdays: settings?.business_weekdays ?? [1, 2, 3, 4, 5], startMinute: Number(settings?.business_start_minute ?? 540), endMinute: Number(settings?.business_end_minute ?? 1020) })) {
          await admin.from('sales_automation_executions').update({ status: 'retry', next_retry_at: new Date(Date.now() + 30 * 60_000).toISOString(), error: 'Waiting for workspace business hours.' }).eq('id', execution.id);
          results.push({ id: execution.id, status: 'waiting_business_hours' }); continue;
        }
        const { count } = await admin.from('communication_events').select('*', { count: 'exact', head: true }).eq('workspace_id', enrollment.workspace_id).eq('channel', step.action).eq('direction', 'outbound').gte('occurred_at', new Date(Date.now() - 3600_000).toISOString());
        const limit = step.action === 'sms' ? Number(settings?.sms_hourly_limit ?? 100) : Number(settings?.email_hourly_limit ?? 200);
        if ((count ?? 0) >= limit) throw new Error(`Workspace ${step.action} hourly rate limit reached.`);
      }
      if (step.action === 'sms') {
        if (!contact?.phone_e164 && !lead?.phone_e164) throw new Error('No SMS-capable phone number.');
        await sendManagedSms({ ...common, to: contact?.phone_e164 ?? lead.phone_e164, body: step.body ?? '' });
      } else if (step.action === 'email') {
        if (!contact?.email && !lead?.email) throw new Error('No email address.');
        await sendManagedEmail({ ...common, to: contact?.email ?? lead.email, subject: step.subject ?? 'Following up', body: step.body ?? '' });
      } else if (step.action === 'call_task' || step.action === 'task') {
        await admin.from('sales_tasks').insert({ workspace_id: enrollment.workspace_id, sales_lead_id: enrollment.sales_lead_id, sales_contact_id: enrollment.sales_contact_id, assigned_user_id: owner, task_type: step.action === 'call_task' ? 'call' : 'follow_up', title: step.title ?? 'Follow up', status: 'open', due_at: new Date().toISOString(), metadata: { automationExecutionId: execution.id } });
      } else if (step.action === 'stage_update' && step.stageId) {
        await admin.from('sales_leads').update({ pipeline_stage_id: step.stageId }).eq('workspace_id', enrollment.workspace_id).eq('assigned_user_id', owner).eq('id', enrollment.sales_lead_id);
      } else if (step.action === 'assignment' && step.assignedUserId) {
        if (step.assignedUserId !== owner) throw new Error('Personal leads cannot be reassigned by automation.');
        await admin.from('sales_leads').update({ assigned_user_id: step.assignedUserId, pipeline_owner_id: step.assignedUserId }).eq('workspace_id', enrollment.workspace_id).eq('assigned_user_id', owner).eq('id', enrollment.sales_lead_id);
      } else if (step.action === 'notification') {
        await appendCommunication(admin, { workspaceId: enrollment.workspace_id, contactId: enrollment.sales_contact_id, leadId: enrollment.sales_lead_id, actorUserId: owner, channel: 'notification', direction: 'internal', eventKind: 'automation_notification', body: step.body ?? step.title ?? 'Follow-up needed.' });
      } else if (step.action === 'enroll' && step.automationId) {
        const { data: target } = await admin.from('sales_automation_definitions').select('id,active_version,is_enabled').eq('workspace_id', enrollment.workspace_id).eq('created_by_user_id', owner).eq('id', step.automationId).maybeSingle();
        if (!target?.is_enabled) throw new Error('Target automation is not enabled.');
        const nested = await admin.from('sales_sequence_enrollments').insert({ workspace_id: enrollment.workspace_id, automation_id: target.id, automation_version: target.active_version, sales_lead_id: enrollment.sales_lead_id, sales_contact_id: enrollment.sales_contact_id, owner_user_id: owner, status: 'active', current_step: 0, next_run_at: new Date().toISOString(), state: { enrolledByExecutionId: execution.id } }).select('id').single();
        if (nested.error) throw nested.error;
        await admin.from('sales_automation_executions').insert({ workspace_id: enrollment.workspace_id, enrollment_id: nested.data.id, step_index: 0, idempotency_key: `${nested.data.id}:0`, scheduled_for: new Date().toISOString() });
      }
      const nextIndex = execution.step_index + 1;
      const nextStep = steps[nextIndex];
      await admin.from('sales_automation_executions').update({ status: 'succeeded', completed_at: new Date().toISOString(), output: { action: step.action } }).eq('id', execution.id);
      if (nextStep) {
        const delayMinutes = step.action === 'delay' ? step.delayMinutes ?? 60 : nextStep.delayMinutes ?? 0;
        const scheduled = new Date(Date.now() + Math.max(0, delayMinutes) * 60_000).toISOString();
        await admin.from('sales_automation_executions').upsert({ workspace_id: enrollment.workspace_id, enrollment_id: enrollment.id, step_index: nextIndex, idempotency_key: `${enrollment.id}:${nextIndex}`, scheduled_for: scheduled }, { onConflict: 'idempotency_key', ignoreDuplicates: true });
        await admin.from('sales_sequence_enrollments').update({ current_step: nextIndex, next_run_at: scheduled }).eq('id', enrollment.id);
      } else {
        await admin.from('sales_sequence_enrollments').update({ status: 'completed', current_step: nextIndex, next_run_at: null }).eq('id', enrollment.id);
      }
      results.push({ id: execution.id, status: 'succeeded' });
    } catch (cause) {
      const message = cause instanceof Error ? cause.message : 'Unknown automation failure';
      const dead = Number(execution.attempt_count) >= 5;
      await admin.from('sales_automation_executions').update({ status: dead ? 'dead_letter' : 'retry', next_retry_at: dead ? null : retryAt(Number(execution.attempt_count)), error: message }).eq('id', execution.id);
      if (dead) await admin.from('sales_sequence_enrollments').update({ status: 'failed', stop_reason: message }).eq('id', execution.enrollment_id);
      results.push({ id: execution.id, status: dead ? 'dead_letter' : 'retry', error: message });
    }
  }
  return NextResponse.json({ claimed: claimed?.length ?? 0, results });
}
