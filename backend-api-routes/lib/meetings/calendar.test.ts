import assert from 'node:assert/strict';
import test from 'node:test';
import {
  meetingCalendarIcs,
  meetingCalendarUrl,
  validMeetingCalendarSignature,
} from './calendar';

test('creates a signed public calendar URL', () => {
  const previous = process.env.CALENDAR_LINK_SECRET;
  process.env.CALENDAR_LINK_SECRET = 'test-calendar-secret';
  try {
    const url = new URL(meetingCalendarUrl('https://wolfgrid.app/', 'meeting-123'));
    assert.equal(url.pathname, '/api/public/meetings/meeting-123/calendar');
    assert.equal(validMeetingCalendarSignature('meeting-123', url.searchParams.get('signature')), true);
    assert.equal(validMeetingCalendarSignature('another-meeting', url.searchParams.get('signature')), false);
  } finally {
    if (previous === undefined) delete process.env.CALENDAR_LINK_SECRET;
    else process.env.CALENDAR_LINK_SECRET = previous;
  }
});

test('builds an interoperable calendar event with the Zoom link and reminder', () => {
  const calendar = meetingCalendarIcs({
    id: 'meeting-123',
    title: 'Solar consultation, follow-up',
    startAt: new Date('2026-09-01T18:00:00.000Z'),
    endAt: new Date('2026-09-01T18:30:00.000Z'),
    joinUrl: 'https://zoom.us/j/123?pwd=abc',
    notes: 'Bring usage bills.',
  });
  assert.match(calendar, /BEGIN:VCALENDAR\r\n/);
  assert.match(calendar, /DTSTART:20260901T180000Z/);
  assert.match(calendar, /SUMMARY:Solar consultation\\, follow-up/);
  assert.match(calendar, /Join Zoom: https:\/\/zoom\.us\/j\/123\?pwd=abc/);
  assert.match(calendar, /TRIGGER:-PT10M/);
});

test('builds a recipient-specific calendar invitation that can be accepted', () => {
  const calendar = meetingCalendarIcs({
    id: 'meeting-456',
    title: 'Solar consultation',
    startAt: new Date('2026-09-01T18:00:00.000Z'),
    endAt: new Date('2026-09-01T18:30:00.000Z'),
    joinUrl: 'https://zoom.us/j/456',
    notes: null,
    organizerEmail: 'daniel@wolfgrid.app',
    attendeeEmail: 'recipient@example.com',
  });
  assert.match(calendar, /METHOD:REQUEST/);
  assert.match(calendar, /ORGANIZER;CN=WolfGrid Sales:mailto:daniel@wolfgrid\.app/);
  assert.match(calendar, /ATTENDEE;ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=TRUE:mailto:recipient@example\.com/);
  assert.match(calendar, /STATUS:CONFIRMED/);
});
