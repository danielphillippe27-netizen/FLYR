import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import ts from 'typescript';
import { NextRequest, NextResponse } from 'next/server';

function harness({ missing = false, unauthorized = false } = {}) {
  const writes: Array<{ table: string; value: any; filters: Array<[string, unknown]> }> = [];
  const existing = { id: 'lead-1', workspace_id: 'workspace-1', assigned_user_id: 'rep-1', name: 'AAA Roofmasters', sales_contact_id: 'contact-1', country_code: 'CA', updated_at: '2026-10-26T14:00:00Z' };
  const admin = { from(table: string) {
    const filters: Array<[string, unknown]> = [];
    let update: any = null;
    const query: any = {
      select: () => query, limit: () => query,
      eq: (key: string, value: unknown) => { filters.push([key, value]); return query; },
      update: (value: any) => { update = value; writes.push({ table, value, filters }); return query; },
      insert: (value: any) => { writes.push({ table, value, filters }); return query; },
      maybeSingle: async () => ({ data: update && filters.some(([key, value]) => key === 'updated_at' && value !== existing.updated_at) ? null : table === 'salespeople' ? { id: 'salesperson-1', workspace_id: 'workspace-1' } : table === 'user_profiles' ? { is_founder: false } : missing ? null : { ...existing, ...update }, error: null }),
      single: async () => ({ data: { ...existing, ...update }, error: null }),
      then: (resolve: any) => resolve({ error: null }),
    };
    return query;
  }};
  const dependencies: Record<string, any> = {
    'next/server': { NextResponse },
    '@/app/api/_utils/request-user': { resolveUserFromRequest: async () => unauthorized ? null : { id: 'rep-1' } },
    '@/app/api/_utils/workspace': { resolveWorkspaceIdForUser: async () => ({ workspaceId: 'workspace-1' }) },
    '@/lib/supabase/server': { createAdminClient: () => admin },
    '@/lib/dialer/phone': {},
  };
  const module = { exports: {} as any };
  const source = readFileSync(new URL('../../app/api/salesperson/leads/[leadId]/route.ts', import.meta.url), 'utf8');
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText, {
    exports: module.exports, require: (name: string) => { assert.ok(name in dependencies, name); return dependencies[name]; }, console: { error() {} },
  });
  const call = (body: any) => module.exports.PATCH(new NextRequest('https://sales.wolfgrid.app/api/salesperson/leads/lead-1', { method: 'PATCH', body: JSON.stringify({ workspaceId: 'workspace-1', ...body }) }), { params: Promise.resolve({ leadId: 'lead-1' }) });
  return { call, writes };
}

test('contact editor saves email and address on both lead and linked contact', async () => {
  const h = harness();
  const response = await h.call({ email: ' INFO@AAAROOFMASTERS.COM ', address: ' 437 Attwell Dr ', notes: 'Ask about roofing services' });
  assert.equal(response.status, 200);
  assert.equal((await response.json()).lead.address, '437 Attwell Dr');
  const lead = h.writes.find((write) => write.table === 'sales_leads')!;
  const contact = h.writes.find((write) => write.table === 'sales_contacts')!;
  assert.equal(lead.value.email_normalized, 'info@aaaroofmasters.com');
  assert.equal(contact.value.email, 'info@aaaroofmasters.com');
  assert.equal(contact.value.address, '437 Attwell Dr');
  assert.ok(lead.filters.some(([key, value]) => key === 'workspace_id' && value === 'workspace-1'));
  assert.ok(contact.filters.some(([key, value]) => key === 'id' && value === 'contact-1'));
});

test('clearing an address persists on the lead and linked contact', async () => {
  const h = harness();
  assert.equal((await h.call({ address: '' })).status, 200);
  for (const write of h.writes.filter((write) => ['sales_leads', 'sales_contacts'].includes(write.table))) assert.equal(write.value.address, null);
});

test('invalid email, unauthorized requests and inaccessible contacts never mutate records', async () => {
  for (const [h, body, status] of [[harness(), { email: 'invalid' }, 400], [harness({ unauthorized: true }), {}, 401], [harness({ missing: true }), {}, 404]] as const) {
    assert.equal((await h.call(body)).status, status);
    assert.equal(h.writes.length, 0);
  }
});


test('stale companion edits return a conflict without changing the linked contact', async () => {
  const h = harness();
  const response = await h.call({ notes: 'Stale draft', expectedUpdatedAt: '2026-10-26T13:00:00Z' });
  assert.equal(response.status, 409);
  assert.equal(h.writes.filter(write => write.table === 'sales_contacts').length, 0);
  assert.match((await response.json()).error, /other screen/);
});
