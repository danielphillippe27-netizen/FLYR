import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import vm from 'node:vm';
import ts from 'typescript';
const require = createRequire(import.meta.url);

function runtimeHarness({ inCall = false, lastLead = false } = {}) {
  const leads = [{ id: 'one', name: 'First', phone: '+14165550101' }, ...lastLead ? [] : [{ id: 'two', name: 'Second', phone: '+14165550102' }]];
  const state: any[] = ['tab', leads, 'one', inCall ? 'call-one' : null, false, null, 0, inCall, false, false];
  let index = 0;
  const requests: any[] = [];
  let hangs = 0;
  const react = {
    createContext: () => ({ Provider: 'Provider' }),
    useState: () => { const i = index++; return [state[i], (value: any) => { state[i] = typeof value === 'function' ? value(state[i]) : value; }]; },
    useRef: (value: any) => ({ current: value }), useEffect: () => {},
    useCallback: (fn: any) => fn, useMemo: (fn: any) => fn(),
  };
  const overrides: Record<string, any> = {
    react,
    '@/lib/hooks/useDialerDevice': { useDialerDevice: () => ({ isInCall: inCall, hangUp: () => hangs++ }) },
    '@/lib/workspace-context': { useWorkspace: () => ({ currentWorkspaceId: 'workspace' }) },
    '@/lib/dialer/phone': { normalizePhoneNumber: () => ({ isValid: true }) },
    '@/lib/dialer/recordings': {},
    '@/components/ui/button': { Button: 'button' },
  };
  const source = readFileSync(new URL('../../../components/dialer/DialerRuntimeProvider.tsx', import.meta.url), 'utf8');
  const output = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX, target: ts.ScriptTarget.ES2022 } }).outputText;
  const module = { exports: {} as any };
  vm.runInNewContext(output, {
    module, exports: module.exports, require: (id: string) => overrides[id] ?? require(id),
    crypto: { randomUUID: () => 'tab' }, console,
    fetch: async (url: string, options: any) => { requests.push({ url, options }); return { ok: true, json: async () => ({ lead: leads[0] }) }; },
  });
  const tree = module.exports.DialerRuntimeProvider({ children: null });
  const context = tree.props.value;
  return { context, state, requests, hangs: () => hangs };
}

test('Next call selects the next lead without an outbound call or device initialization', async () => {
  const h = runtimeHarness();
  assert.equal((await h.context.placeNextDiallerCall()).ok, true);
  assert.equal(h.state[2], 'two');
  assert.equal(h.state[7], false);
  assert.equal(h.requests.some(r => r.url.endsWith('/leads/call')), false);
});

test('Next call hangs up an active call and waits for Dial', async () => {
  const h = runtimeHarness({ inCall: true });
  await h.context.placeNextDiallerCall();
  assert.equal(h.hangs(), 1);
  assert.equal(h.state[2], 'two');
  assert.equal(h.state[3], null);
  assert.equal(h.requests.some(r => r.url.endsWith('/leads/call')), false);
});

test('Last lead does not wrap into an automatic call', async () => {
  const h = runtimeHarness({ lastLead: true });
  assert.equal((await h.context.placeNextDiallerCall()).ok, false);
  assert.equal(h.requests.length, 0);
});

test('demo messages always use demo100, including legacy audience requests', async () => {
  const { NextRequest, NextResponse } = require('next/server');
  const source = readFileSync(new URL('../../../app/api/dialer/leads/[leadId]/demo-message/route.ts', import.meta.url), 'utf8');
  const output = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
  const module = { exports: {} as any };
  vm.runInNewContext(output, {
    module, exports: module.exports, URL, console,
    require: (id: string) => id === '../../../_utils' ? { resolveDialerWorkspace: async () => ({ response: null, context: { user: { id: 'hughes' }, workspace: { id: 'sales' } } }) }
      : id === '@/lib/supabase/server' ? { createAdminClient: () => ({}) }
      : id === '@/lib/dialer/salesperson-settings' ? { resolveSalespersonForUser: async () => ({ full_name: 'Daniel Hughes' }) }
      : id === '@/lib/email/demo' ? { SALES_DEMO_URL: 'https://wolfgrid.app/demo100' } : require(id),
  });
  for (const offer of ['solo', 'team', 'brokerage']) {
    const response = await module.exports.POST(new NextRequest('https://sales.wolfgrid.app/api/dialer/leads/one/demo-message', {
      method: 'POST', body: JSON.stringify({ offer }),
    }), { params: Promise.resolve({ leadId: 'one' }) });
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.demoUrl, 'https://wolfgrid.app/demo100');
    assert.ok(body.textBody.includes('https://wolfgrid.app/demo100'));
    assert.ok(body.emailBody.includes('https://wolfgrid.app/demo100'));
    assert.ok(body.emailBody.includes('Daniel Hughes'));
    assert.equal(body.tracked, false);
  }
});
