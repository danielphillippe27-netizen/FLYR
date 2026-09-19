import { NextRequest, NextResponse } from 'next/server';
import type { DialerCall } from '@/types/database';
import { getDialerRequestContext } from '@/lib/dialer/server';
import { getDialerCallRecording } from '@/lib/dialer/recordings';
import { deleteTelnyxCallRecording } from '@/lib/dialer/telnyx';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ callId: string }> }
) {
  const { callId } = await params;
  const workspaceId = request.nextUrl.searchParams.get('workspaceId') ?? undefined;
  const context = await getDialerRequestContext(request, workspaceId);

  if (context instanceof NextResponse) {
    return context;
  }

  const { data: call, error } = await context.admin
    .from('dialer_calls')
    .select('*')
    .eq('id', callId)
    .eq('workspace_id', context.workspaceId)
    .eq('user_id', context.requestUser.id)
    .maybeSingle();

  if (error) {
    console.error('[dialer/calls/get] failed to load call', error);
    return NextResponse.json({ error: 'Failed to load call details' }, { status: 500 });
  }

  if (!call) {
    return NextResponse.json({ error: 'Call not found' }, { status: 404 });
  }

  return NextResponse.json({ call: call as DialerCall });
}

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ callId: string }> }
) {
  const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  const { callId } = await params;
  const workspaceId = typeof body.workspaceId === 'string' ? body.workspaceId : undefined;
  const context = await getDialerRequestContext(request, workspaceId);

  if (context instanceof NextResponse) return context;
  if (typeof body.contentSaved !== 'boolean') {
    return NextResponse.json({ error: 'contentSaved must be true or false' }, { status: 400 });
  }

  const { data: row, error } = await context.admin
    .from('dialer_calls')
    .select('*')
    .eq('id', callId)
    .eq('workspace_id', context.workspaceId)
    .eq('user_id', context.requestUser.id)
    .maybeSingle();

  if (error) {
    console.error('[dialer/calls/content] failed to load call', error);
    return NextResponse.json({ error: 'Failed to load call' }, { status: 500 });
  }
  if (!row) return NextResponse.json({ error: 'Call not found' }, { status: 404 });

  const call = row as DialerCall;
  const existingPayload = call.status_payload && typeof call.status_payload === 'object'
    ? call.status_payload
    : {};
  const now = new Date().toISOString();
  const nextPayload: Record<string, unknown> = {
    ...existingPayload,
    contentRetention: body.contentSaved ? 'saved' : 'discard',
    contentSaved: body.contentSaved,
    contentRetentionUpdatedAt: now,
  };

  const { data: updated, error: updateError } = await context.admin
    .from('dialer_calls')
    .update({ status_payload: nextPayload, updated_at: now })
    .eq('id', callId)
    .eq('workspace_id', context.workspaceId)
    .eq('user_id', context.requestUser.id)
    .select('*')
    .single();

  if (updateError || !updated) {
    console.error('[dialer/calls/content] failed to update retention', updateError);
    return NextResponse.json({ error: 'Failed to update saved conversation' }, { status: 500 });
  }

  if (!body.contentSaved) {
    const recording = getDialerCallRecording(call);
    if (recording?.recordingSid && (call.telecom_provider ?? recording.provider) === 'telnyx') {
      try {
        await deleteTelnyxCallRecording(recording.recordingSid);
        const { recording: _removedRecording, ...payloadWithoutRecording } = nextPayload;
        const { data: discarded, error: discardUpdateError } = await context.admin
          .from('dialer_calls')
          .update({
            status_payload: { ...payloadWithoutRecording, recordingDiscardedAt: new Date().toISOString() },
            updated_at: new Date().toISOString(),
          })
          .eq('id', callId)
          .eq('workspace_id', context.workspaceId)
          .eq('user_id', context.requestUser.id)
          .select('*')
          .single();
        if (discardUpdateError || !discarded) throw discardUpdateError ?? new Error('Failed to finalize recording deletion');
        return NextResponse.json({ call: discarded as DialerCall });
      } catch (deleteError) {
        console.error('[dialer/calls/content] failed to delete Telnyx recording', deleteError);
        return NextResponse.json({ error: 'Conversation was marked for deletion, but Telnyx deletion must be retried.' }, { status: 502 });
      }
    }
  }

  return NextResponse.json({ call: updated as DialerCall });
}
