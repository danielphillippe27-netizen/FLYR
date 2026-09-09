import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { decryptSocialToken, encryptSocialToken } from '../crypto';
import { isLinkedInPagePostingRole, linkedinOAuthScopes, PLATFORM_SCOPES, SOCIAL_PLATFORMS, isSocialPlatform } from '../platforms';
import { FACEBOOK_PAGE_WEBHOOK_FIELDS, facebookPageHasPostingAccess, INSTAGRAM_WEBHOOK_FIELDS, isExpiredProviderAuthorization } from '../meta';
import { validateSocialTarget } from '../post-validation';

test('WolfSocial accepts only supported provider identifiers', () => {
  assert.deepEqual(SOCIAL_PLATFORMS, ['facebook', 'instagram', 'tiktok', 'youtube', 'linkedin']);
  for (const platform of SOCIAL_PLATFORMS) assert.equal(isSocialPlatform(platform), true);
  assert.equal(isSocialPlatform('instagram-personal'), false);
  assert.equal(isSocialPlatform('youtube-dm'), false);
});

test('TikTok requests only the scopes demonstrated by the direct-post review flow', () => {
  assert.deepEqual(PLATFORM_SCOPES.tiktok, ['user.info.basic', 'video.publish']);
  assert.equal(PLATFORM_SCOPES.tiktok.includes('video.upload'), false);
  assert.equal(PLATFORM_SCOPES.facebook.includes('pages_manage_metadata'), true);
});

test('LinkedIn keeps Company Page permissions behind the approval flag', () => {
  const previous = process.env.LINKEDIN_ORGANIZATION_SCOPES;
  process.env.LINKEDIN_ORGANIZATION_SCOPES = 'false';
  assert.deepEqual(linkedinOAuthScopes(), ['openid', 'profile', 'email', 'w_member_social']);
  process.env.LINKEDIN_ORGANIZATION_SCOPES = 'true';
  assert.deepEqual(linkedinOAuthScopes(), [
    'openid', 'profile', 'email', 'w_member_social',
    'rw_organization_admin', 'r_organization_social', 'w_organization_social',
  ]);
  assert.equal(isLinkedInPagePostingRole('ADMINISTRATOR'), true);
  assert.equal(isLinkedInPagePostingRole('CONTENT_ADMIN'), true);
  assert.equal(isLinkedInPagePostingRole('RECRUITING_POSTER'), false);
  if (previous === undefined) delete process.env.LINKEDIN_ORGANIZATION_SCOPES;
  else process.env.LINKEDIN_ORGANIZATION_SCOPES = previous;
});

test('TikTok uploads video bytes directly without requiring URL ownership verification', () => {
  const publisher = readFileSync(new URL('../publisher.ts', import.meta.url), 'utf8');
  assert.match(publisher, /source: 'FILE_UPLOAD', video_size:/);
  assert.match(publisher, /'Content-Range': `bytes/);
  assert.doesNotMatch(publisher, /source: 'PULL_FROM_URL', video_url:/);
});

test('Meta publishing uses the platform-specific production flows', () => {
  const publisher = readFileSync(new URL('../publisher.ts', import.meta.url), 'utf8');
  const callback = readFileSync(new URL('../../../app/api/social/oauth/[platform]/callback/route.ts', import.meta.url), 'utf8');
  const webhook = readFileSync(new URL('../../../app/api/social/webhooks/meta/route.ts', import.meta.url), 'utf8');
  const reply = readFileSync(new URL('../../../app/api/social/inbox/[threadId]/reply/route.ts', import.meta.url), 'utf8');
  assert.match(publisher, /waitForInstagramContainer/);
  assert.match(publisher, /const container = await instagramRequest[\s\S]*await waitForInstagramContainer\(creationId, token\)/);
  assert.match(publisher, /video_reels/);
  assert.match(publisher, /facebook\.com\/reel\/\$\{initialized\.video_id\}`.*, processing: true/);
  assert.match(publisher, /attached_media\[\$\{index\}\]/);
  assert.match(callback, /grant_type', 'fb_exchange_token'/);
  assert.match(callback, /subscribed_apps/);
  assert.match(webhook, /recipientId: event\.senderId/);
  assert.match(webhook, /event\.message\.is_echo === true/);
  assert.match(reply, /thread\.platform === 'instagram' \? 'graph\.instagram\.com' : 'graph\.facebook\.com'/);
  assert.match(reply, /socialAccessToken/);
});

test('Facebook saves only Pages where the user can post', () => {
  assert.equal(facebookPageHasPostingAccess({ id: '1', access_token: 'token', tasks: ['CREATE_CONTENT'] }), true);
  assert.equal(facebookPageHasPostingAccess({ id: '2', access_token: 'token', tasks: ['MANAGE'] }), true);
  assert.equal(facebookPageHasPostingAccess({ id: '2b', access_token: 'token', tasks: ['PROFILE_PLUS_CREATE_CONTENT'] }), true);
  assert.equal(facebookPageHasPostingAccess({ id: '2c', access_token: 'token', tasks: ['PROFILE_PLUS_FULL_CONTROL'] }), true);
  assert.equal(facebookPageHasPostingAccess({ id: '3', access_token: 'token', tasks: ['ANALYZE', 'MESSAGING', 'MODERATE'] }), false);
  assert.equal(facebookPageHasPostingAccess({ id: '4', tasks: ['CREATE_CONTENT'] }), false);
});

test('Meta webhook subscriptions cover Page feed/comments, Page messaging, and Instagram events', () => {
  assert.deepEqual(FACEBOOK_PAGE_WEBHOOK_FIELDS, ['feed', 'messages', 'messaging_postbacks']);
  assert.deepEqual(INSTAGRAM_WEBHOOK_FIELDS, ['comments', 'messages']);
});

test('expired Meta authorization errors trigger reconnect handling', () => {
  assert.equal(isExpiredProviderAuthorization(new Error('Error validating access token: Session has expired')), true);
  assert.equal(isExpiredProviderAuthorization(new Error('Instagram authorization expired')), true);
  assert.equal(isExpiredProviderAuthorization({ error: { code: 190, error_subcode: 463, message: 'Expired' } }), true);
  assert.equal(isExpiredProviderAuthorization(new Error('Media container is still processing')), false);
});

test('social sync waits for Facebook video processing', () => {
  const sync = readFileSync(new URL('../../../app/api/cron/social-sync/route.ts', import.meta.url), 'utf8');
  assert.match(sync, /async function syncFacebook/);
  assert.match(sync, /url\.searchParams\.set\('fields', 'status'\)/);
  assert.match(sync, /\['facebook', 'tiktok', 'youtube'\]/);
  assert.match(sync, /target\.platform === 'facebook'/);
});

test('provider tokens round-trip through authenticated encryption', () => {
  process.env.SOCIAL_TOKEN_ENCRYPTION_KEY = 'test-only-wolfsocial-key';
  const token = 'provider-token-with-sensitive-content';
  const encrypted = encryptSocialToken(token);
  assert.notEqual(encrypted, token);
  assert.equal(decryptSocialToken(encrypted), token);
  const parts = encrypted.split('.');
  parts[2] = `${parts[2].startsWith('A') ? 'B' : 'A'}${parts[2].slice(1)}`;
  assert.throws(() => decryptSocialToken(parts.join('.')));
});

test('target validation accepts only media combinations the publisher supports', () => {
  const video = [{ mime_type: 'video/mp4', byte_size: 100 }];
  const image = [{ mime_type: 'image/jpeg', byte_size: 100 }];

  assert.equal(validateSocialTarget({ platform: 'youtube', title: 'A short', settings: { madeForKids: false } }, video, 'publish'), null);
  assert.equal(validateSocialTarget({ platform: 'youtube', title: 'x'.repeat(101), settings: { madeForKids: false } }, video, 'publish'), 'YouTube titles must be 100 characters or less');
  assert.equal(validateSocialTarget({ platform: 'youtube', title: 'A short', settings: {} }, video, 'publish'), 'Choose whether the YouTube video is made for kids');
  assert.equal(validateSocialTarget({ platform: 'youtube', title: 'A short', settings: { madeForKids: false } }, image, 'publish'), 'YouTube Shorts requires exactly one video');
  assert.equal(validateSocialTarget({ platform: 'instagram', format: 'carousel' }, image, 'publish'), 'Instagram carousels require at least two media items');
  assert.equal(validateSocialTarget({ platform: 'instagram', format: 'feed' }, image, 'publish'), null);
  assert.equal(validateSocialTarget({ platform: 'instagram', format: 'carousel' }, [...image, ...image], 'publish'), null);
  assert.equal(validateSocialTarget({ platform: 'instagram', format: 'reel' }, video, 'publish'), null);
  assert.equal(validateSocialTarget({ platform: 'instagram', format: 'story' }, image, 'publish'), null);
  assert.equal(validateSocialTarget({ platform: 'linkedin' }, [], 'publish'), null);
  assert.equal(validateSocialTarget({ platform: 'linkedin' }, video, 'publish'), null);
  assert.equal(validateSocialTarget({ platform: 'linkedin' }, [...image, ...video], 'publish'), 'LinkedIn posts cannot mix images and video');
  assert.equal(validateSocialTarget({ platform: 'linkedin' }, [...video, ...video], 'publish'), 'LinkedIn supports one video per post');
  assert.equal(validateSocialTarget({ platform: 'linkedin', caption: 'x'.repeat(3001) }, [], 'publish'), 'LinkedIn posts must be 3,000 characters or less');
  assert.equal(validateSocialTarget({ platform: 'facebook' }, [], 'publish'), null);
  assert.equal(validateSocialTarget({ platform: 'facebook', format: 'story' }, image, 'publish'), 'Facebook Stories are not supported by the WolfSocial Page publishing connection');
  assert.equal(validateSocialTarget({ platform: 'facebook' }, Array.from({ length: 11 }, () => image[0]), 'publish'), 'Facebook supports at most ten images in one WolfSocial post');
  assert.equal(validateSocialTarget({ platform: 'tiktok' }, [...image, ...video], 'draft'), 'TikTok posts cannot mix photos and video');
});

test('TikTok approval fields are enforced only when leaving draft state', () => {
  const video = [{ mime_type: 'video/mp4', byte_size: 100 }];
  assert.equal(validateSocialTarget({ platform: 'tiktok', settings: {} }, video, 'draft'), null);
  assert.equal(validateSocialTarget({ platform: 'tiktok', settings: {} }, video, 'publish'), 'Choose TikTok privacy before publishing');
  assert.equal(validateSocialTarget({ platform: 'tiktok', settings: { privacyLevel: 'SELF_ONLY', musicUsageConfirmed: true, explicitConsent: true } }, video, 'publish'), null);
  assert.equal(validateSocialTarget({ platform: 'tiktok', settings: { privacyLevel: 'PUBLIC_TO_EVERYONE', musicUsageConfirmed: true, explicitConsent: true, commercialContent: true } }, video, 'publish'), 'Choose whether TikTok commercial content promotes your brand, another brand, or both');
  assert.equal(validateSocialTarget({ platform: 'tiktok', settings: { privacyLevel: 'SELF_ONLY', musicUsageConfirmed: true, explicitConsent: true, commercialContent: true, brandContent: true } }, video, 'publish'), 'TikTok branded content visibility cannot be private');
  assert.equal(validateSocialTarget({ platform: 'tiktok', settings: { privacyLevel: 'MUTUAL_FOLLOW_FRIENDS', musicUsageConfirmed: true, explicitConsent: true, commercialContent: true, brandContent: true } }, video, 'publish'), null);
});
