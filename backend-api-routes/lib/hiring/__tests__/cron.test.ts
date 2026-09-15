import { test } from 'node:test';
import assert from 'node:assert/strict';
import { NextRequest } from 'next/server';
import { GET } from '../../../app/api/cron/hiring-leads/route';

test('cron rejects missing, guessed and ordinary user credentials before touching data', async () => {
  const previous = process.env.CRON_SECRET;
  try {
    delete process.env.CRON_SECRET;
    assert.equal((await GET(new NextRequest('https://example.com/api/cron/hiring-leads', {
      headers: { authorization: 'Bearer undefined' },
    }))).status, 401);
    process.env.CRON_SECRET = 'test-scheduler-secret';
    for (const authorization of ['', 'Bearer user-session', 'Bearer wrong-secret']) {
      const response = await GET(new NextRequest('https://example.com/api/cron/hiring-leads', {
        headers: { authorization },
      }));
      assert.equal(response.status, 401);
    }
  } finally {
    if (previous === undefined) delete process.env.CRON_SECRET; else process.env.CRON_SECRET = previous;
  }
});
