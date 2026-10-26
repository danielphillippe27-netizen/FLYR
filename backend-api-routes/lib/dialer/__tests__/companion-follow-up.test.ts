import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import vm from 'node:vm';
import ts from 'typescript';
import { NextRequest, NextResponse } from 'next/server';

const require = createRequire(import.meta.url);
function harness() {
  const filters: Array<[string, string, unknown]> = [];
  const admin = { from(table: string) {
    const query: any = { select: () => query, update: () => query, order: () => query, limit: () => query,
      eq: (key: string, value: unknown) => { filters.push([table, key, value]); return query; }, is: () => query,
      maybeSingle: async () => ({ data: { id: 'event-1' }, error: null }),
      then: (resolve: any) => resolve({ data: table === 'calendar_events' ? [{ id: 'event-1', title: 'iPhone follow-up', start_at: '2026-10-27T14:00:00Z' }] : [{ id: 'task-1', title: 'Web follow-up', due_at: '2026-10-28T14:00:00Z' }], error: null }),
    }; return query;
  }};
  const dependencies: Record<string, unknown> = {
    '@/lib/sales-pro/context': { requireSalesProContext: async () => ({ admin, userId: 'rep-1', workspaceId: 'workspace-1' }), cleanText: (value: any) => typeof value === 'string' && value.trim() ? value.trim() : null, clampLimit: () => 100 },
    '@/lib/sales-pro/personal-references': {}, '@/lib/sales-pro/automation-trigger': {},
  };
  const module = { exports: {} as any };
  vm.runInNewContext(ts.transpileModule(readFileSync(new URL('../../../app/api/tasks/route.ts', import.meta.url), 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText,
    { exports: module.exports, require: (name: string) => dependencies[name] ?? require(name) });
  return { api: module.exports, filters };
}

test('web follow-up queue includes iPhone and web follow-ups in due-date order', async () => {
  const h = harness();
  const response = await h.api.GET(new NextRequest('https://sales.wolfgrid.app/api/tasks'));
  assert.equal(response.status, 200);
  const tasks = (await response.json()).tasks;
  assert.deepEqual(tasks.map((task: any) => task.id), ['calendar:event-1', 'task-1']);
  assert.ok(h.filters.some(([table, key, value]) => table === 'calendar_events' && key === 'user_id' && value === 'rep-1'));
  assert.ok(h.filters.some(([table, key, value]) => table === 'calendar_events' && key === 'workspace_id' && value === 'workspace-1'));
});

test('completing an iPhone follow-up is scoped to its user and workspace', async () => {
  const h = harness();
  const response = await h.api.PATCH(new NextRequest('https://sales.wolfgrid.app/api/tasks', { method: 'PATCH', body: JSON.stringify({ id: 'calendar:event-1', status: 'completed' }) }));
  assert.equal(response.status, 200);
  for (const [key, value] of [['id', 'event-1'], ['user_id', 'rep-1'], ['workspace_id', 'workspace-1']]) assert.ok(h.filters.some(([table, field, actual]) => table === 'calendar_events' && field === key && actual === value));
});
