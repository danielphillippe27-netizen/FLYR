// Isolated live integration check. Creates no emails and always removes its fixtures.
import { createRequire } from 'node:module';
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import assert from 'node:assert/strict';
const web = '/Volumes/Samsung SSD/WolfGrid/Wolfgrid-WEB';
const require = createRequire(web + '/package.json');
const { createClient } = require('@supabase/supabase-js');
const env = require('dotenv').parse(readFileSync(web + '/.env.local'));
const url = env.NEXT_PUBLIC_SUPABASE_URL;
assert.equal(new URL(url).hostname, 'kfnsnwqylsdsbgnwgxva.supabase.co');
const admin = createClient(url, env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
const base = process.argv[2] ?? 'https://wolfgrid.app';
const staged = new URL(base).hostname.endsWith('.vercel.app');
const temp = mkdtempSync(join(tmpdir(), 'map-edit-live-'));
const users = []; let campaign; let workspace; const checks = [];
function ok(data, error) { if (error) throw new Error(error.message); return data; }
async function identity() {
  const email = `map-edit-${randomUUID()}@example.invalid`; const password = randomUUID() + randomUUID();
  const created = await admin.auth.admin.createUser({ email, password, email_confirm: true });
  const user = ok(created.data, created.error).user; users.push(user.id);
  const client = createClient(url, env.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
  const signed = await client.auth.signInWithPassword({ email, password });
  return { id: user.id, token: ok(signed.data, signed.error).session.access_token, client };
}
async function request(method, token, body) {
  const path = `/api/campaigns/${campaign}/map-edits`;
  if (!staged) {
    const response = await fetch(base + path, { method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, ...(body ? { body: JSON.stringify(body) } : {}) });
    return { status: response.status, data: await response.json() };
  }
  const config = join(temp, 'curl.conf'); const payload = join(temp, 'body.json');
  writeFileSync(config, `${token ? 'header = "Authorization: Bearer ' + token + '"\n' : ''}header = "Content-Type: application/json"\n`, { mode: 0o600 });
  const args = ['curl', path, '--deployment', base, '--', '--silent', '--show-error', '--config', config, '--request', method, '--write-out', '\n%{http_code}'];
  if (body) { writeFileSync(payload, JSON.stringify(body), { mode: 0o600 }); args.push('--data-binary', '@' + payload); }
  const raw = execFileSync('vercel', args, { cwd: web, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 60000 }).trim();
  const lines = raw.split('\n'); const status = Number(lines.pop());
  try { return { status, data: JSON.parse(lines.join('\n')) }; } catch { throw new Error(`Expected API JSON, received status ${status}`); }
}
function passed(name) { checks.push(name); console.log('PASS', name); }
try {
  const owner = await identity(); const other = await identity();
  const ws = await admin.from('workspaces').insert({ name: 'Temporary map edit verification', owner_id: owner.id }).select('id').single();
  workspace = ok(ws.data, ws.error).id;
  const c = await admin.from('campaigns').insert({ owner_id: owner.id, workspace_id: workspace, title: 'Temporary map edit verification', name: 'Temporary map edit verification', description: 'Isolated automated fixture; removed after verification.' }).select('id').single();
  campaign = ok(c.data, c.error).id;
  const addr = await admin.from('campaign_addresses').insert({ campaign_id: campaign, formatted: 'Map edit preservation fixture', source: 'manual', visited: true, geom: 'SRID=4326;POINT(-78.7 43.9)' }).select('*').single();
  const original = ok(addr.data, addr.error);
  assert.equal((await request('GET')).status, 401); passed('anonymous denied');
  assert.equal((await request('GET', other.token)).status, 403); passed('outside workspace denied');
  let r = await request('GET', owner.token); assert.equal(r.status, 200); assert.deepEqual(r.data, { revision: 0, features: {} }); passed('owner read');
  const changes = [{ kind: 'address', id: original.id, value: { geometry: { type: 'Point', coordinates: [-78.7001, 43.9001] }, buildingLinkSet: true, buildingId: 'roof', parcelLinkSet: true, parcelId: 'lot' } }, { kind: 'building', id: 'roof', value: { hidden: true } }, { kind: 'parcel', id: 'lot', value: { hidden: true } }];
  const command = { clientMutationId: randomUUID(), baseRevision: 0, changes };
  r = await request('POST', owner.token, command); assert.equal(r.status, 200, JSON.stringify(r.data)); assert.equal(r.data.revision, 1); assert.deepEqual(r.data.features['address:' + original.id], changes[0].value); passed('atomic move, links and multi-select removal persisted');
  r = await request('POST', owner.token, command); assert.equal(r.status, 200); assert.equal(r.data.revision, 1); passed('retry applied once');
  r = await request('POST', owner.token, { ...command, clientMutationId: randomUUID() }); assert.equal(r.status, 409); assert.equal(r.data.revision, 1); passed('stale edit rejected');
  r = await request('POST', owner.token, { clientMutationId: randomUUID(), baseRevision: 1, changes: [{ kind: 'address', id: original.id, value: { geometry: { type: 'Point', coordinates: [999, 43] } } }] }); assert.equal(r.status, 400); passed('invalid geometry rejected');
  const member = await admin.from('workspace_members').upsert({ workspace_id: workspace, user_id: other.id, role: 'member' }, { onConflict: 'workspace_id,user_id' }); ok(member.data, member.error);
  r = await request('GET', other.token); assert.equal(r.status, 200); assert.equal(r.data.revision, 1); passed('teammate receives saved state');
  r = await request('POST', other.token, { clientMutationId: randomUUID(), baseRevision: 1, changes: changes.map(c => ({ ...c, value: null })) }); assert.equal(r.status, 200); assert.equal(r.data.revision, 2); assert.deepEqual(r.data.features, {}); passed('Undo restored original state on server');
  const after = await admin.from('campaign_addresses').select('*').eq('id', original.id).single(); assert.deepEqual(ok(after.data, after.error), original); passed('source address, visited history and metadata unchanged');
  const direct = await owner.client.from('campaign_map_edit_states').select('*').eq('campaign_id', campaign); assert(direct.error); passed('direct client table access denied');
  const rpc = await owner.client.rpc('apply_campaign_map_edits', { p_campaign_id: campaign, p_actor_id: owner.id, p_mutation_id: randomUUID(), p_base_revision: 2, p_changes: changes }); assert(rpc.error); passed('direct client write bypass denied');
  console.log(JSON.stringify({ result: 'PASS', base, checks: checks.length, names: checks }));
} finally {
  if (campaign) { const r = await admin.from('campaigns').delete().eq('id', campaign); ok(r.data, r.error); }
  if (workspace) { const r = await admin.from('workspaces').delete().eq('id', workspace); ok(r.data, r.error); }
  for (const id of users) { const r = await admin.auth.admin.deleteUser(id); ok(r.data, r.error); }
  rmSync(temp, { recursive: true, force: true });
  console.log('Temporary verification accounts and campaign removed.');
}
