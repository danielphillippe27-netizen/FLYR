import { createHmac, randomBytes } from "crypto";

const FUB_OAUTH_CLIENT_ID = process.env.FUB_OAUTH_CLIENT_ID || "";
const FUB_OAUTH_CLIENT_SECRET = process.env.FUB_OAUTH_CLIENT_SECRET || "";
const FUB_OAUTH_SCOPE = process.env.FUB_OAUTH_SCOPE || "";
const FUB_OAUTH_AUTHORIZE_URL =
  process.env.FUB_OAUTH_AUTHORIZE_URL || "https://app.followupboss.com/oauth/authorize";
const FUB_OAUTH_TOKEN_URL =
  process.env.FUB_OAUTH_TOKEN_URL || "https://app.followupboss.com/oauth/token";
const OAUTH_STATE_SECRET = process.env.OAUTH_STATE_SECRET || process.env.CRM_ENCRYPTION_KEY || "";

type OAuthPlatform = "ios" | "web";

type StatePayload = {
  userId: string;
  platform: OAuthPlatform;
  nonce: string;
  iat: number;
};

type TokenExchangePayload = {
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

export function assertOAuthConfig() {
  if (!FUB_OAUTH_CLIENT_ID || !FUB_OAUTH_CLIENT_SECRET) {
    throw new Error("FUB OAuth client credentials are not configured.");
  }
  if (!OAUTH_STATE_SECRET) {
    throw new Error("OAUTH_STATE_SECRET (or CRM_ENCRYPTION_KEY) is required.");
  }
}

export function getFubRedirectUri(origin?: string): string {
  if (process.env.FUB_OAUTH_REDIRECT_URI) {
    return process.env.FUB_OAUTH_REDIRECT_URI;
  }
  const base = origin || process.env.NEXT_PUBLIC_APP_URL || "https://www.flyrpro.app";
  return `${base.replace(/\/$/, "")}/api/integrations/fub/oauth/callback`;
}

export function getWebSuccessUrl(origin?: string): string {
  if (process.env.FUB_OAUTH_WEB_SUCCESS_URL) {
    return process.env.FUB_OAUTH_WEB_SUCCESS_URL;
  }
  const base = origin || process.env.NEXT_PUBLIC_APP_URL || "https://www.flyrpro.app";
  return `${base.replace(/\/$/, "")}/integrations?fub=connected`;
}

export function getWebErrorUrl(origin?: string): string {
  if (process.env.FUB_OAUTH_WEB_ERROR_URL) {
    return process.env.FUB_OAUTH_WEB_ERROR_URL;
  }
  const base = origin || process.env.NEXT_PUBLIC_APP_URL || "https://www.flyrpro.app";
  return `${base.replace(/\/$/, "")}/integrations?fub=error`;
}

export function getIosRedirectUrl(status: "success" | "error", message?: string): string {
  const params = new URLSearchParams({ provider: "fub", status });
  if (message) {
    params.set("message", message);
  }
  return `flyr://oauth?${params.toString()}`;
}

export function createSignedState(userId: string, platform: OAuthPlatform): string {
  assertOAuthConfig();
  const payload: StatePayload = {
    userId,
    platform,
    nonce: base64UrlEncode(randomBytes(12)),
    iat: Math.floor(Date.now() / 1000),
  };
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  return `${encodedPayload}.${signStateValue(encodedPayload)}`;
}

export function parseSignedState(value: string | null | undefined): StatePayload | null {
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
    const payload = JSON.parse(base64UrlDecode(encodedPayload)) as StatePayload;
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

export function buildAuthorizeUrl(state: string, redirectUri: string): string {
  assertOAuthConfig();
  const params = new URLSearchParams({
    response_type: "auth_code",
    client_id: FUB_OAUTH_CLIENT_ID,
    redirect_uri: redirectUri,
    state,
    prompt: "login",
  });

  if (FUB_OAUTH_SCOPE.trim()) {
    params.set("scope", FUB_OAUTH_SCOPE.trim());
  }

  return `${FUB_OAUTH_AUTHORIZE_URL}?${params.toString()}`;
}

function parseTokenExchangeResponse(bodyText: string, context: string): TokenExchangePayload {
  let payload: Record<string, unknown>;
  try {
    payload = JSON.parse(bodyText) as Record<string, unknown>;
  } catch {
    throw new Error(`${context} returned invalid JSON.`);
  }

  const rootAccessToken = typeof payload.access_token === "string" ? payload.access_token : "";
  const legacyData =
    payload.data && typeof payload.data === "object" ? (payload.data as Record<string, unknown>) : null;
  const accessToken =
    rootAccessToken ||
    (legacyData && typeof legacyData.access_token === "string" ? legacyData.access_token : "");

  if (!accessToken) {
    throw new Error(`${context} missing access_token.`);
  }

  const refreshToken =
    typeof payload.refresh_token === "string"
      ? payload.refresh_token
      : legacyData && typeof legacyData.refresh_token === "string"
        ? legacyData.refresh_token
        : undefined;

  const expiresInRaw =
    typeof payload.expires_in === "number" || typeof payload.expires_in === "string"
      ? payload.expires_in
      : legacyData && (typeof legacyData.ttl === "number" || typeof legacyData.ttl === "string")
        ? legacyData.ttl
        : undefined;

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

export async function exchangeCodeForTokens(
  code: string,
  redirectUri: string,
  state: string
): Promise<TokenExchangePayload> {
  assertOAuthConfig();

  const params = new URLSearchParams({
    grant_type: "authorization_code",
    code,
    redirect_uri: redirectUri,
    state,
  });

  const basicAuth = Buffer.from(`${FUB_OAUTH_CLIENT_ID}:${FUB_OAUTH_CLIENT_SECRET}`).toString("base64");
  const response = await fetch(FUB_OAUTH_TOKEN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Authorization: `Basic ${basicAuth}`,
    },
    body: params.toString(),
  });

  const bodyText = await response.text();
  if (!response.ok) {
    throw new Error(bodyText || `Token exchange failed (${response.status})`);
  }

  return parseTokenExchangeResponse(bodyText, "Token exchange");
}

export async function refreshFubAccessToken(refreshToken: string): Promise<TokenExchangePayload> {
  assertOAuthConfig();

  const params = new URLSearchParams({
    grant_type: "refresh_token",
    refresh_token: refreshToken,
  });

  const basicAuth = Buffer.from(`${FUB_OAUTH_CLIENT_ID}:${FUB_OAUTH_CLIENT_SECRET}`).toString("base64");
  const response = await fetch(FUB_OAUTH_TOKEN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Authorization: `Basic ${basicAuth}`,
    },
    body: params.toString(),
  });

  const bodyText = await response.text();
  if (!response.ok) {
    throw new Error(bodyText || `Refresh token exchange failed (${response.status})`);
  }

  return parseTokenExchangeResponse(bodyText, "Refresh token exchange");
}
