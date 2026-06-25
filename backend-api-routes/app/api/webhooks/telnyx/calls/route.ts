import { NextResponse, type NextRequest } from "next/server";
import { createAdminClient } from "@/lib/supabase/server";
import {
  findContactForInbound,
  normalizePhone,
  verifyTelnyxWebhookSignature,
} from "@/lib/dialer/telnyx-messaging";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type TelnyxCallWebhookEvent = {
  data?: {
    id?: string | null;
    event_type?: string | null;
    occurred_at?: string | null;
    payload?: Record<string, unknown> | null;
  } | null;
};

function clean(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

function configuredWorkspaceId(): string | null {
  const value = clean(process.env.TELNYX_DEFAULT_WORKSPACE_ID) ?? clean(process.env.DIALER_ENABLED_WORKSPACE_IDS);
  return value?.split(/[\n,]/)[0]?.trim() || null;
}

function stringFromAny(payload: Record<string, unknown>, keys: string[]): string | null {
  for (const key of keys) {
    const direct = clean(payload[key]);
    if (direct) return direct;
    const nested = payload[key] as Record<string, unknown> | null | undefined;
    const phone = clean(nested?.phone_number) ?? clean(nested?.number);
    if (phone) return phone;
  }
  return null;
}

function providerCallId(payload: Record<string, unknown>, eventId: string): string {
  return (
    clean(payload.call_control_id) ??
    clean(payload.call_session_id) ??
    clean(payload.call_leg_id) ??
    clean(payload.call_id) ??
    eventId
  );
}

function eventStatus(eventType: string, payload: Record<string, unknown>): string {
  const status = clean(payload.status)?.toLowerCase();
  if (status) return status;
  const hangupCause = clean(payload.hangup_cause)?.toLowerCase() ?? clean(payload.cause)?.toLowerCase();
  if (eventType.includes("answered")) return "answered";
  if (eventType.includes("hangup") || eventType.includes("ended")) {
    if (hangupCause?.includes("no_answer") || hangupCause?.includes("timeout") || hangupCause?.includes("unanswered")) {
      return "missed";
    }
    return "completed";
  }
  if (eventType.includes("initiated") || eventType.includes("ringing")) return "ringing";
  return "open";
}

function directionFor(payload: Record<string, unknown>): "inbound" | "outbound" {
  const direction = clean(payload.direction)?.toLowerCase();
  return direction === "outbound" ? "outbound" : "inbound";
}

export async function POST(request: NextRequest) {
  const rawBody = await request.text();
  const verified = verifyTelnyxWebhookSignature({
    rawBody,
    signature: request.headers.get("telnyx-signature-ed25519"),
    timestamp: request.headers.get("telnyx-timestamp"),
    publicKey: process.env.TELNYX_PUBLIC_KEY,
  });

  if (!verified) {
    return NextResponse.json({ error: "Invalid Telnyx webhook signature." }, { status: 403 });
  }

  try {
    const event = JSON.parse(rawBody) as TelnyxCallWebhookEvent;
    const data = event.data;
    const payload = data?.payload ?? null;
    const eventType = data?.event_type ?? null;
    if (!data?.id || !eventType || !payload) {
      return NextResponse.json({ ok: true, ignored: true });
    }

    if (!eventType.startsWith("call.")) {
      return NextResponse.json({ ok: true, ignored: true });
    }

    const workspaceId = configuredWorkspaceId();
    if (!workspaceId) {
      console.warn("[telnyx/calls] TELNYX_DEFAULT_WORKSPACE_ID or DIALER_ENABLED_WORKSPACE_IDS is required.");
      return NextResponse.json({ ok: true, ignored: true, reason: "workspace not configured" });
    }

    const direction = directionFor(payload);
    const from = normalizePhone(stringFromAny(payload, ["from", "from_number", "caller_id_number"]));
    const to = normalizePhone(stringFromAny(payload, ["to", "to_number", "destination_number"]));
    const status = eventStatus(eventType, payload);
    const occurredAt = clean(data.occurred_at) ?? new Date().toISOString();
    const answeredAt = status === "answered" ? occurredAt : clean(payload.answered_at);
    const endedAt = ["missed", "completed", "failed"].includes(status) ? occurredAt : clean(payload.ended_at);
    const missedAt = direction === "inbound" && status === "missed" ? occurredAt : null;

    const admin = createAdminClient();
    const contact = direction === "inbound" && from
      ? await findContactForInbound(admin, workspaceId, from)
      : null;

    await admin
      .from("dialer_calls")
      .upsert(
        {
          workspace_id: workspaceId,
          contact_id: contact?.id ?? null,
          provider: "telnyx",
          provider_call_id: providerCallId(payload, data.id),
          direction,
          from_number_e164: from,
          to_number_e164: to,
          status,
          started_at: clean(payload.started_at) ?? occurredAt,
          answered_at: answeredAt,
          ended_at: endedAt,
          missed_at: missedAt,
          raw_payload: event,
        },
        { onConflict: "provider,provider_call_id", ignoreDuplicates: false }
      )
      .throwOnError();

    return NextResponse.json({ ok: true });
  } catch (error) {
    console.error("[telnyx/calls]", error);
    return NextResponse.json({ error: "Failed to process Telnyx call webhook." }, { status: 500 });
  }
}

export async function GET() {
  return NextResponse.json({
    ok: true,
    provider: "telnyx",
    events: ["call.initiated", "call.answered", "call.hangup"],
  });
}
