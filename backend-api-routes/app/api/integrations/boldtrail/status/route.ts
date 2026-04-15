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
      .from("crm_connections")
      .select("status, connected_at, updated_at, last_sync_at, error_reason, metadata")
      .eq("user_id", user.id)
      .eq("provider", "boldtrail")
      .maybeSingle();

    if (!row) {
      return NextResponse.json({
        connected: false,
        status: "disconnected",
        createdAt: null,
        updatedAt: null,
        lastSyncAt: null,
        lastError: null,
        metadata: null,
      });
    }

    return NextResponse.json({
      connected: row.status === "connected",
      status: row.status,
      createdAt: row.connected_at ?? null,
      updatedAt: row.updated_at ?? null,
      lastSyncAt: row.last_sync_at ?? null,
      lastError: row.error_reason ?? null,
      metadata: row.metadata ?? null,
    });
  } catch (error) {
    console.error("[boldtrail/status]", error);
    return NextResponse.json(
      { connected: false, error: "Something went wrong" },
      { status: 500 }
    );
  }
}
