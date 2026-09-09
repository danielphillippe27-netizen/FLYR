import { NextRequest, NextResponse } from 'next/server';
import { resolveUserFromRequest } from '@/app/api/_utils/request-user';
import { createAdminClient } from '@/lib/supabase/server';
import { meetingCalendarUrl } from '@/lib/meetings/calendar';
import {
  parseEmailRecipients,
  parsePhoneRecipients,
  sendMeetingEmails,
  sendMeetingSms,
} from '@/lib/meetings/invitations';
import { scheduleMeetingEmailReminders } from '@/lib/meetings/reminders';
import { resolveSalesReplyAddress } from '@/lib/sales-pro/communications';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

type InvitationBody = {
  attendeeEmails?: unknown;
  attendeePhoneNumbers?: unknown;
  timeZone?: unknown;
};

function text(value: unknown, max = 100): string | null {
  if (typeof value !== 'string') return null;
  const result = value.trim();
  return result ? result.slice(0, max) : null;
}

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ meetingId: string }> }
) {
  const user = await resolveUserFromRequest(request);
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const body = await request.json().catch(() => ({})) as InvitationBody;
  const emails = parseEmailRecipients(body.attendeeEmails);
  const phoneNumbers = parsePhoneRecipients(body.attendeePhoneNumbers);
  if (emails.invalid.length > 0) {
    return NextResponse.json({ error: `Check these email addresses: ${emails.invalid.join(', ')}` }, { status: 400 });
  }
  if (phoneNumbers.invalid.length > 0) {
    return NextResponse.json({ error: `Use valid phone numbers with an area or country code: ${phoneNumbers.invalid.join(', ')}` }, { status: 400 });
  }
  if (emails.recipients.length === 0 && phoneNumbers.recipients.length === 0) {
    return NextResponse.json({ error: 'Add at least one email address or phone number.' }, { status: 400 });
  }

  const { meetingId } = await params;
  const admin = createAdminClient();
  const { data: meeting, error } = await admin
    .from('calendar_events')
    .select('id,workspace_id,title,start_at,end_at,notes,conference_join_url,attendee_emails')
    .eq('id', meetingId)
    .eq('user_id', user.id)
    .eq('conference_provider', 'zoom')
    .is('deleted_at', null)
    .maybeSingle();
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  if (!meeting?.conference_join_url) return NextResponse.json({ error: 'Zoom meeting not found.' }, { status: 404 });

  const invitation = {
    title: String(meeting.title),
    startAt: new Date(meeting.start_at),
    endAt: new Date(meeting.end_at),
    joinUrl: String(meeting.conference_join_url),
    notes: typeof meeting.notes === 'string' ? meeting.notes : null,
    timeZone: text(body.timeZone),
    calendarUrl: meetingCalendarUrl(
      process.env.NEXT_PUBLIC_APP_URL?.replace(/\/+$/, '') ?? request.nextUrl.origin,
      String(meeting.id)
    ),
    calendarEventId: String(meeting.id),
  };
  let replyToEmail: string | null = null;
  try {
    replyToEmail = await resolveSalesReplyAddress(admin, String(meeting.workspace_id), user.id);
  } catch (replyAddressError) {
    console.error('[meetings/reply-address]', replyAddressError);
  }
  let remindersScheduled = 0;
  try {
    remindersScheduled = await scheduleMeetingEmailReminders(admin, {
      workspaceId: String(meeting.workspace_id),
      calendarEventId: String(meeting.id),
      emails: emails.recipients,
      replyToEmail,
      startAt: invitation.startAt,
      timeZone: invitation.timeZone,
    });
  } catch (scheduleError) {
    console.error('[meetings/reminder-schedule]', scheduleError);
  }
  const [email, sms] = await Promise.all([
    sendMeetingEmails({ ...invitation, emails: emails.recipients, replyToEmail }),
    sendMeetingSms({ ...invitation, phoneNumbers: phoneNumbers.recipients }),
  ]);

  if (emails.recipients.length > 0) {
    const existing = Array.isArray(meeting.attendee_emails) ? meeting.attendee_emails : [];
    await admin.from('calendar_events').update({
      attendee_emails: [...new Set([...existing, ...emails.recipients])],
    }).eq('id', meeting.id).eq('user_id', user.id);
  }

  return NextResponse.json({
    deliveries: { email, sms },
    invitationsSent: email.sent + sms.sent,
    invitationsRequested: email.requested + sms.requested,
    remindersScheduled,
  });
}
