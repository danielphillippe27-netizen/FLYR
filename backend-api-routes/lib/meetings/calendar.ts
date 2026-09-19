import { createHmac, timingSafeEqual } from 'node:crypto';

type CalendarMeeting = {
  id: string;
  title: string;
  startAt: Date;
  endAt: Date;
  joinUrl: string;
  notes: string | null;
  organizerEmail?: string | null;
  attendeeEmail?: string | null;
};

function signingSecret(): string {
  const secret = process.env.CALENDAR_LINK_SECRET?.trim() || process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
  if (!secret) throw new Error('Calendar links are not configured.');
  return secret;
}

function signatureFor(eventId: string): string {
  return createHmac('sha256', signingSecret()).update(`wolfgrid-calendar:${eventId}`).digest('base64url');
}

export function meetingCalendarUrl(origin: string, eventId: string): string {
  const base = origin.replace(/\/+$/, '');
  return `${base}/api/public/meetings/${encodeURIComponent(eventId)}/calendar?signature=${encodeURIComponent(signatureFor(eventId))}`;
}

export function validMeetingCalendarSignature(eventId: string, signature: string | null): boolean {
  if (!signature) return false;
  try {
    const expected = Buffer.from(signatureFor(eventId));
    const provided = Buffer.from(signature);
    return expected.length === provided.length && timingSafeEqual(expected, provided);
  } catch {
    return false;
  }
}

function icsDate(value: Date): string {
  return value.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
}

function icsText(value: string): string {
  return value
    .replace(/\\/g, '\\\\')
    .replace(/\r?\n/g, '\\n')
    .replace(/,/g, '\\,')
    .replace(/;/g, '\\;');
}

export function meetingCalendarIcs(input: CalendarMeeting): string {
  const description = [input.notes, `Join Zoom: ${input.joinUrl}`].filter(Boolean).join('\n\n');
  const isInvitation = Boolean(input.organizerEmail && input.attendeeEmail);
  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//WolfGrid//Meeting Invitation//EN',
    'CALSCALE:GREGORIAN',
    `METHOD:${isInvitation ? 'REQUEST' : 'PUBLISH'}`,
    'BEGIN:VEVENT',
    `UID:${icsText(input.id)}@wolfgrid.app`,
    `DTSTAMP:${icsDate(new Date())}`,
    `DTSTART:${icsDate(input.startAt)}`,
    `DTEND:${icsDate(input.endAt)}`,
    `SUMMARY:${icsText(input.title)}`,
    'STATUS:CONFIRMED',
    'SEQUENCE:0',
    ...(isInvitation ? [
      `ORGANIZER;CN=WolfGrid Sales:mailto:${icsText(input.organizerEmail!)}`,
      `ATTENDEE;ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=TRUE:mailto:${icsText(input.attendeeEmail!)}`,
    ] : []),
    'LOCATION:Zoom',
    `DESCRIPTION:${icsText(description)}`,
    `URL:${icsText(input.joinUrl)}`,
    'BEGIN:VALARM',
    'TRIGGER:-PT10M',
    'ACTION:DISPLAY',
    'DESCRIPTION:WolfGrid meeting reminder',
    'END:VALARM',
    'END:VEVENT',
    'END:VCALENDAR',
    '',
  ].join('\r\n');
}
