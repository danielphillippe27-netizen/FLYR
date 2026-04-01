import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

export async function GET(request: Request) {
  try {
    const authHeader = request.headers.get("authorization");
    const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
    if (!token) {
      return NextResponse.json({ connected: false, error: "Missing or invalid authorization" }, { status: 401 });
    }

    const supabaseAnon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    const {
      data: { user },
      error: userError,
    } = await supabaseAnon.auth.getUser(token);
    if (userError || !user) {
      return NextResponse.json({ connected: false, error: "Invalid or expired token" }, { status: 401 });
    }

    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { data: row } = await supabaseAdmin
      .from("user_integrations")
      .select("access_token, refresh_token, expires_at, updated_at, account_id, account_name, provider_config")
      .eq("user_id", user.id)
      .eq("provider", "hubspot")
      .maybeSingle();

    const hasToken = !!(row?.access_token && String(row.access_token).trim());

    if (!row || !hasToken) {
      return NextResponse.json({
        connected: false,
        status: "disconnected",
        createdAt: null,
        updatedAt: null,
        accountId: null,
        accountName: null,
        lastError: null,
      });
    }

    return NextResponse.json({
      connected: true,
      status: "connected",
      createdAt: null,
      updatedAt: row.updated_at ?? null,
      accountId: row.account_id ?? null,
      accountName: row.account_name ?? null,
      lastError: null,
      providerConfig: row.provider_config ?? null,
    });
  } catch (err) {
    console.error("[hubspot/status]", err);
    return NextResponse.json({ connected: false, error: "Something went wrong" }, { status: 500 });
  }
}
