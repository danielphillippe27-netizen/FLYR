import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

import {
  exchangeHubSpotCodeForTokens,
  getHubSpotIosRedirectUrl,
  getHubSpotRedirectUri,
  getHubSpotWebErrorUrl,
  getHubSpotWebSuccessUrl,
  parseHubSpotSignedState,
} from "../../../../../lib/hubspot-oauth";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

function appendMessage(urlString: string, message: string): string {
  try {
    const url = new URL(urlString);
    url.searchParams.set("message", message);
    return url.toString();
  } catch {
    const separator = urlString.includes("?") ? "&" : "?";
    return `${urlString}${separator}message=${encodeURIComponent(message)}`;
  }
}

function redirectWithError(origin: string, platform: "ios" | "web", message: string) {
  if (platform === "ios") {
    return NextResponse.redirect(getHubSpotIosRedirectUrl("error", message));
  }
  return NextResponse.redirect(appendMessage(getHubSpotWebErrorUrl(origin), message));
}

async function fetchHubSpotAccountHint(accessToken: string): Promise<{ accountId?: string; accountName?: string }> {
  try {
    const res = await fetch(`https://api.hubapi.com/oauth/v1/access-tokens/${encodeURIComponent(accessToken)}`);
    if (!res.ok) return {};
    const data = (await res.json()) as Record<string, unknown>;
    const hubId = data.hub_id != null ? String(data.hub_id) : undefined;
    const user = data.user as Record<string, unknown> | undefined;
    const name =
      user && typeof user.user === "string"
        ? user.user
        : user && typeof user.userId === "number"
          ? `Hub ${hubId ?? ""}`.trim()
          : undefined;
    return { accountId: hubId, accountName: name };
  } catch {
    return {};
  }
}

export async function GET(request: Request) {
  const url = new URL(request.url);
  const origin = url.origin;
  const code = url.searchParams.get("code");
  const stateValue = url.searchParams.get("state") || "";
  const parsedState = parseHubSpotSignedState(stateValue);
  const platform = parsedState?.platform === "ios" ? "ios" : "web";

  if (!parsedState?.userId) {
    return redirectWithError(origin, platform, "Invalid or expired OAuth state.");
  }

  if (!code) {
    return redirectWithError(origin, platform, "Missing authorization code.");
  }

  try {
    const redirectUri = getHubSpotRedirectUri(origin);
    const tokens = await exchangeHubSpotCodeForTokens(code, redirectUri);
    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const hint = await fetchHubSpotAccountHint(tokens.accessToken);

    const existingConfig = await supabaseAdmin
      .from("user_integrations")
      .select("provider_config")
      .eq("user_id", parsedState.userId)
      .eq("provider", "hubspot")
      .maybeSingle();

    const prevConfig =
      (existingConfig.data?.provider_config as Record<string, unknown> | null) ?? {};
    const workspaceId = parsedState.workspaceId?.trim();
    const providerConfig = {
      ...prevConfig,
      ...(workspaceId ? { workspaceId } : {}),
    };

    const { error: upsertError } = await supabaseAdmin.from("user_integrations").upsert(
      {
        user_id: parsedState.userId,
        provider: "hubspot",
        access_token: tokens.accessToken,
        refresh_token: tokens.refreshToken ?? null,
        expires_at: tokens.expiresAt ?? null,
        account_id: hint.accountId ?? null,
        account_name: hint.accountName ?? null,
        provider_config: providerConfig,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "user_id,provider" }
    );

    if (upsertError) {
      console.error("[hubspot/oauth/callback] upsert", upsertError);
      return redirectWithError(origin, platform, "Failed to save HubSpot connection.");
    }

    if (platform === "ios") {
      return NextResponse.redirect(getHubSpotIosRedirectUrl("success"));
    }

    return NextResponse.redirect(getHubSpotWebSuccessUrl(origin));
  } catch (error) {
    console.error("[hubspot/oauth/callback]", error);
    return redirectWithError(
      origin,
      platform,
      error instanceof Error ? error.message : "OAuth callback failed."
    );
  }
}
