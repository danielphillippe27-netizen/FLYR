import { createPublicKey, verify } from "node:crypto";
import { createAdminClient } from "@/lib/supabase/server";

export type DialerContact = {
  id: string;
  user_id: string;
  workspace_id: string | null;
  full_name: string | null;
  phone: string | null;
  email?: string | null;
  address?: string | null;
};

type SupabaseAdmin = ReturnType<typeof createAdminClient>;

type TelnyxAddress = {
  phone_number?: string | null;
  status?: string | null;
};

type TelnyxMessagePayload = {
  id?: string | null;
  direction?: string | null;
  from?: TelnyxAddress | null;
  to?: TelnyxAddress[] | null;
  text?: string | null;
  type?: string | null;
  media?: unknown[] | null;
  errors?: unknown[] | null;
  messaging_profile_id?: string | null;
  sent_at?: string | null;
  received_at?: string | null;
  completed_at?: string | null;
};

export type TelnyxWebhookEvent = {
  data?: {
    id?: string | null;
    event_type?: string | null;
    occurred_at?: string | null;
    payload?: TelnyxMessagePayload | null;
  } | null;
};

function clean(value: string | null | undefined): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

export function normalizePhone(value: string | null | undefined): string | null {
  const trimmed = clean(value);
  if (!trimmed) return null;
  const prefixed = trimmed.startsWith("+") ? `+${trimmed.slice(1).replace(/\D/g, "")}` : trimmed.replace(/\D/g, "");
  if (prefixed.startsWith("+") && prefixed.length > 8) return prefixed;
  if (!prefixed.startsWith("+") && prefixed.length === 10) return `+1${prefixed}`;
  if (!prefixed.startsWith("+") && prefixed.length > 10) return `+${prefixed}`;
  return trimmed;
}

export function telnyxSmsFromNumber(): string | null {
  return (
    clean(process.env.TELNYX_DEFAULT_SMS_FROM_NUMBER) ??
    clean(process.env.TELNYX_DEFAULT_FROM_NUMBER) ??
    clean(process.env.TELNYX_FROM_NUMBER) ??
    clean(process.env.DIALER_CANADA_FROM_NUMBER) ??
    clean(process.env.DIALER_US_FROM_NUMBER)
  );
}

export function telnyxMessagingProfileId(): string | null {
  return clean(process.env.TELNYX_MESSAGING_PROFILE_ID);
}

export function webhookUrl(): string | null {
  const base =
    clean(process.env.NEXT_PUBLIC_APP_URL) ??
    clean(process.env.APP_BASE_URL) ??
    (clean(process.env.VERCEL_URL) ? `https://${clean(process.env.VERCEL_URL)}` : null);
  return base ? `${base.replace(/\/$/, "")}/api/webhooks/telnyx/messages` : null;
}

export function publicMessage(row: Record<string, unknown>) {
  return {
    id: row.id,
    workspaceId: row.workspace_id,
    contactId: row.contact_id,
    direction: row.direction,
    from: row.from_number_e164,
    to: row.to_number_e164,
    body: row.body,
    status: row.status,
    messageType: row.message_type,
    media: row.media,
    error: row.error,
    sentAt: row.sent_at,
    receivedAt: row.received_at,
    completedAt: row.completed_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export async function getContactForWorkspace(
  admin: SupabaseAdmin,
  leadId: string,
  workspaceId: string
): Promise<DialerContact | null> {
  const { data, error } = await admin
    .from("contacts")
    .select("id,user_id,workspace_id,full_name,phone,email,address")
    .eq("id", leadId)
    .maybeSingle();

  if (error) throw error;
  const contact = data as DialerContact | null;
  if (!contact) return null;
  if (contact.workspace_id && contact.workspace_id !== workspaceId) return null;
  return contact;
}

export async function findContactForInbound(
  admin: SupabaseAdmin,
  workspaceId: string,
  fromNumber: string
): Promise<DialerContact | null> {
  const normalized = normalizePhone(fromNumber);
  if (!normalized) return null;

  const digits = normalized.replace(/\D/g, "");
  const variants = Array.from(
    new Set([normalized, digits, digits.length > 10 ? digits.slice(-10) : digits].filter(Boolean))
  );

  const { data, error } = await admin
    .from("contacts")
    .select("id,user_id,workspace_id,full_name,phone,email,address")
    .eq("workspace_id", workspaceId)
    .or(variants.map((value) => `phone.ilike.%${value}%`).join(","))
    .order("updated_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) throw error;
  return (data as DialerContact | null) ?? null;
}

export async function sendTelnyxSms(params: {
  to: string;
  text: string;
  from?: string | null;
}) {
  const apiKey = clean(process.env.TELNYX_API_KEY);
  if (!apiKey) {
    throw new Error("TELNYX_API_KEY is not configured.");
  }

  const from = normalizePhone(params.from) ?? normalizePhone(telnyxSmsFromNumber());
  if (!from) {
    throw new Error("TELNYX_DEFAULT_SMS_FROM_NUMBER or TELNYX_FROM_NUMBER is not configured.");
  }

  const to = normalizePhone(params.to);
  if (!to) {
    throw new Error("A valid destination phone number is required.");
  }

  const body: Record<string, unknown> = {
    from,
    to,
    text: params.text,
  };

  const messagingProfileId = telnyxMessagingProfileId();
  if (messagingProfileId) body.messaging_profile_id = messagingProfileId;

  const callbackUrl = webhookUrl();
  if (callbackUrl) body.webhook_url = callbackUrl;

  const response = await fetch("https://api.telnyx.com/v2/messages", {
    method: "POST",
    headers: {
      Accept: "application/json",
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  const json = await response.json().catch(() => null);
  if (!response.ok) {
    const message =
      json?.errors?.[0]?.detail ??
      json?.errors?.[0]?.title ??
      json?.error ??
      "Telnyx rejected the SMS request.";
    const error = new Error(message);
    (error as Error & { status?: number; telnyx?: unknown }).status = response.status;
    (error as Error & { status?: number; telnyx?: unknown }).telnyx = json;
    throw error;
  }

  return json?.data ?? json;
}

function decodeFlexibleKey(value: string): Buffer | null {
  const trimmed = clean(value);
  if (!trimmed) return null;
  if (/^[0-9a-fA-F]+$/.test(trimmed) && trimmed.length % 2 === 0) {
    return Buffer.from(trimmed, "hex");
  }
  try {
    return Buffer.from(trimmed, "base64");
  } catch {
    return null;
  }
}

function ed25519PublicKey(value: string) {
  const decoded = decodeFlexibleKey(value);
  if (!decoded) return null;
  if (decoded.length === 32) {
    const spkiPrefix = Buffer.from("302a300506032b6570032100", "hex");
    return createPublicKey({
      key: Buffer.concat([spkiPrefix, decoded]),
      format: "der",
      type: "spki",
    });
  }
  return createPublicKey({ key: decoded, format: "der", type: "spki" });
}

export function verifyTelnyxWebhookSignature(params: {
  rawBody: string;
  signature: string | null;
  timestamp: string | null;
  publicKey: string | null | undefined;
}): boolean {
  const publicKeyValue = clean(params.publicKey);
  if (!publicKeyValue) return true;
  if (!params.signature || !params.timestamp) return false;

  const timestampSeconds = Number(params.timestamp);
  if (!Number.isFinite(timestampSeconds)) return false;
  if (Math.abs(Date.now() / 1000 - timestampSeconds) > 5 * 60) return false;

  const signature = decodeFlexibleKey(params.signature);
  if (!signature) return false;

  const key = ed25519PublicKey(publicKeyValue);
  if (!key) return false;

  return verify(
    null,
    Buffer.from(`${params.timestamp}|${params.rawBody}`),
    key,
    signature
  );
}

export function payloadStatus(eventType: string | null | undefined, payload: TelnyxMessagePayload): string {
  const firstToStatus = payload.to?.[0]?.status;
  if (firstToStatus) return firstToStatus;
  if (eventType === "message.received") return "received";
  if (eventType === "message.sent") return "sent";
  if (eventType === "message.finalized") return payload.errors?.length ? "failed" : "finalized";
  return clean(payload.direction) ?? "unknown";
}
