import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import {
  buildAuthorizeUrl,
  createOAuthState,
  getFubOAuthRedirectUri,
  type OAuthPlatform,
} from "../../../../../lib/fub-oauth";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY!;

function extractToken(request: Request): string | null {
  const authHeader = request.headers.get("authorization");
  if (authHeader?.startsWith("Bearer ")) {
    return authHeader.slice(7);
  }
  const url = new URL(request.url);
  const queryToken = url.searchParams.get("token");
  return queryToken && queryToken.trim() ? queryToken.trim() : null;
}

export async function GET(request: Request) {
  try {
    const token = extractToken(request);
    if (!token) {
      return NextResponse.json(
        { error: "Missing or invalid authorization" },
        { status: 401 }
      );
    }

    const supabaseAnon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    const {
      data: { user },
      error: userError,
    } = await supabaseAnon.auth.getUser(token);
    if (userError || !user) {
      return NextResponse.json(
        { error: "Invalid or expired token" },
        { status: 401 }
      );
    }

    const url = new URL(request.url);
    const rawPlatform = (url.searchParams.get("platform") || "web").toLowerCase();
    const platform: OAuthPlatform = rawPlatform === "ios" ? "ios" : "web";

    const redirectUri = getFubOAuthRedirectUri(url.origin);
    const state = createOAuthState(user.id, platform);
    const authorizeUrl = buildAuthorizeUrl(state, redirectUri);

    return NextResponse.json({
      success: true,
      authorizeUrl,
      platform,
    });
  } catch (err) {
    console.error("[fub/oauth/start]", err);
    return NextResponse.json(
      { error: "Unable to start OAuth flow." },
      { status: 500 }
    );
  }
}
