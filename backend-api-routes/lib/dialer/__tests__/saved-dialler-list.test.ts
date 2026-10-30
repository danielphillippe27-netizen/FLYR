import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import vm from 'node:vm';
import ts from 'typescript';
import { NextRequest, NextResponse } from 'next/server';

const require = createRequire(import.meta.url);
function compile(path: string, dependencies: Record<string, any>, extra = '') {
  const source = readFileSync(new URL(path, import.meta.url), 'utf8');
  const compiled = ts.transpileModule(source + extra, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
  const module = { exports: {} as any };
  vm.runInNewContext(compiled, { module, exports: module.exports, console, URLSearchParams,
    require: (id: string) => dependencies[id] ?? (id.startsWith('@/') || id.startsWith('../') ? {} : require(id)),
  });
  return module.exports;
}

function listHarness(members: string[], listOwner = 'owner') {
  const rows = Array.from({ length: 120 }, (_, index) => ({
    id: `lead-${index}`, workspace_id: 'workspace', assigned_user_id: index === 119 ? 'someone-else' : 'owner',
    lead_state: index === 118 ? 'archived' : index % 2 ? 'interested' : 'assigned',
    name: `Roofer ${index}`, phone: `+1705555${String(index).padStart(4, '0')}`,
  }));
  const admin = {
    from(table: string) {
      const filters: Array<(row: any) => boolean> = [];
      const q: any = { select: () => q, order: () => q, limit: () => q };
      q.eq = (key: string, value: unknown) => { filters.push(row => row[key] === value); return q; };
      q.neq = (key: string, value: unknown) => { filters.push(row => row[key] !== value); return q; };
      q.in = (key: string, values: unknown[]) => { filters.push(row => values.includes(row[key])); return q; };
      const result = () => (table === 'smart_lists' ? [{ id: 'saved', workspace_id: 'workspace', created_by_user_id: listOwner, criteria: { masterLeadIds: members } }] : rows)
        .filter(row => filters.every(filter => filter(row)));
      q.maybeSingle = async () => ({ data: result()[0] ?? null, error: null });
      q.then = (resolve: any) => Promise.resolve({ data: result(), error: null }).then(resolve);
      return q;
    },
    rpc: async () => ({ data: [], error: null }),
  };
  const route = compile('../../../app/api/dialer/leads/route.ts', {
    '@/lib/dialer/server': { getDialerRequestContext: async () => ({ admin, workspaceId: 'workspace', requestUser: { id: 'owner' } }) },
    '@/lib/dialer/phone': { normalizePhoneNumber: (phone: string) => ({ e164: phone }), phoneMarketFromCountryCode: () => 'CA' },
  });
  return (suffix = '') => route.GET(new NextRequest(`http://localhost/api/dialer/leads?listId=saved${suffix}`)) as Promise<NextResponse>;
}

test('saved list reload returns all 118 owned leads, including completed calls, beyond the old 100-row limit', async () => {
  const get = listHarness(Array.from({ length: 120 }, (_, index) => `lead-${index}`));
  for (let refresh = 0; refresh < 2; refresh++) {
    const response = await get();
    assert.equal(response.status, 200);
    const result = await response.json();
    assert.equal(result.leads.length, 118);
    assert.ok(result.leads.some((row: any) => row.lead_state === 'interested'));
    assert.ok(!result.leads.some((row: any) => row.assigned_user_id !== 'owner' || row.lead_state === 'archived'));
  }
});

test('empty saved lists stay empty instead of falling back to the whole queue', async () => {
  const response = await listHarness([])();
  assert.equal((await response.json()).leads.length, 0);
});

test('another user’s saved list cannot be loaded', async () => {
  const response = await listHarness(['lead-0'], 'someone-else')();
  assert.equal(response.status, 404);
});

test('Places save returns canonical dialler IDs for the complete list, including existing leads', async () => {
  let savedCriteria: any;
  const master = (name: string) => ({ id: `master-${name.split(' ').at(-1)}`, assigned_user_id: 'owner', metadata: {} });
  const admin = { from(table: string) {
    const q: any = { select: () => q, eq: () => q, update: () => q };
    q.insert = (value: any) => { if (table === 'smart_lists') savedCriteria = value.criteria; return q; };
    q.single = async () => ({ data: { id: 'saved-list' }, error: null });
    q.then = (resolve: any) => Promise.resolve({ data: [], error: null }).then(resolve);
    return q;
  } };
  const route = compile('../../../app/api/salesperson/google-places/route.ts', {
    '@/lib/dialer/phone': {
      normalizePhoneMarket: () => 'CA',
      normalizePhoneNumber: (value: string) => ({ isValid: Boolean(value), e164: value || null }),
    },
    '@/lib/sales-leads/master-list': {
      findSalespersonLeadMaster: async (_admin: any, input: any) => ({ available: true, row: Number(input.name.split(' ').at(-1)) < 60 ? master(input.name) : null }),
      ensureSalespersonLeadMaster: async (_admin: any, input: any) => ({ available: true, created: true, row: master(input.name) }),
    },
    '@/lib/company-research/identity': { resolveCompanyForLead: async () => {} },
  }, '\nexport { saveScraperResults };');
  const leads = Array.from({ length: 118 }, (_, index) => ({
    placeId: `place-${index}`, name: `Roofer ${index}`, phone: index < 115 ? `+1705555${String(index).padStart(4, '0')}` : '', formattedAddress: '',
  }));
  const result = await route.saveScraperResults({ admin, userId: 'owner', workspaceId: 'workspace', leads, city: 'Barrie', industry: 'Roofing', countryCode: 'CA' });
  assert.equal(result.listId, 'saved-list');
  assert.equal(result.contactCount, 118);
  assert.equal(savedCriteria.masterLeadIds.length, 118);
  assert.equal(result.dialerLeadIds.length, 115);
  assert.equal(new Set(result.dialerLeadIds).size, 115);
  assert.equal(result.dialerImportedCount, 55);
  assert.equal(result.dialerSkippedCount, 60);
});

test('re-adding an archived list keeps every lead visible after a call and refresh', async () => {
  const rows = Array.from({ length: 117 }, (_, i) => ({
    id: `lead-${i}`, workspace_id: 'workspace', assigned_user_id: 'owner',
    name: `Roofer ${i}`, phone: `+1705555${String(i).padStart(4, '0')}`,
    lead_state: 'archived', disposition: null, metadata: {},
  }));
  const admin = {
    from() {
      const filters: Array<(row: any) => boolean> = [];
      let update: Record<string, unknown> | null = null;
      const query: any = {};
      query.select = () => query; query.order = () => query; query.limit = () => query;
      query.eq = (key: string, value: unknown) => { filters.push(row => row[key] === value); return query; };
      query.neq = (key: string, value: unknown) => { filters.push(row => row[key] !== value); return query; };
      query.in = (key: string, values: unknown[]) => { filters.push(row => values.includes(row[key])); return query; };
      query.update = (value: Record<string, unknown>) => { update = value; return query; };
      query.then = (resolve: any) => {
        const selected = rows.filter(row => filters.every(filter => filter(row)));
        if (update) selected.forEach(row => Object.assign(row, update));
        return Promise.resolve({ data: selected.map(row => ({ ...row })), error: null }).then(resolve);
      };
      return query;
    },
    rpc: async () => ({ data: [], error: null }),
  };
  const route = compile('../../../app/api/dialer/leads/route.ts', {
    '@/lib/dialer/server': { getDialerRequestContext: async () => ({ admin, workspaceId: 'workspace', requestUser: { id: 'owner' } }) },
    '@/lib/sales-leads/master-list': { ensureSalespersonLeadMaster: async (_: any, input: any) => ({ row: { ...rows.find(row => row.phone === input.phone) } }) },
    '@/lib/dialer/phone': { normalizePhoneNumber: (phone: string) => ({ e164: phone }), phoneMarketFromCountryCode: () => 'CA' },
  });
  const response = await route.POST(new NextRequest('http://localhost/api/dialer/leads', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ leads: rows }),
  }));
  assert.equal(response.status, 200);
  assert.equal((await response.json()).leads.length, 117);
  rows[0].lead_state = 'attempting';
  const refreshed = await route.GET(new NextRequest('http://localhost/api/dialer/leads?includeCompleted=1'));
  const payload = await refreshed.json();
  assert.equal(payload.leads.length, 117);
  assert.equal(payload.leads.find((lead: any) => lead.id === 'lead-0').lead_state, 'attempting');
});
