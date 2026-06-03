import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

import { mondayGraphQLRequest } from "../../../../../lib/monday";
import {
  exchangeMondayCodeForTokens,
  getMondayIosRedirectUrl,
  getMondayRedirectUri,
  getMondayWebErrorUrl,
  getMondayWebSuccessUrl,
  parseMondaySignedState,
} from "../../../../../lib/monday-oauth";

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
    return NextResponse.redirect(getMondayIosRedirectUrl("error", message));
  }
  return NextResponse.redirect(appendMessage(getMondayWebErrorUrl(origin), message));
}

async function fetchMondayAccountProfile(
  accessToken: string
): Promise<{ accountId?: string; accountName?: string }> {
  try {
    const data = await mondayGraphQLRequest<{
      account?: { id?: string | number | null; name?: string | null };
      me?: { id?: string | number | null; name?: string | null };
    }>(
      accessToken,
      `
        query {
          account {
            id
            name
          }
          me {
            id
            name
          }
        }
      `
    );

    return {
      accountId: data.account?.id != null ? String(data.account.id) : data.me?.id != null ? String(data.me.id) : undefined,
      accountName: data.account?.name ?? data.me?.name ?? undefined,
    };
  } catch (error) {
    console.warn("[monday/oauth/callback] account profile", error);
    return {};
  }
}

export async function GET(request: Request) {
  const url = new URL(request.url);
  const origin = url.origin;
  const code = url.searchParams.get("code");
  const stateValue = url.searchParams.get("state") || "";
  const parsedState = parseMondaySignedState(stateValue);
  const platform = parsedState?.platform === "ios" ? "ios" : "web";

  if (!parsedState?.userId) {
    return redirectWithError(origin, platform, "Invalid or expired OAuth state.");
  }

  if (!code) {
    return redirectWithError(origin, platform, "Missing authorization code.");
  }

  try {
    const redirectUri = getMondayRedirectUri(origin);
    const tokens = await exchangeMondayCodeForTokens(code, redirectUri);
    const hint = await fetchMondayAccountProfile(tokens.accessToken);
    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const existingConfig = await supabaseAdmin
      .from("user_integrations")
      .select("provider_config")
      .eq("user_id", parsedState.userId)
      .eq("provider", "monday")
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
        provider: "monday",
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
      console.error("[monday/oauth/callback] upsert", upsertError);
      return redirectWithError(origin, platform, "Failed to save Monday.com connection.");
    }

    if (platform === "ios") {
      return NextResponse.redirect(getMondayIosRedirectUrl("success"));
    }

    return NextResponse.redirect(getMondayWebSuccessUrl(origin));
  } catch (error) {
    console.error("[monday/oauth/callback]", error);
    return redirectWithError(
      origin,
      platform,
      error instanceof Error ? error.message : "OAuth callback failed."
    );
  }
}
