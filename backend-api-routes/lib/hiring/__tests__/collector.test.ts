import { test } from 'node:test';
import assert from 'node:assert/strict';
import { collectHiringLeads } from '../collector';

function fakeDB(claim = true, failIngest = false) {
  const batches: unknown[] = [];
  const summaries: Array<Record<string, unknown>> = [];
  return {
    batches, summaries,
    rpc: async (name: string, args: Record<string, unknown>) => {
      if (name === 'claim_hiring_collection') return { data: claim ? `run-${args.p_country}` : null, error: null };
      batches.push(args.p_postings);
      return { data: null, error: failIngest ? { message: 'db failure' } : null };
    },
    from: () => ({ update: (summary: Record<string, unknown>) => {
      summaries.push(summary);
      return { eq: () => ({ eq: async () => ({ error: null }) }) };
    } }),
  };
}
const job = { id: '1', title: 'Engineer', created: '2026-09-15T00:00:00Z',
  company: { display_name: 'Example' }, location: { display_name: 'Remote' }, redirect_url: 'https://example.com/jobs/1' };

test('collector reports success, partial results, failures, and skips without spending requests', async () => {
  const previous = { enabled: process.env.HIRING_ADZUNA_ENABLED, id: process.env.ADZUNA_APP_ID, key: process.env.ADZUNA_APP_KEY };
  process.env.HIRING_ADZUNA_ENABLED = 'true'; process.env.ADZUNA_APP_ID = 'test'; process.env.ADZUNA_APP_KEY = 'test';
  try {
    const db = fakeDB();
    const success = await collectHiringLeads(db as never, (async () => Response.json({ count: 1, results: [job] })) as typeof fetch);
    assert.equal(success.runs.length, 2);
    assert.ok(success.runs.every(r => r.status === 'complete' && r.fetched === 1));
    assert.equal(db.batches.length, 2);

    const partial = await collectHiringLeads(fakeDB() as never, (async () => Response.json({ count: 500, results: [job] })) as typeof fetch);
    assert.ok(partial.runs.every(r => r.status === 'partial'));

    let pageCalls = 0;
    const bounded = await collectHiringLeads(fakeDB() as never, (async () => {
      pageCalls++;
      return Response.json({ count: 20000, results: Array.from({ length: 50 }, (_, i) => ({ ...job, id: String(i) })) });
    }) as typeof fetch);
    assert.equal(pageCalls, 20);
    assert.ok(bounded.runs.every(r => r.status === 'partial' && r.fetched === 500));

    const mixed = await collectHiringLeads(fakeDB() as never, (async (url) =>
      String(url).includes('/ca/') ? new Response('', { status: 503 }) : Response.json({ count: 1, results: [job] })
    ) as typeof fetch);
    assert.equal(mixed.runs[0].status, 'failed');
    assert.equal(mixed.runs[1].status, 'complete');

    const failure = await collectHiringLeads(fakeDB() as never, (async () => new Response('secret provider body', { status: 429 })) as typeof fetch);
    assert.ok(failure.runs.every(r => r.status === 'failed'));
    assert.ok(!JSON.stringify(failure).includes('secret provider body'));

    const dbFailure = await collectHiringLeads(fakeDB(true, true) as never, (async () => Response.json({ count: 1, results: [job] })) as typeof fetch);
    assert.ok(dbFailure.runs.every(r => r.status === 'failed' && r.fetched === 0));

    let calls = 0;
    const noFetch = (async () => { calls++; throw new Error('Should not fetch'); }) as typeof fetch;
    const skipped = await collectHiringLeads(fakeDB(false) as never, noFetch);
    assert.ok(skipped.runs.every(r => r.status === 'already_claimed'));
    process.env.HIRING_ADZUNA_ENABLED = 'false';
    assert.equal((await collectHiringLeads(fakeDB() as never, noFetch)).configured, false);
    assert.equal(calls, 0);
  } finally {
    for (const [key, value] of Object.entries({ HIRING_ADZUNA_ENABLED: previous.enabled, ADZUNA_APP_ID: previous.id, ADZUNA_APP_KEY: previous.key })) {
      if (value === undefined) delete process.env[key]; else process.env[key] = value;
    }
  }
});
