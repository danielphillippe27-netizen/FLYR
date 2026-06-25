import { NextResponse, type NextRequest } from "next/server";
import { createAdminClient } from "@/lib/supabase/server";
import { resolveDialerWorkspace } from "../../../_utils";
import {
  getContactForWorkspace,
  normalizePhone,
  publicMessage,
  sendTelnyxSms,
  telnyxSmsFromNumber,
} from "@/lib/dialer/telnyx-messaging";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type RouteContext = {
  params: Promise<{ leadId: string }>;
};

function cleanBody(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

function outboundMessageFromTelnyx(params: {
  workspaceId: string;
  contactId: string | null;
  from: string;
  to: string;
  body: string;
  sent: Awaited<ReturnType<typeof sendTelnyxSms>>;
  now: string;
}) {
  return {
    id: params.sent?.id ?? null,
    workspace_id: params.workspaceId,
    contact_id: params.contactId,
    direction: "outbound",
    from_number_e164: params.from,
    to_number_e164: params.to,
    body: params.body,
    message_type: params.sent?.type ?? "SMS",
    status: params.sent?.to?.[0]?.status ?? "queued",
    media: params.sent?.media ?? [],
    error: params.sent?.errors?.length ? params.sent.errors : null,
    sent_at: params.sent?.sent_at ?? params.now,
    received_at: null,
    completed_at: null,
    created_at: params.now,
    updated_at: params.now,
  };
}

async function resolveLead(request: NextRequest, leadId: string, options?: { allowMissing?: boolean }) {
  const { response, context } = await resolveDialerWorkspace(request);
  if (response) return { response, context: null, contact: null };

  const admin = createAdminClient();
  const contact = await getContactForWorkspace(admin, leadId, context!.workspace!.id);
  if (!contact && !options?.allowMissing) {
    return {
      response: NextResponse.json({ error: "Dialer lead was not found." }, { status: 404 }),
      context: null,
      contact: null,
    };
  }

  return { response: null, context, contact };
}

export async function GET(request: NextRequest, routeContext: RouteContext) {
  try {
    const { leadId } = await routeContext.params;
    const resolved = await resolveLead(request, leadId);
    if (resolved.response) return resolved.response;

    const admin = createAdminClient();
    const { data, error } = await admin
      .from("dialer_messages")
      .select("*")
      .eq("workspace_id", resolved.context!.workspace!.id)
      .eq("contact_id", resolved.contact!.id)
      .order("created_at", { ascending: false })
      .limit(100);

    if (error) throw error;
    return NextResponse.json({
      messages: ((data ?? []) as Record<string, unknown>[]).map(publicMessage).reverse(),
    });
  } catch (error) {
    console.error("[dialer/leads/sms] GET", error);
    return NextResponse.json(
      { error: "Failed to load text history." },
      { status: 500 }
    );
  }
}

export async function POST(request: NextRequest, routeContext: RouteContext) {
  try {
    const { leadId } = await routeContext.params;
    const payload = await request.json().catch(() => ({}));
    const body = cleanBody(payload.body ?? payload.text ?? payload.message);
    if (!body) {
      return NextResponse.json({ error: "Message body is required." }, { status: 400 });
    }
    if (body.length > 1600) {
      return NextResponse.json({ error: "Message body is too long." }, { status: 400 });
    }

    const resolved = await resolveLead(request, leadId, { allowMissing: true });
    if (resolved.response) return resolved.response;

    const fallbackPhone = typeof payload.phone === "string" ? payload.phone : null;
    const to = normalizePhone(resolved.contact?.phone ?? fallbackPhone);
    if (!to) {
      return NextResponse.json(
        { error: "Dialer lead needs a valid phone number before texting." },
        { status: 400 }
      );
    }

    const sent = await sendTelnyxSms({ to, text: body });
    const now = new Date().toISOString();
    const from = normalizePhone(sent?.from?.phone_number) ?? normalizePhone(telnyxSmsFromNumber())!;
    const providerMessageId = sent?.id ?? null;
    const status = sent?.to?.[0]?.status ?? "queued";
    const optimisticMessage = outboundMessageFromTelnyx({
      workspaceId: resolved.context!.workspace!.id,
      contactId: resolved.contact?.id ?? null,
      from,
      to,
      body,
      sent,
      now,
    });

    if (!resolved.contact) {
      return NextResponse.json({
        message: publicMessage(optimisticMessage),
        warning: sent?.errors?.length ? "Text queued with Telnyx warnings." : null,
      });
    }

    const admin = createAdminClient();
    const { data, error } = await admin
      .from("dialer_messages")
      .upsert(
        {
          workspace_id: resolved.context!.workspace!.id,
          contact_id: resolved.contact.id,
          sender_user_id: resolved.context!.user.id,
          provider: "telnyx",
          provider_message_id: providerMessageId,
          direction: "outbound",
          from_number_e164: from,
          to_number_e164: to,
          body,
          message_type: sent?.type ?? "SMS",
          status,
          media: sent?.media ?? [],
          error: sent?.errors?.length ? sent.errors : null,
          raw_payload: sent,
          sent_at: sent?.sent_at ?? now,
        },
        { onConflict: "provider,provider_message_id", ignoreDuplicates: false }
      )
      .select("*")
      .single();

    if (error) {
      console.warn("[dialer/leads/sms] message storage failed", error.message);
      return NextResponse.json({
        message: publicMessage(optimisticMessage),
        warning: "Text sent, but message history is unavailable.",
      });
    }

    await admin
      .from("contact_activities")
      .insert({
        contact_id: resolved.contact.id,
        type: "text",
        note: body,
        timestamp: now,
      })
      .then(({ error }) => {
        if (error) console.warn("[dialer/leads/sms] contact activity failed", error.message);
      });

    return NextResponse.json({
      message: publicMessage(data as Record<string, unknown>),
      warning: sent?.errors?.length ? "Text queued with Telnyx warnings." : null,
    });
  } catch (error) {
    console.error("[dialer/leads/sms] POST", error);
    const status = (error as Error & { status?: number }).status ?? 500;
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Failed to send text message." },
      { status }
    );
  }
}
