import { createDecipheriv } from "crypto";
import type { SupabaseClient } from "@supabase/supabase-js";
import { refreshOAuthToken } from "./fub-oauth";

const CRM_ENCRYPTION_KEY = process.env.CRM_ENCRYPTION_KEY!;
const FUB_SYSTEM_NAME = process.env.FUB_SYSTEM_NAME || "FLYR";
const FUB_SYSTEM_KEY = process.env.FUB_SYSTEM_KEY;
const OAUTH_EXPIRY_SKEW_SECONDS = 90;

function getEncryptionKey(): Buffer {
  if (!CRM_ENCRYPTION_KEY || CRM_ENCRYPTION_KEY.length < 32) {
    throw new Error("CRM_ENCRYPTION_KEY must be at least 32 chars (hex or raw)");
  }
  const buf = Buffer.from(CRM_ENCRYPTION_KEY, "hex");
  if (buf.length === 32) return buf;
  return Buffer.from(CRM_ENCRYPTION_KEY.slice(0, 32), "utf8");
}

type Blob = { iv: string; tag: string; ciphertext: string };

export function decrypt(encryptedBase64: string): string {
  const key = getEncryptionKey();
  const json = Buffer.from(encryptedBase64, "base64").toString("utf8");
  const blob = JSON.parse(json) as Blob;
  const iv = Buffer.from(blob.iv, "base64");
  const tag = Buffer.from(blob.tag, "base64");
  const ciphertext = Buffer.from(blob.ciphertext, "base64");
  const decipher = createDecipheriv("aes-256-gcm", key, iv, { authTagLength: 16 });
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString("utf8");
}

function getSystemHeaders(): Record<string, string> {
  const headers: Record<string, string> = { "X-System": FUB_SYSTEM_NAME };
  if (FUB_SYSTEM_KEY) {
    headers["X-System-Key"] = FUB_SYSTEM_KEY;
  }
  return headers;
}

export type FubAuth = {
  mode: "oauth" | "api_key";
  headers: Record<string, string>;
};

export async function getFubApiKeyForUser(
  supabaseAdmin: SupabaseClient,
  userId: string
): Promise<string | null> {
  const { data: conn } = await supabaseAdmin
    .from("crm_connections")
    .select("id")
    .eq("user_id", userId)
    .eq("provider", "fub")
    .maybeSingle();
  if (!conn?.id) return null;

  const { data: secret } = await supabaseAdmin
    .from("crm_connection_secrets")
    .select("encrypted_api_key")
    .eq("connection_id", conn.id)
    .maybeSingle();
  if (!secret?.encrypted_api_key) return null;

  return decrypt(secret.encrypted_api_key);
}

export async function getFubAuthForUser(
  supabaseAdmin: SupabaseClient,
  userId: string
): Promise<FubAuth | null> {
  // Prefer OAuth token when present; refresh if expired or near expiry.
  const { data: oauth } = await supabaseAdmin
    .from("user_integrations")
    .select("access_token, refresh_token, expires_at")
    .eq("user_id", userId)
    .eq("provider", "fub")
    .maybeSingle();

  const oauthToken = oauth?.access_token ? String(oauth.access_token).trim() : "";
  const refreshToken = oauth?.refresh_token ? String(oauth.refresh_token).trim() : "";
  const rawExpiresAt = oauth?.expires_at;
  const parsedExpiresAt =
    typeof rawExpiresAt === "number"
      ? rawExpiresAt
      : typeof rawExpiresAt === "string"
        ? Number.parseInt(rawExpiresAt, 10)
        : NaN;
  const expiresAt = Number.isFinite(parsedExpiresAt) ? parsedExpiresAt : null;

  if (oauthToken) {
    const now = Math.floor(Date.now() / 1000);
    const shouldRefresh = expiresAt != null && now >= (expiresAt - OAUTH_EXPIRY_SKEW_SECONDS);

    if (shouldRefresh && refreshToken) {
      try {
        const refreshed = await refreshOAuthToken(refreshToken);
        const nextAccessToken = refreshed.accessToken.trim();
        const nextRefreshToken = (refreshed.refreshToken || refreshToken).trim();

        await supabaseAdmin
          .from("user_integrations")
          .update({
            access_token: nextAccessToken,
            refresh_token: nextRefreshToken || null,
            expires_at: refreshed.expiresAt ?? null,
            updated_at: new Date().toISOString(),
          })
          .eq("user_id", userId)
          .eq("provider", "fub");

        return {
          mode: "oauth",
          headers: {
            ...getSystemHeaders(),
            Authorization: `Bearer ${nextAccessToken}`,
          },
        };
      } catch (err) {
        console.warn("[crm-auth] fub oauth refresh failed", err);
      }
    }

    // If token is expired and refresh failed/unavailable, fall back to API key if configured.
    const isExpired = expiresAt != null && now >= expiresAt;
    if (!isExpired) {
      return {
        mode: "oauth",
        headers: {
          ...getSystemHeaders(),
          Authorization: `Bearer ${oauthToken}`,
        },
      };
    }
  }

  const apiKey = await getFubApiKeyForUser(supabaseAdmin, userId);
  if (!apiKey) return null;

  const basicAuth = Buffer.from(`${apiKey}:`).toString("base64");
  return {
    mode: "api_key",
    headers: {
      ...getSystemHeaders(),
      Authorization: `Basic ${basicAuth}`,
    },
  };
}
