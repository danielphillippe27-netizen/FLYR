import { NextRequest, NextResponse } from 'next/server';
import { clampLimit, cleanText, requireSalesProContext } from '@/lib/sales-pro/context';

export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const limit = clampLimit(request.nextUrl.searchParams.get('limit'), 100, 300);
  const offset = Number(request.nextUrl.searchParams.get('offset') ?? 0);
  if (!Number.isSafeInteger(offset) || offset < 0) return NextResponse.json({ error: 'Invalid page.' }, { status: 400 });
  const taskId = cleanText(request.nextUrl.searchParams.get('taskId'));
  if (taskId) {
    const { data: task, error: taskError } = await context.admin.from('sales_tasks').select('id')
      .eq('workspace_id', context.workspaceId).eq('assigned_user_id', context.userId)
      .eq('task_type', 'demo_follow_up').eq('id', taskId).maybeSingle();
    if (taskError) return NextResponse.json({ error: 'Unable to load demo.' }, { status: 500 });
    if (!task) return NextResponse.json({ error: 'Demo follow-up not found.' }, { status: 404 });
    const { data, error } = await context.admin.from('communication_events')
      .select('id,channel,subject,body,status,occurred_at,to_addresses')
      .eq('workspace_id', context.workspaceId).eq('actor_user_id', context.userId)
      .eq('metadata->>demoFollowUpTaskId', taskId)
      .order('occurred_at', { ascending: false }).order('id').range(offset, offset + limit - 1);
    if (error) return NextResponse.json({ error: 'Unable to load demo send history.' }, { status: 500 });
    return NextResponse.json({ events: data ?? [], hasMore: data?.length === limit });
  }
  const { data, error } = await context.admin.from('sales_tasks')
    .select('id,title,due_at,status,completed_at,sales_lead_id,sales_contact_id,metadata')
    .eq('workspace_id', context.workspaceId).eq('assigned_user_id', context.userId)
    .eq('task_type', 'demo_follow_up')
    .order('due_at', { ascending: true }).order('id').range(offset, offset + limit - 1);
  if (error) return NextResponse.json({ error: 'Unable to load demo follow-ups.' }, { status: 500 });
  return NextResponse.json({ tasks: data ?? [], hasMore: data?.length === limit });
}
