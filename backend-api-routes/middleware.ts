import { createServerClient } from '@supabase/ssr';
import { NextRequest, NextResponse } from 'next/server';
import { withSharedWolfGridCookie } from '@/lib/supabase/shared-cookie';

export async function middleware(request: NextRequest) {
  const isWolfSocialHost = request.nextUrl.hostname === 'social.wolfgrid.app' || request.nextUrl.hostname.startsWith('social.');
  const rewriteUrl = request.nextUrl.clone();
  if (isWolfSocialHost && request.nextUrl.pathname === '/') rewriteUrl.pathname = '/wolfsocial';
  if (isWolfSocialHost && (request.nextUrl.pathname === '/app' || request.nextUrl.pathname.startsWith('/app/'))) rewriteUrl.pathname = '/wolfsocial/app';
  const response = rewriteUrl.pathname === request.nextUrl.pathname
    ? NextResponse.next({ request })
    : NextResponse.rewrite(rewriteUrl, { request });
  response.headers.set('x-wolfsocial-host', isWolfSocialHost ? '1' : '0');
  if (request.nextUrl.pathname === '/login') return response;

  // Native clients authenticate API requests with a Bearer token. API routes
  // validate that token through resolveUserFromRequest, so attempting an
  // additional cookie-based auth refresh here only adds a redundant network
  // round-trip (and can leave every iOS request waiting when Auth is slow).
  if (request.headers.get('authorization')?.startsWith('Bearer ')) {
    return response;
  }

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
  if (!url || !key) return response;
  const supabase = createServerClient(url, key, {
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll(cookiesToSet) {
        cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
        cookiesToSet.forEach(({ name, value, options }) => response.cookies.set(name, value, withSharedWolfGridCookie(request.nextUrl.hostname, options)));
      },
    },
  });
  await supabase.auth.getUser();
  return response;
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|robots.txt|sitemap.xml|.*\\.[a-zA-Z0-9]+$).*)'],
};
