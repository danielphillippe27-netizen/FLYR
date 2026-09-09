import { NextRequest, NextResponse } from 'next/server';
import { dialerCallContentRetention, getDialerCallRecording } from '@/lib/dialer/recordings';
import { getDialerRequestContext } from '@/lib/dialer/server';
import type { DialerCall, SalesLead } from '@/types/database';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest) {
  const context = await getDialerRequestContext(request, request.nextUrl.searchParams.get('workspaceId'));
  if (context instanceof NextResponse) return context;

  try {
    let leadQuery = context.admin
      .from('sales_leads')
      .select('id,name,company,phone,phone_e164,is_starred,assigned_user_id,assigned_salesperson_id')
      .eq('workspace_id', context.workspaceId);
    leadQuery = leadQuery.eq('assigned_user_id', context.requestUser.id);

    const { data: leadRows, error: leadError } = await leadQuery.limit(2000);
    if (leadError) throw leadError;
    const leads = (leadRows ?? []) as Array<Pick<SalesLead, 'id' | 'name' | 'company' | 'phone' | 'phone_e164' | 'is_starred'>>;
    if (leads.length === 0) return NextResponse.json({ groups: [] });

    const leadIds = leads.map((lead) => lead.id);
    const { data: callRows, error: callError } = await context.admin
      .from('dialer_calls')
      .select('*')
      .eq('workspace_id', context.workspaceId)
      .eq('user_id', context.requestUser.id)
      .in('sales_lead_id', leadIds)
      .order('created_at', { ascending: false })
      .limit(2000);
    if (callError) throw callError;

    const callsByLead = new Map<string, DialerCall[]>();
    for (const call of (callRows ?? []) as DialerCall[]) {
      if (!call.sales_lead_id) continue;
      const lead = leads.find((candidate) => candidate.id === call.sales_lead_id);
      const retention = dialerCallContentRetention(call);
      const isLegacySavedCall = retention === null && lead?.is_starred === true;
      if (retention !== 'saved' && !isLegacySavedCall) continue;
      const recording = getDialerCallRecording(call);
      if (!recording || recording.status !== 'completed' || !recording.mp3Url) continue;
      const calls = callsByLead.get(call.sales_lead_id) ?? [];
      calls.push(call);
      callsByLead.set(call.sales_lead_id, calls);
    }

    const groups = leads
      .flatMap((lead) => {
        const calls = callsByLead.get(lead.id) ?? [];
        if (calls.length === 0) return [];
        return [{
          leadId: lead.id,
          leadName: lead.name || 'Lead',
          company: lead.company ?? null,
          phone: lead.phone_e164 ?? lead.phone ?? null,
          isStarred: true,
          recordings: calls.map((call) => {
            const recording = getDialerCallRecording(call)!;
            const params = new URLSearchParams({ workspaceId: context.workspaceId });
            return {
              callId: call.id,
              createdAt: call.created_at,
              answeredAt: call.answered_at ?? null,
              endedAt: call.ended_at ?? null,
              durationSeconds: call.duration_seconds ?? recording.durationSeconds ?? null,
              provider: call.telecom_provider ?? recording.provider,
              recordingStatus: recording.status,
              recordingUpdatedAt: recording.updatedAt,
              downloadUrl: `/api/dialer/calls/${encodeURIComponent(call.id)}/recording?${params.toString()}`,
              playbackUrl: `/api/dialer/calls/${encodeURIComponent(call.id)}/recording?${params.toString()}&playback=1`,
            };
          }),
        }];
      })
      .sort((left, right) => Number(right.isStarred) - Number(left.isStarred));

    return NextResponse.json({ groups });
  } catch (error) {
    console.error('[dialer/recordings]', error);
    return NextResponse.json({ error: 'Failed to load recordings.' }, { status: 500 });
  }
}
