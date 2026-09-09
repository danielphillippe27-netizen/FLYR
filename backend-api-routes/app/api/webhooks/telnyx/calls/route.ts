import { communicationNumberOwner } from '@/lib/sales-pro/communication-owner';
import { NextResponse, type NextRequest } from "next/server";
import { createAdminClient } from "@/lib/supabase/server";
import {
  findContactForInbound,
  normalizePhone,
  verifyTelnyxWebhookSignature,
} from "@/lib/dialer/telnyx-messaging";
import { appendCommunication } from "@/lib/sales-pro/communications";
import { decodeTelnyxClientState, deleteTelnyxCallRecording, startTelnyxCallRecording } from "@/lib/dialer/telnyx";

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
  return direction === "outbound" || direction === "outgoing" ? "outbound" : "inbound";
}

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" ? value as Record<string, unknown> : {};
}

function numberFrom(value: unknown): number | null {
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function secondsBetween(start: string | null, end: string | null): number | null {
  if (!start || !end) return null;
  const duration = new Date(end).getTime() - new Date(start).getTime();
  return Number.isFinite(duration) && duration >= 0 ? Math.round(duration / 1000) : null;
}

function recordingFromEvent(
  eventType: string,
  payload: Record<string, unknown>,
  occurredAt: string
): Record<string, unknown> | null {
  if (!eventType.includes("recording")) return null;
  const recordingUrls = record(payload.recording_urls);
  const publicRecordingUrls = record(payload.public_recording_urls);
  const mp3Url = clean(recordingUrls.mp3) ?? clean(publicRecordingUrls.mp3);
  const wavUrl = clean(recordingUrls.wav) ?? clean(publicRecordingUrls.wav);
  const startedAt = clean(payload.recording_started_at) ?? clean(payload.start_time);
  const endedAt = clean(payload.recording_ended_at) ?? clean(payload.end_time);
  const durationMillis = numberFrom(payload.duration_millis);
  const durationSeconds = durationMillis == null
    ? secondsBetween(startedAt, endedAt)
    : Math.round(durationMillis / 1000);
  const channelValue = payload.channels === "dual" ? 2 : payload.channels === "single" ? 1 : numberFrom(payload.channels);
  const failed = eventType.includes("error") || eventType.includes("failed");

  return {
    recordingSid: clean(payload.recording_id) ?? clean(payload.id) ?? `telnyx-${occurredAt}`,
    recordingUrl: mp3Url ?? wavUrl,
    mp3Url,
    wavUrl,
    provider: "telnyx",
    status: failed ? "failed" : eventType.includes("saved") ? "completed" : "pending",
    durationSeconds,
    channels: channelValue,
    updatedAt: occurredAt,
    errorCode: clean(payload.error_code) ?? clean(payload.code),
    callControlId: clean(payload.call_control_id),
    callLegId: clean(payload.call_leg_id),
    callSessionId: clean(payload.call_session_id),
    recording_urls: recordingUrls,
    public_recording_urls: publicRecordingUrls,
  };
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

    const direction = directionFor(payload);
    const from = normalizePhone(stringFromAny(payload, ["from", "from_number", "caller_id_number"]));
    const to = normalizePhone(stringFromAny(payload, ["to", "to_number", "destination_number"]));
    const admin = createAdminClient();
    const numberOwner = await communicationNumberOwner(admin, direction === "inbound" ? to : from);
    const workspaceId = numberOwner?.workspaceId ?? configuredWorkspaceId();
    if (!workspaceId) return NextResponse.json({ ok: true, ignored: true, reason: "unknown destination" });
    const status = eventStatus(eventType, payload);
    const occurredAt = clean(data.occurred_at) ?? new Date().toISOString();
    const answeredAt = status === "answered" ? occurredAt : clean(payload.answered_at);
    const endedAt = ["missed", "completed", "failed"].includes(status) ? occurredAt : clean(payload.ended_at);
    const missedAt = direction === "inbound" && status === "missed" ? occurredAt : null;



    const decodedClientState = decodeTelnyxClientState(payload.client_state);
    const decodedClientStateRecord = decodedClientState as Record<string, unknown>;
    const callRequestId = clean(decodedClientState.callRequestId) ?? clean(decodedClientStateRecord.call_request_id);
    const providerIds = [
      clean(payload.call_control_id),
      clean(payload.call_session_id),
      clean(payload.call_leg_id),
    ].filter((value): value is string => Boolean(value));
    const findDialerCall = async (column: string, value: string) => {
      const { data: row, error } = await admin
        .from("dialer_calls")
        .select("*")
        .eq("workspace_id", workspaceId)
        .eq(column, value)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (error) throw error;
      return row ? row as Record<string, unknown> : null;
    };

    let dialerCall = callRequestId ? await findDialerCall("call_request_id", callRequestId) : null;
    for (const id of providerIds) {
      if (dialerCall) break;
      dialerCall = await findDialerCall("provider_call_id", id);
      if (!dialerCall) dialerCall = await findDialerCall("provider_parent_call_id", id);
    }

    const ownerUserId = clean(dialerCall?.user_id) ?? numberOwner?.userId ?? null;
    const contact = direction === "inbound" && from
      ? await findContactForInbound(admin, workspaceId, from, ownerUserId)
      : null;
    const recording = recordingFromEvent(eventType, payload, occurredAt);
    let recordingWasDiscarded = false;
    if (dialerCall) {
      const existingPayload = record(dialerCall.status_payload);
      const retention = clean(existingPayload.contentRetention) ?? clean(existingPayload.content_retention);
      recordingWasDiscarded = Boolean(recording && retention === "discard");
      const recordingIdToDiscard = clean(recording?.recordingSid);
      if (recordingWasDiscarded && recordingIdToDiscard) {
        await deleteTelnyxCallRecording(recordingIdToDiscard);
      }
      const allowedStatuses = new Set([
        "pending", "initiated", "ringing", "in-progress", "answered", "completed",
        "busy", "failed", "no-answer", "canceled",
      ]);
      const normalizedDialerStatus = status === "missed" ? "no-answer" : status;
      const updates: Record<string, unknown> = {
        telecom_provider: "telnyx",
        provider_call_id: clean(payload.call_control_id) ?? dialerCall.provider_call_id ?? providerIds[0] ?? null,
        provider_parent_call_id: clean(payload.call_session_id) ?? dialerCall.provider_parent_call_id ?? null,
        from_number_e164: from ?? dialerCall.from_number_e164 ?? null,
        to_number_e164: to ?? dialerCall.to_number_e164 ?? null,
        status_payload: {
          ...existingPayload,
          telnyxLastEvent: event,
          ...(recording && !recordingWasDiscarded ? { recording } : {}),
          ...(recordingWasDiscarded ? { recordingDiscardedAt: occurredAt } : {}),
        },
        updated_at: occurredAt,
      };
      if (allowedStatuses.has(normalizedDialerStatus)) updates.status = normalizedDialerStatus;
      if (answeredAt) updates.answered_at = answeredAt;
      if (endedAt) updates.ended_at = endedAt;
      const duration = secondsBetween(
        clean(dialerCall.answered_at) ?? answeredAt,
        endedAt
      );
      if (duration != null) updates.duration_seconds = duration;

      await admin.from("dialer_calls").update(updates).eq("id", dialerCall.id).throwOnError();

      const callControlId = clean(payload.call_control_id);
      if (eventType === "call.answered" && callControlId) {
        await startTelnyxCallRecording(callControlId, {
          commandId: `${callRequestId ?? String(dialerCall.id)}:content-recording`,
          clientState: clean(payload.client_state),
        }).catch((error) => {
          console.warn("[telnyx/calls] unable to start content recording", error);
        });
      }
    } else {
      await admin
        .from("dialer_calls")
        .upsert(
          {
            workspace_id: workspaceId,
            user_id: ownerUserId,
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
    }

    const participant = direction === "inbound" ? from : to;
    const { data: salesContact } = participant && ownerUserId ? await admin.from("sales_contacts")
      .select("id").eq("workspace_id", workspaceId).eq("owner_user_id", ownerUserId).eq("phone_e164", participant).is("merged_into_id", null).maybeSingle()
      : { data: null };
    const { data: salesLead } = salesContact ? await admin.from("sales_leads")
      .select("id,assigned_user_id").eq("workspace_id", workspaceId).eq("assigned_user_id", ownerUserId).eq("sales_contact_id", salesContact.id).order("updated_at", { ascending: false }).limit(1).maybeSingle()
      : { data: null };
    const recordingUrls = record(payload.recording_urls);
    const publicRecordingUrls = record(payload.public_recording_urls);
    const recordingUrl = recordingWasDiscarded
      ? null
      : (
          clean(payload.recording_url)
          ?? clean(recordingUrls.mp3)
          ?? clean(publicRecordingUrls.mp3)
          ?? clean(recordingUrls.wav)
          ?? clean(publicRecordingUrls.wav)
        );
    const isVoicemail = eventType.includes("voicemail");
    await appendCommunication(admin, {
      workspaceId, contactId: salesContact?.id ?? null, leadId: salesLead?.id ?? null, actorUserId: ownerUserId,
      channel: isVoicemail ? "voicemail" : "call", direction,
      eventKind: isVoicemail ? "voicemail_received" : eventType, provider: "telnyx",
      providerEventId: data.id, providerThreadId: providerCallId(payload, data.id),
      body: isVoicemail ? "New voicemail" : `${direction} call: ${status}`,
      fromAddress: from, toAddresses: to ? [to] : [], status, occurredAt,
      attachments: recordingUrl ? [{ type: "audio", url: recordingUrl }] : [],
      metadata: { ownershipVerified: true, providerCallId: providerCallId(payload, data.id), recordingUrl, transcriptionStatus: isVoicemail ? "pending" : null },
    });

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
    events: ["call.initiated", "call.answered", "call.hangup", "call.recording.saved", "call.recording.error"],
  });
}
