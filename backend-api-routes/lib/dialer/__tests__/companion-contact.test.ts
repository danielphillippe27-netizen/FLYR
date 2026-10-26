import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import vm from 'node:vm';
import ts from 'typescript';
import { NextRequest, NextResponse } from 'next/server';
import { normalizePhoneNumber } from '../phone';

const require = createRequire(import.meta.url);
function harness(denied = false) {
  const filters: Array<[string, unknown]> = [];
  const query: any = { select: () => query, eq: (key: string, value: unknown) => { filters.push([key, value]); return query; }, order: () => query,
    limit: async () => ({ data: [{ id: 'own-lead', name: 'AAA Roofmasters' }], error: null }) };
  const dependencies: Record<string, unknown> = {
    '@/lib/sales-pro/context': {
      cleanText: (value: unknown) => typeof value === 'string' && value.trim() ? value.trim() : null,
      requireSalesProContext: async () => denied ? NextResponse.json({ error: 'Unauthorized' }, { status: 401 }) : { admin: { from: () => query }, userId: 'rep-1', workspaceId: 'workspace-1' },
    },
    '@/lib/dialer/phone': { normalizePhoneNumber },
  };
  const module = { exports: {} as any };
  const source = readFileSync(new URL('../../../app/api/dialer/companion/route.ts', import.meta.url), 'utf8');
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText,
    { exports: module.exports, require: (name: string) => dependencies[name] ?? require(name) });
  return { filters, get: (queryString: string) => module.exports.GET(new NextRequest(`https://sales.wolfgrid.app/api/dialer/companion?${queryString}`)) };
}

test('phone matching is normalized and scoped to the signed-in user and workspace', async () => {
  const h = harness();
  const response = await h.get('phone=%2B1%20(905)%20949-1553');
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('cache-control'), 'private, no-store');
  for (const [key, value] of [['phone_e164', '+19059491553'], ['assigned_user_id', 'rep-1'], ['workspace_id', 'workspace-1']]) assert.ok(h.filters.some(([field, actual]) => field === key && actual === value));
});

test('explicit contact selection still enforces ownership and workspace', async () => {
  const h = harness();
  assert.equal((await h.get('leadId=foreign-id')).status, 200);
  assert.ok(h.filters.some(([key, value]) => key === 'id' && value === 'foreign-id'));
  assert.ok(h.filters.some(([key, value]) => key === 'assigned_user_id' && value === 'rep-1'));
});

test('unauthorized and missing identities cannot enumerate contacts', async () => {
  assert.equal((await harness(true).get('phone=%2B19059491553')).status, 401);
  const h = harness();
  assert.deepEqual((await (await h.get('')).json()).leads, []);
  assert.equal(h.filters.length, 0);
});
