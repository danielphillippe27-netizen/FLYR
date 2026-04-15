import { createHmac, randomBytes } from "crypto";

const HUBSPOT_CLIENT_ID = process.env.HUBSPOT_CLIENT_ID || "";
const HUBSPOT_CLIENT_SECRET = process.env.HUBSPOT_CLIENT_SECRET || "";
// Default scopes match HubSpot’s current developer-platform catalog (scope search).
// Granular `crm.objects.notes.write` / tasks / meetings are not listed there; notes & tasks
// still use standard CRM activity APIs and typically work with contacts scopes alone.
const HUBSPOT_OAUTH_SCOPE =
  process.env.HUBSPOT_OAUTH_SCOPE ||
  [
    "oauth",
    "crm.objects.contacts.read",
    "crm.objects.contacts.write",
    "crm.schemas.appointments.read",
    "crm.schemas.appointments.write",
    "crm.objects.appointments.read",
    "crm.objects.appointments.write",
  ].join(" ");
const HUBSPOT_AUTHORIZE_URL =
  process.env.HUBSPOT_OAUTH_AUTHORIZE_URL || "https://app.hubspot.com/oauth/authorize";
const HUBSPOT_TOKEN_URL = process.env.HUBSPOT_OAUTH_TOKEN_URL || "https://api.hubapi.com/oauth/v1/token";
const OAUTH_STATE_SECRET = process.env.OAUTH_STATE_SECRET || process.env.CRM_ENCRYPTION_KEY || "";

export type OAuthPlatform = "ios" | "web";

export type HubSpotStatePayload = {
  userId: string;
  platform: OAuthPlatform;
  workspaceId?: string | null;
  nonce: string;
  iat: number;
};

export type HubSpotTokenPayload = {
  accessToken: string;
  refreshToken?: string;
  expiresAt?: number;
};

function base64UrlEncode(value: Buffer | string): string {
  return Buffer.from(value)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function base64UrlDecode(value: string): string {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const remainder = normalized.length % 4;
  const padded = remainder === 0 ? normalized : normalized + "=".repeat(4 - remainder);
  return Buffer.from(padded, "base64").toString("utf8");
}

function signStateValue(encodedPayload: string): string {
  return base64UrlEncode(createHmac("sha256", OAUTH_STATE_SECRET).update(encodedPayload).digest());
}

export function assertHubSpotOAuthConfig() {
  if (!HUBSPOT_CLIENT_ID || !HUBSPOT_CLIENT_SECRET) {
    throw new Error("HubSpot OAuth client credentials are not configured.");
  }
  if (!OAUTH_STATE_SECRET) {
    throw new Error("OAUTH_STATE_SECRET (or CRM_ENCRYPTION_KEY) is required.");
  }
}

export function getHubSpotRedirectUri(origin?: string): string {
  if (process.env.HUBSPOT_OAUTH_REDIRECT_URI) {
    return process.env.HUBSPOT_OAUTH_REDIRECT_URI;
  }
  const base = origin || process.env.NEXT_PUBLIC_APP_URL || "https://www.flyrpro.app";
  return `${base.replace(/\/$/, "")}/api/integrations/hubspot/oauth/callback`;
}

export function getHubSpotWebSuccessUrl(origin?: string): string {
  if (process.env.HUBSPOT_OAUTH_WEB_SUCCESS_URL) {
    return process.env.HUBSPOT_OAUTH_WEB_SUCCESS_URL;
  }
  const base = origin || process.env.NEXT_PUBLIC_APP_URL || "https://www.flyrpro.app";
  return `${base.replace(/\/$/, "")}/integrations?hubspot=connected`;
}

export function getHubSpotWebErrorUrl(origin?: string): string {
  if (process.env.HUBSPOT_OAUTH_WEB_ERROR_URL) {
    return process.env.HUBSPOT_OAUTH_WEB_ERROR_URL;
  }
  const base = origin || process.env.NEXT_PUBLIC_APP_URL || "https://www.flyrpro.app";
  return `${base.replace(/\/$/, "")}/integrations?hubspot=error`;
}

export function getHubSpotIosRedirectUrl(status: "success" | "error", message?: string): string {
  const params = new URLSearchParams({ provider: "hubspot", status });
  if (message) {
    params.set("message", message);
  }
  return `flyr://oauth?${params.toString()}`;
}

export function createHubSpotSignedState(
  userId: string,
  platform: OAuthPlatform,
  workspaceId?: string | null
): string {
  assertHubSpotOAuthConfig();
  const payload: HubSpotStatePayload = {
    userId,
    platform,
    workspaceId: workspaceId?.trim() || null,
    nonce: base64UrlEncode(randomBytes(12)),
    iat: Math.floor(Date.now() / 1000),
  };
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  return `${encodedPayload}.${signStateValue(encodedPayload)}`;
}

export function parseHubSpotSignedState(value: string | null | undefined): HubSpotStatePayload | null {
  if (!value || !OAUTH_STATE_SECRET) {
    return null;
  }

  const [encodedPayload, signature] = value.split(".");
  if (!encodedPayload || !signature) {
    return null;
  }

  if (signStateValue(encodedPayload) !== signature) {
    return null;
  }

  try {
    const payload = JSON.parse(base64UrlDecode(encodedPayload)) as HubSpotStatePayload;
    const age = Math.floor(Date.now() / 1000) - payload.iat;
    if (!payload.userId || !payload.platform || !payload.iat || age > 600) {
      return null;
    }
    if (payload.platform !== "ios" && payload.platform !== "web") {
      return null;
    }
    return payload;
  } catch {
    return null;
  }
}

export function buildHubSpotAuthorizeUrl(state: string, redirectUri: string): string {
  assertHubSpotOAuthConfig();
  const params = new URLSearchParams({
    client_id: HUBSPOT_CLIENT_ID,
    redirect_uri: redirectUri,
    scope: HUBSPOT_OAUTH_SCOPE.trim(),
    state,
  });
  return `${HUBSPOT_AUTHORIZE_URL}?${params.toString()}`;
}

export async function exchangeHubSpotCodeForTokens(
  code: string,
  redirectUri: string
): Promise<HubSpotTokenPayload> {
  assertHubSpotOAuthConfig();

  const params = new URLSearchParams({
    grant_type: "authorization_code",
    client_id: HUBSPOT_CLIENT_ID,
    client_secret: HUBSPOT_CLIENT_SECRET,
    redirect_uri: redirectUri,
    code,
  });

  const response = await fetch(HUBSPOT_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: params.toString(),
  });

  const bodyText = await response.text();
  if (!response.ok) {
    throw new Error(bodyText || `HubSpot token exchange failed (${response.status})`);
  }

  let data: Record<string, unknown>;
  try {
    data = JSON.parse(bodyText) as Record<string, unknown>;
  } catch {
    throw new Error("HubSpot token exchange returned invalid JSON.");
  }

  const accessToken = typeof data.access_token === "string" ? data.access_token : "";
  if (!accessToken) {
    throw new Error("HubSpot token exchange missing access_token.");
  }

  const refreshToken = typeof data.refresh_token === "string" ? data.refresh_token : undefined;
  const expiresInRaw = data.expires_in;
  const expiresIn =
    typeof expiresInRaw === "number"
      ? expiresInRaw
      : typeof expiresInRaw === "string"
        ? Number.parseInt(expiresInRaw, 10)
        : Number.NaN;

  return {
    accessToken,
    refreshToken,
    expiresAt: Number.isFinite(expiresIn) ? Math.floor(Date.now() / 1000) + expiresIn : undefined,
  };
}

export async function refreshHubSpotAccessToken(refreshToken: string): Promise<HubSpotTokenPayload> {
  assertHubSpotOAuthConfig();

  const params = new URLSearchParams({
    grant_type: "refresh_token",
    client_id: HUBSPOT_CLIENT_ID,
    client_secret: HUBSPOT_CLIENT_SECRET,
    refresh_token: refreshToken,
  });

  const response = await fetch(HUBSPOT_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: params.toString(),
  });

  const bodyText = await response.text();
  if (!response.ok) {
    throw new Error(bodyText || `HubSpot refresh failed (${response.status})`);
  }

  let data: Record<string, unknown>;
  try {
    data = JSON.parse(bodyText) as Record<string, unknown>;
  } catch {
    throw new Error("HubSpot refresh returned invalid JSON.");
  }

  const accessToken = typeof data.access_token === "string" ? data.access_token : "";
  if (!accessToken) {
    throw new Error("HubSpot refresh missing access_token.");
  }

  const nextRefresh =
    typeof data.refresh_token === "string" ? data.refresh_token : refreshToken;
  const expiresInRaw = data.expires_in;
  const expiresIn =
    typeof expiresInRaw === "number"
      ? expiresInRaw
      : typeof expiresInRaw === "string"
        ? Number.parseInt(expiresInRaw, 10)
        : Number.NaN;

  return {
    accessToken,
    refreshToken: nextRefresh,
    expiresAt: Number.isFinite(expiresIn) ? Math.floor(Date.now() / 1000) + expiresIn : undefined,
  };
}
