import { createHash, randomBytes } from 'crypto';
import { NextRequest, NextResponse } from 'next/server';
import { requireSocialUser } from '@/lib/social/auth';
import { isSocialPlatform, linkedinOAuthScopes, metaApiVersion, oauthCallbackUrl, platformCredentials, PLATFORM_SCOPES, socialOrigin, type SocialPlatform } from '@/lib/social/platforms';

function stateHash(value: string) {
  return createHash('sha256').update(value).digest('hex');
}

function authorizeUrl(platform: SocialPlatform, requestUrl: string, state: string) {
  const credentials = platformCredentials(platform);
  if (!credentials.clientId || !credentials.clientSecret) throw new Error(`${platform}_not_configured`);
  const callback = oauthCallbackUrl(platform, requestUrl);
  let authorize: URL;
  if (platform === 'facebook') {
    authorize = new URL(`https://www.facebook.com/${metaApiVersion()}/dialog/oauth`);
  } else if (platform === 'instagram') {
    authorize = new URL('https://www.instagram.com/oauth/authorize');
    authorize.searchParams.set('enable_fb_login', '0');
    authorize.searchParams.set('force_authentication', '1');
  } else if (platform === 'tiktok') {
    authorize = new URL('https://www.tiktok.com/v2/auth/authorize/');
    authorize.searchParams.set('client_key', credentials.clientId);
    authorize.searchParams.set('disable_auto_auth', '1');
  } else if (platform === 'linkedin') {
    authorize = new URL('https://www.linkedin.com/oauth/v2/authorization');
  } else {
    authorize = new URL('https://accounts.google.com/o/oauth2/v2/auth');
    authorize.searchParams.set('access_type', 'offline');
    authorize.searchParams.set('prompt', 'consent select_account');
  }
  if (platform !== 'tiktok') authorize.searchParams.set('client_id', credentials.clientId);
  authorize.searchParams.set('redirect_uri', callback);
  authorize.searchParams.set('response_type', 'code');
  const scopes = platform === 'linkedin' ? linkedinOAuthScopes() : PLATFORM_SCOPES[platform];
  authorize.searchParams.set('scope', scopes.join(
    platform === 'instagram' || platform === 'tiktok' ? ',' : ' ',
  ));
  authorize.searchParams.set('state', state);
  return authorize;
}

async function begin(request: NextRequest, platform: SocialPlatform, surface: 'standalone' | 'sales_web' | 'sales_ios') {
  const context = await requireSocialUser(request);
  if (!context) return { error: 'Unauthorized', status: 401 as const };
  const state = randomBytes(32).toString('base64url');
  const returnTo = surface === 'sales_ios'
    ? 'wolfgridsales://social/oauth-complete'
    : surface === 'standalone'
      ? `${socialOrigin(request.url)}/app?section=connections`
      : `${(process.env.NEXT_PUBLIC_SALES_APP_URL || new URL(request.url).origin).replace(/\/$/, '')}/social?section=connections`;
  const { error } = await context.admin.from('social_oauth_states').insert({
    state_hash: stateHash(state),
    social_workspace_id: context.socialWorkspaceId,
    user_id: context.user.id,
    platform,
    initiating_surface: surface,
    return_to: returnTo,
    expires_at: new Date(Date.now() + 10 * 60_000).toISOString(),
  });
  if (error) return { error: error.message, status: 500 as const };
  try {
    return { authorize: authorizeUrl(platform, request.url, state), state };
  } catch (error) {
    return { error: error instanceof Error ? error.message : 'Provider not configured', status: 503 as const };
  }
}

export async function GET(request: NextRequest, { params }: { params: Promise<{ platform: string }> }) {
  const { platform: rawPlatform } = await params;
  if (!isSocialPlatform(rawPlatform)) return NextResponse.json({ error: 'Unsupported platform' }, { status: 404 });
  const surface = request.nextUrl.searchParams.get('surface') === 'standalone' ? 'standalone' : 'sales_web';
  const result = await begin(request, rawPlatform, surface);
  if ('error' in result) {
    if (result.status === 401) return NextResponse.redirect(new URL('/login', socialOrigin(request.url)));
    return NextResponse.redirect(new URL(`/social?error=${encodeURIComponent(result.error)}`, request.url));
  }
  return NextResponse.redirect(result.authorize);
}

// Native iOS first requests an authorize URL with its Supabase bearer token.
export async function POST(request: NextRequest, { params }: { params: Promise<{ platform: string }> }) {
  const { platform: rawPlatform } = await params;
  if (!isSocialPlatform(rawPlatform)) return NextResponse.json({ error: 'Unsupported platform' }, { status: 404 });
  const result = await begin(request, rawPlatform, 'sales_ios');
  if ('error' in result) return NextResponse.json({ error: result.error }, { status: result.status });
  return NextResponse.json({ authorizeUrl: result.authorize.toString(), callbackScheme: 'wolfgridsales' });
}
