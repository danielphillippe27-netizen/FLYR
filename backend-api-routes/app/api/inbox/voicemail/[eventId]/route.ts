import { NextRequest, NextResponse } from 'next/server';
import { requireSalesProContext } from '@/lib/sales-pro/context';

export const runtime = 'nodejs';

export async function GET(request: NextRequest, { params }: { params: Promise<{ eventId: string }> }) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const { eventId } = await params;
  const { data } = await context.admin.from('communication_events').select('metadata,attachments').eq('workspace_id', context.workspaceId).eq('actor_user_id', context.userId).eq('id', eventId).eq('channel', 'voicemail').maybeSingle();
  const metadata = data?.metadata as Record<string, unknown> | null; const attachments = Array.isArray(data?.attachments) ? data.attachments as Array<Record<string, unknown>> : [];
  const url = typeof metadata?.recordingUrl === 'string' ? metadata.recordingUrl : typeof attachments[0]?.url === 'string' ? attachments[0].url : null;
  if (!url) return NextResponse.json({ error: 'Voicemail recording is unavailable.' }, { status: 404 });
  const response = await fetch(url, { headers: process.env.TELNYX_API_KEY ? { Authorization: `Bearer ${process.env.TELNYX_API_KEY}` } : undefined, cache: 'no-store' });
  if (!response.ok || !response.body) return NextResponse.json({ error: 'Voicemail provider could not return the recording.' }, { status: 502 });
  return new NextResponse(response.body, { headers: { 'Content-Type': response.headers.get('content-type') ?? 'audio/mpeg', 'Content-Disposition': request.nextUrl.searchParams.get('download') === '1' ? `attachment; filename="voicemail-${eventId}.mp3"` : 'inline', 'Cache-Control': 'private, no-store' } });
}
