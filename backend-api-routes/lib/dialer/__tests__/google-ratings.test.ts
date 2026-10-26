import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import vm from 'node:vm';
import ts from 'typescript';
import { NextRequest } from 'next/server';

const require = createRequire(import.meta.url);
function harness(rows: any[], refreshed?: any) {
  let refreshes = 0;
  const filters: Array<(row: any) => boolean> = [];
  const query: any = {
    select: () => query, order: () => query, limit: () => query,
    eq: (key: string, value: unknown) => { filters.push(row => row[key] === value); return query; },
    neq: (key: string, value: unknown) => { filters.push(row => row[key] !== value); return query; },
    in: (key: string, values: unknown[]) => { filters.push(row => values.includes(row[key])); return query; },
    then: (resolve: any, reject: any) => Promise.resolve({ data: rows.filter(row => filters.every(filter => filter(row))), error: null }).then(resolve, reject),
  };
  const overrides: Record<string, unknown> = {
    '@/lib/dialer/server': { getDialerRequestContext: async () => ({ workspaceId: 'workspace', requestUser: { id: 'owner' }, admin: {
      from: () => query, rpc: async () => ({ data: [], error: null }),
    } }) },
    '@/lib/dialer/phone': { normalizePhoneNumber: (phone: string) => ({ e164: phone }), phoneMarketFromCountryCode: () => 'CA' },
    '@/lib/sales-leads/master-list': {},
    '@/lib/sales-leads/google-place-details': { refreshGooglePlaceDetails: async (_context: unknown, row: any) => { refreshes++; return refreshed ?? row; } },
    '@/lib/sales-pro/communications': {}, '@/lib/email/demo': {}, '@/lib/dialer/demo-email-handle': {},
  };
  const source = readFileSync(new URL('../../../app/api/dialer/leads/route.ts', import.meta.url), 'utf8');
  const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
  const module = { exports: {} as any };
  vm.runInNewContext(compiled, { module, exports: module.exports, console, require: (id: string) => overrides[id] ?? require(id) });
  return { get: module.exports.GET, refreshes: () => refreshes };
}
const lead = (overrides: Record<string, unknown> = {}) => ({
  id: 'lead', workspace_id: 'workspace', assigned_user_id: 'owner', name: 'Business',
  phone_e164: '+14165550123', lead_state: 'new', source: 'google_places', external_id: 'place',
  metadata: { googlePlaceId: 'place', googleRating: 4.7, googleReviewCount: 123 }, ...overrides,
});

test('iPhone dialler receives saved Google rating and review count without a provider request', async () => {
  const h = harness([lead()]);
  const response = await h.get(new NextRequest('https://sales.wolfgrid.app/api/dialer/leads'));
  assert.equal(response.status, 200);
  const { leads } = await response.json();
  assert.equal(leads[0].google_place_id, 'place');
  assert.equal(leads[0].google_rating, 4.7);
  assert.equal(leads[0].google_rating_count, 123);
  assert.equal(h.refreshes(), 0);
});
test('missing ratings stay null and preserve the place ID for an on-demand refresh', async () => {
  const h = harness([lead({ metadata: {} })]);
  const response = await h.get(new NextRequest('https://sales.wolfgrid.app/api/dialer/leads'));
  const { leads } = await response.json();
  assert.equal(leads[0].google_place_id, 'place');
  assert.equal(leads[0].google_rating, null);
  assert.equal(leads[0].google_rating_count, null);
});
test('selected lead refresh returns the enriched rating in the same response', async () => {
  const h = harness([lead({ metadata: {} })], lead());
  const response = await h.get(new NextRequest('https://sales.wolfgrid.app/api/dialer/leads?leadIds=lead&refreshGoogleRating=1'));
  const { leads } = await response.json();
  assert.equal(leads[0].google_rating, 4.7);
  assert.equal(h.refreshes(), 1);
});
test('a focused refresh cannot read or enrich another owner’s lead', async () => {
  const h = harness([lead({ assigned_user_id: 'other' })], lead());
  const response = await h.get(new NextRequest('https://sales.wolfgrid.app/api/dialer/leads?leadIds=lead&refreshGoogleRating=1'));
  const { leads } = await response.json();
  assert.equal(leads.length, 0);
  assert.equal(h.refreshes(), 0);
});
