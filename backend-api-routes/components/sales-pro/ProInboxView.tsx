'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Bell,
  Loader2,
  Mail,
  MessageCircle,
  Phone,
  Plus,
  RefreshCw,
  Send,
} from 'lucide-react';
import { STORMS_DEMO_TITLE, STORMS_DEMO_SUBJECT, stormsDemoBody } from '@/lib/email/storms-demo';
import { EmailComposer } from './EmailComposer';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { useWorkspace } from '@/lib/workspace-context';
import type { SalesLead } from '@/types/database';

type InboxSource = 'all' | 'sms' | 'email';

type InboxContact = {
  id: string;
  fullName: string | null;
  phone: string | null;
  email: string | null;
  address: string | null;
};

type InboxAttachment = {
  url: string;
  mimeType: string;
  fileName: string | null;
  storagePath: string | null;
};

type InboxEvent = {
  id: string;
  source: string;
  kind: string;
  direction: 'inbound' | 'outbound' | null;
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
  attachments?: InboxAttachment[];
};

type InboxThread = {
  id: string;
  contactId: string | null;
  leadId?: string | null;
  contact: InboxContact | null;
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

type InboxPayload = {
  threads?: InboxThread[];
  error?: string;
};

type LeadsPayload = {
  leads?: SalesLead[];
  error?: string;
};

const sourceOptions: Array<{ value: InboxSource; label: string }> = [
  { value: 'all', label: 'All' },
  { value: 'sms', label: 'Messages' },
  { value: 'email', label: 'Email' },
];

function clean(value: string | null | undefined) {
  return value?.trim() || null;
}

function phoneDigits(value: string | null | undefined) {
  return (value ?? '').replace(/\D/g, '');
}

function phoneIdentityKey(value: string | null | undefined) {
  const digits = phoneDigits(value);
  if (!digits) return null;
  return digits.length > 10 ? digits.slice(-10) : digits;
}

function threadPhone(thread: InboxThread) {
  if (clean(thread.primaryPhone)) return clean(thread.primaryPhone);
  if (clean(thread.contact?.phone)) return clean(thread.contact?.phone);
  for (const event of [...thread.events].reverse()) {
    if (event.direction === 'inbound' && clean(event.fromPhone)) return clean(event.fromPhone);
    if (event.direction === 'outbound' && clean(event.toPhone)) return clean(event.toPhone);
    if (clean(event.fromPhone) || clean(event.toPhone)) return clean(event.fromPhone) ?? clean(event.toPhone);
  }
  return null;
}

function threadEmail(thread: InboxThread) {
  if (clean(thread.primaryEmail)) return clean(thread.primaryEmail)?.toLowerCase() ?? null;
  if (clean(thread.contact?.email)) return clean(thread.contact?.email)?.toLowerCase() ?? null;
  for (const event of [...thread.events].reverse()) {
    const email = clean(event.fromEmail) ?? clean(event.toEmail);
    if (email) return email.toLowerCase();
  }
  return null;
}

function matchingLead(thread: InboxThread, leads: SalesLead[]) {
  const contactId = clean(thread.contactId)?.toLowerCase();
  if (contactId) {
    const match = leads.find((lead) =>
      lead.id.toLowerCase() === contactId || clean(lead.sales_contact_id)?.toLowerCase() === contactId
    );
    if (match) return match;
  }

  const phoneKey = phoneIdentityKey(threadPhone(thread));
  if (phoneKey) {
    const match = leads.find((lead) => phoneIdentityKey(lead.phone) === phoneKey);
    if (match) return match;
  }

  const email = threadEmail(thread);
  return email ? leads.find((lead) => clean(lead.email)?.toLowerCase() === email) : undefined;
}

function resolveContacts(threads: InboxThread[], leads: SalesLead[]) {
  if (!leads.length) return threads;
  return threads.map((thread) => {
    if (clean(thread.contact?.fullName)) return thread;
    const lead = matchingLead(thread, leads);
    if (!lead) return thread;
    return {
      ...thread,
      contactId: thread.contactId ?? clean(lead.sales_contact_id),
      leadId: lead.id,
      contact: {
        id: clean(lead.sales_contact_id) ?? lead.id,
        fullName: clean(lead.name),
        phone: clean(lead.phone),
        email: clean(lead.email),
        address: clean(lead.address) ?? ([clean(lead.city), clean(lead.region)].filter(Boolean).join(', ') || null),
      },
      title: clean(lead.name) ?? thread.title,
      primaryPhone: threadPhone(thread) ?? clean(lead.phone),
      primaryEmail: thread.primaryEmail ?? clean(lead.email),
    };
  });
}

function sortThreads(threads: InboxThread[]) {
  return [...threads].sort((left, right) => {
    const timeDifference = Date.parse(right.latestAt) - Date.parse(left.latestAt);
    return timeDifference || left.id.localeCompare(right.id);
  });
}

function consolidateThreads(threads: InboxThread[]) {
  const groups = new Map<string, InboxThread[]>();
  for (const thread of threads) {
    const phoneKey = phoneIdentityKey(threadPhone(thread));
    const hasSms = thread.latestSource === 'sms' || thread.events.some((event) => event.source === 'sms');
    const key = phoneKey && hasSms ? `sms:${phoneKey}` : `thread:${thread.id}`;
    groups.set(key, [...(groups.get(key) ?? []), thread]);
  }

  return sortThreads([...groups.values()].map((group) => {
    if (group.length === 1) return group[0];
    const ordered = [...group].sort((left, right) => Date.parse(left.latestAt) - Date.parse(right.latestAt));
    const latest = ordered.at(-1) ?? ordered[0];
    const preferredIdentity = [...ordered].reverse().find((thread) => clean(thread.contact?.fullName));
    const eventsById = new Map<string, InboxEvent>();
    for (const event of ordered.flatMap((thread) => thread.events)) eventsById.set(event.id, event);
    const events = [...eventsById.values()].sort((left, right) => Date.parse(left.occurredAt) - Date.parse(right.occurredAt));
    return {
      ...latest,
      id: preferredIdentity?.id ?? latest.id,
      contactId: preferredIdentity?.contactId ?? ordered.find((thread) => thread.contactId)?.contactId ?? null,
      leadId: preferredIdentity?.leadId ?? ordered.find((thread) => thread.leadId)?.leadId ?? null,
      contact: preferredIdentity?.contact ?? ordered.find((thread) => thread.contact)?.contact ?? null,
      title: preferredIdentity?.title ?? latest.title,
      subtitle: preferredIdentity?.subtitle ?? latest.subtitle,
      primaryPhone: threadPhone(preferredIdentity ?? latest) ?? threadPhone(latest),
      primaryEmail: preferredIdentity?.primaryEmail ?? ordered.find((thread) => thread.primaryEmail)?.primaryEmail ?? null,
      unreadCount: events.filter((event) => event.direction !== 'outbound' && !event.readAt).length,
      needsResponse: ordered.some((thread) => thread.needsResponse),
      events,
    };
  }));
}

function genericTitle(value: string) {
  const normalized = value.trim().toLowerCase();
  return ['inbound text', 'incoming message', 'sent message', 'unknown contact', 'unknown person', 'no contact', 'unnamed contact'].includes(normalized)
    || normalized.startsWith('new text from ');
}

function threadTitle(thread: InboxThread) {
  const contactValue = clean(thread.contact?.fullName)
    ?? clean(thread.contact?.phone)
    ?? clean(thread.contact?.email)
    ?? clean(thread.contact?.address);
  if (contactValue) return contactValue;
  const title = clean(thread.title) ?? 'Unknown contact';
  return genericTitle(title) ? threadPhone(thread) ?? threadEmail(thread) ?? title : title;
}

function sourceIcon(source: string) {
  if (source === 'sms') return MessageCircle;
  if (source === 'email') return Mail;
  if (source === 'call' || source === 'voicemail') return Phone;
  return Bell;
}

function relativeTime(value: string) {
  const time = Date.parse(value);
  if (!Number.isFinite(time)) return '';
  const seconds = Math.max(0, Math.floor((Date.now() - time) / 1000));
  if (seconds < 60) return 'now';
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h`;
  const days = Math.floor(hours / 24);
  if (days < 7) return `${days}d`;
  return new Date(value).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

function shouldShowTimestamp(events: InboxEvent[], index: number) {
  if (index === 0) return true;
  const current = new Date(events[index].occurredAt);
  const previous = new Date(events[index - 1].occurredAt);
  return current.toDateString() !== previous.toDateString() || current.getTime() - previous.getTime() >= 15 * 60 * 1000;
}

function timestampLabel(value: string) {
  const date = new Date(value);
  const today = new Date();
  const sameDay = date.toDateString() === today.toDateString();
  return date.toLocaleString(undefined, sameDay
    ? { hour: 'numeric', minute: '2-digit' }
    : { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
}

export function ProInboxView() {
  const { currentWorkspaceId } = useWorkspace();
  const [threads, setThreads] = useState<InboxThread[]>([]);
  const [selected, setSelected] = useState<InboxThread | null>(null);
  const [source, setSource] = useState<InboxSource>('all');
  const [composingEmail, setComposingEmail] = useState(false);
  const [reply, setReply] = useState('');
  const [emailSubject, setEmailSubject] = useState('Following up');
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const knownLeads = useRef<SalesLead[]>([]);
  const leadWorkspace = useRef(currentWorkspaceId);
  const lastLeadsFetchAt = useRef(0);
  const lastEmailSyncAt = useRef(0);
  const emailSyncInFlight = useRef(false);
  const requestSequence = useRef(0);

  const load = useCallback(async (syncEmail = false) => {
    if (!currentWorkspaceId) {
      setLoading(false);
      return;
    }
    const requestId = ++requestSequence.current;
    if (!syncEmail) setLoading(true);
    try {
      const workspace = encodeURIComponent(currentWorkspaceId);
      const inboxResponse = await fetch(`/api/inbox?workspaceId=${workspace}&source=${source}&status=open&limit=200&syncEmail=${syncEmail ? '1' : '0'}`, { cache: 'no-store' });
      const inboxPayload = (await inboxResponse.json().catch(() => ({}))) as InboxPayload;
      if (!inboxResponse.ok) throw new Error(inboxPayload.error || 'Unable to load the inbox.');
      if (requestId !== requestSequence.current) return;
      const rawThreads = inboxPayload.threads ?? [];
      const nextThreads = consolidateThreads(resolveContacts(rawThreads, knownLeads.current));
      setThreads(nextThreads);
      setSelected((current) => {
        if (!current) return null;
        const currentPhone = phoneIdentityKey(threadPhone(current));
        return nextThreads.find((thread) => thread.id === current.id)
          ?? nextThreads.find((thread) => currentPhone && phoneIdentityKey(threadPhone(thread)) === currentPhone)
          ?? null;
      });
      setError(null);
      if (Date.now() - lastLeadsFetchAt.current > 60_000) {
        lastLeadsFetchAt.current = Date.now();
        void fetch(`/api/salesperson/leads?workspaceId=${workspace}`, { cache: 'no-store' })
          .then(async (response) => response.ok ? ((await response.json()) as LeadsPayload).leads ?? [] : [])
          .then((leads) => {
            if (leadWorkspace.current !== currentWorkspaceId) return;
            knownLeads.current = leads;
            if (requestId !== requestSequence.current) return;
            setThreads(consolidateThreads(resolveContacts(rawThreads, leads)));
          })
          .catch(() => { lastLeadsFetchAt.current = 0; });
      }
    } catch (loadError) {
      if (requestId === requestSequence.current) setError(loadError instanceof Error ? loadError.message : 'Unable to load the inbox.');
    } finally {
      if (requestId === requestSequence.current && !syncEmail) setLoading(false);
    }
  }, [currentWorkspaceId, source]);

  useEffect(() => {
    leadWorkspace.current = currentWorkspaceId;
    knownLeads.current = [];
    lastLeadsFetchAt.current = 0;
    lastEmailSyncAt.current = 0;
  }, [currentWorkspaceId]);

  useEffect(() => {
    void (async () => {
      await load();
      if ((source === 'all' || source === 'email') && Date.now() - lastEmailSyncAt.current > 30_000) {
        lastEmailSyncAt.current = Date.now();
        emailSyncInFlight.current = true;
        try { await load(true); } finally { emailSyncInFlight.current = false; }
      }
    })();
    const timer = window.setInterval(() => { if (!emailSyncInFlight.current) void load(); }, 10_000);
    return () => window.clearInterval(timer);
  }, [load, source]);

  const unreadTotal = useMemo(() => threads.reduce((total, thread) => total + thread.unreadCount, 0), [threads]);

  async function openThread(thread: InboxThread) {
    const readEvents = thread.events.filter((event) => event.direction !== 'outbound' && !event.readAt);
    const readAt = new Date().toISOString();
    const nextThread = { ...thread, unreadCount: 0, needsResponse: false, events: thread.events.map((event) => readEvents.some((item) => item.id === event.id) ? { ...event, readAt } : event) };
    setSelected(nextThread);
    setThreads((current) => current.map((item) => item.id === thread.id ? nextThread : item));
    if (!readEvents.length) return;
    await Promise.all(readEvents.map((event) => fetch('/api/inbox', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: event.id, read: true }),
    })));
  }

  async function sendReply() {
    if (!selected || !reply.trim() || sending) return;
    const isEmail = source === 'email' || selected.latestSource === 'email';
    const phone = threadPhone(selected);
    const email = threadEmail(selected);
    if (isEmail && !email) {
      setError('This contact does not have an email address.');
      return;
    }
    if (!isEmail && !phone) {
      setError('This contact does not have a phone number.');
      return;
    }
    setSending(true);
    setError(null);
    try {
      const response = await fetch('/api/inbox', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          channel: isEmail ? 'email' : 'sms',
          contactId: selected.contactId,
          leadId: selected.leadId,
          phone,
          email,
          to: isEmail ? email : phone,
          subject: isEmail ? emailSubject.trim() || 'Following up' : undefined,
          body: reply.trim(),
        }),
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error || 'Unable to send the message.');
      setReply('');
      await load();
    } catch (sendError) {
      setError(sendError instanceof Error ? sendError.message : 'Unable to send the message.');
    } finally {
      setSending(false);
    }
  }

  function chooseSource(nextSource: InboxSource) {
    setSource(nextSource);
    setSelected(null);
    setReply('');
  }

  return (
    <div className="grid h-full min-h-0 grid-rows-[minmax(0,1fr)_minmax(0,2fr)] overflow-hidden lg:grid-cols-[390px_minmax(0,1fr)] lg:grid-rows-1">
      {composingEmail && <EmailComposer open onOpenChange={setComposingEmail} onSent={() => void load()} />}
      <aside className="flex min-h-0 min-w-0 flex-col overflow-hidden border-r bg-background">
        <div className="shrink-0 border-b px-4 pb-3 pt-4">
          <div className="flex items-center justify-between">
            <div>
              <div className="flex items-center gap-2">
                <h1 className="text-2xl font-semibold tracking-tight">Inbox</h1>
                {unreadTotal ? <span className="rounded-full bg-primary px-2 py-0.5 text-xs font-semibold text-primary-foreground">{unreadTotal}</span> : null}
              </div>
              <p className="text-xs text-muted-foreground">Messages and email</p>
            </div>
            <div className="flex items-center gap-2">
            <Button variant="outline" size="sm" onClick={() => setComposingEmail(true)}><Mail className="h-4 w-4" /> New email</Button>
            <Button size="icon" variant="outline" onClick={() => void load()} disabled={loading} aria-label="Refresh inbox">
              <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} />
            </Button>
            </div>
          </div>
          <div className="mt-4 grid grid-cols-3 rounded-lg bg-muted p-1">
            {sourceOptions.map((option) => (
              <button
                key={option.value}
                onClick={() => chooseSource(option.value)}
                className={`rounded-md px-2 py-1.5 text-xs font-medium transition ${source === option.value ? 'bg-background text-foreground shadow-sm' : 'text-muted-foreground hover:text-foreground'}`}
              >
                {option.label}
              </button>
            ))}
          </div>
        </div>

        {error ? <p className="shrink-0 border-b bg-destructive/5 px-4 py-2 text-sm text-destructive">{error}</p> : null}
        <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain">
          {loading && !threads.length ? (
            <div className="grid min-h-52 place-items-center text-muted-foreground"><Loader2 className="h-5 w-5 animate-spin" /></div>
          ) : threads.length ? threads.map((thread) => (
            <ThreadRow key={thread.id} thread={thread} selected={selected?.id === thread.id} onClick={() => void openThread(thread)} />
          )) : (
            <div className="grid min-h-52 place-items-center text-sm text-muted-foreground">No {source === 'all' ? 'messages or email yet' : source === 'sms' ? 'messages' : 'email'}.</div>
          )}
        </div>
      </aside>

      <main className="flex min-h-0 min-w-0 flex-col overflow-hidden bg-background">
        {selected ? (
          <ConversationPane
            thread={selected}
            source={source}
            reply={reply}
            setReply={setReply}
            emailSubject={emailSubject}
            setEmailSubject={setEmailSubject}
            sending={sending}
            onSend={() => void sendReply()}
          />
        ) : (
          <div className="grid flex-1 place-items-center text-muted-foreground">
            <div className="text-center"><MessageCircle className="mx-auto mb-3 h-8 w-8 opacity-40" /><p>Choose a conversation.</p></div>
          </div>
        )}
      </main>
    </div>
  );
}

function ThreadRow({ thread, selected, onClick }: { thread: InboxThread; selected: boolean; onClick: () => void }) {
  const Icon = sourceIcon(thread.latestSource);
  return (
    <button
      onClick={onClick}
      className={`flex h-16 w-full items-center gap-3 border-b px-4 text-left transition ${selected ? 'bg-muted' : thread.needsResponse ? 'bg-primary/[0.06] hover:bg-primary/[0.09]' : 'hover:bg-muted/60'}`}
    >
      <span className="relative grid h-8 w-8 shrink-0 place-items-center rounded-lg bg-muted">
        <Icon className={`h-4 w-4 ${thread.unreadCount ? 'text-primary' : 'text-muted-foreground'}`} />
        {thread.unreadCount ? <span className="absolute -right-0.5 -top-0.5 h-2 w-2 rounded-full bg-primary ring-2 ring-background" /> : null}
      </span>
      <span className="min-w-0 flex-1">
        <span className="flex items-baseline gap-2">
          <span className={`min-w-0 flex-1 truncate text-sm ${thread.unreadCount ? 'font-semibold' : 'font-medium'}`}>{threadTitle(thread)}</span>
          <time className="shrink-0 text-[11px] text-muted-foreground">{relativeTime(thread.latestAt)}</time>
        </span>
        <span className="mt-0.5 block truncate text-xs text-muted-foreground">{clean(thread.latestPreview) ?? clean(thread.subtitle) ?? ''}</span>
      </span>
    </button>
  );
}

const messageTemplates = [
  { title: STORMS_DEMO_TITLE, subject: STORMS_DEMO_SUBJECT, body: stormsDemoBody },
  {
    title: 'Introduction',
    subject: 'A quick introduction to WolfGrid',
    body: (name?: string | null) => `Hey ${name?.trim() || 'there'}, Daniel here with WolfGrid. How are you currently managing your team's door-to-door sales and follow-ups? Happy to show you how WolfGrid could help.`,
  },
  {
    title: 'Quick follow-up',
    subject: 'Checking in',
    body: (name?: string | null) => `Hey ${name?.trim() || 'there'}, just checking in on my last message. Any questions I can help with?`,
  },
  {
    title: 'Book a walkthrough',
    subject: 'Your WolfGrid walkthrough',
    body: (name?: string | null) => `Hey ${name?.trim() || 'there'}, would you be open to a quick WolfGrid walkthrough? Let me know a day and time that works for you.`,
  },
];

function MessageTemplatePicker({ disabled, onSelect }: {
  disabled: boolean;
  onSelect: (template: typeof messageTemplates[number]) => void;
}) {
  const [open, setOpen] = useState(false);
  const pickerRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!open) return;
    const closeOutside = (event: PointerEvent) => {
      if (!pickerRef.current?.contains(event.target as Node)) setOpen(false);
    };
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        setOpen(false);
        triggerRef.current?.focus();
      }
    };
    document.addEventListener('pointerdown', closeOutside);
    document.addEventListener('keydown', closeOnEscape);
    return () => {
      document.removeEventListener('pointerdown', closeOutside);
      document.removeEventListener('keydown', closeOnEscape);
    };
  }, [open]);

  return (
    <div ref={pickerRef} className="relative shrink-0" onBlur={(event) => {
      if (!event.currentTarget.contains(event.relatedTarget)) setOpen(false);
    }}>
      <Button ref={triggerRef} type="button" variant="ghost" size="icon"
        className="h-10 w-10 rounded-full" aria-label="Choose message template"
        aria-expanded={open && !disabled} disabled={disabled} onClick={() => setOpen((value) => !value)}>
        <Plus className="h-5 w-5" />
      </Button>
      {open && !disabled ? (
        <div role="group" aria-label="Message templates" className="absolute bottom-full left-0 z-40 mb-2 max-h-[min(20rem,50dvh)] w-64 max-w-[calc(100vw-2rem)] overflow-y-auto rounded-xl border border-border bg-popover p-1.5 text-popover-foreground shadow-lg">
          <p className="px-3 py-2 text-xs font-semibold text-muted-foreground">Message templates</p>
          {messageTemplates.map((template) => (
            <button key={template.title} type="button" className="block w-full rounded-lg px-3 py-2.5 text-left text-sm hover:bg-muted focus-visible:bg-muted focus-visible:outline-none"
              onClick={() => { onSelect(template); setOpen(false); triggerRef.current?.focus(); }}>
              {template.title}
            </button>
          ))}
        </div>
      ) : null}
    </div>
  );
}

function ConversationPane({
  thread,
  source,
  reply,
  setReply,
  emailSubject,
  setEmailSubject,
  sending,
  onSend,
}: {
  thread: InboxThread;
  source: InboxSource;
  reply: string;
  setReply: (value: string) => void;
  emailSubject: string;
  setEmailSubject: (value: string) => void;
  sending: boolean;
  onSend: () => void;
}) {
  const isEmail = source === 'email' || thread.latestSource === 'email';
  const phone = threadPhone(thread);
  const email = threadEmail(thread);
  const canReply = isEmail ? Boolean(email) : Boolean(phone);

  return (
    <>
      <header className="flex h-16 shrink-0 items-center gap-3 border-b px-5">
        <div className="min-w-0">
          <h2 className="truncate font-semibold">{threadTitle(thread)}</h2>
          <p className="truncate text-xs text-muted-foreground">{isEmail ? email : phone}</p>
        </div>
        {isEmail && email ? (
          <a href={`mailto:${email}`} className="ml-auto grid h-9 w-9 place-items-center rounded-full border hover:bg-muted" aria-label="Email contact"><Mail className="h-4 w-4" /></a>
        ) : phone ? (
          <a href={`tel:${phoneDigits(phone)}`} className="ml-auto grid h-9 w-9 place-items-center rounded-full border hover:bg-muted" aria-label="Call contact"><Phone className="h-4 w-4" /></a>
        ) : null}
      </header>

      <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-5 py-4">
        <div className="mx-auto max-w-3xl space-y-1">
          {thread.events.map((event, index) => (
            <div key={event.id}>
              {shouldShowTimestamp(thread.events, index) ? <div className="py-3 text-center text-[11px] font-medium text-muted-foreground">{timestampLabel(event.occurredAt)}</div> : null}
              <InboxEventView event={event} showDeliveryStatus={event.direction === 'outbound' && (index === thread.events.length - 1 || thread.events[index + 1]?.direction !== 'outbound')} />
            </div>
          ))}
        </div>
      </div>

      <div className="shrink-0 border-t bg-background/95 px-4 py-3 backdrop-blur">
        <div className="mx-auto max-w-3xl">
          {isEmail ? (
            <div className="mb-2 flex items-center gap-2 border-b pb-2">
              <span className="text-xs font-semibold text-muted-foreground">Subject</span>
              <Input className="h-7 border-0 px-1 shadow-none focus-visible:ring-0" value={emailSubject} onChange={(event) => setEmailSubject(event.target.value)} />
            </div>
          ) : null}
          <div className="flex items-end gap-2">
            <MessageTemplatePicker key={thread.id} disabled={!canReply || sending} onSelect={(template) => {
              setReply(template.body(thread.contact?.fullName));
              if (isEmail) setEmailSubject(template.subject);
            }} />
            <Textarea
              value={reply}
              onChange={(event) => setReply(event.target.value)}
              placeholder={canReply ? (isEmail ? 'Write an email' : 'Message') : isEmail ? 'No email on contact' : 'No phone on contact'}
              className="min-h-10 max-h-32 resize-none rounded-2xl py-2.5"
              disabled={!canReply || sending}
              onKeyDown={(event) => {
                if (event.key === 'Enter' && !event.shiftKey) {
                  event.preventDefault();
                  onSend();
                }
              }}
            />
            <Button size="icon" className="h-10 w-10 shrink-0 rounded-full" disabled={!canReply || !reply.trim() || sending} onClick={onSend} aria-label="Send message">
              {sending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
            </Button>
          </div>
        </div>
      </div>
    </>
  );
}

function InboxEventView({ event, showDeliveryStatus }: { event: InboxEvent; showDeliveryStatus: boolean }) {
  if (event.source === 'sms') {
    const outbound = event.direction === 'outbound';
    return (
      <div className={`flex py-0.5 ${outbound ? 'justify-end' : 'justify-start'}`}>
        <div className={`max-w-[76%] ${outbound ? 'text-right' : 'text-left'}`}>
          <div className={`overflow-hidden rounded-[19px] ${outbound ? 'bg-primary text-primary-foreground' : 'bg-muted text-foreground'}`}>
            {event.attachments?.map((attachment) => (
              <a key={attachment.storagePath ?? attachment.url} href={attachment.url} target="_blank" rel="noreferrer" className="block border-b border-black/10 px-3 py-2 text-xs underline">
                {attachment.mimeType.startsWith('video/') ? 'Open video' : 'Open photo'}
              </a>
            ))}
            {clean(event.body) ?? clean(event.preview) ? <p className="whitespace-pre-wrap px-3 py-2 text-sm">{clean(event.body) ?? clean(event.preview)}</p> : null}
          </div>
          {showDeliveryStatus ? <p className="mt-1 px-1 text-[10px] font-medium text-muted-foreground">{['delivered', 'finalized'].includes(event.status.toLowerCase()) ? 'Delivered' : ['failed', 'delivery_failed'].includes(event.status.toLowerCase()) ? 'Not Delivered' : 'Sent'}</p> : null}
        </div>
      </div>
    );
  }

  const Icon = sourceIcon(event.source);
  return (
    <div className="my-1 flex items-start gap-3 rounded-lg border bg-card p-3">
      <span className="grid h-8 w-8 shrink-0 place-items-center rounded-lg bg-muted"><Icon className="h-4 w-4 text-primary" /></span>
      <div className="min-w-0 flex-1">
        <div className="flex items-baseline gap-3"><p className="flex-1 text-sm font-semibold capitalize">{event.title || event.source}</p><time className="text-[10px] text-muted-foreground">{new Date(event.occurredAt).toLocaleString(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })}</time></div>
        {clean(event.body) ?? clean(event.preview) ? <p className="mt-1 whitespace-pre-wrap text-xs text-muted-foreground">{clean(event.body) ?? clean(event.preview)}</p> : null}
      </div>
    </div>
  );
}
