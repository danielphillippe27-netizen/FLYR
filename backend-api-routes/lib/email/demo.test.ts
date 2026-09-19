import test from 'node:test';
import assert from 'node:assert/strict';
import { demoEmailContent, SALES_DEMO_URL } from './demo';

test('demo button and plain text use demo100, with the sender signature', () => {
  const content = demoEmailContent({ recipientName: 'Sawmills Solar', senderName: 'Daniel Phillippe', senderEmail: 'daniel@wolfgrid.app' });
  assert.match(content.html, /href="https:\/\/wolfgrid.app\/demo100"[^>]*>Watch the demo/);
  assert.ok(content.text.includes(SALES_DEMO_URL));
  assert.ok(content.html.includes('Daniel Phillippe'));
  assert.ok(content.html.includes('mailto:daniel@wolfgrid.app'));
  assert.ok(content.text.includes('Daniel Phillippe\nWolfGrid\ndaniel@wolfgrid.app'));
  assert.ok(!content.html.includes('/demo-1'));
});

test('recipient and sender values cannot inject email HTML', () => {
  const content = demoEmailContent({ recipientName: '<img src=x onerror=alert(1)>', senderName: 'A & B', senderEmail: 'sales@example.com' });
  assert.ok(!content.html.includes('<img'));
  assert.ok(content.html.includes('&lt;img'));
  assert.ok(content.html.includes('A &amp; B'));
});

test('missing profile uses a neutral signature without impersonating Daniel', () => {
  const content = demoEmailContent({ senderEmail: 'alex@example.com' });
  assert.ok(content.text.includes('Hi there,'));
  assert.ok(content.text.includes('WolfGrid Sales'));
  assert.ok(content.html.includes('mailto:alex@example.com'));
  assert.ok(!content.html.includes('Daniel'));
});
