import { Resend } from 'resend';
import { normalizePhoneNumber } from '@/lib/dialer/phone';
import { sendTelnyxSms, telnyxSmsFromNumber } from '@/lib/dialer/telnyx-messaging';
import { meetingCalendarIcs } from '@/lib/meetings/calendar';

export type ParsedRecipients = {
  recipients: string[];
  invalid: string[];
};

export type InvitationDelivery = {
  requested: number;
  sent: number;
  failed: number;
  error?: string;
};

type MeetingInvitation = {
  title: string;
  startAt: Date;
  endAt: Date;
  joinUrl: string;
  notes: string | null;
  timeZone?: string | null;
  calendarUrl?: string | null;
  calendarEventId?: string | null;
};

function clean(value: unknown, max: number): string | null {
  if (typeof value !== 'string') return null;
  const result = value.trim();
  return result ? result.slice(0, max) : null;
}

function unique(values: string[]): string[] {
  return [...new Set(values)];
}

export function parseEmailRecipients(value: unknown, limit = 25): ParsedRecipients {
  if (!Array.isArray(value)) return { recipients: [], invalid: [] };
  const candidates = unique(value.map((item) => clean(item, 254)?.toLowerCase()).filter((item): item is string => Boolean(item)));
  const recipients: string[] = [];
  const invalid: string[] = [];
  for (const candidate of candidates.slice(0, limit)) {
    (/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(candidate) ? recipients : invalid).push(candidate);
  }
  return { recipients, invalid };
}

export function parsePhoneRecipients(value: unknown, limit = 25): ParsedRecipients {
  if (!Array.isArray(value)) return { recipients: [], invalid: [] };
  const candidates = unique(value.map((item) => clean(item, 40)).filter((item): item is string => Boolean(item)));
  const recipients: string[] = [];
  const invalid: string[] = [];
  for (const candidate of candidates.slice(0, limit)) {
    const normalized = normalizePhoneNumber(candidate, 'CA');
    if (normalized.e164) recipients.push(normalized.e164);
    else invalid.push(candidate);
  }
  return { recipients: unique(recipients), invalid };
}

function safeTimeZone(value: string | null | undefined): string {
  if (!value) return 'America/Toronto';
  try {
    new Intl.DateTimeFormat('en-CA', { timeZone: value }).format();
    return value;
  } catch {
    return 'America/Toronto';
  }
}

export function meetingInvitationTime(input: Pick<MeetingInvitation, 'startAt' | 'endAt' | 'timeZone'>): string {
  const timeZone = safeTimeZone(input.timeZone);
  const date = input.startAt.toLocaleDateString('en-CA', {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
    year: 'numeric',
    timeZone,
  });
  const start = input.startAt.toLocaleTimeString('en-CA', {
    hour: 'numeric',
    minute: '2-digit',
    timeZone,
    timeZoneName: 'short',
  });
  const end = input.endAt.toLocaleTimeString('en-CA', {
    hour: 'numeric',
    minute: '2-digit',
    timeZone,
    timeZoneName: 'short',
  });
  return `${date}, ${start} – ${end}`;
}

export function meetingInvitationText(input: MeetingInvitation): string {
  return [
    `You're invited: ${input.title}`,
    meetingInvitationTime(input),
    'Accept this calendar invitation to add the meeting, Zoom link, and reminder to your calendar.',
    input.notes,
    input.calendarUrl ? `Accept meeting: ${input.calendarUrl}` : null,
    `Join Zoom: ${input.joinUrl}`,
    'Sent with WolfGrid',
  ].filter(Boolean).join('\n\n');
}

export function meetingReminderText(input: MeetingInvitation): string {
  return [
    `Your meeting starts in 5 minutes: ${input.title}`,
    meetingInvitationTime(input),
    `Join Zoom: ${input.joinUrl}`,
    'Sent with WolfGrid',
  ].join('\n\n');
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function errorMessage(results: PromiseSettledResult<unknown>[]): string | undefined {
  const rejected = results.find((result): result is PromiseRejectedResult => result.status === 'rejected');
  if (!rejected) return undefined;
  return rejected.reason instanceof Error ? rejected.reason.message : 'The provider rejected one or more invitations.';
}

export function meetingInvitationHtml(input: MeetingInvitation): string {
  const title = escapeHtml(input.title);
  const time = escapeHtml(meetingInvitationTime(input));
  const joinUrl = escapeHtml(input.joinUrl);
  const notes = input.notes
    ? `<tr><td style="padding:0 40px 28px"><div style="font-size:12px;line-height:18px;font-weight:700;letter-spacing:.08em;color:#64748b;text-transform:uppercase;margin-bottom:8px">A note from your host</div><div style="font-size:15px;line-height:24px;color:#334155;white-space:pre-wrap">${escapeHtml(input.notes)}</div></td></tr>`
    : '';
  const acceptButton = input.calendarUrl
    ? `<tr>
              <td style="padding:0 40px 18px">
                <a href="${escapeHtml(input.calendarUrl)}" style="display:block;background:#ef2b2d;color:#ffffff;text-align:center;text-decoration:none;padding:15px 20px;border-radius:10px;font-size:16px;line-height:22px;font-weight:800">Accept Meeting</a>
              </td>
            </tr>`
    : '';

  return `<!doctype html>
<html lang="en">
  <body style="margin:0;padding:0;background:#f1f5f9;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#0f172a">
    <div style="display:none;max-height:0;overflow:hidden;opacity:0">Calendar invitation: ${title} — ${time}</div>
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background:#f1f5f9">
      <tr>
        <td align="center" style="padding:32px 16px">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:600px;background:#ffffff;border-radius:20px;overflow:hidden;box-shadow:0 10px 30px rgba(15,23,42,.08)">
            <tr>
              <td style="background:#111827;padding:24px 40px;border-bottom:4px solid #ef2b2d">
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0">
                  <tr>
                    <td style="font-size:24px;line-height:28px;font-weight:800;letter-spacing:-.02em;color:#ffffff">Wolf<span style="color:#ef2b2d">Grid</span></td>
                    <td align="right" style="font-size:11px;line-height:16px;font-weight:700;letter-spacing:.12em;color:#cbd5e1;text-transform:uppercase">Zoom meeting</td>
                  </tr>
                </table>
              </td>
            </tr>
            <tr>
              <td style="padding:40px 40px 18px">
                <div style="font-size:13px;line-height:20px;font-weight:700;color:#ef2b2d;letter-spacing:.08em;text-transform:uppercase;margin-bottom:10px">You're invited</div>
                <h1 style="margin:0;font-size:30px;line-height:38px;letter-spacing:-.025em;color:#0f172a">${title}</h1>
              </td>
            </tr>
            <tr>
              <td style="padding:0 40px 28px">
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background:#f8fafc;border:1px solid #e2e8f0;border-radius:12px">
                  <tr>
                    <td width="48" valign="top" style="padding:18px 0 18px 18px"><span style="display:inline-block;border:1px solid #cbd5e1;border-radius:5px;padding:3px 4px;font-size:9px;line-height:12px;font-weight:800;letter-spacing:.05em;color:#475569">CAL</span></td>
                    <td style="padding:18px 18px 18px 0;font-size:16px;line-height:25px;font-weight:600;color:#1e293b">${time}</td>
                  </tr>
                </table>
              </td>
            </tr>
            ${notes}
            <tr>
              <td style="padding:0 40px 20px;font-size:14px;line-height:22px;color:#475569">
                Accept this invitation to add the meeting, Zoom link, and reminder to your calendar.
              </td>
            </tr>
            ${acceptButton}
            <tr>
              <td style="padding:0 40px 18px">
                <a href="${joinUrl}" style="display:block;background:#ffffff;color:#0f172a;text-align:center;text-decoration:none;padding:14px 20px;border:2px solid #cbd5e1;border-radius:10px;font-size:16px;line-height:22px;font-weight:800">Join Zoom meeting</a>
              </td>
            </tr>
            <tr>
              <td style="padding:0 40px 36px;font-size:12px;line-height:19px;color:#64748b">
                The calendar invitation is also attached to this email. At meeting time, use this Zoom link:<br>
                <a href="${joinUrl}" style="color:#475569;text-decoration:underline;word-break:break-all">${joinUrl}</a>
              </td>
            </tr>
            <tr>
              <td style="background:#f8fafc;border-top:1px solid #e2e8f0;padding:20px 40px;font-size:12px;line-height:18px;color:#64748b">
                Sent with WolfGrid. Reply to this email to contact the meeting host.
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>`;
}

export function meetingReminderHtml(input: MeetingInvitation): string {
  const title = escapeHtml(input.title);
  const time = escapeHtml(meetingInvitationTime(input));
  const joinUrl = escapeHtml(input.joinUrl);

  return `<!doctype html>
<html lang="en">
  <body style="margin:0;padding:0;background:#f1f5f9;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#0f172a">
    <div style="display:none;max-height:0;overflow:hidden;opacity:0">${title} starts in 5 minutes — join on Zoom</div>
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background:#f1f5f9">
      <tr>
        <td align="center" style="padding:32px 16px">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:600px;background:#ffffff;border-radius:20px;overflow:hidden;box-shadow:0 10px 30px rgba(15,23,42,.08)">
            <tr>
              <td style="background:#111827;padding:24px 40px;border-bottom:4px solid #ef2b2d">
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0">
                  <tr>
                    <td style="font-size:24px;line-height:28px;font-weight:800;letter-spacing:-.02em;color:#ffffff">Wolf<span style="color:#ef2b2d">Grid</span></td>
                    <td align="right" style="font-size:11px;line-height:16px;font-weight:700;letter-spacing:.12em;color:#cbd5e1;text-transform:uppercase">Zoom meeting</td>
                  </tr>
                </table>
              </td>
            </tr>
            <tr>
              <td style="padding:40px 40px 18px">
                <div style="font-size:13px;line-height:20px;font-weight:700;color:#ef2b2d;letter-spacing:.08em;text-transform:uppercase;margin-bottom:10px">Starting in 5 minutes</div>
                <h1 style="margin:0;font-size:30px;line-height:38px;letter-spacing:-.025em;color:#0f172a">${title}</h1>
              </td>
            </tr>
            <tr>
              <td style="padding:0 40px 28px">
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background:#f8fafc;border:1px solid #e2e8f0;border-radius:12px">
                  <tr>
                    <td width="48" valign="top" style="padding:18px 0 18px 18px"><span style="display:inline-block;border:1px solid #cbd5e1;border-radius:5px;padding:3px 4px;font-size:9px;line-height:12px;font-weight:800;letter-spacing:.05em;color:#475569">CAL</span></td>
                    <td style="padding:18px 18px 18px 0;font-size:16px;line-height:25px;font-weight:600;color:#1e293b">${time}</td>
                  </tr>
                </table>
              </td>
            </tr>
            <tr>
              <td style="padding:0 40px 18px">
                <a href="${joinUrl}" style="display:block;background:#ef2b2d;color:#ffffff;text-align:center;text-decoration:none;padding:15px 20px;border-radius:10px;font-size:16px;line-height:22px;font-weight:800">Join Zoom meeting</a>
              </td>
            </tr>
            <tr>
              <td style="padding:0 40px 36px;font-size:12px;line-height:19px;color:#64748b">
                If the button doesn't work, copy and paste this link:<br>
                <a href="${joinUrl}" style="color:#475569;text-decoration:underline;word-break:break-all">${joinUrl}</a>
              </td>
            </tr>
            <tr>
              <td style="background:#f8fafc;border-top:1px solid #e2e8f0;padding:20px 40px;font-size:12px;line-height:18px;color:#64748b">
                Sent with WolfGrid. Reply to this email to contact the meeting host.
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>`;
}

export function meetingDeliveryConfigured() {
  return {
    email: Boolean(process.env.RESEND_API_KEY?.trim() && (process.env.RESEND_FROM_EMAIL ?? process.env.INVITES_FROM_EMAIL)?.trim()),
    sms: Boolean(process.env.TELNYX_API_KEY?.trim() && telnyxSmsFromNumber()),
  };
}

export async function sendMeetingEmails(input: MeetingInvitation & {
  emails: string[];
  replyToEmail: string | null;
}): Promise<InvitationDelivery> {
  const requested = input.emails.length;
  if (requested === 0) return { requested: 0, sent: 0, failed: 0 };
  const apiKey = process.env.RESEND_API_KEY?.trim();
  const from = (process.env.RESEND_FROM_EMAIL ?? process.env.INVITES_FROM_EMAIL)?.trim();
  if (!apiKey || !from) {
    return { requested, sent: 0, failed: requested, error: 'Email sending is not configured.' };
  }

  const resend = new Resend(apiKey);
  const results = await Promise.allSettled(input.emails.map(async (to) => {
    const calendar = input.calendarEventId && input.replyToEmail
      ? meetingCalendarIcs({
          id: input.calendarEventId,
          title: input.title,
          startAt: input.startAt,
          endAt: input.endAt,
          joinUrl: input.joinUrl,
          notes: input.notes,
          organizerEmail: input.replyToEmail,
          attendeeEmail: to,
        })
      : null;
    const result = await resend.emails.send({
      from,
      to,
      replyTo: input.replyToEmail ?? undefined,
      subject: `You're invited: ${input.title}`,
      text: meetingInvitationText(input),
      html: meetingInvitationHtml(input),
      attachments: calendar ? [{
        filename: 'wolfgrid-meeting.ics',
        content: Buffer.from(calendar, 'utf8'),
        contentType: 'text/calendar; charset=utf-8; method=REQUEST',
      }] : undefined,
      headers: calendar ? { 'Content-Class': 'urn:content-classes:calendarmessage' } : undefined,
    });
    if (result.error) throw new Error(result.error.message);
    return result.data;
  }));
  const sent = results.filter((result) => result.status === 'fulfilled').length;
  return { requested, sent, failed: requested - sent, error: errorMessage(results) };
}

export async function sendMeetingReminderEmail(input: MeetingInvitation & {
  email: string;
  replyToEmail: string | null;
}): Promise<void> {
  const apiKey = process.env.RESEND_API_KEY?.trim();
  const from = (process.env.RESEND_FROM_EMAIL ?? process.env.INVITES_FROM_EMAIL)?.trim();
  if (!apiKey || !from) throw new Error('Email sending is not configured.');

  const result = await new Resend(apiKey).emails.send({
    from,
    to: input.email,
    replyTo: input.replyToEmail ?? undefined,
    subject: `Starting in 5 minutes: ${input.title}`,
    text: meetingReminderText(input),
    html: meetingReminderHtml(input),
  });
  if (result.error) throw new Error(result.error.message);
}

export async function sendMeetingSms(input: MeetingInvitation & {
  phoneNumbers: string[];
}): Promise<InvitationDelivery> {
  const requested = input.phoneNumbers.length;
  if (requested === 0) return { requested: 0, sent: 0, failed: 0 };
  if (!process.env.TELNYX_API_KEY?.trim() || !telnyxSmsFromNumber()) {
    return { requested, sent: 0, failed: requested, error: 'SMS sending is not configured.' };
  }

  const message = meetingInvitationText(input);
  const results = await Promise.allSettled(input.phoneNumbers.map((to) => sendTelnyxSms({ to, text: message })));
  const sent = results.filter((result) => result.status === 'fulfilled').length;
  return { requested, sent, failed: requested - sent, error: errorMessage(results) };
}
