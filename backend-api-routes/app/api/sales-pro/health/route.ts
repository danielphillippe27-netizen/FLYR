import { NextRequest, NextResponse } from 'next/server';
import { requireSalesProContext } from '@/lib/sales-pro/context';

export async function GET(request: NextRequest) {
  const context = await requireSalesProContext(request, { admin: true });
  if (context instanceof NextResponse) return context;
  const now = new Date().toISOString(); const dayAgo = new Date(Date.now() - 86400_000).toISOString();
  const [threads, backlog, deadLetters, failures, bookings] = await Promise.all([
    context.admin.from('communication_threads').select('latest_event_at').eq('workspace_id', context.workspaceId).order('latest_event_at', { ascending: false }).limit(1).maybeSingle(),
    context.admin.from('sales_automation_executions').select('*', { count: 'exact', head: true }).eq('workspace_id', context.workspaceId).in('status', ['pending', 'retry']).lte('scheduled_for', now),
    context.admin.from('sales_automation_executions').select('*', { count: 'exact', head: true }).eq('workspace_id', context.workspaceId).eq('status', 'dead_letter'),
    context.admin.from('sales_automation_executions').select('*', { count: 'exact', head: true }).eq('workspace_id', context.workspaceId).in('status', ['retry', 'dead_letter']).gte('updated_at', dayAgo),
    context.admin.from('sales_bookings').select('*', { count: 'exact', head: true }).eq('workspace_id', context.workspaceId).gte('created_at', dayAgo),
  ]);
  return NextResponse.json({ checkedAt: now, inboxLatestEventAt: threads.data?.latest_event_at ?? null, automationBacklog: backlog.count ?? 0, deadLetters: deadLetters.count ?? 0, automationFailures24h: failures.count ?? 0, bookings24h: bookings.count ?? 0 });
}
