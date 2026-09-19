import { NextRequest, NextResponse } from 'next/server';
import { createAdminClient } from '@/lib/supabase/server';
import {
  exchangeZoomCode,
  getZoomUser,
  parseZoomState,
  zoomOAuthResultUrl,
  type ZoomOAuthPlatform,
} from '@/lib/zoom';

function redirect(request: NextRequest, platform: ZoomOAuthPlatform, status: 'success' | 'error', message?: string) {
  return NextResponse.redirect(new URL(zoomOAuthResultUrl(platform, status, message), request.nextUrl.origin));
}

export async function GET(request: NextRequest) {
  const state = parseZoomState(request.nextUrl.searchParams.get('state') ?? '');
  const platform: ZoomOAuthPlatform = state?.platform ?? 'web';
  const providerError = request.nextUrl.searchParams.get('error_description') || request.nextUrl.searchParams.get('error');
  if (providerError) return redirect(request, platform, 'error', providerError);
  if (!state) return redirect(request, platform, 'error', 'Invalid or expired Zoom authorization.');

  const code = request.nextUrl.searchParams.get('code');
  if (!code) return redirect(request, platform, 'error', 'Zoom did not return an authorization code.');

  try {
    const tokens = await exchangeZoomCode(code, request.nextUrl.origin);
    const zoomUser = await getZoomUser(tokens.accessToken);
    const admin = createAdminClient();
    const { error } = await admin.from('zoom_connections').upsert({
      user_id: state.userId,
      access_token: tokens.accessToken,
      refresh_token: tokens.refreshToken,
      expires_at: tokens.expiresAt,
      zoom_user_id: zoomUser.id,
      zoom_email: zoomUser.email ?? null,
      updated_at: new Date().toISOString(),
    }, { onConflict: 'user_id' });
    if (error) throw new Error('Could not save your Zoom connection.');
    return redirect(request, platform, 'success');
  } catch (error) {
    console.error('[zoom/oauth/callback]', error);
    return redirect(request, platform, 'error', error instanceof Error ? error.message : 'Zoom authorization failed.');
  }
}
