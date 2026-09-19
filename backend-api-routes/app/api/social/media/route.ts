import { randomUUID } from 'crypto';
import { NextRequest, NextResponse } from 'next/server';
import { requireSocialUser } from '@/lib/social/auth';
import { createSocialMediaUrl } from '@/lib/social/media-url';
import { socialOrigin } from '@/lib/social/platforms';

const ALLOWED = new Set(['image/jpeg', 'image/png', 'image/webp', 'video/mp4', 'video/quicktime', 'video/webm']);
const MAX_BYTES = 4 * 1024 * 1024 * 1024;

export const runtime = 'nodejs';
export const maxDuration = 300;

export async function GET(request: NextRequest) {
  const context = await requireSocialUser(request);
  if (!context) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const { data, error } = await context.admin.from('social_media_assets').select('id,original_name,mime_type,byte_size,width,height,duration_seconds,created_at').eq('social_workspace_id', context.socialWorkspaceId).order('created_at', { ascending: false }).limit(200);
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  const origin = socialOrigin(request.url);
  return NextResponse.json({ assets: (data ?? []).map((asset) => ({ ...asset, preview_url: createSocialMediaUrl(asset.id, origin) })) });
}

export async function POST(request: NextRequest) {
  const context = await requireSocialUser(request);
  if (!context) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const form = await request.formData();
  const file = form.get('file');
  if (!(file instanceof File)) return NextResponse.json({ error: 'A media file is required' }, { status: 400 });
  if (!ALLOWED.has(file.type)) return NextResponse.json({ error: 'Unsupported media type' }, { status: 415 });
  if (file.size <= 0 || file.size > MAX_BYTES) return NextResponse.json({ error: 'Media must be smaller than 4 GB' }, { status: 413 });
  const extension = file.name.includes('.') ? file.name.split('.').pop()?.replace(/[^a-z0-9]/gi, '').toLowerCase() : 'bin';
  const path = `${context.user.id}/${new Date().toISOString().slice(0, 10)}/${randomUUID()}.${extension || 'bin'}`;
  const { error: uploadError } = await context.admin.storage.from('social-media').upload(path, file, { contentType: file.type, upsert: false });
  if (uploadError) return NextResponse.json({ error: uploadError.message }, { status: 500 });
  const { data, error } = await context.admin.from('social_media_assets').insert({ social_workspace_id: context.socialWorkspaceId, user_id: context.user.id, storage_path: path, mime_type: file.type, byte_size: file.size, original_name: file.name }).select('id,original_name,mime_type,byte_size,created_at').single();
  if (error) {
    await context.admin.storage.from('social-media').remove([path]);
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
  return NextResponse.json({ asset: { ...data, preview_url: createSocialMediaUrl(data.id, socialOrigin(request.url)) } }, { status: 201 });
}
