import assert from 'node:assert/strict';
import test from 'node:test';
import {
  metricComparison,
  percentageChange,
  rangesForPeriod,
} from './performance-comparison';

test('uses standard percentage growth', () => {
  assert.equal(percentageChange(10, 5), 100);
  assert.equal(percentageChange(5, 10), -50);
  assert.equal(percentageChange(0, 0), 0);
  assert.equal(percentageChange(3, 0), null);
  assert.deepEqual(metricComparison(3, null), {
    previousValue: null,
    percentageChange: null,
  });
});

test('daily ranges follow local time across daylight saving changes', () => {
  const ranges = rangesForPeriod(
    'daily',
    'America/Toronto',
    new Date('2026-03-08T16:30:00.000Z')
  );
  assert.equal(ranges.current.start.toISOString(), '2026-03-08T05:00:00.000Z');
  assert.equal(ranges.previous.start.toISOString(), '2026-03-07T05:00:00.000Z');
  assert.equal(ranges.previous.end.toISOString(), '2026-03-07T17:30:00.000Z');
});

test('weekly ranges begin on Monday in the requested timezone', () => {
  const ranges = rangesForPeriod(
    'weekly',
    'America/Toronto',
    new Date('2026-08-05T17:43:00.000Z')
  );
  assert.equal(ranges.current.start.toISOString(), '2026-08-03T04:00:00.000Z');
  assert.equal(ranges.previous.start.toISOString(), '2026-07-27T04:00:00.000Z');
  assert.equal(ranges.previous.end.toISOString(), '2026-07-29T17:43:00.000Z');
});

test('monthly comparison clamps to a shorter previous month', () => {
  const ranges = rangesForPeriod(
    'monthly',
    'UTC',
    new Date('2026-03-31T12:00:00.000Z')
  );
  assert.equal(ranges.previous.start.toISOString(), '2026-02-01T00:00:00.000Z');
  assert.equal(ranges.previous.end.toISOString(), '2026-02-28T12:00:00.000Z');
});

test('yearly comparison clamps leap day', () => {
  const ranges = rangesForPeriod(
    'yearly',
    'UTC',
    new Date('2028-02-29T09:15:00.000Z')
  );
  assert.equal(ranges.previous.start.toISOString(), '2027-01-01T00:00:00.000Z');
  assert.equal(ranges.previous.end.toISOString(), '2027-02-28T09:15:00.000Z');
});

test('falls back to UTC for an invalid timezone', () => {
  const ranges = rangesForPeriod('daily', 'Not/AZone', new Date('2026-08-05T12:00:00Z'));
  assert.equal(ranges.timezone, 'UTC');
  assert.equal(ranges.current.start.toISOString(), '2026-08-05T00:00:00.000Z');
});
