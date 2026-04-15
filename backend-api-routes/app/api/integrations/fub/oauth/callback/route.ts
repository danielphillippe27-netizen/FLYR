import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

import {
  exchangeCodeForTokens,
  getFubRedirectUri,
  getIosRedirectUrl,
  getWebErrorUrl,
  getWebSuccessUrl,
  parseSignedState,
} from "../../../../../lib/fub-oauth";

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
    return NextResponse.redirect(getIosRedirectUrl("error", message));
  }
  return NextResponse.redirect(appendMessage(getWebErrorUrl(origin), message));
}

export async function GET(request: Request) {
  const url = new URL(request.url);
  const origin = url.origin;
  const responseValue = url.searchParams.get("response");
  const code = url.searchParams.get("code");
  const stateValue = url.searchParams.get("state") || "";
  const parsedState = parseSignedState(stateValue);
  const platform = parsedState?.platform === "ios" ? "ios" : "web";

  if (!parsedState?.userId) {
    return redirectWithError(origin, platform, "Invalid or expired OAuth state.");
  }

  if (responseValue === "denied") {
    return redirectWithError(origin, platform, "Follow Up Boss access was denied.");
  }

  if (!code) {
    return redirectWithError(origin, platform, "Missing authorization code.");
  }

  try {
    const redirectUri = getFubRedirectUri(origin);
    const tokens = await exchangeCodeForTokens(code, redirectUri, stateValue);
    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const { error: upsertIntegrationError } = await supabaseAdmin.from("user_integrations").upsert(
      {
        user_id: parsedState.userId,
        provider: "fub",
        access_token: tokens.accessToken,
        refresh_token: tokens.refreshToken ?? null,
        expires_at: tokens.expiresAt ?? null,
        api_key: null,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "user_id,provider" }
    );

    if (upsertIntegrationError) {
      console.error("[fub/oauth/callback] upsert integration", upsertIntegrationError);
      return redirectWithError(origin, platform, "Failed to save OAuth tokens.");
    }

    const { data: existingConnection, error: fetchConnectionError } = await supabaseAdmin
      .from("crm_connections")
      .select("id")
      .eq("user_id", parsedState.userId)
      .eq("provider", "fub")
      .maybeSingle();

    if (fetchConnectionError) {
      console.error("[fub/oauth/callback] fetch connection", fetchConnectionError);
      return redirectWithError(origin, platform, "Failed to load CRM connection.");
    }

    let connectionId = existingConnection?.id as string | undefined;
    if (connectionId) {
      const { error: updateConnectionError } = await supabaseAdmin
        .from("crm_connections")
        .update({
          status: "connected",
          connected_at: new Date().toISOString(),
          last_sync_at: null,
          error_reason: null,
          metadata: { auth_mode: "oauth" },
          updated_at: new Date().toISOString(),
        })
        .eq("id", connectionId);

      if (updateConnectionError) {
        console.error("[fub/oauth/callback] update connection", updateConnectionError);
        return redirectWithError(origin, platform, "Failed to update CRM connection.");
      }
    } else {
      const { data: insertedConnection, error: insertConnectionError } = await supabaseAdmin
        .from("crm_connections")
        .insert({
          user_id: parsedState.userId,
          provider: "fub",
          status: "connected",
          connected_at: new Date().toISOString(),
          metadata: { auth_mode: "oauth" },
          updated_at: new Date().toISOString(),
        })
        .select("id")
        .single();

      if (insertConnectionError || !insertedConnection?.id) {
        console.error("[fub/oauth/callback] insert connection", insertConnectionError);
        return redirectWithError(origin, platform, "Failed to create CRM connection.");
      }

      connectionId = insertedConnection.id as string;
    }

    if (connectionId) {
      const { error: deleteSecretError } = await supabaseAdmin
        .from("crm_connection_secrets")
        .delete()
        .eq("connection_id", connectionId);

      if (deleteSecretError) {
        console.warn("[fub/oauth/callback] delete stale secret", deleteSecretError);
      }
    }

    if (platform === "ios") {
      return NextResponse.redirect(getIosRedirectUrl("success"));
    }

    return NextResponse.redirect(getWebSuccessUrl(origin));
  } catch (error) {
    console.error("[fub/oauth/callback]", error);
    return redirectWithError(
      origin,
      platform,
      error instanceof Error ? error.message : "OAuth callback failed."
    );
  }
}
