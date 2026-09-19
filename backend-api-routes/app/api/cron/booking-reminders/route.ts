import { NextRequest, NextResponse } from 'next/server';
import { Resend } from 'resend';
import { createAdminClient } from '@/lib/supabase/server';
import { sendMeetingReminderEmail } from '@/lib/meetings/invitations';
import { appendCommunication, resolveSalesReplyAddress } from '@/lib/sales-pro/communications';

export const runtime = 'nodejs';
export const maxDuration = 300;

type ProcessResult = { id: string; status: 'sent' | 'failed' | 'skipped' };

async function processBookingReminders(now: Date): Promise<ProcessResult[]> {
  const admin = createAdminClient();
  const horizon = new Date(now.getTime() + 2 * 60_000);
  const { data, error } = await admin
    .from('sales_booking_reminders')
    .select('*,sales_bookings(*)')
    .is('sent_at', null)
    .lte('scheduled_for', horizon.toISOString())
    .order('scheduled_for')
    .limit(100);
  if (error) throw new Error(error.message);

  const results: ProcessResult[] = [];
  for (const reminder of data ?? []) {
    try {
      const booking = reminder.sales_bookings;
      if (!booking || booking.status !== 'confirmed') {
        await admin.from('sales_booking_reminders').update({ sent_at: now.toISOString() }).eq('id', reminder.id);
        results.push({ id: String(reminder.id), status: 'skipped' });
        continue;
      }
      if (reminder.channel === 'email') {
        const from = process.env.RESEND_FROM_EMAIL?.trim();
        if (!process.env.RESEND_API_KEY || !from) throw new Error('Resend is not configured.');
        const sent = await new Resend(process.env.RESEND_API_KEY).emails.send({
          from,
          to: booking.guest_email,
          subject: 'Meeting reminder',
          text: `Reminder: your WolfGrid meeting starts at ${booking.starts_at}. Join Zoom: ${booking.zoom_join_url}`,
        });
        if (sent.error) throw new Error(sent.error.message);
      } else {
        await appendCommunication(admin, {
          workspaceId: reminder.workspace_id,
          contactId: booking.sales_contact_id,
          leadId: booking.sales_lead_id,
          actorUserId: booking.assigned_user_id,
          channel: 'notification',
          direction: 'internal',
          eventKind: 'meeting_reminder',
          body: `Meeting with ${booking.guest_name} starts at ${booking.starts_at}.`,
        });
      }
      await admin.from('sales_booking_reminders').update({ sent_at: now.toISOString(), error: null }).eq('id', reminder.id);
      results.push({ id: String(reminder.id), status: 'sent' });
    } catch (cause) {
      await admin.from('sales_booking_reminders').update({
        attempt_count: Number(reminder.attempt_count) + 1,
        error: cause instanceof Error ? cause.message : 'Unknown error',
      }).eq('id', reminder.id);
      results.push({ id: String(reminder.id), status: 'failed' });
    }
  }
  return results;
}

async function processDirectMeetingReminders(now: Date): Promise<ProcessResult[]> {
  const admin = createAdminClient();
  const { data, error } = await admin
    .from('meeting_email_reminders')
    .select('*,calendar_events(id,user_id,title,start_at,end_at,notes,conference_join_url,deleted_at)')
    .is('sent_at', null)
    .lte('scheduled_for', now.toISOString())
    .order('scheduled_for')
    .limit(100);
  if (error) throw new Error(error.message);

  const results: ProcessResult[] = [];
  for (const reminder of data ?? []) {
    try {
      const meeting = reminder.calendar_events;
      const startsAt = meeting?.start_at ? new Date(meeting.start_at) : null;
      if (
        !meeting ||
        meeting.deleted_at ||
        !meeting.conference_join_url ||
        !startsAt ||
        startsAt.getTime() <= now.getTime()
      ) {
        await admin.from('meeting_email_reminders').update({ sent_at: now.toISOString() }).eq('id', reminder.id);
        results.push({ id: String(reminder.id), status: 'skipped' });
        continue;
      }

      const replyToEmail = await resolveSalesReplyAddress(
        admin,
        String(reminder.workspace_id),
        String(meeting.user_id)
      );
      await sendMeetingReminderEmail({
        title: String(meeting.title),
        startAt: startsAt,
        endAt: new Date(meeting.end_at),
        joinUrl: String(meeting.conference_join_url),
        notes: typeof meeting.notes === 'string' ? meeting.notes : null,
        timeZone: typeof reminder.time_zone === 'string' ? reminder.time_zone : null,
        email: String(reminder.recipient_email),
        replyToEmail,
      });
      await admin.from('meeting_email_reminders').update({ sent_at: now.toISOString(), error: null }).eq('id', reminder.id);
      results.push({ id: String(reminder.id), status: 'sent' });
    } catch (cause) {
      await admin.from('meeting_email_reminders').update({
        attempt_count: Number(reminder.attempt_count) + 1,
        error: cause instanceof Error ? cause.message : 'Unknown error',
      }).eq('id', reminder.id);
      results.push({ id: String(reminder.id), status: 'failed' });
    }
  }
  return results;
}

export async function GET(request: NextRequest) {
  if (!process.env.CRON_SECRET || request.headers.get('authorization') !== `Bearer ${process.env.CRON_SECRET}`) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const now = new Date();
  try {
    const [bookingReminders, meetingReminders] = await Promise.all([
      processBookingReminders(now),
      processDirectMeetingReminders(now),
    ]);
    return NextResponse.json({
      processed: bookingReminders.length + meetingReminders.length,
      bookingReminders,
      meetingReminders,
    });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Reminder processing failed.' }, { status: 500 });
  }
}
