import { communicationNumberOwner } from '@/lib/sales-pro/communication-owner';
import { NextResponse, type NextRequest } from "next/server";
import { createAdminClient } from "@/lib/supabase/server";
import { findContactForInbound, normalizePhone } from "@/lib/dialer/telnyx-messaging";
import { resolveDialerWorkspace } from "../_utils";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function clean(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

function iso(value: unknown): string | null {
  const text = clean(value);
  if (!text) return null;
  const date = new Date(text);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function normalizedDirection(value: unknown): "inbound" | "outbound" {
  return clean(value) === "outbound" ? "outbound" : "inbound";
}

function normalizedStatus(value: unknown, direction: "inbound" | "outbound"): string {
  const status = clean(value)?.toLowerCase();
  if (status) return status;
  return direction === "inbound" ? "missed" : "completed";
}

export async function POST(request: NextRequest) {
  try {
    const { response, context } = await resolveDialerWorkspace(request);
    if (response) return response;

    const body = await request.json().catch(() => ({}));
    const workspaceId = context!.workspace!.id;
    const direction = normalizedDirection(body.direction);
    const status = normalizedStatus(body.status, direction);
    const from = normalizePhone(clean(body.from) ?? clean(body.fromNumber) ?? clean(body.from_number_e164));
    const to = normalizePhone(clean(body.to) ?? clean(body.toNumber) ?? clean(body.to_number_e164));
    const providerCallId = clean(body.providerCallId) ?? clean(body.callId) ?? clean(body.provider_call_id);
    const endedAt = iso(body.endedAt) ?? iso(body.ended_at) ?? new Date().toISOString();
    const answeredAt = iso(body.answeredAt) ?? iso(body.answered_at);
    const startedAt = iso(body.startedAt) ?? iso(body.started_at) ?? endedAt;
    const missedAt = status === "missed" ? endedAt : null;

    if (!providerCallId) {
      return NextResponse.json({ error: "providerCallId is required." }, { status: 400 });
    }

    if (direction === "inbound" && !from) {
      return NextResponse.json({ error: "Inbound calls require a caller number." }, { status: 400 });
    }

    const admin = createAdminClient();
    const numberOwner = await communicationNumberOwner(admin, direction === "inbound" ? to : from);
    if (numberOwner?.workspaceId !== workspaceId || numberOwner?.userId !== context!.user.id) {
      return NextResponse.json({ error: "Call number is not assigned to you." }, { status: 403 });
    }
    const contact = direction === "inbound" && from
      ? await findContactForInbound(admin, workspaceId, from, context!.user.id)
      : null;

    const row = {
      workspace_id: workspaceId,
      contact_id: contact?.id ?? null,
      user_id: context!.user.id,
      provider: "telnyx",
      provider_call_id: providerCallId,
      direction,
      from_number_e164: from,
      to_number_e164: to,
      status,
      disposition: clean(body.disposition),
      started_at: startedAt,
      answered_at: answeredAt,
      ended_at: endedAt,
      missed_at: missedAt,
      raw_payload: body,
    };

    // Ignore a conflicting provider ID before updating through the owner scope.
    // A client-supplied call ID must never let a user take over someone else's row.
    const inserted = await admin.from("dialer_calls")
      .upsert(row, { onConflict: "provider,provider_call_id", ignoreDuplicates: true })
      .select("*").maybeSingle();
    if (inserted.error) throw inserted.error;
    const { data, error } = inserted.data ? inserted : await admin.from("dialer_calls")
      .update(row).eq("workspace_id", workspaceId).eq("user_id", context!.user.id)
      .eq("provider", "telnyx").eq("provider_call_id", providerCallId).select("*").maybeSingle();
    if (!error && !data) return NextResponse.json({ error: "Call not found." }, { status: 404 });

    if (error) throw error;

    if (contact?.id && status === "missed") {
      await admin
        .from("contact_activities")
        .insert({
          communication_owner_user_id: context!.user.id,
          contact_id: contact.id,
          type: "call",
          note: `Missed call from ${from}`,
          timestamp: endedAt,
        })
        .then(({ error }) => {
          if (error) console.warn("[dialer/calls] contact activity failed", error.message);
        });
    }

    return NextResponse.json({ call: data });
  } catch (error) {
    console.error("[dialer/calls] POST", error);
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Failed to save call." },
      { status: 500 }
    );
  }
}
