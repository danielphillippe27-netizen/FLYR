import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

type VerifyBody = { transactionId: string; productId: string };

/**
 * POST /api/billing/apple/verify
 * Validates JWT, then verifies the Apple transaction and upserts entitlements.
 * TODO: Production must verify the transaction with Apple (App Store Server API or
 * verify StoreKit 2 JWS from client). This implementation upserts entitlements
 * so the flow works end-to-end; add Apple verification before launch.
 */
export async function POST(request: Request) {
  try {
    const authHeader = request.headers.get("authorization");
    const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
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

    const body = (await request.json()) as VerifyBody;
    const transactionId =
      typeof body.transactionId === "string" ? body.transactionId.trim() : String(body.transactionId ?? "");
    const productId = typeof body.productId === "string" ? body.productId.trim() : "";
    if (!transactionId || !productId) {
      return NextResponse.json(
        { error: "Missing transactionId or productId" },
        { status: 400 }
      );
    }

    // TODO: Verify transaction with Apple (App Store Server API or JWS verification).
    // For MVP we derive period end from productId and upsert.
    const isYearly = productId.toLowerCase().includes("yearly");
    const now = new Date();
    const currentPeriodEnd = new Date(now);
    if (isYearly) {
      currentPeriodEnd.setFullYear(currentPeriodEnd.getFullYear() + 1);
    } else {
      currentPeriodEnd.setMonth(currentPeriodEnd.getMonth() + 1);
    }

    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { error: upsertError } = await supabaseAdmin.from("entitlements").upsert(
      {
        user_id: user.id,
        plan: "pro",
        is_active: true,
        source: "apple",
        current_period_end: currentPeriodEnd.toISOString(),
        updated_at: new Date().toISOString(),
      },
      { onConflict: "user_id" }
    );

    if (upsertError) {
      console.error("[billing/apple/verify] upsert error:", upsertError);
      return NextResponse.json({ error: "Failed to update entitlement" }, { status: 500 });
    }

    return NextResponse.json({ ok: true });
  } catch (err) {
    console.error("[billing/apple/verify]", err);
    return NextResponse.json({ error: "Server error" }, { status: 500 });
  }
}
