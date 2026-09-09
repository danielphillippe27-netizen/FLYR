import { NextRequest, NextResponse } from 'next/server';
import type { DialerCall, DiallerLead } from '@/types/database';
import { getTwilioAccountSid, getTwilioAuthToken } from '@/lib/dialer/env';
import { getDialerCallRecording } from '@/lib/dialer/recordings';
import { getDialerRequestContext } from '@/lib/dialer/server';
import { findTelnyxCallRecording, getTelnyxCallRecording as retrieveTelnyxRecording } from '@/lib/dialer/telnyx';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const FILENAME_SAFE_CHARS = /[^a-z0-9._-]+/gi;

function cleanFilenamePart(value: string | null | undefined): string {
  return (value ?? '')
    .trim()
    .replace(FILENAME_SAFE_CHARS, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '')
    .slice(0, 60);
}

function buildRecordingFilename(lead: DiallerLead, recordingSid: string): string {
  const leadName = cleanFilenamePart(lead.name) || 'lead';
  const company = cleanFilenamePart(lead.company);
  const sid = cleanFilenamePart(recordingSid) || 'recording';
  return [leadName, company, sid].filter(Boolean).join('-') + '.mp3';
}

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ leadId: string }> }
) {
  const workspaceId = request.nextUrl.searchParams.get('workspaceId');
  const { leadId } = await params;

  const context = await getDialerRequestContext(request, workspaceId);
  if (context instanceof NextResponse) {
    return context;
  }

  let leadQuery = context.admin
    .from('sales_leads')
    .select('*')
    .eq('id', leadId)
    .eq('workspace_id', context.workspaceId);
  leadQuery = leadQuery.eq('assigned_user_id', context.requestUser.id);
  const { data: lead, error: leadError } = await leadQuery.maybeSingle();

  if (leadError) {
    console.error('[dialer/leads/recording] failed to load dialler lead', leadError);
    return NextResponse.json({ error: 'Failed to load dialler lead.' }, { status: 500 });
  }

  if (!lead) {
    return NextResponse.json({ error: 'Dialler lead not found.' }, { status: 404 });
  }

  const { data: calls, error: callsError } = await context.admin
    .from('dialer_calls')
    .select('*')
    .eq('workspace_id', context.workspaceId)
    .eq('user_id', context.requestUser.id)
    .eq('sales_lead_id', leadId)
    .order('created_at', { ascending: false })
    .limit(10);

  if (callsError) {
    console.error('[dialer/leads/recording] failed to load recorded calls', callsError);
    return NextResponse.json({ error: 'Failed to load lead recordings.' }, { status: 500 });
  }

  const recordedCall = ((calls ?? []) as DialerCall[]).find((call) => {
    const recording = getDialerCallRecording(call);
    return recording?.status === 'completed' && Boolean(recording.mp3Url);
  });
  const recording = recordedCall ? getDialerCallRecording(recordedCall) : null;

  if (!recordedCall || !recording) {
    return NextResponse.json({ error: 'Recording is not available yet.' }, { status: 404 });
  }

  const recordedCallId = recordedCall.id;
  const provider = recordedCall.telecom_provider ?? recording.provider;
  let mediaUrl = recording.mp3Url;
  if (provider === 'telnyx') {
    try {
      let refreshed = await retrieveTelnyxRecording(recording.recordingSid).catch(() => null);
      refreshed = refreshed ?? await findTelnyxCallRecording({
        callControlId: recording.callControlId ?? recordedCall.provider_call_id,
        callLegId: recording.callLegId,
        callSessionId: recording.callSessionId ?? recordedCall.provider_parent_call_id,
      });
      mediaUrl = refreshed?.mp3Url ?? mediaUrl;
    } catch (error) {
      console.warn('[dialer/leads/recording] failed to refresh Telnyx recording URL', error);
    }
  }
  const headers = provider === 'telnyx'
    ? undefined
    : { Authorization: `Basic ${Buffer.from(`${getTwilioAccountSid()}:${getTwilioAuthToken()}`).toString('base64')}` };
  const mediaResponse = await fetch(mediaUrl, {
    headers,
    cache: 'no-store',
  });

  if (!mediaResponse.ok || !mediaResponse.body) {
    return NextResponse.json({ error: 'Unable to fetch recording audio.' }, { status: 502 });
  }

  const filename = buildRecordingFilename(lead as DiallerLead, recording.recordingSid);

  return new NextResponse(mediaResponse.body, {
    status: 200,
    headers: {
      'Content-Type': mediaResponse.headers.get('content-type') ?? 'audio/mpeg',
      'Content-Disposition': `attachment; filename="${filename}"`,
      'Cache-Control': 'private, no-store',
      'X-Dialer-Call-Id': recordedCallId,
      'X-Dialer-Recording-Sid': recording.recordingSid,
    },
  });
}
