import { createAdminClient } from '@/lib/supabase/server';

type AdminClient = ReturnType<typeof createAdminClient>;

type ScheduleMeetingRemindersInput = {
  workspaceId: string;
  calendarEventId: string;
  emails: string[];
  replyToEmail: string | null;
  startAt: Date;
  timeZone: string | null;
};

export async function scheduleMeetingEmailReminders(
  admin: AdminClient,
  input: ScheduleMeetingRemindersInput
): Promise<number> {
  const scheduledFor = new Date(input.startAt.getTime() - 5 * 60_000);
  if (scheduledFor.getTime() <= Date.now() || input.emails.length === 0) return 0;

  const rows = input.emails.map((recipientEmail) => ({
    workspace_id: input.workspaceId,
    calendar_event_id: input.calendarEventId,
    recipient_email: recipientEmail,
    host_email: input.replyToEmail,
    time_zone: input.timeZone,
    scheduled_for: scheduledFor.toISOString(),
    sent_at: null,
    attempt_count: 0,
    error: null,
  }));
  const { error } = await admin
    .from('meeting_email_reminders')
    .upsert(rows, { onConflict: 'calendar_event_id,recipient_email' });
  if (error) throw new Error(error.message);
  return rows.length;
}
