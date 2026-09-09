import assert from 'node:assert/strict';
import test from 'node:test';
import { brandedEmailContent } from './signature';

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
