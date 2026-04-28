import { AccessToken } from "livekit-server-sdk";

const LIVEKIT_URL = process.env.LIVEKIT_URL?.trim();
const LIVEKIT_API_KEY = process.env.LIVEKIT_API_KEY?.trim();
const LIVEKIT_API_SECRET = process.env.LIVEKIT_API_SECRET?.trim();

export type LiveKitParticipantDescriptor = {
  identity: string;
  name?: string;
  metadata?: string;
};

export function groupSessionVoiceRoomName(sessionId: string): string {
  return `flyr-session-${sessionId.toLowerCase()}`;
}

export function campaignVoiceRoomName(campaignId: string): string {
  return `flyr-campaign-${campaignId.toLowerCase()}`;
}

export function liveKitServerURL(): string {
  if (!LIVEKIT_URL) {
    throw new Error("LIVEKIT_URL is not configured.");
  }
  return LIVEKIT_URL;
}

export async function issueGroupSessionVoiceToken(
  participant: LiveKitParticipantDescriptor,
  roomName: string,
  ttlSeconds = 900
): Promise<string> {
  if (!LIVEKIT_API_KEY || !LIVEKIT_API_SECRET) {
    throw new Error("LiveKit signing credentials are not configured.");
  }

  const token = new AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET, {
    identity: participant.identity,
    name: participant.name,
    metadata: participant.metadata,
    ttl: ttlSeconds,
  });

  token.addGrant({
    room: roomName,
    roomJoin: true,
    canPublish: true,
    canPublishData: false,
    canSubscribe: true,
  });

  return token.toJwt();
}
