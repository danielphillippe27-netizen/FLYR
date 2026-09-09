import assert from 'node:assert/strict';
import test from 'node:test';
import { isInsideBusinessWindow, legacyPipelineStageKey, localClock } from './scheduling';

test('maps every documented legacy stage deterministically', () => {
  assert.deepEqual(['new_lead', 'attempting_contact', 'connected', 'demo_sent', 'trial_sent', 'trial_active', 'closing', 'nurture', 'won', 'lost'].map(legacyPipelineStageKey), ['new', 'contacted', 'conversation', 'proposal', 'proposal', 'proposal', 'proposal', 'contacted', 'won', 'lost']);
});

test('business hours use the workspace timezone across DST', () => {
  const window = { timezone: 'America/Toronto', weekdays: [1, 2, 3, 4, 5], startMinute: 540, endMinute: 1020 };
  assert.equal(isInsideBusinessWindow(new Date('2026-03-09T13:00:00Z'), window), true);
  assert.equal(localClock(new Date('2026-03-09T13:00:00Z'), window.timezone).minute, 540);
  assert.equal(isInsideBusinessWindow(new Date('2026-03-08T14:00:00Z'), window), false);
});
