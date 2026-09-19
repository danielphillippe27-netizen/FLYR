import assert from 'node:assert/strict';
import test from 'node:test';
import {
  meetingInvitationHtml,
  meetingInvitationText,
  meetingInvitationTime,
  meetingReminderHtml,
  meetingReminderText,
  parseEmailRecipients,
  parsePhoneRecipients,
} from './invitations';

test('normalizes and deduplicates meeting email recipients', () => {
  assert.deepEqual(parseEmailRecipients([' Person@Example.com ', 'person@example.com', 'bad address']), {
    recipients: ['person@example.com'],
    invalid: ['bad address'],
  });
});

test('normalizes Canadian and international meeting phone recipients', () => {
  assert.deepEqual(parsePhoneRecipients(['647 555 0100', '+1 (647) 555-0100', 'not-a-number']), {
    recipients: ['+16475550100'],
    invalid: ['not-a-number'],
  });
});

test('builds a recipient-safe invitation containing the Zoom join URL', () => {
  const input = {
    title: 'Listing consultation',
    startAt: new Date('2026-09-01T18:00:00.000Z'),
    endAt: new Date('2026-09-01T18:30:00.000Z'),
    joinUrl: 'https://zoom.us/j/123',
    notes: 'Bring your questions.',
    timeZone: 'America/Toronto',
    calendarUrl: 'https://wolfgrid.app/api/public/meetings/abc/calendar?signature=123',
  };
  assert.match(meetingInvitationTime(input), /2:00 p\.m\./i);
  assert.match(meetingInvitationText(input), /Join Zoom: https:\/\/zoom\.us\/j\/123/);
  assert.match(meetingInvitationText(input), /Accept meeting:/);
  assert.doesNotMatch(meetingInvitationText(input), /start_url/);
});

test('builds a branded, escaped HTML invitation with a resilient join link', () => {
  const input = {
    title: 'Listing <consultation>',
    startAt: new Date('2026-09-01T18:00:00.000Z'),
    endAt: new Date('2026-09-01T18:30:00.000Z'),
    joinUrl: 'https://zoom.us/j/123?pwd=abc&name=host',
    notes: '<script>alert("no")</script>',
    timeZone: 'America/Toronto',
    calendarUrl: 'https://wolfgrid.app/calendar?event=123&signature=abc',
  };
  const html = meetingInvitationHtml(input);
  assert.match(html, /Wolf<span[^>]*>Grid<\/span>/);
  assert.match(html, /You're invited/i);
  assert.match(html, /Accept Meeting/);
  assert.match(html, /Join Zoom meeting/);
  assert.ok(html.indexOf('Accept Meeting') < html.indexOf('Join Zoom meeting'));
  assert.match(html, /signature=abc/);
  assert.match(html, /https:\/\/zoom\.us\/j\/123\?pwd=abc&amp;name=host/);
  assert.match(html, /Listing &lt;consultation&gt;/);
  assert.match(html, /&lt;script&gt;alert\(&quot;no&quot;\)&lt;\/script&gt;/);
  assert.doesNotMatch(html, /<script>alert/);
});

test('builds a branded five-minute reminder with only the join action', () => {
  const input = {
    title: 'Listing consultation',
    startAt: new Date('2026-09-01T18:00:00.000Z'),
    endAt: new Date('2026-09-01T18:30:00.000Z'),
    joinUrl: 'https://zoom.us/j/123',
    notes: null,
    timeZone: 'America/Toronto',
  };
  assert.match(meetingReminderText(input), /starts in 5 minutes/i);
  assert.match(meetingReminderHtml(input), /Starting in 5 minutes/);
  assert.match(meetingReminderHtml(input), /Join Zoom meeting/);
  assert.doesNotMatch(meetingReminderHtml(input), /Add to calendar/);
});
