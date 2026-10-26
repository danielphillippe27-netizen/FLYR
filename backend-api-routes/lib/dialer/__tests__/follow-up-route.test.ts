import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import vm from 'node:vm';
import ts from 'typescript';
import { NextRequest, NextResponse } from 'next/server';

const require = createRequire(import.meta.url);

function harness(options: { failTask?: boolean; unauthorized?: boolean; notFound?: boolean } = {}) {
  const leadUpdates: any[] = [];
  const tasks: any[] = [];
  const filters: any[] = [];
  const existing = { id: 'lead-1', workspace_id: 'workspace-1', name: 'Sam', company: 'Solar Team', notes: 'Call back', sales_contact_id: 'sales-contact-1' };
  let patch = {};
  const leads: any = {
    select: () => leads, eq: () => leads,
    maybeSingle: async () => ({ data: options.notFound ? null : existing, error: null }),
    update: (value: any) => { patch = value; leadUpdates.push(value); return leads; },
    single: async () => ({ data: { ...existing, ...patch }, error: null }),
  };
  const events: any = {
    select: () => events,
    eq: (key: string, value: any) => { filters.push([key, value]); return events; },
    maybeSingle: async () => ({ data: tasks[0] ?? null, error: null }),
    insert: async (value: any) => {
      if (options.failTask) return { error: { message: 'storage failure' } };
      tasks.push({ id: 'event-1', ...value });
      return { error: null };
    },
    update: (value: any) => { Object.assign(tasks[0], value); return events; },
    then: (resolve: any) => resolve({ error: null }),
  };
  const context = {
    admin: { from: (table: string) => table === 'calendar_events' ? events : leads },
    workspaceId: 'workspace-1', requestUser: { id: 'rep-1' }, salesperson: null,
  };
  const overrides: Record<string, any> = {
    '@/lib/dialer/server': { getDialerRequestContext: async () => options.unauthorized ? NextResponse.json({ error: 'Unauthorized' }, { status: 401 }) : context },
    '@/lib/sales-leads/master-list': {},
    '@/lib/sales-leads/google-place-details': {},
    '@/lib/sales-pro/communications': {},
    '@/lib/email/demo': {},
    '@/lib/dialer/demo-email-handle': {},
  };
  const source = readFileSync(new URL('../../../app/api/dialer/leads/route.ts', import.meta.url), 'utf8');
  const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
  const module = { exports: {} as any };
  vm.runInNewContext(compiled, { exports: module.exports, module, require: (id: string) => overrides[id] ?? require(id), console: { error() {}, warn() {} } });
  const call = (body: Record<string, unknown>) => module.exports.PATCH(new NextRequest('https://sales.wolfgrid.app/api/dialer/leads', { method: 'PATCH', body: JSON.stringify({ id: 'lead-1', workspaceId: 'workspace-1', ...body }) }));
  return { leadUpdates, tasks, filters, call };
}

const followUp = { disposition: 'callback', followUpAt: '2026-10-28T14:00:00Z', followUpName: 'Discuss pricing', notes: 'Bring quote', createNotification: true };

test('dialler follow-up creates the calendar task Future reads under the signed-in user', async () => {
  const h = harness();
  assert.equal((await h.call(followUp)).status, 200);
  assert.equal(h.leadUpdates[0].next_follow_up_at, followUp.followUpAt);
  assert.equal(h.tasks.length, 1);
  const task = h.tasks[0];
  assert.equal(task.user_id, 'rep-1');
  assert.equal(task.workspace_id, 'workspace-1');
  assert.equal(task.event_type, 'follow_up');
  assert.equal(task.title, 'Discuss pricing');
  assert.equal(task.start_at, '2026-10-28T14:00:00.000Z');
  assert.equal(task.end_at, '2026-10-28T14:30:00.000Z');
  assert.equal(task.notes, 'Bring quote');
  assert.equal(task.contact_name, 'Sam');
  // Sales contacts belong to a separate table from calendar_events.contact_id.
  assert.equal(task.contact_id, undefined);
  assert.equal(task.deleted_at, null);
});

test('retry and reschedule reuse the same task and restore a completed follow-up', async () => {
  const h = harness();
  await h.call(followUp);
  h.tasks[0].deleted_at = '2026-10-27T12:00:00Z';
  assert.equal((await h.call({ ...followUp, followUpAt: '2026-10-29T15:00:00Z' })).status, 200);
  assert.equal(h.tasks.length, 1);
  assert.equal(h.tasks[0].start_at, '2026-10-29T15:00:00.000Z');
  assert.equal(h.tasks[0].deleted_at, null);
  assert.ok(h.filters.some(([key, value]) => key === 'user_id' && value === 'rep-1'));
  assert.ok(h.filters.some(([key, value]) => key === 'workspace_id' && value === 'workspace-1'));
});

test('task storage failure returns an error instead of success', async () => {
  const h = harness({ failTask: true });
  const response = await h.call(followUp);
  assert.equal(response.status, 502);
  assert.match((await response.json()).error, /follow-up task could not be saved/);
  assert.equal(h.tasks.length, 0);
});

test('invalid follow-up dates cannot mutate the lead or create a task', async () => {
  for (const date of [null, '', 'bad-date']) {
    const h = harness();
    assert.equal((await h.call({ ...followUp, followUpAt: date })).status, 400);
    assert.equal(h.leadUpdates.length, 0);
    assert.equal(h.tasks.length, 0);
  }
});

test('ordinary saves do not create tasks; unauthorized and missing leads do not mutate data', async () => {
  const h = harness();
  assert.equal((await h.call({ notes: 'A note' })).status, 200);
  assert.equal(h.tasks.length, 0);
  for (const options of [{ unauthorized: true }, { notFound: true }]) {
    const denied = harness(options);
    assert.ok([401, 404].includes((await denied.call(followUp)).status));
    assert.equal(denied.leadUpdates.length, 0);
    assert.equal(denied.tasks.length, 0);
  }
});


test('iPhone cannot overwrite notes that changed on the web', async () => {
  const h = harness();
  const response = await h.call({ notes: 'My draft', expectedNotes: 'An older saved note' });
  assert.equal(response.status, 409);
  assert.equal(h.leadUpdates.length, 0);
  assert.match((await response.json()).error, /other screen/);
});
