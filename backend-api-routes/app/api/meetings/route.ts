import { NextRequest, NextResponse } from 'next/server';
import { resolveUserFromRequest } from '@/app/api/_utils/request-user';
import { resolveWorkspaceIdForUser, type MinimalSupabaseClient } from '@/app/api/_utils/workspace';
import { createAdminClient } from '@/lib/supabase/server';
import { createZoomMeeting, deleteZoomMeeting, zoomAccessTokenForUser } from '@/lib/zoom';
import { meetingCalendarUrl } from '@/lib/meetings/calendar';
import {
  meetingDeliveryConfigured,
  parseEmailRecipients,
  parsePhoneRecipients,
  sendMeetingEmails,
  sendMeetingSms,
} from '@/lib/meetings/invitations';
import { scheduleMeetingEmailReminders } from '@/lib/meetings/reminders';
import { resolveSalesReplyAddress } from '@/lib/sales-pro/communications';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

type CreateMeetingBody = {
  title?: unknown;
  startAt?: unknown;
  endAt?: unknown;
  notes?: unknown;
  attendeeEmails?: unknown;
  attendeePhoneNumbers?: unknown;
  timeZone?: unknown;
  contactId?: unknown;
  contactName?: unknown;
  workspaceId?: unknown;
};

const meetingSelect = 'id,event_type,title,start_at,end_at,notes,location,contact_id,contact_name,conference_provider,conference_id,conference_join_url,attendee_emails,created_at';

function text(value: unknown, max = 500): string | null {
  if (typeof value !== 'string') return null;
  const result = value.trim();
  return result ? result.slice(0, max) : null;
}

export async function GET(request: NextRequest) {
  const user = await resolveUserFromRequest(request);
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const now = new Date();
  const start = request.nextUrl.searchParams.get('start') ?? now.toISOString();
  const end = request.nextUrl.searchParams.get('end') ?? new Date(now.getFullYear(), now.getMonth() + 4, 1).toISOString();
  const admin = createAdminClient();
  const [{ data, error }, { data: connection }] = await Promise.all([
    admin.from('calendar_events').select(meetingSelect)
      .eq('user_id', user.id).eq('conference_provider', 'zoom').is('deleted_at', null)
      .gte('start_at', start).lt('start_at', end).order('start_at'),
    admin.from('zoom_connections').select('zoom_email').eq('user_id', user.id).maybeSingle(),
  ]);
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({
    connected: Boolean(connection),
    zoomEmail: connection?.zoom_email ?? null,
    deliveryConfigured: meetingDeliveryConfigured(),
    meetings: data ?? [],
  });
}

export async function POST(request: NextRequest) {
  const user = await resolveUserFromRequest(request);
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const body = await request.json().catch(() => ({})) as CreateMeetingBody;
  const title = text(body.title, 200);
  const startAt = new Date(typeof body.startAt === 'string' ? body.startAt : '');
  const endAt = new Date(typeof body.endAt === 'string' ? body.endAt : '');
  if (!title) return NextResponse.json({ error: 'Meeting title is required.' }, { status: 400 });
  if (Number.isNaN(startAt.getTime()) || Number.isNaN(endAt.getTime()) || endAt <= startAt) {
    return NextResponse.json({ error: 'Choose a valid meeting start and end time.' }, { status: 400 });
  }
  if (startAt.getTime() < Date.now() - 60_000) {
    return NextResponse.json({ error: 'Meeting start time must be in the future.' }, { status: 400 });
  }
  const emails = parseEmailRecipients(body.attendeeEmails);
  const phoneNumbers = parsePhoneRecipients(body.attendeePhoneNumbers);
  if (emails.invalid.length > 0) {
    return NextResponse.json({ error: `Check these email addresses: ${emails.invalid.join(', ')}` }, { status: 400 });
  }
  if (phoneNumbers.invalid.length > 0) {
    return NextResponse.json({ error: `Use valid phone numbers with an area or country code: ${phoneNumbers.invalid.join(', ')}` }, { status: 400 });
  }
  const durationMinutes = Math.min(1440, Math.max(1, Math.ceil((endAt.getTime() - startAt.getTime()) / 60_000)));
  const admin = createAdminClient();

  const requestedWorkspace = text(body.workspaceId, 64);
  const workspace = await resolveWorkspaceIdForUser(
    admin as unknown as MinimalSupabaseClient,
    user.id,
    requestedWorkspace
  );
  if (!workspace.workspaceId) {
    return NextResponse.json({ error: workspace.error ?? 'Workspace not found.' }, { status: workspace.status ?? 400 });
  }
  const contactId = text(body.contactId, 64);
  if (contactId) {
    const [legacy,crm] = await Promise.all([
      admin.from('contacts').select('id').eq('id',contactId).eq('user_id',user.id).eq('workspace_id',workspace.workspaceId).maybeSingle(),
      admin.from('sales_contacts').select('id').eq('id',contactId).eq('owner_user_id',user.id).eq('workspace_id',workspace.workspaceId).maybeSingle(),
    ]);
    if (legacy.error || crm.error) return NextResponse.json({error:'Contact lookup failed.'},{status:500});
    if (!legacy.data && !crm.data) return NextResponse.json({error:'Contact not found.'},{status:404});
  }
  const accessToken = await zoomAccessTokenForUser(admin, user.id).catch(() => null);
  if (!accessToken) return NextResponse.json({ error: 'Connect Zoom before creating a meeting.', code: 'zoom_not_connected' }, { status: 409 });
  let zoomMeeting: Awaited<ReturnType<typeof createZoomMeeting>> | null = null;
  let savedMeeting: Record<string, unknown> | null = null;
  try {
    zoomMeeting = await createZoomMeeting(accessToken, {
      topic: title,
      startAt: startAt.toISOString(),
      durationMinutes,
      agenda: text(body.notes, 2000),
    });
    const meetingNotes = text(body.notes, 4000);
    const { data, error } = await admin.from('calendar_events').insert({
      user_id: user.id,
      workspace_id: workspace.workspaceId,
      title,
      start_at: startAt.toISOString(),
      end_at: endAt.toISOString(),
      event_type: 'appointment',
      notes: meetingNotes,
      contact_id: contactId,
      contact_name: text(body.contactName, 200),
      location: 'Zoom',
      color_key: 'blue',
      conference_provider: 'zoom',
      conference_id: String(zoomMeeting.id),
      conference_join_url: zoomMeeting.join_url,
      attendee_emails: emails.recipients,
    }).select(meetingSelect).single();
    if (error) throw new Error(error.message);
    savedMeeting = data;
  } catch (error) {
    if (zoomMeeting) await deleteZoomMeeting(accessToken, String(zoomMeeting.id)).catch(() => undefined);
    console.error('[meetings/create]', error);
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Could not create the Zoom meeting.' }, { status: 502 });
  }

  const invitation = {
    title,
    startAt,
    endAt,
    joinUrl: zoomMeeting.join_url,
    notes: text(body.notes, 4000),
    timeZone: text(body.timeZone, 100),
    calendarUrl: meetingCalendarUrl(
      process.env.NEXT_PUBLIC_APP_URL?.replace(/\/+$/, '') ?? request.nextUrl.origin,
      String(savedMeeting.id)
    ),
    calendarEventId: String(savedMeeting.id),
  };
  let replyToEmail: string | null = null;
  try {
    replyToEmail = await resolveSalesReplyAddress(admin, workspace.workspaceId, user.id);
  } catch (error) {
    console.error('[meetings/reply-address]', error);
  }
  let remindersScheduled = 0;
  try {
    remindersScheduled = await scheduleMeetingEmailReminders(admin, {
      workspaceId: workspace.workspaceId,
      calendarEventId: String(savedMeeting.id),
      emails: emails.recipients,
      replyToEmail,
      startAt,
      timeZone: invitation.timeZone,
    });
  } catch (error) {
    console.error('[meetings/reminder-schedule]', error);
  }
  const [email, sms] = await Promise.all([
    sendMeetingEmails({ ...invitation, emails: emails.recipients, replyToEmail }),
    sendMeetingSms({ ...invitation, phoneNumbers: phoneNumbers.recipients }),
  ]);
  return NextResponse.json({
    meeting: savedMeeting,
    deliveries: { email, sms },
    invitationsSent: email.sent + sms.sent,
    invitationsRequested: email.requested + sms.requested,
    remindersScheduled,
  }, { status: 201 });
}
