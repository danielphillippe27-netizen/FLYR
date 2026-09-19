import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import vm from 'node:vm';
import ts from 'typescript';
import { NextRequest, NextResponse } from 'next/server';

const require = createRequire(import.meta.url);
function harness(options: { status?: number; unauthorized?: boolean; retention?: string } = {}) {
  const requests: Headers[] = [];
  const query = {
    select: () => query, eq: () => query,
    maybeSingle: async () => ({ data: { telecom_provider: 'telnyx', created_at: '2026-09-08T12:00:00Z' }, error: null }),
  };
  const overrides = {
    '@/lib/dialer/server': { getDialerRequestContext: async () => options.unauthorized
      ? NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
      : { workspaceId: 'workspace-1', requestUser: { id: 'user-1' }, admin: { from: () => query } } },
    '@/lib/dialer/env': {},
    '@/lib/dialer/recordings': {
      dialerCallContentRetention: () => options.retention ?? 'saved',
      getDialerCallRecording: () => ({ mp3Url: 'https://media.example/recording.mp3', recordingSid: 'recording-1' }),
    },
    '@/lib/dialer/telnyx': {
      getTelnyxCallRecording: async () => ({ mp3Url: 'https://media.example/fresh.mp3' }),
    },
  };
  const source = readFileSync(new URL('../../../app/api/dialer/calls/[callId]/recording/route.ts', import.meta.url), 'utf8');
  const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
  const module = { exports: {} as { GET: (request: NextRequest, context: unknown) => Promise<NextResponse> } };
  vm.runInNewContext(compiled, {
    exports: module.exports, module, require: (id: string) => overrides[id] ?? require(id),
    console, Headers, Buffer,
    fetch: async (_url: string, init: RequestInit) => {
      requests.push(new Headers(init.headers));
      const status = options.status ?? 206;
      return new Response(status === 416 ? null : 'audio', { status, headers: {
        'content-type': 'audio/mpeg', 'accept-ranges': 'bytes',
        ...(status === 206 ? { 'content-range': 'bytes 0-4/100', 'content-length': '5' } : {}),
        ...(status === 416 ? { 'content-range': 'bytes */100' } : {}),
      } });
    },
  });
  return {
    requests,
    call: (playback = true) => module.exports.GET(new NextRequest(
      `https://sales.wolfgrid.app/api/dialer/calls/call-1/recording?workspaceId=workspace-1${playback ? '&playback=1' : ''}`,
      { headers: { Range: 'bytes=0-4' } },
    ), { params: Promise.resolve({ callId: 'call-1' }) }),
  };
}

test('playback streams partial audio inline and preserves seeking headers', async () => {
  const h = harness();
  const response = await h.call();
  assert.equal(h.requests[0].get('range'), 'bytes=0-4');
  assert.equal(response.status, 206);
  assert.equal(response.headers.get('content-range'), 'bytes 0-4/100');
  assert.equal(response.headers.get('content-length'), '5');
  assert.equal(response.headers.get('accept-ranges'), 'bytes');
  assert.match(response.headers.get('content-disposition')!, /^inline;/);
  assert.equal(await response.text(), 'audio');
});

test('MP3 downloads remain attachments and providers may return the whole file', async () => {
  const response = await harness({ status: 200 }).call(false);
  assert.equal(response.status, 200);
  assert.match(response.headers.get('content-disposition')!, /^attachment;/);
  assert.equal(response.headers.get('content-range'), null);
});

test('unsatisfiable ranges preserve the provider response', async () => {
  const response = await harness({ status: 416 }).call();
  assert.equal(response.status, 416);
  assert.equal(response.headers.get('content-range'), 'bytes */100');
});

test('unauthorized and discarded recordings never fetch audio', async () => {
  for (const options of [{ unauthorized: true }, { retention: 'discard' }]) {
    const h = harness(options);
    assert.ok([401, 404].includes((await h.call()).status));
    assert.equal(h.requests.length, 0);
  }
});
