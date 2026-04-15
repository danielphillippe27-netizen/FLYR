import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

import { BoldTrailAPIClient, BoldTrailTokenValidator, maskBoldTrailToken } from "../../../../lib/boldtrail";
import { getBoldTrailTokenForUser } from "../../../../lib/crm-auth";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

type TestBody = {
  api_token?: string;
};

export async function POST(request: Request) {
  try {
    const authHeader = request.headers.get("authorization");
    const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
    if (!token) {
      return NextResponse.json({ success: false, error: "Missing or invalid authorization" }, { status: 401 });
    }

    const supabaseAnon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    const {
      data: { user },
      error: userError,
    } = await supabaseAnon.auth.getUser(token);
    if (userError || !user) {
      return NextResponse.json({ success: false, error: "Invalid or expired token" }, { status: 401 });
    }

    let body: TestBody = {};
    try {
      body = (await request.json()) as TestBody;
    } catch {
      body = {};
    }

    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const enteredToken = typeof body.api_token === "string" ? body.api_token.trim() : "";
    const storedToken = enteredToken ? null : await getBoldTrailTokenForUser(supabaseAdmin, user.id);
    const candidateToken = enteredToken || storedToken || "";
    const usingStoredToken = !enteredToken;

    if (!candidateToken) {
      return NextResponse.json(
        { success: false, error: "BoldTrail is not connected" },
        { status: 404 }
      );
    }

    const now = new Date().toISOString();
    const validator = new BoldTrailTokenValidator(new BoldTrailAPIClient());

    try {
      const validation = await validator.validate(candidateToken);

      if (usingStoredToken) {
        await updateStoredTestResult(supabaseAdmin, user.id, {
          errorReason: null,
          metadataPatch: {
            accountName: validation.accountName ?? null,
            userEmail: validation.userEmail ?? null,
            tokenHint: maskBoldTrailToken(candidateToken),
            lastTestedAt: now,
            lastValidatedAt: now,
            lastTestResult: "success",
          },
        });
      }

      console.info("[boldtrail/test]", {
        userId: user.id,
        usingStoredToken,
        tokenHint: maskBoldTrailToken(candidateToken),
      });

      return NextResponse.json({
        success: true,
        message: "Connection successful",
        account: {
          name: validation.accountName ?? null,
          email: validation.userEmail ?? null,
        },
        tokenHint: maskBoldTrailToken(candidateToken),
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unable to connect to BoldTrail";
      if (usingStoredToken) {
        await updateStoredTestResult(supabaseAdmin, user.id, {
          errorReason: message,
          metadataPatch: {
            lastTestedAt: now,
            lastTestResult: "failed",
          },
        });
      }

      const status = /invalid token/i.test(message) ? 401 : 502;
      return NextResponse.json(
        { success: false, error: message },
        { status }
      );
    }
  } catch (error) {
    console.error("[boldtrail/test]", error);
    return NextResponse.json(
      { success: false, error: "Something went wrong" },
      { status: 500 }
    );
  }
}

async function updateStoredTestResult(
  supabaseAdmin: any,
  userId: string,
  updates: {
    errorReason: string | null;
    metadataPatch: Record<string, unknown>;
  }
) {
  const { data: row } = await supabaseAdmin
    .from("crm_connections")
    .select("id, metadata")
    .eq("user_id", userId)
    .eq("provider", "boldtrail")
    .maybeSingle();

  if (!row?.id) return;

  const metadata = {
    ...((row.metadata as Record<string, unknown> | null) ?? {}),
    ...updates.metadataPatch,
  };

  await supabaseAdmin
    .from("crm_connections")
    .update({
      metadata,
      error_reason: updates.errorReason,
      updated_at: new Date().toISOString(),
    })
    .eq("id", row.id);
}
