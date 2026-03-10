import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import {
  buildIosResultUrl,
  exchangeOAuthCode,
  getFubOAuthRedirectUri,
  getWebErrorUrl,
  getWebSuccessUrl,
  verifyOAuthState,
} from "../../../../../lib/fub-oauth";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

function withMessage(url: string, message: string): string {
  try {
    const parsed = new URL(url);
    parsed.searchParams.set("message", message);
    return parsed.toString();
  } catch {
    const suffix = url.includes("?") ? "&" : "?";
    return `${url}${suffix}message=${encodeURIComponent(message)}`;
  }
}

function redirectForError(origin: string, platform: "ios" | "web", message: string) {
  if (platform === "ios") {
    return NextResponse.redirect(buildIosResultUrl("error", message));
  }
  return NextResponse.redirect(withMessage(getWebErrorUrl(origin), message));
}

export async function GET(request: Request) {
  const url = new URL(request.url);
  const origin = url.origin;
  const errorParam = url.searchParams.get("error");
  const code = url.searchParams.get("code");
  const rawState = url.searchParams.get("state") || "";

  const state = verifyOAuthState(rawState);
  const platform: "ios" | "web" = state?.platform === "ios" ? "ios" : "web";

  if (!state?.userId) {
    return redirectForError(origin, platform, "Invalid or expired OAuth state.");
  }
  if (errorParam) {
    const desc = url.searchParams.get("error_description") || errorParam;
    return redirectForError(origin, platform, desc);
  }
  if (!code) {
    return redirectForError(origin, platform, "Missing authorization code.");
  }

  try {
    const redirectUri = getFubOAuthRedirectUri(origin);
    const tokenData = await exchangeOAuthCode(code, redirectUri);
    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Persist OAuth credentials for FUB.
    const { error: upsertIntegrationError } = await supabaseAdmin
      .from("user_integrations")
      .upsert(
        {
          user_id: state.userId,
          provider: "fub",
          access_token: tokenData.accessToken,
          refresh_token: tokenData.refreshToken ?? null,
          expires_at: tokenData.expiresAt ?? null,
          api_key: null,
          updated_at: new Date().toISOString(),
        },
        { onConflict: "user_id,provider" }
      );

    if (upsertIntegrationError) {
      console.error("[fub/oauth/callback] upsert integration", upsertIntegrationError);
      return redirectForError(origin, platform, "Failed to save OAuth tokens.");
    }

    const { data: existingConn, error: connFetchError } = await supabaseAdmin
      .from("crm_connections")
      .select("id")
      .eq("user_id", state.userId)
      .eq("provider", "fub")
      .maybeSingle();

    if (connFetchError) {
      console.error("[fub/oauth/callback] fetch connection", connFetchError);
      return redirectForError(origin, platform, "Failed to load CRM connection.");
    }

    let connectionId = existingConn?.id as string | undefined;
    if (connectionId) {
      const { error: connUpdateError } = await supabaseAdmin
        .from("crm_connections")
        .update({
          status: "connected",
          connected_at: new Date().toISOString(),
          last_sync_at: null,
          error_reason: null,
          metadata: {
            auth_mode: "oauth",
          },
          updated_at: new Date().toISOString(),
        })
        .eq("id", connectionId);
      if (connUpdateError) {
        console.error("[fub/oauth/callback] update connection", connUpdateError);
        return redirectForError(origin, platform, "Failed to update CRM connection.");
      }
    } else {
      const { data: inserted, error: connInsertError } = await supabaseAdmin
        .from("crm_connections")
        .insert({
          user_id: state.userId,
          provider: "fub",
          status: "connected",
          connected_at: new Date().toISOString(),
          metadata: {
            auth_mode: "oauth",
          },
          updated_at: new Date().toISOString(),
        })
        .select("id")
        .single();
      if (connInsertError || !inserted?.id) {
        console.error("[fub/oauth/callback] insert connection", connInsertError);
        return redirectForError(origin, platform, "Failed to create CRM connection.");
      }
      connectionId = inserted.id as string;
    }

    // OAuth should be source of truth after connection; remove API-key secret if present.
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
      return NextResponse.redirect(buildIosResultUrl("success"));
    }
    return NextResponse.redirect(getWebSuccessUrl(origin));
  } catch (err) {
    console.error("[fub/oauth/callback]", err);
    const message = err instanceof Error ? err.message : "OAuth callback failed.";
    return redirectForError(origin, platform, message);
  }
}
