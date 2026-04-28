import { createHash, randomBytes } from "crypto";

export const CAMPAIGN_INVITE_TTL_DAYS = 30;
export const SESSION_INVITE_TTL_HOURS = 12;

export function makeInviteToken(): string {
  return randomBytes(24).toString("hex");
}

export function hashInviteToken(token: string): string {
  return createHash("sha256").update(token.trim()).digest("hex");
}
