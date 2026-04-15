import { refreshFubAccessToken } from "./fub-oauth";

type FubIntegrationRow = {
  access_token: string | null;
  refresh_token: string | null;
  expires_at: number | null;
};

type FubAuth =
  | {
      mode: "apiKey";
      headers: Record<string, string>;
    }
  | {
      mode: "oauth";
      headers: Record<string, string>;
      expiresAt: number | null;
    };

const X_SYSTEM = "FLYR";
const X_SYSTEM_KEY =
  process.env.FUB_SYSTEM_KEY?.trim() ||
  process.env.X_SYSTEM_KEY?.trim() ||
  null;

function basicAuthHeaders(apiKey: string): Record<string, string> {
  const basicAuth = Buffer.from(`${apiKey}:`).toString("base64");
  return {
    Authorization: `Basic ${basicAuth}`,
    "X-System": X_SYSTEM,
    ...(X_SYSTEM_KEY ? { "X-System-Key": X_SYSTEM_KEY } : {}),
  };
}

function bearerAuthHeaders(accessToken: string): Record<string, string> {
  return {
    Authorization: `Bearer ${accessToken}`,
    "X-System": X_SYSTEM,
    ...(X_SYSTEM_KEY ? { "X-System-Key": X_SYSTEM_KEY } : {}),
  };
}

async function getEncryptedApiKeyForUser(
  supabaseAdmin: any,
  userId: string
): Promise<string | null> {
  const { getFubApiKeyForUser } = await import("./crm-auth");
  return getFubApiKeyForUser(supabaseAdmin, userId);
}

async function getOauthIntegration(
  supabaseAdmin: any,
  userId: string
): Promise<FubIntegrationRow | null> {
  const { data } = await supabaseAdmin
    .from("user_integrations")
    .select("access_token, refresh_token, expires_at")
    .eq("user_id", userId)
    .eq("provider", "fub")
    .maybeSingle();

  if (!data) {
    return null;
  }

  return data as FubIntegrationRow;
}

/** OAuth Bearer auth with refresh when needed. Caller must ensure access_token is non-empty. */
async function fubAuthFromOAuth(
  supabaseAdmin: any,
  userId: string,
  integration: FubIntegrationRow
): Promise<FubAuth> {
  const accessToken = integration.access_token!.trim();
  const now = Math.floor(Date.now() / 1000);
  const shouldRefresh = integration.expires_at != null && integration.expires_at <= now + 60;

  if (!shouldRefresh) {
    return {
      mode: "oauth",
      headers: bearerAuthHeaders(accessToken),
      expiresAt: integration.expires_at,
    };
  }

  if (!integration.refresh_token) {
    return {
      mode: "oauth",
      headers: bearerAuthHeaders(accessToken),
      expiresAt: integration.expires_at,
    };
  }

  const refreshed = await refreshFubAccessToken(integration.refresh_token);

  await supabaseAdmin
    .from("user_integrations")
    .update({
      access_token: refreshed.accessToken,
      refresh_token: refreshed.refreshToken ?? integration.refresh_token,
      expires_at: refreshed.expiresAt ?? null,
      updated_at: new Date().toISOString(),
    })
    .eq("user_id", userId)
    .eq("provider", "fub");

  return {
    mode: "oauth",
    headers: bearerAuthHeaders(refreshed.accessToken),
    expiresAt: refreshed.expiresAt ?? null,
  };
}

export async function getFubAuthForUser(
  supabaseAdmin: any,
  userId: string
): Promise<FubAuth | null> {
  // Prefer OAuth (Bearer) when connected via Follow Up Boss OAuth so a stale
  // encrypted API key in crm_connection_secrets cannot override valid tokens.
  const integration = await getOauthIntegration(supabaseAdmin, userId);
  if (integration?.access_token?.trim()) {
    return fubAuthFromOAuth(supabaseAdmin, userId, integration);
  }

  const apiKey = await getEncryptedApiKeyForUser(supabaseAdmin, userId);
  if (apiKey) {
    return {
      mode: "apiKey",
      headers: basicAuthHeaders(apiKey),
    };
  }

  return null;
}
