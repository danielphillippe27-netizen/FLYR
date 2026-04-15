import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

import { BoldTrailAPIClient, BoldTrailTokenValidator, maskBoldTrailToken } from "../../../../lib/boldtrail";
import { encryptCRMSecret } from "../../../../lib/crm-auth";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

type ConnectBody = {
  api_token?: string;
};

export async function POST(request: Request) {
  try {
    const authHeader = request.headers.get("authorization");
    const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
    if (!token) {
      return NextResponse.json(
        { connected: false, error: "Missing or invalid authorization" },
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
        { connected: false, error: "Invalid or expired token" },
        { status: 401 }
      );
    }

    const body = (await request.json()) as ConnectBody;
    const rawToken = typeof body.api_token === "string" ? body.api_token.trim() : "";
    if (!rawToken) {
      return NextResponse.json(
        { connected: false, error: "API token is required" },
        { status: 400 }
      );
    }

    const validator = new BoldTrailTokenValidator(new BoldTrailAPIClient());
    let accountName: string | null = null;
    let userEmail: string | null = null;
    try {
      const validation = await validator.validate(rawToken);
      accountName = validation.accountName ?? null;
      userEmail = validation.userEmail ?? null;
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unable to connect to BoldTrail";
      const status = /invalid token/i.test(message) ? 401 : 502;
      return NextResponse.json(
        { connected: false, error: message },
        { status }
      );
    }

    const now = new Date().toISOString();
    const encrypted = encryptCRMSecret(rawToken);
    const tokenHint = maskBoldTrailToken(rawToken);
    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const { data: existing } = await supabaseAdmin
      .from("crm_connections")
      .select("id, metadata")
      .eq("user_id", user.id)
      .eq("provider", "boldtrail")
      .maybeSingle();

    const metadata = {
      ...((existing?.metadata as Record<string, unknown> | null) ?? {}),
      providerLabel: "BoldTrail / kvCORE",
      accountName,
      userEmail,
      tokenHint,
      lastValidatedAt: now,
      lastTestedAt: now,
      lastTestResult: "success",
    };

    let connectionId = existing?.id as string | undefined;
    if (connectionId) {
      await supabaseAdmin
        .from("crm_connections")
        .update({
          status: "connected",
          connected_at: now,
          error_reason: null,
          metadata,
          updated_at: now,
        })
        .eq("id", connectionId);
    } else {
      const { data: inserted, error: insertError } = await supabaseAdmin
        .from("crm_connections")
        .insert({
          user_id: user.id,
          provider: "boldtrail",
          status: "connected",
          connected_at: now,
          metadata,
          updated_at: now,
        })
        .select("id")
        .single();

      if (insertError || !inserted?.id) {
        return NextResponse.json(
          { connected: false, error: "Failed to save BoldTrail connection" },
          { status: 500 }
        );
      }
      connectionId = inserted.id as string;
    }

    await supabaseAdmin.from("crm_connection_secrets").upsert(
      {
        connection_id: connectionId,
        encrypted_api_key: encrypted,
      },
      { onConflict: "connection_id" }
    );

    console.info("[boldtrail/connect]", {
      userId: user.id,
      tokenHint,
      accountName,
    });

    return NextResponse.json({
      connected: true,
      account: {
        name: accountName,
        email: userEmail,
      },
      tokenHint,
      message: "Connection successful",
    });
  } catch (error) {
    console.error("[boldtrail/connect]", error);
    return NextResponse.json(
      { connected: false, error: "Something went wrong" },
      { status: 500 }
    );
  }
}
