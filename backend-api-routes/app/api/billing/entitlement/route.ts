import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

/** GET /api/billing/entitlement — Always return an entitlement (create default free row if none). */
export async function GET(request: Request) {
  try {
    const authHeader = request.headers.get("authorization");
    const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
    if (!token) {
      return NextResponse.json(
        { plan: "free", is_active: false, source: "none", current_period_end: null },
        { status: 200 }
      );
    }

    const supabaseAnon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    const {
      data: { user },
      error: userError,
    } = await supabaseAnon.auth.getUser(token);
    if (userError || !user) {
      return NextResponse.json(
        { plan: "free", is_active: false, source: "none", current_period_end: null },
        { status: 200 }
      );
    }

    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { data: existing, error: selectError } = await supabaseAdmin
      .from("entitlements")
      .select("plan, is_active, source, current_period_end, updated_at")
      .eq("user_id", user.id)
      .maybeSingle();

    if (selectError) {
      console.error("[billing/entitlement] select error:", selectError);
      return NextResponse.json(
        { plan: "free", is_active: false, source: "none", current_period_end: null },
        { status: 200 }
      );
    }

    if (existing) {
      return NextResponse.json({
        plan: existing.plan,
        is_active: existing.is_active,
        source: existing.source,
        current_period_end: existing.current_period_end ?? null,
      });
    }

    // No row: create default free row and return it
    const { data: inserted, error: insertError } = await supabaseAdmin
      .from("entitlements")
      .insert({
        user_id: user.id,
        plan: "free",
        is_active: false,
        source: "none",
        current_period_end: null,
        updated_at: new Date().toISOString(),
      })
      .select("plan, is_active, source, current_period_end")
      .single();

    if (insertError || !inserted) {
      console.error("[billing/entitlement] insert error:", insertError);
      return NextResponse.json(
        { plan: "free", is_active: false, source: "none", current_period_end: null },
        { status: 200 }
      );
    }

    return NextResponse.json({
      plan: inserted.plan,
      is_active: inserted.is_active,
      source: inserted.source,
      current_period_end: inserted.current_period_end ?? null,
    });
  } catch (err) {
    console.error("[billing/entitlement]", err);
    return NextResponse.json(
      { plan: "free", is_active: false, source: "none", current_period_end: null },
      { status: 200 }
    );
  }
}
