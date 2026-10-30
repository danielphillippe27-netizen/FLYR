import assert from 'node:assert/strict';
import test from 'node:test';
import { unmatchedDialerMessages } from './inbox-message-identity';

const canonical = { channel: 'sms', provider: 'telnyx', provider_event_id: 'message-1' };
const legacy = { id: 'log-1', provider: 'telnyx', provider_message_id: 'message-1', body: 'Hey' };

test('one SMS stored in communications and dialler history appears once', () => {
  assert.deepEqual(unmatchedDialerMessages([legacy], [canonical]), []);
});

test('separate sends with identical text remain separate messages', () => {
  const second = { ...legacy, id: 'log-2', provider_message_id: 'message-2' };
  assert.deepEqual(unmatchedDialerMessages([legacy, second], [canonical]), [second]);
});

test('legacy-only messages remain visible when canonical history is unavailable or filtered out', () => {
  assert.deepEqual(unmatchedDialerMessages([legacy], []), [legacy]);
});

test('provider identity is namespaced and only SMS records suppress dialler messages', () => {
  assert.deepEqual(unmatchedDialerMessages([legacy], [{ ...canonical, provider: 'other' }]), [legacy]);
  assert.deepEqual(unmatchedDialerMessages([legacy], [{ ...canonical, channel: 'email' }]), [legacy]);
});

test('missing message identities never hide messages by guessing from body or timestamp', () => {
  const missingId = { ...legacy, provider_message_id: null };
  const missingProvider = { ...legacy, provider: '' };
  assert.deepEqual(unmatchedDialerMessages([missingId, missingProvider], [canonical]), [missingId, missingProvider]);
  assert.deepEqual(unmatchedDialerMessages([legacy], [{ ...canonical, provider_event_id: null }]), [legacy]);
});

test('normalizes provider names without changing case-sensitive provider message IDs', () => {
  assert.deepEqual(unmatchedDialerMessages([legacy], [{ ...canonical, provider: ' TELNYX ' }]), []);
  assert.deepEqual(unmatchedDialerMessages([legacy], [{ ...canonical, provider_event_id: 'MESSAGE-1' }]), [legacy]);
});

test('inbound and outbound mirrored SMS and media messages use provider identity', () => {
  for (const direction of ['inbound', 'outbound']) {
    const message = { ...legacy, direction, body: '', media: [{ url: 'https://example.com/photo.jpg' }] };
    assert.deepEqual(unmatchedDialerMessages([message], [canonical]), []);
  }
});
