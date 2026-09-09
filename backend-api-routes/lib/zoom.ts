import { createHmac, randomBytes, timingSafeEqual } from 'crypto';

export type ZoomOAuthPlatform = 'ios' | 'web';

type ZoomState = {
  userId: string;
  platform: ZoomOAuthPlatform;
  nonce: string;
  issuedAt: number;
};

type ZoomTokenResponse = {
  access_token?: string;
  refresh_token?: string;
  expires_in?: number;
};

export type ZoomMeeting = {
  id: number;
  uuid?: string;
  topic: string;
  start_time?: string;
  duration?: number;
  join_url: string;
};

const authorizeEndpoint = 'https://zoom.us/oauth/authorize';
const tokenEndpoint = 'https://zoom.us/oauth/token';
const apiBase = 'https://api.zoom.us/v2';
const stateMaxAgeSeconds = 10 * 60;

function config() {
  const clientId = process.env.ZOOM_OAUTH_CLIENT_ID?.trim() ?? '';
  const clientSecret = process.env.ZOOM_OAUTH_CLIENT_SECRET?.trim() ?? '';
  const stateSecret = (
    process.env.OAUTH_STATE_SECRET ??
    process.env.CRM_ENCRYPTION_KEY ??
    process.env.ENCRYPTION_KEY ??
    ''
  ).trim();
  if (!clientId || !clientSecret) throw new Error('Zoom OAuth credentials are not configured.');
  if (!stateSecret) throw new Error('OAUTH_STATE_SECRET is required.');
  return { clientId, clientSecret, stateSecret };
}

function base64Url(value: string | Buffer): string {
  return Buffer.from(value).toString('base64url');
}

function signature(payload: string): string {
  return base64Url(createHmac('sha256', config().stateSecret).update(payload).digest());
}

function redirectUri(origin: string): string {
  return process.env.ZOOM_OAUTH_REDIRECT_URI?.trim() || `${origin}/api/integrations/zoom/oauth/callback`;
}

export function createZoomState(userId: string, platform: ZoomOAuthPlatform): string {
  const payload = base64Url(JSON.stringify({
    userId,
    platform,
    nonce: base64Url(randomBytes(18)),
    issuedAt: Math.floor(Date.now() / 1000),
  } satisfies ZoomState));
  return `${payload}.${signature(payload)}`;
}

export function parseZoomState(raw: string): ZoomState | null {
  try {
    const [payload, suppliedSignature] = raw.split('.');
    if (!payload || !suppliedSignature) return null;
    const expected = Buffer.from(signature(payload));
    const supplied = Buffer.from(suppliedSignature);
    if (expected.length !== supplied.length || !timingSafeEqual(expected, supplied)) return null;
    const state = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')) as ZoomState;
    const age = Math.floor(Date.now() / 1000) - state.issuedAt;
    if (!state.userId || !['ios', 'web'].includes(state.platform) || age < 0 || age > stateMaxAgeSeconds) return null;
    return state;
  } catch {
    return null;
  }
}

export function zoomAuthorizeUrl(origin: string, state: string): string {
  const { clientId } = config();
  const params = new URLSearchParams({
    response_type: 'code',
    client_id: clientId,
    redirect_uri: redirectUri(origin),
    state,
  });
  return `${authorizeEndpoint}?${params.toString()}`;
}

async function tokenRequest(params: URLSearchParams) {
  const { clientId, clientSecret } = config();
  const response = await fetch(tokenEndpoint, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${Buffer.from(`${clientId}:${clientSecret}`).toString('base64')}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: params.toString(),
    cache: 'no-store',
  });
  const raw = await response.text();
  if (!response.ok) throw new Error(zoomError(raw, `Zoom token request failed (${response.status}).`));
  const result = JSON.parse(raw) as ZoomTokenResponse;
  if (!result.access_token || !result.refresh_token || !result.expires_in) {
    throw new Error('Zoom returned an incomplete token response.');
  }
  return {
    accessToken: result.access_token,
    refreshToken: result.refresh_token,
    expiresAt: Math.floor(Date.now() / 1000) + result.expires_in,
  };
}

export function exchangeZoomCode(code: string, origin: string) {
  return tokenRequest(new URLSearchParams({
    grant_type: 'authorization_code',
    code,
    redirect_uri: redirectUri(origin),
  }));
}

export function refreshZoomToken(refreshToken: string) {
  return tokenRequest(new URLSearchParams({
    grant_type: 'refresh_token',
    refresh_token: refreshToken,
  }));
}

async function zoomJson<T>(path: string, accessToken: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${apiBase}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
      ...init?.headers,
    },
    cache: 'no-store',
  });
  const raw = await response.text();
  if (!response.ok) throw new Error(zoomError(raw, `Zoom request failed (${response.status}).`));
  return raw ? JSON.parse(raw) as T : {} as T;
}

function zoomError(raw: string, fallback: string): string {
  try {
    const parsed = JSON.parse(raw) as { message?: string; reason?: string };
    return parsed.message || parsed.reason || fallback;
  } catch {
    return raw.trim() || fallback;
  }
}

export function getZoomUser(accessToken: string) {
  return zoomJson<{ id: string; email?: string; first_name?: string; last_name?: string }>('/users/me', accessToken);
}

export function createZoomMeeting(accessToken: string, input: {
  topic: string;
  startAt: string;
  durationMinutes: number;
  agenda?: string | null;
}) {
  return zoomJson<ZoomMeeting>('/users/me/meetings', accessToken, {
    method: 'POST',
    body: JSON.stringify({
      topic: input.topic,
      type: 2,
      start_time: input.startAt,
      duration: input.durationMinutes,
      timezone: 'UTC',
      agenda: input.agenda || undefined,
      settings: {
        join_before_host: false,
        waiting_room: true,
        mute_upon_entry: true,
        approval_type: 2,
      },
    }),
  });
}

export async function deleteZoomMeeting(accessToken: string, meetingId: string): Promise<void> {
  await zoomJson(`/meetings/${encodeURIComponent(meetingId)}`, accessToken, { method: 'DELETE' });
}

export async function zoomAccessTokenForUser(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  admin: any,
  userId: string
): Promise<string | null> {
  const { data } = await admin
    .from('zoom_connections')
    .select('access_token,refresh_token,expires_at')
    .eq('user_id', userId)
    .maybeSingle();
  if (!data?.access_token || !data?.refresh_token) return null;
  const expiresAt = Number(data.expires_at);
  if (Number.isFinite(expiresAt) && expiresAt > Math.floor(Date.now() / 1000) + 90) {
    return String(data.access_token);
  }
  const refreshed = await refreshZoomToken(String(data.refresh_token));
  const { error } = await admin.from('zoom_connections').update({
    access_token: refreshed.accessToken,
    refresh_token: refreshed.refreshToken,
    expires_at: refreshed.expiresAt,
    updated_at: new Date().toISOString(),
  }).eq('user_id', userId);
  if (error) throw new Error('Could not save the refreshed Zoom connection.');
  return refreshed.accessToken;
}

export function zoomOAuthResultUrl(platform: ZoomOAuthPlatform, status: 'success' | 'error', message?: string) {
  if (platform === 'ios') {
    const params = new URLSearchParams({ provider: 'zoom', status });
    if (message) params.set('message', message);
    return `wolfgridsales://oauth?${params.toString()}`;
  }
  const params = new URLSearchParams({ zoom: status === 'success' ? 'connected' : 'error' });
  if (message) params.set('message', message);
  return `/meetings?${params.toString()}`;
}
