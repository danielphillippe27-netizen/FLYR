import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

import {
  groupSessionVoiceRoomName,
  campaignVoiceRoomName,
  issueGroupSessionVoiceToken,
  liveKitServerURL,
} from "../../../../lib/livekit";
import { validateCampaignVoiceAccess } from "../../../../lib/campaign-voice-access";
import { validateGroupSessionVoiceMembership } from "../../../../lib/live-session-membership";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY =
  process.env.SUPABASE_ANON_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

type JoinVoiceBody = {
  campaign_id?: string;
  campaignId?: string;
  session_id?: string;
};

function anonClient() {
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
}

function getBearerToken(request: Request): string | null {
  const authHeader = request.headers.get("authorization");
  return authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
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

    let body: JoinVoiceBody;
    try {
      body = (await request.json()) as JoinVoiceBody;
    } catch {
      return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
    }

    const sessionId = body.session_id?.trim();
    const campaignId = body.campaign_id?.trim() ?? body.campaignId?.trim();

    let roomName: string;
    let participantMetadata: string;
    let membership:
      | Awaited<ReturnType<typeof validateGroupSessionVoiceMembership>>
      | Awaited<ReturnType<typeof validateCampaignVoiceAccess>>;

    if (sessionId) {
      const sessionMembership = await validateGroupSessionVoiceMembership(sessionId, user.id);
      if (!sessionMembership || !sessionMembership.campaignId) {
        return NextResponse.json(
          { error: "You are not authorized to join this live session voice room." },
          { status: 403 }
        );
      }

      membership = sessionMembership;
      roomName = groupSessionVoiceRoomName(sessionMembership.sessionId);
      participantMetadata = JSON.stringify({
        user_id: sessionMembership.userId,
        campaign_id: sessionMembership.campaignId,
        workspace_id: sessionMembership.workspaceId,
        session_id: sessionMembership.sessionId,
        feature: "session_voice",
      });
    } else {
      if (!campaignId) {
        return NextResponse.json({ error: "session_id or campaign_id is required." }, { status: 400 });
      }

      membership = await validateCampaignVoiceAccess(campaignId, user.id);
      if (!membership) {
        return NextResponse.json(
          { error: "You are not authorized to join this campaign voice room." },
          { status: 403 }
        );
      }

      roomName = campaignVoiceRoomName(membership.campaignId);
      participantMetadata = JSON.stringify({
        user_id: membership.userId,
        campaign_id: membership.campaignId,
        workspace_id: membership.workspaceId,
        feature: "campaign_voice",
      });
    }

    const expiresInSeconds = 900;

    const liveKitToken = await issueGroupSessionVoiceToken(
      {
        identity: membership.userId,
        name: membership.displayName,
        metadata: participantMetadata,
      },
      roomName,
      expiresInSeconds
    );

    return NextResponse.json({
      room_name: roomName,
      participant_identity: membership.userId,
      participant_name: membership.displayName,
      livekit_url: liveKitServerURL(),
      token: liveKitToken,
      expires_in_seconds: expiresInSeconds,
    });
  } catch (error) {
    console.error("[live-sessions/voice/join] failed:", error);
    return NextResponse.json({ error: "Unable to join live voice." }, { status: 500 });
  }
}
