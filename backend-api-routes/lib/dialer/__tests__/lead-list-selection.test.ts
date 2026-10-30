import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import ts from 'typescript';
import { parseFocusedLeadIds } from '../lead-list-selection';

test('focused dialler lists retain more than 100 unique leads', () => {
  const ids = Array.from({ length: 840 }, (_, index) => `lead-${index}`);
  assert.deepEqual(parseFocusedLeadIds([...ids, ids[0], ' ', ids[1]].join(',')), ids);
});

function loaderHarness(fetchResponse: (...args: any[]) => any) {
  const source = readFileSync(new URL('../../../components/dialer/PowerDialerPage.tsx', import.meta.url), 'utf8');
  const start = source.indexOf('  const loadDiallerLeads = useCallback(');
  const end = source.indexOf('\n  useEffect(', start);
  const state: any = { leads: [{ id: 'kept-lead' }], active: 'kept-lead', errors: [], loading: false };
  const scope: any = {
    useCallback: (callback: any) => callback,
    currentWorkspaceId: 'workspace', focusedLeadIds: [], focusedListId: '', focusedListName: '', hasFocusedDialerList: false,
    leadLoadSequence: { current: 0 },
    setLoadingLeads: (value: boolean) => { state.loading = value; },
    setError: (error: any) => { state.errors.push(error); },
    setLeads: (leads: any) => { state.leads = leads; },
    setActiveLeadId: (update: any) => { state.active = update(state.active); },
    setCurrentWorkspaceId: () => {}, setMessage: () => {},
    statusForLead: () => 'pending', fetch: fetchResponse, URLSearchParams,
  };
  const compiled = ts.transpileModule(`${source.slice(start, end)}\nglobalThis.load = loadDiallerLeads;`, {
    compilerOptions: { target: ts.ScriptTarget.ES2022 },
  }).outputText;
  vm.runInNewContext(compiled, scope);
  return { state, scope, load: scope.load };
}

test('a failed background refresh keeps the current lead list and active business', async () => {
  const h = loaderHarness(async () => ({ ok: false, status: 503, json: async () => ({ error: 'Temporarily unavailable' }) }));
  await h.load({ silent: true });
  assert.equal(h.state.leads[0].id, 'kept-lead');
  assert.equal(h.state.active, 'kept-lead');
  assert.match(h.state.errors.at(-1), /Temporarily unavailable/);
});

test('an older refresh cannot replace a newer full list', async () => {
  const pending: Array<(value: any) => void> = [];
  const h = loaderHarness(() => new Promise(resolve => pending.push(resolve)));
  const oldRequest = h.load();
  const newRequest = h.load();
  const newer = Array.from({ length: 118 }, (_, index) => ({ id: `lead-${index}` }));
  pending[1]({ ok: true, json: async () => ({ leads: newer }) });
  await newRequest;
  pending[0]({ ok: true, json: async () => ({ leads: [{ id: 'outdated' }] }) });
  await oldRequest;
  assert.equal(h.state.leads.length, 118);
  assert.equal(h.state.leads[0].id, 'lead-0');
});

test('reload requests retain completed leads and use the saved list ID', async () => {
  let requested = '';
  const h = loaderHarness(async (url: string) => { requested = url; return { ok: true, json: async () => ({ leads: [] }) }; });
  h.scope.focusedListId = 'saved-list';
  await h.load();
  const url = new URL(requested, 'https://example.com');
  assert.equal(url.searchParams.get('includeCompleted'), '1');
  assert.equal(url.searchParams.get('listId'), 'saved-list');
});
