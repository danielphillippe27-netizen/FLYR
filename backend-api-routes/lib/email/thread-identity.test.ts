import assert from 'node:assert/strict';
import test from 'node:test';
import { counterpartyEmail, replyEmailForEvents } from './thread-identity';

test('uses the recipient as the identity for an outbound email', () => {
  assert.equal(counterpartyEmail({
    direction: 'outbound',
    fromEmail: 'daniel@wolfgrid.app',
    toEmail: 'santanawelsh00@hotmail.com',
  }), 'santanawelsh00@hotmail.com');
});

test('uses the sender as the identity for an inbound email', () => {
  assert.equal(counterpartyEmail({
    direction: 'inbound',
    fromEmail: 'santanawelsh00@hotmail.com',
    toEmail: 'daniel@wolfgrid.app',
  }), 'santanawelsh00@hotmail.com');
});

test('never falls back to our address when an outbound recipient is missing', () => {
  assert.equal(counterpartyEmail({
    direction: 'outbound',
    fromEmail: 'daniel@wolfgrid.app',
    toEmail: null,
  }), null);
});

test('finds the newest usable counterparty across a thread', () => {
  assert.equal(replyEmailForEvents([
    { direction: 'inbound', fromEmail: 'old@example.com', toEmail: 'daniel@wolfgrid.app' },
    { direction: 'outbound', fromEmail: 'daniel@wolfgrid.app', toEmail: 'new@example.com' },
  ]), 'new@example.com');
});
