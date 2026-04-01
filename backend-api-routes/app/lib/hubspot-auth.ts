import type { SupabaseClient } from "@supabase/supabase-js";

import { refreshHubSpotAccessToken } from "./hubspot-oauth";

export type HubSpotIntegrationRow = {
  access_token: string | null;
  refresh_token: string | null;
  expires_at: number | null;
};

const REFRESH_BUFFER_SEC = 300;

export async function loadHubSpotIntegration(
  supabaseAdmin: SupabaseClient,
  userId: string
): Promise<HubSpotIntegrationRow | null> {
  const { data, error } = await supabaseAdmin
    .from("user_integrations")
    .select("access_token, refresh_token, expires_at")
    .eq("user_id", userId)
    .eq("provider", "hubspot")
    .maybeSingle();

  if (error) {
    console.error("[hubspot-auth] load integration", error);
    return null;
  }

  if (!data) return null;
  return {
    access_token: typeof data.access_token === "string" ? data.access_token : null,
    refresh_token: typeof data.refresh_token === "string" ? data.refresh_token : null,
    expires_at:
      data.expires_at != null && Number.isFinite(Number(data.expires_at))
        ? Number(data.expires_at)
        : null,
  };
}

/**
 * Returns a valid HubSpot access token, refreshing server-side when near expiry.
 */
export async function getHubSpotAccessTokenForUser(
  supabaseAdmin: SupabaseClient,
  userId: string
): Promise<string | null> {
  const row = await loadHubSpotIntegration(supabaseAdmin, userId);
  if (!row?.access_token?.trim()) {
    return null;
  }

  const now = Math.floor(Date.now() / 1000);
  const exp = row.expires_at;
  const needsRefresh =
    row.refresh_token?.trim() &&
    exp != null &&
    exp - now < REFRESH_BUFFER_SEC;

  if (!needsRefresh) {
    return row.access_token.trim();
  }

  try {
    const refreshed = await refreshHubSpotAccessToken(row.refresh_token!.trim());
    const { error: updateError } = await supabaseAdmin
      .from("user_integrations")
      .update({
        access_token: refreshed.accessToken,
        refresh_token: refreshed.refreshToken ?? row.refresh_token,
        expires_at: refreshed.expiresAt ?? null,
        updated_at: new Date().toISOString(),
      })
      .eq("user_id", userId)
      .eq("provider", "hubspot");

    if (updateError) {
      console.error("[hubspot-auth] persist refresh", updateError);
      return row.access_token.trim();
    }

    return refreshed.accessToken;
  } catch (e) {
    console.warn("[hubspot-auth] refresh failed", e);
    return row.access_token.trim();
  }
}
