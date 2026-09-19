import { NextRequest, NextResponse } from 'next/server';
import { createAdminClient } from '@/lib/supabase/server';
import { meetingCalendarIcs, validMeetingCalendarSignature } from '@/lib/meetings/calendar';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ meetingId: string }> }
) {
  const { meetingId } = await params;
  if (!validMeetingCalendarSignature(meetingId, request.nextUrl.searchParams.get('signature'))) {
    return NextResponse.json({ error: 'Calendar link is invalid.' }, { status: 404 });
  }

  const { data: meeting, error } = await createAdminClient()
    .from('calendar_events')
    .select('id,title,start_at,end_at,notes,conference_join_url')
    .eq('id', meetingId)
    .eq('conference_provider', 'zoom')
    .is('deleted_at', null)
    .maybeSingle();
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  if (!meeting?.conference_join_url) return NextResponse.json({ error: 'Meeting not found.' }, { status: 404 });

  const calendar = meetingCalendarIcs({
    id: String(meeting.id),
    title: String(meeting.title),
    startAt: new Date(meeting.start_at),
    endAt: new Date(meeting.end_at),
    joinUrl: String(meeting.conference_join_url),
    notes: typeof meeting.notes === 'string' ? meeting.notes : null,
  });
  return new NextResponse(calendar, {
    headers: {
      'Content-Type': 'text/calendar; charset=utf-8',
      'Content-Disposition': 'attachment; filename="wolfgrid-meeting.ics"',
      'Cache-Control': 'private, no-store',
      'X-Content-Type-Options': 'nosniff',
    },
  });
}
