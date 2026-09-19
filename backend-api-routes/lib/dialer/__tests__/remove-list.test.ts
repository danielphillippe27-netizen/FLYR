import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';
import ts from 'typescript';
import { NextRequest, NextResponse } from 'next/server';

const leadId = '00000000-0000-4000-8000-000000000001';

function harness(fail = false) {
  const calls: Array<[string, ...unknown[]]> = [];
  const query: any = {};
  for (const method of ['from', 'update', 'eq', 'neq', 'in', 'select', 'order', 'limit']) {
    query[method] = (...args: unknown[]) => { calls.push([method, ...args]); return query; };
  }
  query.maybeSingle = async () => ({ data: { id: leadId }, error: null });
  query.then = (resolve: (value: unknown) => unknown) => Promise.resolve({ count: 123, error: fail ? new Error('database failed') : null }).then(resolve);
  const dependencies: Record<string, unknown> = {
    'next/server': { NextResponse },
    '@/lib/dialer/server': { getDialerRequestContext: async () => ({ admin: query, workspaceId: 'workspace', requestUser: { id: 'owner' } }) },
    '@/lib/sales-leads/master-list': {},
    '@/lib/sales-pro/communications': {},
    '@/lib/email/demo': {},
    '@/lib/dialer/demo-email-handle': {},
  };
  const module = { exports: {} as any };
  const source = readFileSync(new URL('../../../app/api/dialer/leads/route.ts', import.meta.url), 'utf8');
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText, {
    exports: module.exports,
    require: (id: string) => { assert.ok(id in dependencies, id); return dependencies[id]; },
    console: { error() {} },
  });
  return {
    calls,
    load: () => module.exports.GET(new NextRequest(`http://localhost/api/dialer/leads?leadIds=${leadId}`)) as Promise<NextResponse>,
    remove: (body: unknown) => module.exports.DELETE(new NextRequest('http://localhost/api/dialer/leads', {
      method: 'DELETE', body: JSON.stringify(body), headers: { 'Content-Type': 'application/json' },
    })) as Promise<NextResponse>,
  };
}

test('Remove List accepts bulk requests without a lead ID and scopes active queue archival', async () => {
  const h = harness();
  const response = await h.remove({ deleteAll: true });
  assert.equal(response.status, 200);
  assert.equal((await response.json()).deletedCount, 123);
  assert.ok(h.calls.some(([method, key, value]) => method === 'eq' && key === 'workspace_id' && value === 'workspace'));
  assert.ok(h.calls.some(([method, key, value]) => method === 'eq' && key === 'assigned_user_id' && value === 'owner'));
  assert.ok(h.calls.some(([method, key]) => method === 'in' && key === 'lead_state'));
  assert.equal((h.calls.find(([method]) => method === 'update')![1] as any).lead_state, 'archived');
  assert.deepEqual(h.calls.filter(([method]) => method === 'from').map((call) => call[1]), ['sales_leads']);
});

test('focused list removal retains every selected ID, including lists above 100 leads', async () => {
  const h = harness();
  const ids = Array.from({ length: 150 }, (_, i) => `00000000-0000-4000-8000-${String(i).padStart(12, '0')}`);
  assert.equal((await h.remove({ deleteAll: true, ids })).status, 200);
  const selected = h.calls.find(([method, key]) => method === 'in' && key === 'id')![2] as string[];
  assert.deepEqual(Array.from(selected), ids);
  assert.ok(!h.calls.some(([method, key]) => method === 'in' && key === 'lead_state'));
});

test('empty and invalid selections cannot clear the whole queue', async () => {
  for (const ids of [[], null, 'invalid', ['invalid'], [leadId, 42]]) {
    const h = harness();
    const response = await h.remove({ deleteAll: true, ids });
    assert.equal(response.status, Array.isArray(ids) && ids.length === 0 ? 200 : 400);
    assert.equal(h.calls.length, 0);
  }
});

test('single lead removal remains supported and missing targets are rejected', async () => {
  const h = harness();
  assert.equal((await h.remove({ id: leadId })).status, 200);
  assert.ok(h.calls.some(([method, key, value]) => method === 'eq' && key === 'id' && value === leadId));
  assert.equal((await harness().remove({})).status, 400);
  assert.equal((await harness().remove({ deleteAll: 'true' })).status, 400);
});

test('database failures do not report a successful list removal', async () => {
  assert.equal((await harness(true).remove({ deleteAll: true })).status, 500);
});

test('reopening a focused list excludes leads already removed from the queue', async () => {
  const h = harness();
  assert.equal((await h.load()).status, 200);
  assert.ok(h.calls.some(([method, key, value]) => method === 'neq' && key === 'lead_state' && value === 'archived'));
});
