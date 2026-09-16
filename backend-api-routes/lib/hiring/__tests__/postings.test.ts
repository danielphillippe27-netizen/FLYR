import { test } from 'node:test';
import assert from 'node:assert/strict';
import { adzunaSearchURL, feedQuerySchema, hiringSourceConfigured, parseAdzunaPage, postingFingerprint } from '../postings';

const row = {
  id: 'job-1', title: 'Sales Representative', created: '2026-09-15T08:00:00Z',
  redirect_url: 'https://www.adzuna.ca/jobs/details/1', company: { display_name: 'Example Inc.' },
  location: { display_name: 'Toronto, Ontario' }, salary_min: 50000,
};

test('validates source records without inventing contact details or currency', () => {
  const page = parseAdzunaPage({ count: 1, results: [row] }, 'CA');
  assert.equal(page.postings.length, 1);
  assert.equal(page.postings[0].country, 'CA');
  assert.equal(page.postings[0].contact_email, null);
  assert.equal(page.postings[0].currency, null);
  assert.equal(page.postings[0].posted_at, row.created);
});

test('deduplicates case and whitespace variants, preserves different roles and countries', () => {
  const p = parseAdzunaPage({ count: 1, results: [row] }, 'CA').postings[0];
  assert.equal(postingFingerprint(p), postingFingerprint({ ...p, company: '  EXAMPLE Inc.  ', external_id: 'other-source-id', provider: 'other' }));
  assert.notEqual(postingFingerprint(p), postingFingerprint({ ...p, country: 'US' }));
  assert.notEqual(postingFingerprint(p), postingFingerprint({ ...p, location: 'Ottawa, Ontario' }));
  assert.notEqual(postingFingerprint(p), postingFingerprint({ ...p, title: 'Sales Manager' }));
});

test('rejects missing company, unsafe links and bad dates while keeping valid rows', () => {
  const page = parseAdzunaPage({ count: 4, results: [row,
    { ...row, company: {} }, { ...row, redirect_url: 'javascript:alert(1)' }, { ...row, created: 'yesterday' },
  ] }, 'US');
  assert.equal(page.rejected, 3);
  assert.equal(page.received, 4);
  assert.equal(page.postings.length, 1);
  assert.throws(() => parseAdzunaPage({ error: 'quota' }, 'US'));
});

test('requires explicit connector enablement and credentials; queries only CA/US', () => {
  const env = { HIRING_ADZUNA_ENABLED: 'true', ADZUNA_APP_ID: 'test-id', ADZUNA_APP_KEY: 'test-key' };
  assert.equal(hiringSourceConfigured({}), false);
  assert.equal(hiringSourceConfigured({ ...env, HIRING_ADZUNA_ENABLED: 'false' }), false);
  for (const country of ['CA', 'US'] as const) {
    const url = adzunaSearchURL(country, 2, env);
    assert.equal(url.pathname, `/v1/api/jobs/${country.toLowerCase()}/search/2`);
    assert.equal(url.searchParams.get('sort_by'), 'date');
    assert.equal(url.searchParams.get('max_days_old'), '3');
    assert.equal(url.searchParams.has('what'), false); // All industries and roles.
  }
});

test('rejects unsupported countries, unbounded pages and invalid filters', () => {
  assert.equal(feedQuerySchema.safeParse({ country: 'GB' }).success, false);
  assert.equal(feedQuerySchema.safeParse({ days: '-1' }).success, false);
  assert.equal(feedQuerySchema.safeParse({ offset: 'NaN' }).success, false);
  assert.equal(feedQuerySchema.safeParse({ offset: '100001' }).success, false);
  assert.equal(feedQuerySchema.safeParse({ status: 'unknown' }).success, false);
  assert.equal(feedQuerySchema.parse({}).country, 'all');
});
