import test from 'node:test';
import assert from 'node:assert/strict';
import { lastContactedAt, lastContactedLabel } from '../last-contacted';

const now = new Date(2026, 9, 26, 14, 0);
const at = (day: number, hour = 9, minute = 50) => new Date(2026, 9, day, hour, minute).toISOString();

test('today shows the local call time, earlier calls show a day', () => {
  assert.match(lastContactedLabel({ called_at: at(26) }, now), /9:50/);
  assert.equal(lastContactedLabel({ called_at: at(25) }, now), 'Yesterday');
  assert.match(lastContactedLabel({ called_at: at(24) }, now), /Oct.*24|24.*Oct/);
});

test('a recorded call still shows when lead timestamps were never updated', () => {
  const lead = { called_at: null, last_contacted_at: null, shared_call_history: { last_called_at: at(26), last_called_by: 'You' } };
  assert.equal(lastContactedAt(lead)?.toISOString(), at(26));
  assert.match(lastContactedLabel(lead, now), /9:50/);
});

test('uses the newest contact or call across sources and ignores invalid timestamps', () => {
  assert.equal(lastContactedAt({ last_touch_at: at(25), called_at: at(26), last_contacted_at: 'invalid' })?.toISOString(), at(26));
  assert.equal(lastContactedAt({ called_at: 'invalid' }), null);
  assert.equal(lastContactedLabel({}, now), 'Never contacted');
});

test('previous calendar day remains Yesterday across daylight-saving transitions', () => {
  const nextDay = new Date(2026, 10, 2, 0, 15);
  const previous = new Date(2026, 10, 1, 0, 30).toISOString();
  assert.equal(lastContactedLabel({ called_at: previous }, nextDay), 'Yesterday');
});
