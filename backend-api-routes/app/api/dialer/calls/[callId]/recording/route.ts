import { NextRequest, NextResponse } from 'next/server';
import type { DialerCall } from '@/types/database';
import { getDialerRequestContext } from '@/lib/dialer/server';
import { getTwilioAccountSid, getTwilioAuthToken } from '@/lib/dialer/env';
import { dialerCallContentRetention, getDialerCallRecording } from '@/lib/dialer/recordings';
import { findTelnyxCallRecording, getTelnyxCallRecording as retrieveTelnyxRecording } from '@/lib/dialer/telnyx';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ callId: string }> }
) {
  const workspaceId = request.nextUrl.searchParams.get('workspaceId');
  const { callId } = await params;

  const context = await getDialerRequestContext(request, workspaceId);
  if (context instanceof NextResponse) {
    return context;
  }

  const { data: call, error } = await context.admin
    .from('dialer_calls')
    .select('*')
    .eq('id', callId)
    .eq('workspace_id', context.workspaceId).eq('user_id', context.requestUser.id)
    .maybeSingle();

  if (error) {
    console.error('[dialer/recording] failed to load call', error);
    return NextResponse.json({ error: 'Failed to load call details' }, { status: 500 });
  }

  if (!call) {
    return NextResponse.json({ error: 'Call not found' }, { status: 404 });
  }

  const retention = dialerCallContentRetention(call as DialerCall);
  if (retention === 'pending' || retention === 'discard') {
    return NextResponse.json({ error: 'Recording was not saved for content' }, { status: 404 });
  }

  const recording = getDialerCallRecording(call as DialerCall);
  if (!recording?.mp3Url) {
    return NextResponse.json({ error: 'Recording is not available yet' }, { status: 404 });
  }

  const provider = (call as DialerCall).telecom_provider ?? recording.provider;
  let mediaUrl = recording.mp3Url;
  if (provider === 'telnyx') {
    try {
      let refreshed = await retrieveTelnyxRecording(recording.recordingSid).catch(() => null);
      refreshed = refreshed ?? await findTelnyxCallRecording({
        callControlId: recording.callControlId ?? (call as DialerCall).provider_call_id,
        callLegId: recording.callLegId,
        callSessionId: recording.callSessionId ?? (call as DialerCall).provider_parent_call_id,
      });
      mediaUrl = refreshed?.mp3Url ?? mediaUrl;
    } catch (error) {
      console.warn('[dialer/recording] failed to refresh Telnyx recording URL', error);
    }
  }
  const headers = new Headers();
  if (provider !== 'telnyx') {
    headers.set('Authorization', `Basic ${Buffer.from(`${getTwilioAccountSid()}:${getTwilioAuthToken()}`).toString('base64')}`);
  }
  const range = request.headers.get('range');
  if (range) headers.set('Range', range);
  const mediaResponse = await fetch(mediaUrl, {
    headers,
    cache: 'no-store',
  });

  if (mediaResponse.status === 416) {
    const rangeHeaders = new Headers({ 'Cache-Control': 'private, no-store' });
    const contentRange = mediaResponse.headers.get('content-range');
    if (contentRange) rangeHeaders.set('Content-Range', contentRange);
    return new NextResponse(null, { status: 416, headers: rangeHeaders });
  }

  if (!mediaResponse.ok || !mediaResponse.body) {
    return NextResponse.json({ error: 'Unable to fetch recording audio' }, { status: 502 });
  }

  const statusPayload = (call as DialerCall).status_payload as Record<string, unknown> | null;
  const contactName = typeof statusPayload?.diallerLeadName === 'string'
    ? statusPayload.diallerLeadName.trim()
    : 'conversation';
  const safeContactName = contactName
    .normalize('NFKD')
    .replace(/[^a-zA-Z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .toLowerCase() || 'conversation';
  const dateTime = new Date((call as DialerCall).created_at).toISOString().replace(/[:.]/g, '-');
  const fileName = `${safeContactName}-${dateTime}.mp3`;

  const responseHeaders = new Headers({
      'Content-Type': mediaResponse.headers.get('content-type') ?? 'audio/mpeg',
      'Cache-Control': 'private, no-store',
      'Content-Disposition': `${request.nextUrl.searchParams.get('playback') === '1' ? 'inline' : 'attachment'}; filename="${fileName}"`,
  });
  for (const name of ['content-length', 'content-range', 'accept-ranges']) {
    const value = mediaResponse.headers.get(name);
    if (value) responseHeaders.set(name, value);
  }

  return new NextResponse(mediaResponse.body, {
    status: mediaResponse.status,
    headers: responseHeaders,
  });
}
