import { NextRequest, NextResponse } from 'next/server';
import { createAdminClient } from '@/lib/supabase/server';
import { verifySocialMediaUrl } from '@/lib/social/media-url';

export const runtime = 'nodejs';
export const maxDuration = 300;

export async function GET(request: NextRequest, { params }: { params: Promise<{ assetId: string }> }) {
  const { assetId } = await params;
  if (!verifySocialMediaUrl(assetId, request.nextUrl.searchParams.get('expires'), request.nextUrl.searchParams.get('signature'))) return NextResponse.json({ error: 'Invalid or expired media URL' }, { status: 403 });
  const admin = createAdminClient();
  const { data: asset } = await admin.from('social_media_assets').select('storage_path,mime_type,byte_size,original_name').eq('id', assetId).maybeSingle();
  if (!asset) return NextResponse.json({ error: 'Media not found' }, { status: 404 });
  const { data: signed } = await admin.storage.from('social-media').createSignedUrl(asset.storage_path, 300);
  if (!signed?.signedUrl) return NextResponse.json({ error: 'Media unavailable' }, { status: 500 });
  const range = request.headers.get('range');
  const source = await fetch(signed.signedUrl, { headers: range ? { Range: range } : undefined });
  if (!source.ok || !source.body) return NextResponse.json({ error: 'Media unavailable' }, { status: 502 });
  const headers = new Headers({
    'Content-Type': source.headers.get('content-type') || asset.mime_type,
    'Content-Length': source.headers.get('content-length') || String(asset.byte_size),
    'Content-Disposition': `inline; filename="${String(asset.original_name || 'media').replace(/["\r\n]/g, '')}"`,
    'Cache-Control': 'private, max-age=60',
    'Accept-Ranges': source.headers.get('accept-ranges') || 'bytes',
  });
  const contentRange = source.headers.get('content-range');
  if (contentRange) headers.set('Content-Range', contentRange);
  return new NextResponse(source.body, { status: source.status, headers });
}
