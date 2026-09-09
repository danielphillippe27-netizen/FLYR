import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import vm from 'node:vm';
import ts from 'typescript';
import { NextRequest, NextResponse } from 'next/server';

const require = createRequire(import.meta.url);

function harness(options: { failSend?: boolean; unauthorized?: boolean; dnc?: boolean } = {}) {
  const sends: any[] = [];
  const updates: any[] = [];
  const existing = { id: 'lead-1', workspace_id: 'workspace-1', name: 'Solar Team', email: 'old@example.com', sales_contact_id: null, lead_state: options.dnc ? 'dnc' : 'queued' };
  let patch = {};
  const query: any = {
    select: () => query, eq: () => query, or: () => query,
    maybeSingle: async () => ({ data: existing, error: null }),
    update: (value: any) => { patch = value; updates.push(value); return query; },
    single: async () => ({ data: { ...existing, ...patch }, error: null }),
  };
  const context = {
    admin: { from: () => query }, workspaceId: 'workspace-1', requestUser: { id: 'rep-1', email: 'login@example.com' },
    salesperson: { id: 'salesperson-1', full_name: 'Alex Sales', demo_email_handle: 'alex', demo_email_reply_to: 'reply@example.com' },
  };
  const overrides: Record<string, any> = {
    '@/lib/dialer/server': { getDialerRequestContext: async () => options.unauthorized ? NextResponse.json({ error: 'Unauthorized' }, { status: 401 }) : context },
    '@/lib/sales-leads/master-list': {},
    '@/lib/sales-pro/communications': { sendManagedEmail: async (input: any) => { sends.push(input); if (options.failSend) throw new Error('provider failure'); } },
    '@/lib/email/demo': { SALES_DEMO_URL: 'https://wolfgrid.app/demo100' },
    '@/lib/dialer/demo-email-handle': { DEMO_EMAIL_DOMAIN: 'wolfgrid.app', DEMO_EMAIL_HANDLE_PATTERN: /^[a-z]+$/, normalizeDemoEmailHandle: (value: string) => value },
  };
  const source = readFileSync(new URL('../../../app/api/dialer/leads/route.ts', import.meta.url), 'utf8');
  const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
  const module = { exports: {} as any };
  vm.runInNewContext(compiled, { exports: module.exports, module, require: (id: string) => overrides[id] ?? require(id), console: { error() {}, warn() {} } });
  const call = (body: Record<string, unknown>) => module.exports.PATCH(new NextRequest('https://sales.wolfgrid.app/api/dialer/leads', { method: 'PATCH', body: JSON.stringify({ id: 'lead-1', workspaceId: 'workspace-1', ...body }) }));
  return { sends, updates, call };
}

test('save and send uses the saved recipient and authenticated salesperson signature', async () => {
  const h = harness();
  const response = await h.call({ email: ' Buyer@Example.com ', sendDemoEmail: true });
  assert.equal(response.status, 200);
  assert.equal((await response.json()).demoEmailSent, true);
  assert.equal(h.sends.length, 1);
  assert.equal(h.sends[0].to, 'buyer@example.com');
  assert.equal(h.sends[0].demo.senderName, 'Alex Sales');
  assert.equal(h.sends[0].demo.senderAddress, 'alex@wolfgrid.app');
  assert.equal(h.sends[0].demo.replyTo, 'reply@example.com');
  assert.ok(h.sends[0].body.includes('https://wolfgrid.app/demo100'));
});

test('ordinary save does not send an email', async () => {
  const h = harness();
  assert.equal((await h.call({ email: 'buyer@example.com' })).status, 200);
  assert.equal(h.sends.length, 0);
});

test('invalid recipients and unauthorized requests do not send or mutate leads', async () => {
  for (const [h, email] of [[harness(), 'invalid'], [harness({ unauthorized: true }), 'buyer@example.com'], [harness({ dnc: true }), 'buyer@example.com']] as const) {
    const response = await h.call({ email, sendDemoEmail: true });
    assert.ok([400, 401].includes(response.status));
    assert.equal(h.sends.length, 0);
    assert.equal(h.updates.length, 0);
  }
});

test('provider failure never reports a successful demo send', async () => {
  const h = harness({ failSend: true });
  const response = await h.call({ email: 'buyer@example.com', sendDemoEmail: true });
  const body = await response.json();
  assert.equal(response.status, 502);
  assert.equal(body.demoEmailSent, false);
  assert.equal(body.lead.email, 'buyer@example.com');
  assert.ok(body.error.includes('Contact saved'));
});
