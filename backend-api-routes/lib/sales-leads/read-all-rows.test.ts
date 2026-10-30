import test from 'node:test';
import assert from 'node:assert/strict';
import { readAllRows } from './read-all-rows';

test('loads older list members beyond the default 1,000-row database ceiling', async () => {
  const source = Array.from({ length: 1057 }, (_, id) => ({ id }));
  const ranges: number[][] = [];
  const result = await readAllRows({ range: async (from, to) => {
    ranges.push([from, to]);
    return { data: source.slice(from, to + 1), error: null };
  } });
  assert.equal(result.length, 1057);
  assert.deepEqual(result, source);
  assert.deepEqual(ranges, [[0, 499], [500, 999], [1000, 1499]]);
});

test('a later page failure does not return a silently truncated list', async () => {
  await assert.rejects(readAllRows({ range: async (from) => from === 0
    ? { data: Array.from({ length: 500 }, (_, id) => ({ id })), error: null }
    : { data: null, error: { message: 'Refresh unavailable' } },
  }), /Refresh unavailable/);
});
