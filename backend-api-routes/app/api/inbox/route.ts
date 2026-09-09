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
import { appendCommunication, sendManagedEmail, sendManagedSms } from "@/lib/sales-pro/communications";
import { syncICloudInbox } from "@/lib/email/icloud-sync";
import { counterpartyEmail, replyEmailForEvents } from "@/lib/email/thread-identity";
import { getSalespersonSmsFromNumber } from "@/lib/dialer/salesperson-settings";

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
  source: string;
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
  attachments: InboxAttachment[];
};

type InboxAttachment = {
  url: string;
  mimeType: string;
  fileName: string | null;
  storagePath: string | null;
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
  latestSource: string;
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

function inboxAttachments(value: unknown): InboxAttachment[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item): InboxAttachment[] => {
    if (typeof item === "string") {
      const url = clean(item);
      return url ? [{ url, mimeType: "application/octet-stream", fileName: null, storagePath: null }] : [];
    }
    if (!item || typeof item !== "object") return [];
    const row = item as Record<string, unknown>;
    const url = clean(row.url) ?? clean(row.media_url) ?? clean(row.content_url);
    if (!url) return [];
    return [{
      url,
      mimeType: clean(row.mimeType) ?? clean(row.mime_type) ?? clean(row.content_type) ?? "application/octet-stream",
      fileName: clean(row.fileName) ?? clean(row.file_name) ?? null,
      storagePath: clean(row.storagePath) ?? clean(row.storage_path) ?? null,
    }];
  });
}

async function refreshedInboxAttachments(
  admin: ReturnType<typeof createAdminClient>,
  value: unknown
): Promise<InboxAttachment[]> {
  return Promise.all(inboxAttachments(value).map(async (attachment) => {
    if (!attachment.storagePath) return attachment;
    const { data } = await admin.storage.from("message-media").createSignedUrl(attachment.storagePath, 60 * 60);
    return data?.signedUrl ? { ...attachment, url: data.signedUrl } : attachment;
  }));
}

function usefulThreadSubject(value: unknown): string | null {
  const subject = clean(value);
  if (!subject) return null;
  const normalized = subject.toLowerCase();
  return ["unknown contact", "no contact", "unnamed contact"].includes(normalized)
    ? null
    : subject;
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

async function contactMapForIds(admin: ReturnType<typeof createAdminClient>, workspaceId: string, userId: string, ids: string[]) {
  const uniqueIds = Array.from(new Set(ids.filter(Boolean)));
  if (!uniqueIds.length) return new Map<string, ContactSummary>();

  const { data, error } = await admin
    .from("contacts")
    .select("id,full_name,phone,email,address,workspace_id")
    .eq("workspace_id", workspaceId).eq("user_id", userId)
    .in("id", uniqueIds);

  if (error) throw error;

  return new Map(
    ((data ?? []) as Record<string, unknown>[])
      .map(publicContact)
      .filter((contact): contact is ContactSummary => !!contact)
      .map((contact) => [contact.id, contact])
  );
}

async function contactMapForPhones(admin: ReturnType<typeof createAdminClient>, workspaceId: string, userId: string, phones: string[]) {
  const variants = Array.from(new Set(phones.flatMap(phoneSearchTerms)));
  if (!variants.length) return new Map<string, ContactSummary>();

  const { data, error } = await admin
    .from("contacts")
    .select("id,full_name,phone,email,address,workspace_id,updated_at")
    .eq("workspace_id", workspaceId).eq("user_id", userId)
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
  const attachments = inboxAttachments(row.media);
  const mediaPreview = attachments[0]?.mimeType.startsWith("video/") ? "Video" : attachments.length ? "Photo" : null;

  return {
    id: `sms:${String(row.id)}`,
    source: "sms",
    kind: direction === "inbound" ? "message_inbound" : "message_outbound",
    direction,
    title: direction === "inbound" ? "Incoming message" : "Sent message",
    preview: body ?? mediaPreview,
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
    attachments,
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
    attachments: [],
  };
}

function callEvent(row: Record<string, unknown>, contact: ContactSummary | null): InboxEvent {
  const direction = row.direction === "outbound" ? "outbound" : "inbound";
  const fromPhone = clean(row.from_number_e164);
  const toPhone = clean(row.to_number_e164);
  const status = clean(row.status) ?? "missed";
  const occurredAt = clean(row.missed_at) ?? clean(row.ended_at) ?? eventTime(row);
  const isMissed = direction === "inbound" && ["missed", "no-answer"].includes(status);
  const title = isMissed ? "Missed call" : direction === "inbound" ? "Incoming call" : "Outgoing call";
  const contactId = clean(row.contact_id) ?? contact?.id ?? null;
  const participantPhone = direction === "inbound" ? fromPhone : toPhone;
  const participantLabel = contactTitle(contact, participantPhone);

  return {
    id: `call:${String(row.id)}`,
    source: "call",
    kind: isMissed ? "missed_call" : "call",
    direction,
    title,
    preview: direction === "inbound" ? `From ${participantLabel}` : `To ${participantLabel}`,
    body: title,
    status,
    occurredAt,
    readAt: direction === "outbound" || !isMissed ? occurredAt : null,
    fromLabel: direction === "inbound" ? participantLabel : "You",
    fromEmail: direction === "inbound" ? contact?.email ?? null : null,
    fromPhone,
    toLabel: direction === "outbound" ? participantLabel : "You",
    toEmail: direction === "outbound" ? contact?.email ?? null : null,
    toPhone,
    contactId,
    href: null,
    attachments: [],
  };
}

function replyPhoneForEvents(events: InboxEvent[]): string | null {
  for (const event of [...events].reverse()) {
    const candidate = event.direction === "inbound"
      ? event.fromPhone
      : event.direction === "outbound"
        ? event.toPhone
        : event.fromPhone ?? event.toPhone;
    const normalized = normalizePhone(candidate);
    if (normalized) return normalized;
  }
  return null;
}

function buildThreads(events: InboxEvent[], contacts: Map<string, ContactSummary>): InboxThread[] {
  const groups = new Map<string, InboxEvent[]>();

  for (const event of events) {
    const normalizedPhone = normalizePhone(event.direction === "outbound" ? event.toPhone : event.fromPhone);
    const email = counterpartyEmail(event);
    const fallbackKey =
      normalizedPhone ? `phone:${normalizedPhone}` :
      email ? `email:${email.toLowerCase()}` :
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
      const fallbackEmail = replyEmailForEvents(sortedEvents);
      const fallbackTitle = fallbackPhone ?? fallbackEmail;
      const primaryPhone = clean(contact?.phone) ?? fallbackPhone;
      const primaryEmail = clean(contact?.email) ?? fallbackEmail;

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

function threadPhoneIdentity(thread: InboxThread): string | null {
  const phone = clean(thread.primaryPhone) ?? replyPhoneForEvents(thread.events);
  const keys = phoneMatchKeys(phone);
  return keys.length ? keys[keys.length - 1] : null;
}

function threadIdentity(thread: InboxThread): string {
  const phone = threadPhoneIdentity(thread);
  if (phone) return `phone:${phone}`;
  if (thread.contactId) return `contact:${thread.contactId}`;
  if (thread.primaryEmail) return `email:${thread.primaryEmail.toLowerCase()}`;
  return `thread:${thread.id}`;
}

function mergeInboxThreads(threads: InboxThread[]): InboxThread[] {
  const groups = new Map<string, InboxThread[]>();
  for (const thread of threads) {
    const key = threadIdentity(thread);
    groups.set(key, [...(groups.get(key) ?? []), thread]);
  }

  return Array.from(groups.values()).map((group) => {
    const orderedThreads = [...group].sort((left, right) => Date.parse(left.latestAt) - Date.parse(right.latestAt));
    const latestThread = orderedThreads[orderedThreads.length - 1];
    const identityThread = [...orderedThreads].reverse().find((thread) => clean(thread.contact?.fullName)) ?? latestThread;
    const events = Array.from(new Map(
      orderedThreads.flatMap((thread) => thread.events).map((event) => [event.id, event])
    ).values()).sort((left, right) => Date.parse(left.occurredAt) - Date.parse(right.occurredAt));
    const latestEvent = events[events.length - 1];

    return {
      id: identityThread.id,
      contactId: identityThread.contactId ?? orderedThreads.find((thread) => thread.contactId)?.contactId ?? null,
      contact: identityThread.contact ?? orderedThreads.find((thread) => thread.contact)?.contact ?? null,
      title: identityThread.title,
      subtitle: identityThread.subtitle ?? latestThread.subtitle,
      primaryPhone: identityThread.primaryPhone ?? latestThread.primaryPhone ?? replyPhoneForEvents(events),
      primaryEmail: identityThread.primaryEmail ?? latestThread.primaryEmail,
      latestAt: latestEvent.occurredAt,
      latestSource: latestEvent.source,
      latestPreview: latestEvent.preview ?? latestEvent.body,
      unreadCount: events.filter((event) => event.direction === "inbound" && !event.readAt).length,
      needsResponse: orderedThreads.some((thread) => thread.needsResponse),
      events,
    } satisfies InboxThread;
  }).sort((left, right) => Date.parse(right.latestAt) - Date.parse(left.latestAt));
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

    if (source === "all" || source === "email") {
      await syncICloudInbox(admin, workspaceId, context!.user.id).catch((error) => {
        console.warn("[inbox] iCloud sync failed", error instanceof Error ? error.message : error);
      });
    }

    const canonicalInboxThreads: InboxThread[] = [];
    let canonicalQuery = admin.from("communication_threads")
      .select("*,sales_contacts(id,name,phone,email,address),communication_events(*)")
      .eq("workspace_id", workspaceId).eq("assigned_user_id", context!.user.id).eq("sales_contacts.owner_user_id", context!.user.id).eq("sales_contacts.workspace_id", workspaceId).neq("status", "archived")
      .order("latest_event_at", { ascending: false })
      .limit(source === "all" ? limit : Math.min(limit * 4, 800));
    if (contactId) canonicalQuery = canonicalQuery.eq("sales_contact_id", contactId);
    const { data: canonicalThreads, error: canonicalError } = await canonicalQuery;
    if (canonicalError) {
      console.warn("[inbox] canonical communications unavailable; using call/message logs", canonicalError.message);
    } else if (canonicalThreads?.length) {
      const mappedThreads = await Promise.all(canonicalThreads.map(async (row): Promise<InboxThread | null> => {
        const contact = row.sales_contacts;
        const matchingEvents = [...(row.communication_events ?? [])]
          .filter((event) => event.actor_user_id === context!.user.id && event.workspace_id === workspaceId)
          .filter((event) => source === "all" || (source === "call" ? ["call", "voicemail"].includes(event.channel) : event.channel === source))
          .sort((left, right) => Date.parse(left.occurred_at) - Date.parse(right.occurred_at));
        if (!matchingEvents.length) return null;
        const events: InboxEvent[] = await Promise.all(matchingEvents.map(async (event) => ({
          id: event.id, source: event.channel, kind: event.event_kind, direction: event.direction,
          title: event.subject || event.event_kind.replaceAll("_", " "), preview: event.body, body: event.body,
          status: event.status, occurredAt: event.occurred_at, readAt: event.read_at,
          fromLabel: event.from_address, fromEmail: event.channel === "email" ? event.from_address : null,
          fromPhone: event.channel === "sms" || event.channel === "call" || event.channel === "voicemail" ? event.from_address : null,
          toLabel: event.to_addresses?.[0] ?? null, toEmail: event.channel === "email" ? event.to_addresses?.[0] ?? null : null,
          toPhone: event.channel === "sms" || event.channel === "call" ? event.to_addresses?.[0] ?? null : null,
          contactId: row.sales_contact_id, href: event.metadata?.recordingUrl ?? null,
          attachments: await refreshedInboxAttachments(admin, event.attachments),
        })));
        const latest = events.at(-1)!;
        const eventPhone = replyPhoneForEvents(events);
        const primaryPhone = clean(contact?.phone) ?? eventPhone;
        const primaryEmail = clean(contact?.email) ?? replyEmailForEvents(events);
        return {
          id: row.id, contactId: row.sales_contact_id, contact: contact ? { id: contact.id, fullName: contact.name, phone: contact.phone, email: contact.email, address: contact.address } : null,
          title: contact?.name || primaryPhone || primaryEmail || usefulThreadSubject(row.subject) || "Unknown contact",
          subtitle: contact?.email || contact?.phone || primaryPhone || primaryEmail || null,
          primaryPhone, primaryEmail, latestAt: latest.occurredAt,
          latestSource: latest.source,
          latestPreview: latest.body || latest.preview || (latest.attachments?.[0]?.mimeType.startsWith("video/") ? "Video" : latest.attachments?.length ? "Photo" : null),
          unreadCount: events.filter((event) => event.direction === "inbound" && !event.readAt).length,
          needsResponse: latest.direction === "inbound" && (
            latest.source === "sms" || latest.source === "email" || latest.source === "voicemail" ||
            (latest.source === "call" && ["missed", "no-answer"].includes(latest.status))
          ),
          events,
        } satisfies InboxThread;
      }));
      canonicalInboxThreads.push(...mappedThreads.filter((thread): thread is InboxThread => thread !== null));
    }

    const messageRows: Record<string, unknown>[] = [];
    const activityRows: Record<string, unknown>[] = [];
    const callRows: Record<string, unknown>[] = [];

    if (source === "all" || source === "sms") {
      let query = admin
        .from("dialer_messages")
        .select("*")
        .eq("workspace_id", workspaceId)
        .eq("sender_user_id", context!.user.id)
        .order("created_at", { ascending: false })
        .limit(limit * 4);
      if (contactId) query = query.eq("contact_id", contactId);
      const { data, error } = await query;
      if (error) throw error;
      messageRows.push(...((data ?? []) as Record<string, unknown>[]));
    }

    // Legacy contact activities have no communication owner; never expose them in a personal inbox.

    if (source === "all" || source === "call") {
      let query = admin
        .from("dialer_calls")
        .select("*")
        .eq("workspace_id", workspaceId)
        .eq("user_id", context!.user.id)
        .order("created_at", { ascending: false })
        .limit(limit * 4);
      if (contactId) query = query.eq("contact_id", contactId);
      const { data, error } = await query;
      if (error) {
        console.warn("[inbox] dialer call log unavailable", error.message);
      } else {
        callRows.push(...((data ?? []) as Record<string, unknown>[]));
      }
    }

    const messageContactIds = messageRows.map((row) => clean(row.contact_id)).filter((id): id is string => !!id);
    const callContactIds = callRows.map((row) => clean(row.contact_id)).filter((id): id is string => !!id);
    const activityContacts = activityRows
      .map((row) => publicContact(row.contacts as Record<string, unknown> | null))
      .filter((contact): contact is ContactSummary => !!contact);
    const contacts = await contactMapForIds(admin, workspaceId, context!.user.id, [
      ...messageContactIds,
      ...callContactIds,
      ...activityContacts.map((contact) => contact.id),
    ]).catch((error) => {
      console.warn("[inbox] contact lookup by id failed", error instanceof Error ? error.message : error);
      return new Map<string, ContactSummary>();
    });
    for (const contact of activityContacts) contacts.set(contact.id, contact);
    const phoneContacts = await contactMapForPhones(admin, workspaceId, context!.user.id, [
      ...messageRows.flatMap((row) => [clean(row.from_number_e164), clean(row.to_number_e164)]),
      ...callRows.flatMap((row) => [clean(row.from_number_e164), clean(row.to_number_e164)]),
    ].filter((phone): phone is string => !!phone)).catch((error) => {
      console.warn("[inbox] contact lookup by phone failed", error instanceof Error ? error.message : error);
      return new Map<string, ContactSummary>();
    });
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
    const threads = mergeInboxThreads([
      ...canonicalInboxThreads,
      ...buildThreads(events, contacts),
    ]).slice(0, limit);
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
    const attachments = inboxAttachments(payload.attachments).slice(0, 1);
    const requestedLeadId = clean(payload.leadId);
    const workspaceId = context!.workspace!.id;
    const admin = createAdminClient();
    let requestedLead: { id: string; sales_contact_id?: string | null; phone?: string | null; email?: string | null } | null = null;
    if (requestedLeadId) {
      let leadQuery = admin
        .from("sales_leads")
        .select("id,sales_contact_id,phone,email")
        .eq("workspace_id", workspaceId)
        .eq("id", requestedLeadId)
        .limit(1);
      leadQuery = leadQuery.eq("assigned_user_id", context!.user.id);
      const { data: lead, error: leadError } = await leadQuery.maybeSingle();
      if (leadError) throw leadError;
      if (!lead) return NextResponse.json({ error: "Lead not found." }, { status: 404 });
      requestedLead = lead;
    }
    const contactId = clean(payload.contactId) ?? requestedLead?.sales_contact_id ?? null;
    const phone = normalizePhone(
      clean(payload.phone) ?? clean(payload.to) ?? clean(payload.toPhone) ?? requestedLead?.phone ?? null
    );

    const requestedChannel = clean(payload.channel);
    if (requestedChannel === "email") {
      if (!body) return NextResponse.json({ error: "Message body is required." }, { status: 400 });
      const to = clean(payload.email) ?? clean(payload.to) ?? requestedLead?.email ?? null;
      if (!to) return NextResponse.json({ error: "A recipient email is required." }, { status: 400 });
      const { data: lead } = contactId ? await admin.from("sales_leads").select("id").eq("workspace_id", workspaceId).eq("assigned_user_id", context!.user.id).eq("sales_contact_id", contactId).order("updated_at", { ascending: false }).limit(1).maybeSingle() : { data: null };
      const normalizedEmail = to.toLowerCase();
      const diallerLeadId = requestedLead?.id ?? lead?.id ?? null;
      if (diallerLeadId) {
        const { error: leadEmailError } = await admin
          .from("sales_leads")
          .update({ email: normalizedEmail, email_normalized: normalizedEmail, updated_at: new Date().toISOString() })
          .eq("workspace_id", workspaceId)
          .eq("assigned_user_id", context!.user.id).eq("id", diallerLeadId);
        if (leadEmailError) throw leadEmailError;
      }
      if (contactId) {
        const { error: contactEmailError } = await admin
          .from("sales_contacts")
          .update({ email: normalizedEmail, email_normalized: normalizedEmail, updated_at: new Date().toISOString() })
          .eq("workspace_id", workspaceId)
          .eq("owner_user_id", context!.user.id).eq("id", contactId);
        if (contactEmailError) {
          console.warn("[inbox] contact email enrichment failed", contactEmailError.message);
        }
      }
      const sent = await sendManagedEmail({ admin, workspaceId, userId: context!.user.id, senderEmail: context!.user.email, contactId, leadId: requestedLead?.id ?? lead?.id ?? null, to, subject: clean(payload.subject) ?? "Following up", body });
      return NextResponse.json({ sent: true, emailId: sent.event?.provider_event_id ?? null });
    }

    if (!body && !attachments.length) {
      return NextResponse.json({ error: "A message, photo, or video is required." }, { status: 400 });
    }
    if ((body?.length ?? 0) > 1600) {
      return NextResponse.json({ error: "Message body is too long." }, { status: 400 });
    }
    if (!phone) {
      return NextResponse.json({ error: "A phone number is required to reply." }, { status: 400 });
    }

    const { data: salesContact } = contactId ? await admin.from("sales_contacts").select("id").eq("workspace_id", workspaceId).eq("owner_user_id", context!.user.id).eq("id", contactId).maybeSingle() : { data: null };
    if (salesContact || requestedLead) {
      const { data: lead } = salesContact
        ? await admin.from("sales_leads").select("id").eq("workspace_id", workspaceId).eq("assigned_user_id", context!.user.id).eq("sales_contact_id", salesContact.id).order("updated_at", { ascending: false }).limit(1).maybeSingle()
        : { data: null };
      const sentCanonical = await sendManagedSms({ admin, workspaceId, userId: context!.user.id, contactId: salesContact?.id ?? contactId, leadId: requestedLead?.id ?? lead?.id ?? null, to: phone, body: body ?? "", attachments });
      return NextResponse.json({ message: sentCanonical.event, warning: null });
    }
    const contact = contactId ? await getContactForWorkspace(admin, contactId, workspaceId, context!.user.id) : null;
    if (contactId && !contact) return NextResponse.json({ error: "Contact not found." }, { status: 404 });
    const senderNumber = await getSalespersonSmsFromNumber(admin, { userId: context!.user.id, workspaceId }, null);
    if (!senderNumber) throw Object.assign(new Error("A personal phone number must be assigned before texting."), { status: 409 });
    const sent = await sendTelnyxSms({ from: senderNumber, to: phone, text: body ?? "", mediaUrls: attachments.map((attachment) => attachment.url) });
    const now = new Date().toISOString();
    const from = normalizePhone(sent?.from?.phone_number) ?? senderNumber!;
    const providerMessageId = sent?.id ?? null;
    const status = sent?.to?.[0]?.status ?? "queued";
    const optimisticMessage = {
      id: providerMessageId,
      workspace_id: workspaceId,
      contact_id: contact?.id ?? null,
      direction: "outbound",
      from_number_e164: from,
      to_number_e164: phone,
      body: body ?? "",
      message_type: sent?.type ?? "SMS",
      status,
      media: attachments.length ? attachments : sent?.media ?? [],
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
          body: body ?? "",
          message_type: sent?.type ?? "SMS",
          status,
          media: attachments.length ? attachments : sent?.media ?? [],
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
          communication_owner_user_id: context!.user.id,
          contact_id: contact.id,
          type: "text",
          note: body ?? (attachments[0]?.mimeType.startsWith("video/") ? "Video" : "Photo"),
          timestamp: now,
        })
        .then(({ error }) => {
          if (error) console.warn("[inbox] reply contact activity failed", error.message);
        });
    }

    await appendCommunication(admin, { workspaceId, actorUserId: context!.user.id, channel: "sms", direction: "outbound", eventKind: "sms_sent", provider: "telnyx", providerEventId: providerMessageId, body, fromAddress: from, toAddresses: [phone], status });

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

    if (id && !id.includes(":")) {
      const admin = createAdminClient(); const now = new Date().toISOString();
      const { data: event } = await admin.from("communication_events").select("thread_id").eq("actor_user_id", context!.user.id).eq("workspace_id", context!.workspace!.id).eq("id", id).maybeSingle();
      if (event) {
        if (payload.read !== false) await admin.from("communication_events").update({ read_at: now }).eq("id", id);
        await admin.from("communication_threads").update({ last_read_at: now, ...(status ? { status } : {}) }).eq("workspace_id", context!.workspace!.id).eq("assigned_user_id", context!.user.id).eq("id", event.thread_id);
        return NextResponse.json({ ok: true });
      }
      const thread = await admin.from("communication_threads").select("id").eq("assigned_user_id", context!.user.id).eq("workspace_id", context!.workspace!.id).eq("id", id).maybeSingle();
      if (thread.data) {
        await admin.from("communication_threads").update({ last_read_at: now, ...(status ? { status } : {}) }).eq("id", id);
        return NextResponse.json({ ok: true });
      }
    }

    if (id?.startsWith("sms:") && status) {
      const messageId = id.slice(4);
      await createAdminClient()
        .from("dialer_messages")
        .update({ status })
        .eq("workspace_id", context!.workspace!.id)
        .eq("sender_user_id", context!.user.id)
        .eq("id", messageId)
        .throwOnError();
    }

    return NextResponse.json({ ok: true });
  } catch (error) {
    console.error("[inbox] PATCH", error);
    return NextResponse.json({ error: "Failed to update inbox item." }, { status: 500 });
  }
}
