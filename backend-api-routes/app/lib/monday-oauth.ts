import { createHmac, randomBytes } from "crypto";

const MONDAY_CLIENT_ID = process.env.MONDAY_CLIENT_ID || process.env.MONDAY_OAUTH_CLIENT_ID || "";
const MONDAY_CLIENT_SECRET =
  process.env.MONDAY_CLIENT_SECRET || process.env.MONDAY_OAUTH_CLIENT_SECRET || "";
const MONDAY_OAUTH_SCOPE = process.env.MONDAY_OAUTH_SCOPE || "boards:read boards:write";
const MONDAY_AUTHORIZE_URL =
  process.env.MONDAY_OAUTH_AUTHORIZE_URL || "https://auth.monday.com/oauth2/authorize";
const MONDAY_TOKEN_URL =
  process.env.MONDAY_OAUTH_TOKEN_URL || "https://auth.monday.com/oauth2/token";
const OAUTH_STATE_SECRET = process.env.OAUTH_STATE_SECRET || process.env.CRM_ENCRYPTION_KEY || "";

export type MondayOAuthPlatform = "ios" | "web";

export type MondayStatePayload = {
  userId: string;
  platform: MondayOAuthPlatform;
  workspaceId?: string | null;
  nonce: string;
  iat: number;
};

export type MondayTokenPayload = {
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

export function assertMondayOAuthConfig() {
  if (!MONDAY_CLIENT_ID || !MONDAY_CLIENT_SECRET) {
    throw new Error("Monday.com OAuth client credentials are not configured.");
  }
  if (!OAUTH_STATE_SECRET) {
    throw new Error("OAUTH_STATE_SECRET (or CRM_ENCRYPTION_KEY) is required.");
  }
}

export function getMondayRedirectUri(origin?: string): string {
  const configuredRedirectUri = process.env.MONDAY_OAUTH_REDIRECT_URI || process.env.MONDAY_REDIRECT_URI || "";
  if (/^https?:\/\//i.test(configuredRedirectUri)) {
    return configuredRedirectUri;
  }
  const base = origin || process.env.NEXT_PUBLIC_APP_URL || "https://wolfgrid.app";
  return `${base.replace(/\/$/, "")}/api/integrations/monday/oauth/callback`;
}

export function getMondayWebSuccessUrl(origin?: string): string {
  const base = origin || process.env.NEXT_PUBLIC_APP_URL || "https://wolfgrid.app";
  return `${base.replace(/\/$/, "")}/integrations?monday=connected`;
}

export function getMondayWebErrorUrl(origin?: string): string {
  const base = origin || process.env.NEXT_PUBLIC_APP_URL || "https://wolfgrid.app";
  return `${base.replace(/\/$/, "")}/integrations?monday=error`;
}

export function getMondayIosRedirectUrl(status: "success" | "error", message?: string): string {
  const params = new URLSearchParams({ provider: "monday", status });
  if (message) params.set("message", message);
  return `wolfgrid://oauth?${params.toString()}`;
}

export function createMondaySignedState(
  userId: string,
  platform: MondayOAuthPlatform,
  workspaceId?: string | null
): string {
  assertMondayOAuthConfig();
  const payload: MondayStatePayload = {
    userId,
    platform,
    workspaceId: workspaceId?.trim() || null,
    nonce: base64UrlEncode(randomBytes(12)),
    iat: Math.floor(Date.now() / 1000),
  };
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  return `${encodedPayload}.${signStateValue(encodedPayload)}`;
}

export function parseMondaySignedState(value: string | null | undefined): MondayStatePayload | null {
  if (!value || !OAUTH_STATE_SECRET) return null;

  const [encodedPayload, signature] = value.split(".");
  if (!encodedPayload || !signature) return null;
  if (signStateValue(encodedPayload) !== signature) return null;

  try {
    const payload = JSON.parse(base64UrlDecode(encodedPayload)) as MondayStatePayload;
    const age = Math.floor(Date.now() / 1000) - payload.iat;
    if (!payload.userId || !payload.platform || !payload.iat || age > 600) return null;
    if (payload.platform !== "ios" && payload.platform !== "web") return null;
    return payload;
  } catch {
    return null;
  }
}

export function buildMondayAuthorizeUrl(state: string, redirectUri: string): string {
  assertMondayOAuthConfig();
  const params = new URLSearchParams({
    client_id: MONDAY_CLIENT_ID,
    redirect_uri: redirectUri,
    scope: MONDAY_OAUTH_SCOPE.trim(),
    state,
  });
  return `${MONDAY_AUTHORIZE_URL}?${params.toString()}`;
}

export async function exchangeMondayCodeForTokens(
  code: string,
  redirectUri: string
): Promise<MondayTokenPayload> {
  assertMondayOAuthConfig();

  const params = new URLSearchParams({
    code,
    client_id: MONDAY_CLIENT_ID,
    client_secret: MONDAY_CLIENT_SECRET,
    redirect_uri: redirectUri,
  });

  const response = await fetch(MONDAY_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: params.toString(),
  });

  const bodyText = await response.text();
  if (!response.ok) {
    throw new Error(bodyText || `Monday.com token exchange failed (${response.status})`);
  }

  let data: Record<string, unknown>;
  try {
    data = JSON.parse(bodyText) as Record<string, unknown>;
  } catch {
    throw new Error("Monday.com token exchange returned invalid JSON.");
  }

  const accessToken = typeof data.access_token === "string" ? data.access_token : "";
  if (!accessToken) {
    throw new Error("Monday.com token exchange missing access_token.");
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
