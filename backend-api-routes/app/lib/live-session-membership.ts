import { createClient } from "@supabase/supabase-js";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

export type LiveSessionVoiceMembership = {
  sessionId: string;
  campaignId: string | null;
  workspaceId: string | null;
  userId: string;
  displayName: string;
};

type SessionParticipantRow = {
  session_id: string;
  campaign_id: string | null;
  user_id: string;
  left_at: string | null;
};

type SessionRow = {
  id: string;
  user_id: string;
  campaign_id: string | null;
  workspace_id: string | null;
  end_time: string | null;
};

type ProfileRow = {
  id: string;
  full_name?: string | null;
  display_name?: string | null;
  email?: string | null;
};

function adminClient() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
}

function normalizeDisplayName(profile: ProfileRow | null, fallbackUserId: string): string {
  const candidate = profile?.display_name?.trim()
    || profile?.full_name?.trim()
    || profile?.email?.trim();

  if (candidate) return candidate;
  return `Rep ${fallbackUserId.slice(0, 4).toUpperCase()}`;
}

export async function validateGroupSessionVoiceMembership(
  sessionId: string,
  userId: string
): Promise<LiveSessionVoiceMembership | null> {
  const admin = adminClient();

  const { data: sessionData, error: sessionError } = await admin
    .from("sessions")
    .select("id,user_id,campaign_id,workspace_id,end_time")
    .eq("id", sessionId)
    .maybeSingle();

  if (sessionError) {
    throw sessionError;
  }

  const session = sessionData as SessionRow | null;
  if (!session || session.end_time) {
    return null;
  }

  let participant: SessionParticipantRow | null = null;

  const { data: participantData, error: participantError } = await admin
    .from("session_participants")
    .select("session_id,campaign_id,user_id,left_at")
    .eq("session_id", sessionId)
    .eq("user_id", userId)
    .maybeSingle();

  if (participantError) {
    const message = [participantError.message, participantError.details, participantError.hint]
      .filter(Boolean)
      .join(" ")
      .toLowerCase();

    const isMissingTable = message.includes("session_participants")
      && (message.includes("does not exist") || message.includes("schema cache"));

    if (!isMissingTable) {
      throw participantError;
    }
  } else {
    participant = participantData as SessionParticipantRow | null;
  }

  const isHost = session.user_id === userId;
  const isActiveParticipant = !!participant && !participant.left_at;

  if (!isHost && !isActiveParticipant) {
    return null;
  }

  let profile: ProfileRow | null = null;
  const { data: profileData, error: profileError } = await admin
    .from("profiles")
    .select("id,full_name,display_name,email")
    .eq("id", userId)
    .maybeSingle();

  if (profileError) {
    const message = [profileError.message, profileError.details, profileError.hint]
      .filter(Boolean)
      .join(" ")
      .toLowerCase();

    if (!message.includes("profiles")) {
      throw profileError;
    }
  } else {
    profile = (profileData as ProfileRow | null) ?? null;
  }

  return {
    sessionId: session.id,
    campaignId: participant?.campaign_id ?? session.campaign_id ?? null,
    workspaceId: session.workspace_id ?? null,
    userId,
    displayName: normalizeDisplayName(profile, userId),
  };
}
