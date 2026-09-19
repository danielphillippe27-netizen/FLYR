import { randomUUID } from 'crypto';
import { NextRequest, NextResponse } from 'next/server';
import { requireSocialUser } from '@/lib/social/auth';

const ALLOWED = new Set(['image/jpeg', 'image/png', 'image/webp', 'video/mp4', 'video/quicktime', 'video/webm']);
const MAX_BYTES = 4 * 1024 * 1024 * 1024;

export async function POST(request: NextRequest) {
  const context = await requireSocialUser(request);
  if (!context) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const body = await request.json().catch(() => ({}));
  const mimeType = String(body.mimeType || '');
  const byteSize = Number(body.byteSize || 0);
  const originalName = String(body.fileName || 'media').slice(0, 255);
  if (!ALLOWED.has(mimeType)) return NextResponse.json({ error: 'Unsupported media type' }, { status: 415 });
  if (!Number.isFinite(byteSize) || byteSize <= 0 || byteSize > MAX_BYTES) return NextResponse.json({ error: 'Media must be smaller than 4 GB' }, { status: 413 });
  const extension = originalName.includes('.') ? originalName.split('.').pop()?.replace(/[^a-z0-9]/gi, '').toLowerCase() : 'bin';
  const storagePath = `${context.user.id}/${new Date().toISOString().slice(0, 10)}/${randomUUID()}.${extension || 'bin'}`;
  const { data, error } = await context.admin.storage.from('social-media').createSignedUploadUrl(storagePath);
  if (error || !data) return NextResponse.json({ error: error?.message || 'Could not create upload URL' }, { status: 500 });
  return NextResponse.json({ upload: { signedUrl: data.signedUrl, token: data.token, storagePath, mimeType, byteSize, originalName } });
}

