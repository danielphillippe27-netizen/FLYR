import { createHmac, timingSafeEqual } from 'crypto';

function secret(): string {
  const value = process.env.SOCIAL_MEDIA_URL_SECRET || process.env.SOCIAL_TOKEN_ENCRYPTION_KEY || process.env.CRM_ENCRYPTION_KEY;
  if (!value) throw new Error('SOCIAL_MEDIA_URL_SECRET is not configured');
  return value;
}

function signature(assetId: string, expires: number): string {
  return createHmac('sha256', secret()).update(`${assetId}.${expires}`).digest('base64url');
}

export function createSocialMediaUrl(assetId: string, origin: string, lifetimeSeconds = 3600): string {
  const expires = Math.floor(Date.now() / 1000) + lifetimeSeconds;
  const url = new URL(`/api/social/media/${assetId}/source`, origin);
  url.searchParams.set('expires', String(expires));
  url.searchParams.set('signature', signature(assetId, expires));
  return url.toString();
}

export function verifySocialMediaUrl(assetId: string, expiresValue: string | null, signatureValue: string | null): boolean {
  const expires = Number(expiresValue);
  if (!Number.isFinite(expires) || expires < Math.floor(Date.now() / 1000) || !signatureValue) return false;
  const expected = Buffer.from(signature(assetId, expires));
  const actual = Buffer.from(signatureValue);
  return expected.length === actual.length && timingSafeEqual(expected, actual);
}
