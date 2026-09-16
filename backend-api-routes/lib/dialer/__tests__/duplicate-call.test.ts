import test from 'node:test';
import assert from 'node:assert/strict';
import { duplicateCallConflict } from '../duplicate-call';
import { normalizePhoneNumber } from '../phone';

test('formats a duplicate warning without exposing database details', () => {
  const result = duplicateCallConflict({ code: 'PDC01', details: JSON.stringify({
    last_called_at: '2026-09-09T12:00:00Z', last_called_by: 'Jamie',
    last_called_by_user_id: 'rep-a', retry_after: '2026-09-10T12:00:00Z', secret: 'private notes',
  }) }, 'rep-b');
  assert.equal(result?.code, 'duplicate_call');
  assert.match(result!.error, /Jamie already attempted/);
  assert.equal(result?.retry_after, '2026-09-10T12:00:00Z');
  assert.equal(JSON.stringify(result).includes('private notes'), false);
});
test('identifies the current rep and tolerates missing or malformed details', () => {
  assert.match(duplicateCallConflict({ code: 'PDC01', details: '{"last_called_by_user_id":"me"}' }, 'me')!.error, /^You /);
  for (const details of ['invalid', 'null', '{}']) {
    assert.match(duplicateCallConflict({ code: 'PDC01', details }, 'me')!.error, /^A teammate /);
  }
  assert.equal(duplicateCallConflict({ code: '23505' }, 'me'), null);
  assert.equal(duplicateCallConflict(null, 'me'), null);
});
test('manual and imported North American phone formats share a key', () => {
  const formats = ['(416) 555-0123', '4165550123', '+1 416 555 0123', '14165550123'];
  assert.deepEqual(formats.map(value => normalizePhoneNumber(value).e164), Array(4).fill('+14165550123'));
});
