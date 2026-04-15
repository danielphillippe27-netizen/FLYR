import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

import {
  buildAuthorizeUrl,
  createSignedState,
  getFubRedirectUri,
} from "../../../../../lib/fub-oauth";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY!;

function getBearerToken(request: Request): string | null {
  const authHeader = request.headers.get("authorization");
  if (authHeader?.startsWith("Bearer ")) {
    return authHeader.slice(7);
  }

  const token = new URL(request.url).searchParams.get("token");
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
    const redirectUri = getFubRedirectUri(url.origin);
    const state = createSignedState(user.id, platform);
    const authorizeUrl = buildAuthorizeUrl(state, redirectUri);

    return NextResponse.json({
      success: true,
      authorizeUrl,
      platform,
    });
  } catch (error) {
    console.error("[fub/oauth/start]", error);
    return NextResponse.json({ error: "Unable to start OAuth flow." }, { status: 500 });
  }
}
