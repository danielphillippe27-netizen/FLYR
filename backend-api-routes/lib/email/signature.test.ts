import assert from 'node:assert/strict';
import test from 'node:test';
import { brandedEmailContent } from './signature';
import { demoEmailContent } from './demo';

test('adds Daniel Phillippe signature and linked brand icons for Daniel mail', () => {
  const content = brandedEmailContent('Hello <friend>\nHow are you?', 'daniel@wolfgrid.app');

  assert.match(content.text, /Daniel Phillippe\nFounder · WolfGrid\nwolfgrid\.app \| daniel@wolfgrid\.app/);
  assert.match(content.html, /Hello &lt;friend&gt;<br>How are you\?/);
  assert.match(content.html, /bgcolor="#ef2b2d"/);
  assert.match(content.html, /href="mailto:daniel@wolfgrid\.app"/);
  assert.doesNotMatch(content.html, /border-top/);
  assert.match(content.html, /favicons\?domain=instagram\.com&amp;sz=64/);
  assert.match(content.html, /href="https:\/\/www\.youtube\.com\/"/);
  assert.match(content.html, /width="18" height="18"/);
});

test('does not add Daniel signature to another sender', () => {
  const content = brandedEmailContent('Hello', 'rep@example.com');

  assert.equal(content.text, 'Hello');
  assert.doesNotMatch(content.html, /Daniel Phillippe/);
});


test('Christian mail uses Christian Phillippe, Head of Sales, with his own email', () => {
  for (const address of ['christian@wolfgrid.app', 'Christian Phillippe <CHRISTIAN@WOLFGRID.APP>']) {
    const content = brandedEmailContent('Here is your demo.', address);
    assert.match(content.text, /Christian Phillippe\nHead of Sales · WolfGrid\nwolfgrid\.app \| christian@wolfgrid\.app/);
    assert.match(content.html, />Christian Phillippe<\/div>/);
    assert.match(content.html, /Head of Sales/);
    assert.match(content.html, /href="mailto:christian@wolfgrid\.app"/);
    assert.doesNotMatch(content.html, /Daniel Phillippe|Founder|daniel@wolfgrid/);
  }
});

test('Christian demo emails use his own name and Head of Sales title', () => {
  const content = demoEmailContent({ senderName: 'Daniel Phillippe', senderEmail: 'christian@wolfgrid.app' });
  assert.match(content.text, /Christian Phillippe\nHead of Sales · WolfGrid/);
  assert.match(content.html, /Christian Phillippe/);
  assert.match(content.html, /Head of Sales/);
  assert.doesNotMatch(content.html, /Daniel Phillippe|Founder/);
});
