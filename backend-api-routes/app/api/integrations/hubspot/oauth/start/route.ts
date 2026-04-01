import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

import {
  buildHubSpotAuthorizeUrl,
  createHubSpotSignedState,
  getHubSpotRedirectUri,
} from "../../../../../lib/hubspot-oauth";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY!;

function getBearerToken(request: Request): string | null {
  const authHeader = request.headers.get("authorization");
  if (authHeader?.startsWith("Bearer ")) {
    return authHeader.slice(7);
  }

  const url = new URL(request.url);
  const token =
    url.searchParams.get("token") ||
    url.searchParams.get("access_token") ||
    url.searchParams.get("accessToken");
  return token && token.trim() ? token.trim() : null;
}

export async function GET(request: Request) {
  try {
    const token = getBearerToken(request);
    if (!token) {
      return NextResponse.json({ error: "Missing or invalid authorization" }, { status: 401 });
    }

    const supabaseAnon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    const {
      data: { user },
      error: userError,
    } = await supabaseAnon.auth.getUser(token);

    if (userError || !user) {
      return NextResponse.json({ error: "Invalid or expired token" }, { status: 401 });
    }

    const url = new URL(request.url);
    const rawPlatform = (url.searchParams.get("platform") || "web").toLowerCase();
    const platform = rawPlatform === "ios" ? "ios" : "web";
    const workspaceId = url.searchParams.get("workspaceId") || url.searchParams.get("workspace_id");

    const origin = url.origin;
    const redirectUri = getHubSpotRedirectUri(origin);
    const state = createHubSpotSignedState(user.id, platform, workspaceId);
    const authorizeUrl = buildHubSpotAuthorizeUrl(state, redirectUri);

    return NextResponse.json({
      success: true,
      authorizeUrl,
      platform,
    });
  } catch (error) {
    console.error("[hubspot/oauth/start]", error);
    const message = error instanceof Error ? error.message : "Unable to start OAuth flow.";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
