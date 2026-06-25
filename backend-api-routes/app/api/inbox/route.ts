import { NextResponse, type NextRequest } from "next/server";
import { createAdminClient } from "@/lib/supabase/server";
import { resolveDialerWorkspace } from "../dialer/_utils";
import {
  getContactForWorkspace,
  normalizePhone,
  publicMessage,
  sendTelnyxSms,
  telnyxSmsFromNumber,
} from "@/lib/dialer/telnyx-messaging";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type ContactSummary = {
  id: string;
  fullName: string | null;
  phone: string | null;
  email: string | null;
  address: string | null;
};

type InboxEvent = {
  id: string;
  source: "sms" | "email" | "call";
  kind: string;
  direction: "inbound" | "outbound" | null;
  title: string;
  preview: string | null;
  body: string | null;
  status: string;
  occurredAt: string;
  readAt: string | null;
  fromLabel: string | null;
  fromEmail: string | null;
  fromPhone: string | null;
  toLabel: string | null;
  toEmail: string | null;
  toPhone: string | null;
  contactId: string | null;
  href: string | null;
};

type InboxThread = {
  id: string;
  contactId: string | null;
  contact: ContactSummary | null;
  title: string;
  subtitle: string | null;
  primaryPhone: string | null;
  primaryEmail: string | null;
  latestAt: string;
  latestSource: "sms" | "email" | "call";
  latestPreview: string | null;
  unreadCount: number;
  needsResponse: boolean;
  events: InboxEvent[];
};

function clean(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

function sourceParam(value: string | null): "all" | "sms" | "email" | "call" {
  return value === "sms" || value === "email" || value === "call" ? value : "all";
}

function eventTime(row: Record<string, unknown>): string {
  return clean(row.received_at) ?? clean(row.sent_at) ?? clean(row.timestamp) ?? clean(row.created_at) ?? new Date().toISOString();
}

function contactTitle(contact: ContactSummary | null, fallback: string | null): string {
  return (
    clean(contact?.fullName) ??
    clean(contact?.phone) ??
    clean(contact?.email) ??
    clean(contact?.address) ??
    fallback ??
    "Unknown contact"
  );
}

function contactSubtitle(contact: ContactSummary | null): string | null {
  return [clean(contact?.phone), clean(contact?.email), clean(contact?.address)].filter(Boolean).join(" • ") || null;
}

function publicContact(row: Record<string, unknown> | null | undefined): ContactSummary | null {
  if (!row?.id) return null;
  return {
    id: String(row.id),
    fullName: clean(row.full_name),
    phone: clean(row.phone),
    email: clean(row.email),
    address: clean(row.address),
  };
}

function phoneMatchKeys(value: string | null | undefined): string[] {
  const normalized = normalizePhone(value);
  if (!normalized) return [];
  const digits = normalized.replace(/\D/g, "");
  const lastTen = digits.length >= 10 ? digits.slice(-10) : digits;
  return Array.from(new Set([normalized, digits, lastTen].filter(Boolean)));
}

function phoneSearchTerms(value: string | null | undefined): string[] {
  const normalized = normalizePhone(value);
  if (!normalized) return [];
  const digits = normalized.replace(/\D/g, "");
  const lastTen = digits.length >= 10 ? digits.slice(-10) : digits;
  const lastFour = digits.length >= 4 ? digits.slice(-4) : digits;
  return Array.from(new Set([normalized, digits, lastTen, lastFour].filter(Boolean)));
}

function sourceForActivity(type: string | null): "sms" | "email" | "call" | null {
  if (type === "text") return "sms";
  if (type === "email") return "email";
  if (type === "call") return "call";
  return null;
}

async function contactMapForIds(admin: ReturnType<typeof createAdminClient>, workspaceId: string, ids: string[]) {
  const uniqueIds = Array.from(new Set(ids.filter(Boolean)));
  if (!uniqueIds.length) return new Map<string, ContactSummary>();

  const { data, error } = await admin
    .from("contacts")
    .select("id,full_name,phone,email,address,workspace_id")
    .eq("workspace_id", workspaceId)
    .in("id", uniqueIds);

  if (error) throw error;

  return new Map(
    ((data ?? []) as Record<string, unknown>[])
      .map(publicContact)
      .filter((contact): contact is ContactSummary => !!contact)
      .map((contact) => [contact.id, contact])
  );
}

async function contactMapForPhones(admin: ReturnType<typeof createAdminClient>, workspaceId: string, phones: string[]) {
  const variants = Array.from(new Set(phones.flatMap(phoneSearchTerms)));
  if (!variants.length) return new Map<string, ContactSummary>();

  const { data, error } = await admin
    .from("contacts")
    .select("id,full_name,phone,email,address,workspace_id,updated_at")
    .eq("workspace_id", workspaceId)
    .or(variants.map((value) => `phone.ilike.%${value}%`).join(","))
    .order("updated_at", { ascending: false })
    .limit(Math.min(Math.max(variants.length * 3, 25), 500));

  if (error) throw error;

  const contacts = ((data ?? []) as Record<string, unknown>[])
    .map(publicContact)
    .filter((contact): contact is ContactSummary => !!contact);

  const byPhone = new Map<string, ContactSummary>();
  for (const contact of contacts) {
    for (const key of phoneMatchKeys(contact.phone)) {
      if (!byPhone.has(key)) byPhone.set(key, contact);
    }
  }
  return byPhone;
}

function contactForPhone(phoneContacts: Map<string, ContactSummary>, phone: string | null): ContactSummary | null {
  for (const key of phoneMatchKeys(phone)) {
    const contact = phoneContacts.get(key);
    if (contact) return contact;
  }
  return null;
}

function messageEvent(row: Record<string, unknown>, contact: ContactSummary | null): InboxEvent {
  const direction = row.direction === "outbound" ? "outbound" : "inbound";
  const body = clean(row.body);
  const fromPhone = clean(row.from_number_e164);
  const toPhone = clean(row.to_number_e164);
  const contactId = clean(row.contact_id) ?? contact?.id ?? null;

  return {
    id: `sms:${String(row.id)}`,
    source: "sms",
    kind: direction === "inbound" ? "message_inbound" : "message_outbound",
    direction,
    title: direction === "inbound" ? "Incoming message" : "Sent message",
    preview: body,
    body,
    status: clean(row.status) ?? "open",
    occurredAt: eventTime(row),
    readAt: direction === "outbound" ? eventTime(row) : null,
    fromLabel: direction === "inbound" ? contactTitle(contact, fromPhone) : "You",
    fromEmail: null,
    fromPhone,
    toLabel: direction === "outbound" ? contactTitle(contact, toPhone) : "You",
    toEmail: null,
    toPhone,
    contactId,
    href: null,
  };
}

function activityEvent(row: Record<string, unknown>, contact: ContactSummary | null): InboxEvent | null {
  const source = sourceForActivity(clean(row.type));
  if (!source) return null;

  const note = clean(row.note);
  const title = source === "call" ? "Call" : source === "email" ? "Email" : "Message";

  return {
    id: `activity:${String(row.id)}`,
    source,
    kind: `${source}_activity`,
    direction: null,
    title,
    preview: note,
    body: note,
    status: "done",
    occurredAt: eventTime(row),
    readAt: eventTime(row),
    fromLabel: contactTitle(contact, null),
    fromEmail: contact?.email ?? null,
    fromPhone: contact?.phone ?? null,
    toLabel: "You",
    toEmail: null,
    toPhone: null,
    contactId: contact?.id ?? clean(row.contact_id),
    href: null,
  };
}

function callEvent(row: Record<string, unknown>, contact: ContactSummary | null): InboxEvent {
  const fromPhone = clean(row.from_number_e164);
  const toPhone = clean(row.to_number_e164);
  const status = clean(row.status) ?? "missed";
  const occurredAt = clean(row.missed_at) ?? clean(row.ended_at) ?? eventTime(row);
  const title = status === "missed" ? "Missed call" : "Call";
  const contactId = clean(row.contact_id) ?? contact?.id ?? null;

  return {
    id: `call:${String(row.id)}`,
    source: "call",
    kind: status === "missed" ? "missed_call" : "call",
    direction: row.direction === "outbound" ? "outbound" : "inbound",
    title,
    preview: fromPhone ? `From ${contactTitle(contact, fromPhone)}` : title,
    body: fromPhone ? `Missed call from ${fromPhone}` : title,
    status,
    occurredAt,
    readAt: null,
    fromLabel: contactTitle(contact, fromPhone),
    fromEmail: contact?.email ?? null,
    fromPhone,
    toLabel: "You",
    toEmail: null,
    toPhone,
    contactId,
    href: null,
  };
}

function buildThreads(events: InboxEvent[], contacts: Map<string, ContactSummary>): InboxThread[] {
  const groups = new Map<string, InboxEvent[]>();

  for (const event of events) {
    const normalizedPhone = normalizePhone(event.direction === "outbound" ? event.toPhone : event.fromPhone);
    const fallbackKey =
      normalizedPhone ? `phone:${normalizedPhone}` :
      event.fromEmail ? `email:${event.fromEmail.toLowerCase()}` :
      `event:${event.id}`;
    const key = event.contactId ? `contact:${event.contactId}` : fallbackKey;
    groups.set(key, [...(groups.get(key) ?? []), event]);
  }

  return Array.from(groups.entries())
    .map(([key, groupedEvents]) => {
      const sortedEvents = groupedEvents.sort((lhs, rhs) => Date.parse(lhs.occurredAt) - Date.parse(rhs.occurredAt));
      const latest = sortedEvents[sortedEvents.length - 1];
      const contact = latest.contactId ? contacts.get(latest.contactId) ?? null : null;
      const fallbackPhone = normalizePhone(latest.direction === "outbound" ? latest.toPhone : latest.fromPhone);
      const fallbackTitle = fallbackPhone ?? clean(latest.fromEmail) ?? clean(latest.toEmail);
      const primaryPhone = clean(contact?.phone) ?? fallbackPhone;
      const primaryEmail = clean(contact?.email) ?? clean(latest.fromEmail) ?? clean(latest.toEmail);

      return {
        id: latest.contactId ? `contact:${latest.contactId}` : key,
        contactId: latest.contactId,
        contact,
        title: contactTitle(contact, fallbackTitle),
        subtitle: contactSubtitle(contact) ?? primaryPhone ?? primaryEmail,
        primaryPhone,
        primaryEmail,
        latestAt: latest.occurredAt,
        latestSource: latest.source,
        latestPreview: latest.preview ?? latest.body,
        unreadCount: sortedEvents.filter((event) => event.direction === "inbound" && !event.readAt).length,
        needsResponse: latest.source === "sms" && latest.direction === "inbound",
        events: sortedEvents,
      } satisfies InboxThread;
    })
    .sort((lhs, rhs) => Date.parse(rhs.latestAt) - Date.parse(lhs.latestAt));
}

export async function GET(request: NextRequest) {
  try {
    const { response, context } = await resolveDialerWorkspace(request);
    if (response) return response;

    const workspaceId = context!.workspace!.id;
    const admin = createAdminClient();
    const source = sourceParam(request.nextUrl.searchParams.get("source"));
    const contactId = clean(request.nextUrl.searchParams.get("contactId"));
    const limit = Math.min(Math.max(Number(request.nextUrl.searchParams.get("limit") ?? 75) || 75, 1), 200);

    const messageRows: Record<string, unknown>[] = [];
    const activityRows: Record<string, unknown>[] = [];
    const callRows: Record<string, unknown>[] = [];

    if (source === "all" || source === "sms") {
      let query = admin
        .from("dialer_messages")
        .select("*")
        .eq("workspace_id", workspaceId)
        .order("created_at", { ascending: false })
        .limit(limit * 4);
      if (contactId) query = query.eq("contact_id", contactId);
      const { data, error } = await query;
      if (error) throw error;
      messageRows.push(...((data ?? []) as Record<string, unknown>[]));
    }

    if (source === "all" || source === "email" || source === "call") {
      const activityTypes = source === "all" ? ["email", "call"] : [source];
      let query = admin
        .from("contact_activities")
        .select("id,contact_id,type,note,timestamp,created_at,contacts!inner(id,full_name,phone,email,address,workspace_id)")
        .eq("contacts.workspace_id", workspaceId)
        .in("type", activityTypes)
        .order("timestamp", { ascending: false })
        .limit(limit * 4);
      if (contactId) query = query.eq("contact_id", contactId);
      const { data, error } = await query;
      if (error) throw error;
      activityRows.push(...((data ?? []) as Record<string, unknown>[]));
    }

    if (source === "all" || source === "call") {
      let query = admin
        .from("dialer_calls")
        .select("*")
        .eq("workspace_id", workspaceId)
        .eq("direction", "inbound")
        .eq("status", "missed")
        .order("missed_at", { ascending: false, nullsFirst: false })
        .limit(limit * 4);
      if (contactId) query = query.eq("contact_id", contactId);
      const { data, error } = await query;
      if (error) throw error;
      callRows.push(...((data ?? []) as Record<string, unknown>[]));
    }

    const messageContactIds = messageRows.map((row) => clean(row.contact_id)).filter((id): id is string => !!id);
    const callContactIds = callRows.map((row) => clean(row.contact_id)).filter((id): id is string => !!id);
    const activityContacts = activityRows
      .map((row) => publicContact(row.contacts as Record<string, unknown> | null))
      .filter((contact): contact is ContactSummary => !!contact);
    const contacts = await contactMapForIds(admin, workspaceId, [
      ...messageContactIds,
      ...callContactIds,
      ...activityContacts.map((contact) => contact.id),
    ]);
    for (const contact of activityContacts) contacts.set(contact.id, contact);
    const phoneContacts = await contactMapForPhones(admin, workspaceId, [
      ...messageRows.flatMap((row) => [clean(row.from_number_e164), clean(row.to_number_e164)]),
      ...callRows.flatMap((row) => [clean(row.from_number_e164), clean(row.to_number_e164)]),
    ].filter((phone): phone is string => !!phone));
    for (const contact of phoneContacts.values()) contacts.set(contact.id, contact);

    const events = [
      ...messageRows.map((row) => {
        const direction = row.direction === "outbound" ? "outbound" : "inbound";
        const rowContact = clean(row.contact_id) ? contacts.get(String(row.contact_id)) ?? null : null;
        const matchedContact = rowContact ?? contactForPhone(
          phoneContacts,
          direction === "outbound" ? clean(row.to_number_e164) : clean(row.from_number_e164)
        );
        return messageEvent(row, matchedContact);
      }),
      ...callRows.map((row) => {
        const direction = row.direction === "outbound" ? "outbound" : "inbound";
        const rowContact = clean(row.contact_id) ? contacts.get(String(row.contact_id)) ?? null : null;
        const matchedContact = rowContact ?? contactForPhone(
          phoneContacts,
          direction === "outbound" ? clean(row.to_number_e164) : clean(row.from_number_e164)
        );
        return callEvent(row, matchedContact);
      }),
      ...activityRows
        .map((row) => activityEvent(row, publicContact(row.contacts as Record<string, unknown> | null)))
        .filter((event): event is InboxEvent => !!event),
    ];
    const threads = buildThreads(events, contacts).slice(0, limit);
    const items = threads.map((thread) => {
      const latest = thread.events[thread.events.length - 1];
      return {
        ...latest,
        id: latest.id,
        title: thread.title,
        contactId: thread.contactId,
      };
    });

    return NextResponse.json({
      threads,
      items,
      counts: {
        all: threads.length,
        sms: threads.filter((thread) => thread.events.some((event) => event.source === "sms")).length,
        email: threads.filter((thread) => thread.events.some((event) => event.source === "email")).length,
        call: threads.filter((thread) => thread.events.some((event) => event.source === "call")).length,
      },
    });
  } catch (error) {
    console.error("[inbox] GET", error);
    return NextResponse.json({ error: "Failed to load inbox." }, { status: 500 });
  }
}

export async function POST(request: NextRequest) {
  try {
    const { response, context } = await resolveDialerWorkspace(request);
    if (response) return response;

    const payload = await request.json().catch(() => ({}));
    const body = clean(payload.body ?? payload.text ?? payload.message);
    const phone = normalizePhone(clean(payload.phone) ?? clean(payload.to) ?? clean(payload.toPhone));
    const contactId = clean(payload.contactId);

    if (!body) {
      return NextResponse.json({ error: "Message body is required." }, { status: 400 });
    }
    if (body.length > 1600) {
      return NextResponse.json({ error: "Message body is too long." }, { status: 400 });
    }
    if (!phone) {
      return NextResponse.json({ error: "A phone number is required to reply." }, { status: 400 });
    }

    const workspaceId = context!.workspace!.id;
    const admin = createAdminClient();
    const contact = contactId ? await getContactForWorkspace(admin, contactId, workspaceId) : null;
    const sent = await sendTelnyxSms({ to: phone, text: body });
    const now = new Date().toISOString();
    const from = normalizePhone(sent?.from?.phone_number) ?? normalizePhone(telnyxSmsFromNumber())!;
    const providerMessageId = sent?.id ?? null;
    const status = sent?.to?.[0]?.status ?? "queued";
    const optimisticMessage = {
      id: providerMessageId,
      workspace_id: workspaceId,
      contact_id: contact?.id ?? null,
      direction: "outbound",
      from_number_e164: from,
      to_number_e164: phone,
      body,
      message_type: sent?.type ?? "SMS",
      status,
      media: sent?.media ?? [],
      error: sent?.errors?.length ? sent.errors : null,
      sent_at: sent?.sent_at ?? now,
      received_at: null,
      completed_at: null,
      created_at: now,
      updated_at: now,
    };

    const { data, error } = await admin
      .from("dialer_messages")
      .upsert(
        {
          workspace_id: workspaceId,
          contact_id: contact?.id ?? null,
          sender_user_id: context!.user.id,
          provider: "telnyx",
          provider_message_id: providerMessageId,
          direction: "outbound",
          from_number_e164: from,
          to_number_e164: phone,
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
      console.warn("[inbox] reply storage failed", error.message);
      return NextResponse.json({
        message: publicMessage(optimisticMessage),
        warning: "Text sent, but message history is unavailable.",
      });
    }

    if (contact?.id) {
      await admin
        .from("contact_activities")
        .insert({
          contact_id: contact.id,
          type: "text",
          note: body,
          timestamp: now,
        })
        .then(({ error }) => {
          if (error) console.warn("[inbox] reply contact activity failed", error.message);
        });
    }

    return NextResponse.json({
      message: publicMessage(data as Record<string, unknown>),
      warning: sent?.errors?.length ? "Text queued with Telnyx warnings." : null,
    });
  } catch (error) {
    console.error("[inbox] POST", error);
    const status = (error as Error & { status?: number }).status ?? 500;
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Failed to send text message." },
      { status }
    );
  }
}

export async function PATCH(request: NextRequest) {
  try {
    const { response, context } = await resolveDialerWorkspace(request);
    if (response) return response;

    const payload = await request.json().catch(() => ({}));
    const id = clean(payload.id);
    const status = clean(payload.status);

    if (id?.startsWith("sms:") && status) {
      const messageId = id.slice(4);
      await createAdminClient()
        .from("dialer_messages")
        .update({ status })
        .eq("workspace_id", context!.workspace!.id)
        .eq("id", messageId)
        .throwOnError();
    }

    return NextResponse.json({ ok: true });
  } catch (error) {
    console.error("[inbox] PATCH", error);
    return NextResponse.json({ error: "Failed to update inbox item." }, { status: 500 });
  }
}
