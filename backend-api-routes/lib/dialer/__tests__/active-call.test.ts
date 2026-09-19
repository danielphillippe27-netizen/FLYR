import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import vm from 'node:vm';
import ts from 'typescript';
import { NextRequest } from 'next/server';
import * as contract from '../active-call';

const require = createRequire(import.meta.url);
const workspaceId = 'a0000000-0000-4000-8000-000000000001';
const iosId = '20000000-0000-4000-8000-000000000001';
const webId = '30000000-0000-4000-8000-000000000001';
const snapshot = { id: 'native-call', name: 'Jamie Example', phone: '+14165550123', phase: 'connecting', startedAt: '2026-09-09T15:00:00Z', connectedAt: null };

function harness(options: { unauthorized?: boolean; denied?: boolean; fail?: boolean } = {}) {
  let rows: Record<string, any>[] = [];
  let userId = 'user-a';
  let mutations = 0;
  const admin = {
    from(table: string) {
      assert.equal(table, 'dialer_active_devices');
      let mode = 'select';
      let value: Record<string, any>;
      const filters: ((row: Record<string, any>) => boolean)[] = [];
      const query = {
        select: () => query,
        delete: () => { mode = 'delete'; return query; },
        upsert: (row: Record<string, any>) => { mode = 'upsert'; value = row; return query; },
        match: (scope: Record<string, any>) => { filters.push(row => Object.entries(scope).every(([key, val]) => row[key] === val)); return query; },
        neq: (key: string, val: string) => { filters.push(row => row[key] !== val); return query; },
        gt: (key: string, val: string) => { filters.push(row => row[key] > val); return query; },
        lte: (key: string, val: string) => { filters.push(row => row[key] <= val); return query; },
        order: () => query,
        then(resolve: (value: unknown) => void) {
          if (options.fail) return resolve({ error: { code: 'unavailable' }, data: null });
          const matches = (row: Record<string, any>) => filters.every(filter => filter(row));
          if (mode === 'upsert') {
            mutations++;
            rows = rows.filter(row => !['workspace_id', 'user_id', 'device_id'].every(key => row[key] === value[key]));
            rows.push(value);
          } else if (mode === 'delete') {
            mutations++;
            rows = rows.filter(row => !matches(row));
          }
          resolve({ data: rows.filter(matches), error: null });
        },
      };
      return query;
    },
  };
  const overrides: Record<string, unknown> = {
    '@/app/api/_utils/request-user': { resolveUserFromRequest: async () => options.unauthorized ? null : { id: userId } },
    '@/app/api/_utils/workspace': { resolveWorkspaceMembershipForUser: async (_db: unknown, _user: string, requested: string) => ({ workspaceId: options.denied ? null : requested.toLowerCase() }) },
    '@/lib/supabase/server': { createAdminClient: () => admin },
    '@/lib/dialer/active-call': contract,
  };
  const source = readFileSync(new URL('../../../app/api/dialer/active-call/route.ts', import.meta.url), 'utf8');
  const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
  const module = { exports: {} as any };
  vm.runInNewContext(compiled, { exports: module.exports, module, require: (id: string) => overrides[id] ?? require(id), console: { error() {} } });
  return {
    call: (body: Record<string, unknown> = {}) => module.exports.PUT(new NextRequest('https://sales.wolfgrid.app/api/dialer/active-call', {
      method: 'PUT', body: JSON.stringify({ workspaceId, deviceId: iosId, platform: 'ios', call: snapshot, ...body }),
    })),
    setUser: (id: string) => { userId = id; },
    expire: () => { rows.forEach(row => { row.expires_at = '2000-01-01T00:00:00Z'; }); },
    get rows() { return rows; },
    get mutations() { return mutations; },
  };
}

test('iOS call appears on web, changes status, and disappears when iOS ends it', async () => {
  const h = harness();
  const first = await h.call();
  assert.equal(first.status, 200);
  assert.equal(first.headers.get('cache-control'), 'private, no-store');
  assert.equal((await first.json()).calls.length, 0); // never echoes this device
  const web = () => h.call({ deviceId: webId, platform: 'web', call: null });
  let call = (await (await web()).json()).calls[0];
  assert.equal(call.name, snapshot.name);
  assert.equal(call.phone, snapshot.phone);
  assert.equal(call.platform, 'ios');
  assert.ok(Date.parse(call.expiresAt) > Date.now() + 80_000);
  await h.call({ call: { ...snapshot, phase: 'connected', connectedAt: snapshot.startedAt } });
  call = (await (await web()).json()).calls[0];
  assert.equal(call.phase, 'connected');
  assert.equal(call.connectedAt, snapshot.startedAt);
  await h.call({ call: null });
  assert.equal((await (await web()).json()).calls.length, 0);
});

test('web calls appear on iOS and an idle device cannot delete another device call', async () => {
  const h = harness();
  await h.call({ deviceId: webId, platform: 'web' });
  const response = await h.call({ call: null });
  assert.equal((await response.json()).calls[0].platform, 'web');
  assert.equal(h.rows.length, 1);
});

test('native uppercase workspace UUIDs resolve to the same workspace as web', async () => {
  const h = harness();
  assert.equal((await h.call({ workspaceId: workspaceId.toUpperCase() })).status, 200);
  const response = await h.call({ deviceId: webId, platform: 'web', call: null });
  assert.equal((await response.json()).calls[0].name, snapshot.name);
});

test('users and workspaces are isolated even with the same device id', async () => {
  const h = harness();
  await h.call();
  h.setUser('user-b');
  assert.equal((await (await h.call({ call: null })).json()).calls.length, 0);
  assert.equal(h.rows.length, 1);
  h.setUser('user-a');
  const otherWorkspace = '40000000-0000-4000-8000-000000000001';
  assert.equal((await (await h.call({ workspaceId: otherWorkspace, call: null })).json()).calls.length, 0);
  assert.equal(h.rows.length, 1);
});

test('expired calls disappear after a device disconnects without a hangup', async () => {
  const h = harness();
  await h.call();
  h.expire();
  assert.equal((await (await h.call({ deviceId: webId, call: null })).json()).calls.length, 0);
  assert.equal(h.rows.length, 0);
});

test('invalid requests and unauthorized users never mutate presence', async () => {
  for (const [options, body, status] of [
    [{ unauthorized: true }, {}, 401], [{ denied: true }, {}, 403],
    [{}, { call: { ...snapshot, phase: 'ended' } }, 400],
    [{}, { deviceId: 'invalid' }, 400],
    [{}, { call: { ...snapshot, name: 'x'.repeat(301) } }, 400],
  ] as const) {
    const h = harness(options);
    assert.equal((await h.call(body)).status, status);
    assert.equal(h.mutations, 0);
  }
});

test('a failed write is not reported as a successful sync', async () => {
  const h = harness({ fail: true });
  assert.equal((await h.call()).status, 503);
});
