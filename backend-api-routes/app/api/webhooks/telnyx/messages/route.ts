import { communicationNumberOwner } from '@/lib/sales-pro/communication-owner';
import { NextResponse, type NextRequest } from "next/server";
import { createAdminClient } from "@/lib/supabase/server";
import {
  findContactForInbound,
  normalizePhone,
  payloadStatus,
  verifyTelnyxWebhookSignature,
  type TelnyxWebhookEvent,
} from "@/lib/dialer/telnyx-messaging";
import { appendCommunication } from "@/lib/sales-pro/communications";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function clean(value: string | null | undefined): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

function configuredWorkspaceId(): string | null {
  const value = clean(process.env.TELNYX_DEFAULT_WORKSPACE_ID) ?? clean(process.env.DIALER_ENABLED_WORKSPACE_IDS);
  return value?.split(/[\n,]/)[0]?.trim() || null;
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
    const event = JSON.parse(rawBody) as TelnyxWebhookEvent;
    const data = event.data;
    const payload = data?.payload;
    const eventType = data?.event_type ?? null;
    if (!data?.id || !payload?.id || !eventType) {
      return NextResponse.json({ ok: true, ignored: true });
    }

    if (!["message.received", "message.sent", "message.finalized"].includes(eventType)) {
      return NextResponse.json({ ok: true, ignored: true });
    }

    const from = normalizePhone(payload.from?.phone_number);
    const to = normalizePhone(payload.to?.[0]?.phone_number);
    if (!from || !to) {
      return NextResponse.json({ ok: true, ignored: true, reason: "missing numbers" });
    }

    const admin = createAdminClient();
    const direction = payload.direction === "inbound" || eventType === "message.received" ? "inbound" : "outbound";
    const numberOwner = await communicationNumberOwner(admin, direction === "inbound" ? to : from);
    const workspaceId = numberOwner?.workspaceId ?? configuredWorkspaceId();
    if (!workspaceId) {
      console.warn("[telnyx/webhook] TELNYX_DEFAULT_WORKSPACE_ID or DIALER_ENABLED_WORKSPACE_IDS is required.");
      return NextResponse.json({ ok: true, ignored: true, reason: "workspace not configured" });
    }




    const { data: existingMessage, error: existingError } = await admin.from("dialer_messages")
      .select("sender_user_id").eq("workspace_id", workspaceId).eq("provider", "telnyx")
      .eq("provider_message_id", payload.id).maybeSingle();
    if (existingError) throw existingError;
    const ownerUserId = existingMessage?.sender_user_id ?? numberOwner?.userId ?? null;
    const contact =
      direction === "inbound"
        ? await findContactForInbound(admin, workspaceId, from, ownerUserId)
        : null;
    const row = {
      workspace_id: workspaceId,
      sender_user_id: ownerUserId,
      contact_id: contact?.id ?? null,
      provider: "telnyx",
      provider_message_id: payload.id,
      last_provider_event_id: data.id,
      direction,
      from_number_e164: from,
      to_number_e164: to,
      body: payload.text ?? "",
      message_type: payload.type ?? "SMS",
      status: payloadStatus(eventType, payload),
      media: payload.media ?? [],
      error: payload.errors?.length ? payload.errors : null,
      raw_payload: event,
      sent_at: payload.sent_at ?? null,
      received_at: payload.received_at ?? (direction === "inbound" ? data.occurred_at ?? null : null),
      completed_at: payload.completed_at ?? null,
    };

    await admin
      .from("dialer_messages")
      .upsert(row, { onConflict: "provider,provider_message_id", ignoreDuplicates: false })
      .throwOnError();

    const participant = direction === "inbound" ? from : to;
    const { data: salesContact } = ownerUserId ? await admin.from("sales_contacts")
      .select("id").eq("workspace_id", workspaceId).eq("owner_user_id", ownerUserId).eq("phone_e164", participant).is("merged_into_id", null).maybeSingle() : { data: null };
    const { data: salesLead } = salesContact ? await admin.from("sales_leads")
      .select("id,assigned_user_id").eq("workspace_id", workspaceId).eq("assigned_user_id", ownerUserId).eq("sales_contact_id", salesContact.id).order("updated_at", { ascending: false }).limit(1).maybeSingle()
      : { data: null };
    await appendCommunication(admin, {
      workspaceId, contactId: salesContact?.id ?? null, leadId: salesLead?.id ?? null, actorUserId: ownerUserId,
      channel: "sms", direction, eventKind: eventType, provider: "telnyx",
      providerEventId: data.id, providerThreadId: payload.id, body: payload.text ?? "",
      fromAddress: from, toAddresses: [to], status: payloadStatus(eventType, payload),
      occurredAt: payload.received_at ?? payload.sent_at ?? data.occurred_at ?? undefined,
      attachments: payload.media ?? [], metadata: { ownershipVerified: true, providerMessageId: payload.id },
    });
    if (direction === "inbound" && salesContact && /^(stop|stopall|unsubscribe|cancel|end|quit)$/i.test((payload.text ?? "").trim())) {
      await admin.from("sales_communication_preferences").upsert({ workspace_id: workspaceId, sales_contact_id: salesContact.id, channel: "sms", status: "unsubscribed", source: "telnyx_keyword" }, { onConflict: "sales_contact_id,channel" });
      if (salesLead) await admin.from("sales_sequence_enrollments").update({ status: "stopped", stop_reason: "sms_unsubscribe" }).eq("sales_lead_id", salesLead.id).in("status", ["active", "paused"]);
    }

    if (direction === "inbound" && contact?.id) {
      await admin
        .from("contact_activities")
        .insert({
          communication_owner_user_id: ownerUserId,
          contact_id: contact.id,
          type: "text",
          note: payload.text ?? "Inbound text received.",
          timestamp: payload.received_at ?? data.occurred_at ?? new Date().toISOString(),
        })
        .then(({ error }) => {
          if (error) console.warn("[telnyx/webhook] contact activity failed", error.message);
        });
    }

    return NextResponse.json({ ok: true });
  } catch (error) {
    console.error("[telnyx/webhook]", error);
    return NextResponse.json({ error: "Failed to process Telnyx webhook." }, { status: 500 });
  }
}

export async function GET() {
  return NextResponse.json({
    ok: true,
    provider: "telnyx",
    events: ["message.received", "message.sent", "message.finalized"],
  });
}
