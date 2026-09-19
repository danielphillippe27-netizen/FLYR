type CookieOptions = Record<string, unknown>;

export function isWolfGridProductionHost(hostname: string | null | undefined): boolean {
  const host = (hostname || '').split(':')[0].toLowerCase();
  return host === 'wolfgrid.app' || host.endsWith('.wolfgrid.app');
}

export function withSharedWolfGridCookie(hostname: string | null | undefined, options: CookieOptions = {}): CookieOptions {
  if (!isWolfGridProductionHost(hostname)) return options;
  // Sales now uses its own Supabase project. Keep its session host-only so it
  // is never sent to the customer app at wolfgrid.app.
  return { ...options, path: '/', secure: true, sameSite: 'lax' };
}

export function browserSharedCookieOptions(): CookieOptions {
  if (typeof window === 'undefined') return {};
  return withSharedWolfGridCookie(window.location.hostname);
}
