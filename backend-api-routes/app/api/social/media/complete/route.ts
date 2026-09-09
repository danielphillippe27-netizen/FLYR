import { NextRequest, NextResponse } from 'next/server';
import { requireSocialUser } from '@/lib/social/auth';
import { createSocialMediaUrl } from '@/lib/social/media-url';
import { socialOrigin } from '@/lib/social/platforms';

export async function POST(request: NextRequest) {
  const context = await requireSocialUser(request);
  if (!context) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const body = await request.json().catch(() => ({}));
  const storagePath = String(body.storagePath || '');
  if (!storagePath.startsWith(`${context.user.id}/`) || !body.mimeType || !Number(body.byteSize)) return NextResponse.json({ error: 'Invalid upload receipt' }, { status: 400 });
  const { data: signed } = await context.admin.storage.from('social-media').createSignedUrl(storagePath, 60);
  if (!signed?.signedUrl) return NextResponse.json({ error: 'Uploaded media was not found' }, { status: 404 });
  const probe = await fetch(signed.signedUrl, { headers: { Range: 'bytes=0-0' } });
  if (!probe.ok) return NextResponse.json({ error: 'Uploaded media was not found' }, { status: 404 });
  const durationSeconds = Number(body.durationSeconds);
  const { data, error } = await context.admin.from('social_media_assets').insert({ social_workspace_id: context.socialWorkspaceId, user_id: context.user.id, storage_path: storagePath, mime_type: String(body.mimeType), byte_size: Number(body.byteSize), original_name: String(body.originalName || 'media').slice(0, 255), duration_seconds: Number.isFinite(durationSeconds) && durationSeconds > 0 ? durationSeconds : null }).select('id,original_name,mime_type,byte_size,duration_seconds,created_at').single();
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ asset: { ...data, preview_url: createSocialMediaUrl(data.id, socialOrigin(request.url)) } }, { status: 201 });
}
