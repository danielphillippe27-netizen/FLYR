import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import ts from 'typescript';
import { NextRequest, NextResponse } from 'next/server';

test('starting a call stamps the canonical lead using its assigned owner', async () => {
  const writes: Array<{ table: string; value: any; filters: Array<[string, unknown]> }> = [];
  // Canonical sales_leads deliberately has no legacy user_id field.
  const lead = { id: 'lead-1', workspace_id: 'workspace-1', assigned_user_id: 'rep-1', name: 'AAA Roofmasters', phone: '+19059491553', attempt_count: 0 };
  const admin = { from(table: string) {
    const filters: Array<[string, unknown]> = [];
    const query: any = {
      select: () => query,
      eq: (key: string, value: unknown) => { filters.push([key, value]); return query; },
      maybeSingle: async () => ({ data: lead, error: null }),
      insert: () => query,
      update: (value: any) => { writes.push({ table, value, filters }); return query; },
      single: async () => ({ data: { id: `${table}-1` }, error: null }),
      then: (resolve: any) => resolve({ error: null }),
    };
    return query;
  }};
  const dependencies: Record<string, any> = {
    'next/server': { NextResponse },
    '@/lib/dialer/server': { getDialerRequestContext: async () => ({ admin, requestUser: { id: 'rep-1' }, workspaceId: 'workspace-1', settings: { defaultFromNumber: '+16479303824' } }) },
    '@/lib/dialer/env': { getDialerTelecomProvider: () => 'telnyx' },
    '@/lib/dialer/caller-id': { resolveOutboundCallerId: () => '+16479303824' },
    '@/lib/dialer/phone': { normalizePhoneNumber: () => ({ isValid: true, e164: '+19059491553' }), phoneMarketFromCountryCode: () => 'CA' },
    '@/lib/dialer/duplicate-call': {},
  };
  const module = { exports: {} as any };
  const source = readFileSync(new URL('../../../app/api/dialer/leads/call/route.ts', import.meta.url), 'utf8');
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText, {
    exports: module.exports, require: (name: string) => { assert.ok(name in dependencies, name); return dependencies[name]; },
    crypto: { randomUUID: () => 'request-1' }, console,
  });
  const response = await module.exports.POST(new NextRequest('https://sales.wolfgrid.app/api/dialer/leads/call', {
    method: 'POST', body: JSON.stringify({ workspaceId: 'workspace-1', leadId: 'lead-1' }),
  }));
  assert.equal(response.status, 200);
  const update = writes.find((write) => write.table === 'sales_leads')!;
  assert.ok(update);
  assert.equal(update.value.attempt_count, 1);
  assert.ok(Number.isFinite(Date.parse(update.value.last_attempted_at)));
  for (const [key, value] of [['id', 'lead-1'], ['workspace_id', 'workspace-1'], ['assigned_user_id', 'rep-1']]) {
    assert.ok(update.filters.some(([field, actual]) => field === key && actual === value));
  }
});
