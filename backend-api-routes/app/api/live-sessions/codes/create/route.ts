import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

import {
  LIVE_SESSION_CODE_TTL_MINUTES,
  hashLiveSessionCode,
  makeLiveSessionCode,
} from "../../../../lib/live-session-codes";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY =
  process.env.SUPABASE_ANON_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

type CreateLiveSessionCodeBody = {
  session_id?: string;
  sessionId?: string;
};

type SessionRow = {
  id: string;
  user_id: string;
  campaign_id: string | null;
  workspace_id: string | null;
  end_time: string | null;
};

type CampaignRow = {
  id: string;
  title: string | null;
  workspace_id: string | null;
};

function adminClient() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
}

function anonClient() {
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
}

function getBearerToken(request: Request): string | null {
  const authHeader = request.headers.get("authorization");
  return authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
}

function isUniqueViolation(
  error:
    | {
        code?: string | null;
        message?: string | null;
        details?: string | null;
        hint?: string | null;
      }
    | null
    | undefined
): boolean {
  const haystack = [error?.message, error?.details, error?.hint]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();
  return error?.code === "23505" || haystack.includes("duplicate key");
}

function isMissingLiveSessionCodesTable(
  error:
    | {
        message?: string | null;
        details?: string | null;
        hint?: string | null;
      }
    | null
    | undefined
): boolean {
  const haystack = [error?.message, error?.details, error?.hint]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();
  return (
    haystack.includes("live_session_codes") &&
    (haystack.includes("does not exist") ||
      haystack.includes("relation") ||
      haystack.includes("schema cache"))
  );
}

export async function POST(request: Request) {
  try {
    const token = getBearerToken(request);
    if (!token) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const {
      data: { user },
      error: userError,
    } = await anonClient().auth.getUser(token);

    if (userError || !user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    let body: CreateLiveSessionCodeBody;
    try {
      body = (await request.json()) as CreateLiveSessionCodeBody;
    } catch {
      return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
    }

    const sessionId = body.session_id?.trim() ?? body.sessionId?.trim();
    if (!sessionId) {
      return NextResponse.json({ error: "session_id is required." }, { status: 400 });
    }

    const admin = adminClient();

    const { data: sessionData, error: sessionError } = await admin
      .from("sessions")
      .select("id,user_id,campaign_id,workspace_id,end_time")
      .eq("id", sessionId)
      .maybeSingle();

    if (sessionError) {
      console.error("[live-sessions/codes/create] session lookup error:", sessionError);
      return NextResponse.json({ error: "Unable to load live session." }, { status: 500 });
    }

    const session = sessionData as SessionRow | null;
    if (!session) {
      return NextResponse.json({ error: "Live session not found." }, { status: 404 });
    }

    if (session.user_id !== user.id) {
      return NextResponse.json(
        { error: "Only the session host can create a join code." },
        { status: 403 }
      );
    }

    if (session.end_time) {
      return NextResponse.json(
        { error: "This live session has already ended. Start a new session to share a new code." },
        { status: 400 }
      );
    }

    if (!session.campaign_id) {
      return NextResponse.json(
        { error: "This session is not attached to a campaign." },
        { status: 400 }
      );
    }

    const { data: campaignData, error: campaignError } = await admin
      .from("campaigns")
      .select("id,title,workspace_id")
      .eq("id", session.campaign_id)
      .maybeSingle();

    if (campaignError) {
      console.error("[live-sessions/codes/create] campaign lookup error:", campaignError);
      return NextResponse.json({ error: "Unable to load campaign." }, { status: 500 });
    }

    const campaign = campaignData as CampaignRow | null;
    if (!campaign) {
      return NextResponse.json({ error: "Campaign not found." }, { status: 404 });
    }

    const nowIso = new Date().toISOString();
    const revokeResult = await admin
      .from("live_session_codes")
      .update({ revoked_at: nowIso })
      .eq("session_id", session.id)
      .is("revoked_at", null);

    if (revokeResult.error) {
      console.error("[live-sessions/codes/create] code revoke error:", revokeResult.error);
      if (isMissingLiveSessionCodesTable(revokeResult.error)) {
        return NextResponse.json(
          {
            error:
              "Live session codes are not live on the backend yet. Apply the live_session_codes migration and deploy backend-api-routes.",
          },
          { status: 500 }
        );
      }
      return NextResponse.json({ error: "Unable to prepare a session code." }, { status: 500 });
    }

    const expiresAt = new Date(Date.now() + LIVE_SESSION_CODE_TTL_MINUTES * 60 * 1000).toISOString();
    const maxAttempts = 8;

    for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
      const code = makeLiveSessionCode();
      const codeHash = hashLiveSessionCode(code);

      const { error: insertError } = await admin.from("live_session_codes").insert({
        session_id: session.id,
        campaign_id: campaign.id,
        workspace_id: campaign.workspace_id ?? session.workspace_id,
        created_by: user.id,
        code_hash: codeHash,
        expires_at: expiresAt,
      });

      if (!insertError) {
        return NextResponse.json({
          success: true,
          code,
          expires_at: expiresAt,
          expiresAt,
          workspace_id: campaign.workspace_id ?? session.workspace_id,
          workspaceId: campaign.workspace_id ?? session.workspace_id,
          campaign_id: campaign.id,
          campaignId: campaign.id,
          campaign_title: campaign.title,
          campaignTitle: campaign.title,
          session_id: session.id,
          sessionId: session.id,
        });
      }

      if (isUniqueViolation(insertError)) {
        continue;
      }

      console.error("[live-sessions/codes/create] code insert error:", insertError);
      if (isMissingLiveSessionCodesTable(insertError)) {
        return NextResponse.json(
          {
            error:
              "Live session codes are not live on the backend yet. Apply the live_session_codes migration and deploy backend-api-routes.",
          },
          { status: 500 }
        );
      }
      return NextResponse.json({ error: "Unable to create a session code." }, { status: 500 });
    }

    return NextResponse.json(
      { error: "Unable to generate a unique session code. Please try again." },
      { status: 500 }
    );
  } catch (error) {
    console.error("[live-sessions/codes/create] failed:", error);
    return NextResponse.json({ error: "Unable to create a session code." }, { status: 500 });
  }
}
