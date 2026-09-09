import assert from 'node:assert/strict';
import test from 'node:test';
import { publishLinkedIn } from '../publisher';

const originalFetch = global.fetch;

function personConnection() {
  return {
    id: 'connection-1', platform: 'linkedin' as const, external_account_id: 'member-123',
    access_token_encrypted: 'unused-in-unit-test', scopes: ['openid', 'profile', 'email', 'w_member_social'],
    metadata: { accountType: 'person', authorUrn: 'urn:li:person:member-123' },
  };
}

function post(assets: Array<{ id: string; mime_type: string; byte_size: number; position: number }> = []) {
  return { id: 'post-1', caption: 'WolfSocial LinkedIn test', title: 'Test image', content_type: 'feed', settings: { visibility: 'PUBLIC' }, assets, targets: [] };
}

test.afterEach(() => { global.fetch = originalFetch; });

test('publishes a personal text post with w_member_social', async () => {
  const requests: Array<{ url: string; body?: string }> = [];
  global.fetch = async (input, init) => {
    requests.push({ url: String(input), body: init?.body as string | undefined });
    return new Response('', { status: 201, headers: { 'x-restli-id': 'urn:li:share:text-1' } });
  };
  const result = await publishLinkedIn(post() as never, personConnection(), 'member-token');
  assert.equal(result.externalPostId, 'urn:li:share:text-1');
  assert.equal(requests.length, 1);
  const body = JSON.parse(requests[0].body || '{}');
  assert.equal(body.author, 'urn:li:person:member-123');
  assert.equal(body.commentary, 'WolfSocial LinkedIn test');
  assert.equal(body.content, undefined);
});

test('registers, uploads, and attaches one personal image', async () => {
  process.env.SOCIAL_MEDIA_URL_SECRET = 'linkedin-test-media-secret';
  const requests: Array<{ url: string; body?: string }> = [];
  global.fetch = async (input, init) => {
    const url = String(input); requests.push({ url, body: init?.body as string | undefined });
    if (url.includes('images?action=initializeUpload')) return Response.json({ value: { uploadUrl: 'https://upload.linkedin.test/image-1', image: 'urn:li:image:image-1' } });
    if (url.includes('/api/social/media/image-1/source')) return new Response(new Uint8Array([1, 2, 3]), { status: 200 });
    if (url === 'https://upload.linkedin.test/image-1') return new Response('', { status: 201 });
    return new Response('', { status: 201, headers: { 'x-restli-id': 'urn:li:share:image-post' } });
  };
  await publishLinkedIn(post([{ id: 'image-1', mime_type: 'image/jpeg', byte_size: 3, position: 0 }]) as never, personConnection(), 'member-token');
  const publishBody = JSON.parse(requests.at(-1)?.body || '{}');
  assert.deepEqual(publishBody.content.media, { id: 'urn:li:image:image-1', title: 'Test image' });
});

test('registers, uploads, and attaches multiple personal images', async () => {
  process.env.SOCIAL_MEDIA_URL_SECRET = 'linkedin-test-media-secret';
  let imageNumber = 0;
  const requests: Array<{ url: string; body?: string }> = [];
  global.fetch = async (input, init) => {
    const url = String(input); requests.push({ url, body: init?.body as string | undefined });
    if (url.includes('images?action=initializeUpload')) {
      imageNumber += 1;
      return Response.json({ value: { uploadUrl: `https://upload.linkedin.test/image-${imageNumber}`, image: `urn:li:image:image-${imageNumber}` } });
    }
    if (url.includes('/api/social/media/')) return new Response(new Uint8Array([1, 2, 3]), { status: 200 });
    if (url.startsWith('https://upload.linkedin.test/')) return new Response('', { status: 201 });
    return new Response('', { status: 201, headers: { 'x-restli-id': 'urn:li:share:multi-image-post' } });
  };
  await publishLinkedIn(post([
    { id: 'asset-a', mime_type: 'image/jpeg', byte_size: 3, position: 0 },
    { id: 'asset-b', mime_type: 'image/png', byte_size: 3, position: 1 },
  ]) as never, personConnection(), 'member-token');
  const publishBody = JSON.parse(requests.at(-1)?.body || '{}');
  assert.deepEqual(publishBody.content.multiImage.images.map((image: { id: string }) => image.id), ['urn:li:image:image-1', 'urn:li:image:image-2']);
});

test('uploads and publishes a single-part personal video', async () => {
  process.env.SOCIAL_MEDIA_URL_SECRET = 'linkedin-test-media-secret';
  const requests: Array<{ url: string; body?: string; range?: string | null }> = [];
  global.fetch = async (input, init) => {
    const url = String(input);
    const headers = new Headers(init?.headers);
    requests.push({ url, body: init?.body as string | undefined, range: headers.get('range') });
    if (url.endsWith('/rest/videos?action=initializeUpload')) return Response.json({ value: { video: 'urn:li:video:video-1', uploadToken: 'upload-token', uploadInstructions: [{ uploadUrl: 'https://upload.linkedin.test/video-1', firstByte: 0, lastByte: 2 }] } });
    if (url.includes('/api/social/media/video-1/source')) return new Response(new Uint8Array([1, 2, 3]), { status: 206 });
    if (url === 'https://upload.linkedin.test/video-1') return new Response('', { status: 200, headers: { etag: 'part-1' } });
    if (url.endsWith('/rest/videos?action=finalizeUpload')) return new Response('', { status: 200 });
    if (url.includes('/rest/videos/urn%3Ali%3Avideo%3Avideo-1')) return Response.json({ status: 'AVAILABLE' });
    return new Response('', { status: 201, headers: { 'x-restli-id': 'urn:li:share:video-post' } });
  };
  await publishLinkedIn(post([{ id: 'video-1', mime_type: 'video/mp4', byte_size: 3, position: 0 }]) as never, personConnection(), 'member-token');
  assert.equal(requests.find((request) => request.url.includes('/api/social/media/video-1/source'))?.range, 'bytes=0-2');
  const publishBody = JSON.parse(requests.at(-1)?.body || '{}');
  assert.deepEqual(publishBody.content.media, { id: 'urn:li:video:video-1', title: 'Test image' });
});

test('uploads every instructed video part and finalizes with ordered ETags', async () => {
  process.env.SOCIAL_MEDIA_URL_SECRET = 'linkedin-test-media-secret';
  const ranges: string[] = [];
  let finalizeBody = '';
  global.fetch = async (input, init) => {
    const url = String(input);
    if (url.endsWith('/rest/videos?action=initializeUpload')) return Response.json({ value: { video: 'urn:li:video:video-2', uploadToken: 'upload-token-2', uploadInstructions: [
      { uploadUrl: 'https://upload.linkedin.test/video-2/part-1', firstByte: 0, lastByte: 1 },
      { uploadUrl: 'https://upload.linkedin.test/video-2/part-2', firstByte: 2, lastByte: 3 },
    ] } });
    if (url.includes('/api/social/media/video-2/source')) {
      ranges.push(new Headers(init?.headers).get('range') || '');
      return new Response(new Uint8Array([1, 2]), { status: 206 });
    }
    if (url.includes('/part-1')) return new Response('', { status: 200, headers: { etag: 'etag-part-1' } });
    if (url.includes('/part-2')) return new Response('', { status: 200, headers: { etag: 'etag-part-2' } });
    if (url.endsWith('/rest/videos?action=finalizeUpload')) { finalizeBody = init?.body as string; return new Response('', { status: 200 }); }
    if (url.includes('/rest/videos/urn%3Ali%3Avideo%3Avideo-2')) return Response.json({ status: 'AVAILABLE' });
    return new Response('', { status: 201, headers: { 'x-restli-id': 'urn:li:share:multipart-video-post' } });
  };
  await publishLinkedIn(post([{ id: 'video-2', mime_type: 'video/mp4', byte_size: 4, position: 0 }]) as never, personConnection(), 'member-token');
  assert.deepEqual(ranges, ['bytes=0-1', 'bytes=2-3']);
  assert.deepEqual(JSON.parse(finalizeBody).finalizeUploadRequest.uploadedPartIds, ['etag-part-1', 'etag-part-2']);
});
