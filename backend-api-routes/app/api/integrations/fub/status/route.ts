import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

type ConnectionRow = {
  status: string;
  connected_at: string | null;
  updated_at: string;
  last_sync_at: string | null;
  error_reason: string | null;
};

export async function GET(request: Request) {
  try {
    const authHeader = request.headers.get("authorization");
    const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
    if (!token) {
      return NextResponse.json({ connected: false, error: "Missing or invalid authorization" }, { status: 401 });
    }

    const supabaseAnon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    const { data: { user }, error: userError } = await supabaseAnon.auth.getUser(token);
    if (userError || !user) {
      return NextResponse.json({ connected: false, error: "Invalid or expired token" }, { status: 401 });
    }

    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { data: row } = await supabaseAdmin
      .from("crm_connections")
      .select("status, connected_at, updated_at, last_sync_at, error_reason")
      .eq("user_id", user.id)
      .eq("provider", "fub")
      .maybeSingle();

    if (!row) {
      return NextResponse.json({
        connected: false,
        status: "disconnected",
        createdAt: null,
        updatedAt: null,
        lastSyncAt: null,
        lastError: null,
      });
    }

    const conn = row as ConnectionRow;
    return NextResponse.json({
      connected: conn.status === "connected",
      status: conn.status,
      createdAt: conn.connected_at ?? null,
      updatedAt: conn.updated_at ?? null,
      lastSyncAt: conn.last_sync_at ?? null,
      lastError: conn.error_reason ?? null,
    });
  } catch (err) {
    console.error("[fub/status]", err);
    return NextResponse.json(
      { connected: false, error: "Something went wrong" },
      { status: 500 }
    );
  }
}
