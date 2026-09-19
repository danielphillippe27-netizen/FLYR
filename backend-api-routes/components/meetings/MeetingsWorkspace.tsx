'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { CalendarPlus, Check, Clipboard, ExternalLink, Loader2, Mail, MessageSquare, Send, Video, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';

type Meeting = {
  id: string;
  title: string;
  start_at: string;
  end_at: string;
  notes?: string | null;
  contact_name?: string | null;
  conference_join_url: string;
  attendee_emails?: string[];
};

type Delivery = {
  requested: number;
  sent: number;
  failed: number;
  error?: string;
};

type DeliveryConfigured = {
  email: boolean;
  sms: boolean;
};

function localDateTime(date: Date): string {
  const shifted = new Date(date.getTime() - date.getTimezoneOffset() * 60_000);
  return shifted.toISOString().slice(0, 16);
}

function deliveryMessage(deliveries: { email?: Delivery; sms?: Delivery }): string {
  const parts = ([['email', deliveries.email], ['SMS', deliveries.sms]] as const)
    .filter(([, delivery]) => (delivery?.requested ?? 0) > 0)
    .map(([label, delivery]) => delivery?.failed
      ? `${delivery.sent}/${delivery.requested} ${label} invitation${delivery.requested === 1 ? '' : 's'} sent${delivery.error ? ` (${delivery.error})` : ''}`
      : `${delivery?.sent ?? 0} ${label} invitation${delivery?.sent === 1 ? '' : 's'} sent`);
  return parts.length > 0 ? parts.join(' · ') : 'The join link is ready to share';
}

export function MeetingsWorkspace() {
  const defaults = useMemo(() => {
    const start = new Date(Date.now() + 60 * 60_000);
    start.setMinutes(Math.ceil(start.getMinutes() / 15) * 15, 0, 0);
    return { start: localDateTime(start), end: localDateTime(new Date(start.getTime() + 30 * 60_000)) };
  }, []);
  const [meetings, setMeetings] = useState<Meeting[]>([]);
  const [connected, setConnected] = useState(false);
  const [zoomEmail, setZoomEmail] = useState<string | null>(null);
  const [deliveryConfigured, setDeliveryConfigured] = useState<DeliveryConfigured>({ email: false, sms: false });
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [connecting, setConnecting] = useState(false);
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [shareMeetingId, setShareMeetingId] = useState<string | null>(null);
  const [shareEmails, setShareEmails] = useState('');
  const [sharePhoneNumbers, setSharePhoneNumbers] = useState('');
  const [shareSaving, setShareSaving] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [title, setTitle] = useState('WolfGrid meeting');
  const [startAt, setStartAt] = useState(defaults.start);
  const [endAt, setEndAt] = useState(defaults.end);
  const [attendees, setAttendees] = useState('');
  const [phoneNumbers, setPhoneNumbers] = useState('');
  const [notes, setNotes] = useState('');

  const load = useCallback(async () => {
    setLoading(true);
    const response = await fetch('/api/meetings', { cache: 'no-store' });
    const data = await response.json().catch(() => ({}));
    if (response.ok) {
      setMeetings(data.meetings ?? []);
      setConnected(Boolean(data.connected));
      setZoomEmail(data.zoomEmail ?? null);
      setDeliveryConfigured(data.deliveryConfigured ?? { email: false, sms: false });
    } else {
      setMessage(data.error ?? 'Could not load meetings.');
    }
    setLoading(false);
  }, []);

  useEffect(() => { void load(); }, [load]);

  async function connectZoom() {
    setConnecting(true);
    setMessage(null);
    const response = await fetch('/api/integrations/zoom/oauth/start?platform=web');
    const data = await response.json().catch(() => ({}));
    if (response.ok && data.authorizeUrl) {
      window.location.assign(data.authorizeUrl);
      return;
    }
    setMessage(data.error ?? 'Could not connect Zoom.');
    setConnecting(false);
  }

  async function createMeeting(event: React.FormEvent) {
    event.preventDefault();
    setSaving(true);
    setMessage(null);
    const response = await fetch('/api/meetings', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        title,
        startAt: new Date(startAt).toISOString(),
        endAt: new Date(endAt).toISOString(),
        attendeeEmails: attendees.split(/[;,\s]+/).filter(Boolean),
        attendeePhoneNumbers: phoneNumbers.split(/[;,\n]+/).map((value) => value.trim()).filter(Boolean),
        notes,
        timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      }),
    });
    const data = await response.json().catch(() => ({}));
    if (response.ok) {
      setMeetings((current) => [...current, data.meeting].sort((a, b) => a.start_at.localeCompare(b.start_at)));
      const deliveries = (data.deliveries ?? {}) as { email?: Delivery; sms?: Delivery };
      setMessage(`Zoom meeting created. ${deliveryMessage(deliveries)}.`);
      setAttendees('');
      setPhoneNumbers('');
      setNotes('');
    } else {
      setMessage(data.error ?? 'Could not create the meeting.');
      if (data.code === 'zoom_not_connected') setConnected(false);
    }
    setSaving(false);
  }

  async function copyLink(meeting: Meeting) {
    await navigator.clipboard.writeText(meeting.conference_join_url);
    setCopiedId(meeting.id);
    window.setTimeout(() => setCopiedId(null), 1600);
  }

  function openShare(meeting: Meeting) {
    setShareMeetingId(meeting.id);
    setShareEmails('');
    setSharePhoneNumbers('');
    setMessage(null);
  }

  async function sendInvitations(event: React.FormEvent, meeting: Meeting) {
    event.preventDefault();
    setShareSaving(true);
    setMessage(null);
    const response = await fetch(`/api/meetings/${encodeURIComponent(meeting.id)}/invitations`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        attendeeEmails: shareEmails.split(/[;,\s]+/).filter(Boolean),
        attendeePhoneNumbers: sharePhoneNumbers.split(/[;,\n]+/).map((value) => value.trim()).filter(Boolean),
        timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      }),
    });
    const data = await response.json().catch(() => ({}));
    if (response.ok) {
      setMessage(`${deliveryMessage(data.deliveries ?? {})}.`);
      setShareMeetingId(null);
      setShareEmails('');
      setSharePhoneNumbers('');
    } else {
      setMessage(data.error ?? 'Could not send the Zoom invitations.');
    }
    setShareSaving(false);
  }

  return (
    <div className="mx-auto w-full max-w-6xl px-4 py-8 md:px-6">
      <div className="mb-7 flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Meetings</h1>
          <p className="mt-1 text-sm text-muted-foreground">Create a Zoom room and WolfGrid calendar event in one step.</p>
        </div>
        {connected ? (
          <div className="flex items-center gap-2 rounded-full border bg-white px-3 py-2 text-xs text-muted-foreground">
            <span className="h-2 w-2 rounded-full bg-emerald-500" /> Zoom connected{zoomEmail ? ` · ${zoomEmail}` : ''}
          </div>
        ) : null}
      </div>

      {message ? <div className="mb-5 rounded-lg border bg-white px-4 py-3 text-sm">{message}</div> : null}

      {!connected && !loading ? (
        <Card className="max-w-xl">
          <CardHeader><CardTitle className="flex items-center gap-2"><Video className="h-5 w-5 text-blue-600" /> Connect Zoom</CardTitle></CardHeader>
          <CardContent>
            <p className="mb-5 text-sm leading-6 text-muted-foreground">Authorize your Zoom account once. WolfGrid securely refreshes the connection and creates scheduled meetings without exposing host links or credentials.</p>
            <Button onClick={() => void connectZoom()} disabled={connecting}>
              {connecting ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Video className="mr-2 h-4 w-4" />} Connect Zoom
            </Button>
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-6 lg:grid-cols-[400px_1fr]">
          <Card>
            <CardHeader><CardTitle className="flex items-center gap-2"><CalendarPlus className="h-5 w-5" /> New Zoom meeting</CardTitle></CardHeader>
            <CardContent>
              <form className="space-y-4" onSubmit={createMeeting}>
                <div className="space-y-2"><Label htmlFor="meeting-title">Title</Label><Input id="meeting-title" value={title} onChange={(event) => setTitle(event.target.value)} required /></div>
                <div className="grid grid-cols-2 gap-3">
                  <div className="space-y-2"><Label htmlFor="meeting-start">Starts</Label><Input id="meeting-start" type="datetime-local" value={startAt} onChange={(event) => setStartAt(event.target.value)} required /></div>
                  <div className="space-y-2"><Label htmlFor="meeting-end">Ends</Label><Input id="meeting-end" type="datetime-local" value={endAt} onChange={(event) => setEndAt(event.target.value)} required /></div>
                </div>
                <div className="space-y-2">
                  <div className="flex items-center justify-between gap-3"><Label htmlFor="meeting-attendees" className="flex items-center gap-1.5"><Mail className="h-3.5 w-3.5" /> Email recipients</Label><span className={`text-[11px] font-medium ${deliveryConfigured.email ? 'text-emerald-600' : 'text-amber-600'}`}>{deliveryConfigured.email ? 'Ready' : 'Needs setup'}</span></div>
                  <Input id="meeting-attendees" type="text" inputMode="email" placeholder="name@example.com" value={attendees} onChange={(event) => setAttendees(event.target.value)} />
                  <p className="text-xs text-muted-foreground">Separate multiple emails with commas.</p>
                </div>
                <div className="space-y-2">
                  <div className="flex items-center justify-between gap-3"><Label htmlFor="meeting-phones" className="flex items-center gap-1.5"><MessageSquare className="h-3.5 w-3.5" /> SMS recipients</Label><span className={`text-[11px] font-medium ${deliveryConfigured.sms ? 'text-emerald-600' : 'text-amber-600'}`}>{deliveryConfigured.sms ? 'Ready' : 'Needs setup'}</span></div>
                  <Input id="meeting-phones" type="tel" inputMode="tel" placeholder="+1 647 555 0100" value={phoneNumbers} onChange={(event) => setPhoneNumbers(event.target.value)} />
                  <p className="text-xs text-muted-foreground">Separate multiple numbers with commas. Include the country code outside Canada/US.</p>
                </div>
                <div className="space-y-2"><Label htmlFor="meeting-notes">Notes</Label><textarea id="meeting-notes" className="min-h-24 w-full rounded-md border bg-white px-3 py-2 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring" value={notes} onChange={(event) => setNotes(event.target.value)} /></div>
                <Button className="w-full" type="submit" disabled={saving}>
                  {saving ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Video className="mr-2 h-4 w-4" />} Create meeting
                </Button>
              </form>
            </CardContent>
          </Card>

          <Card>
            <CardHeader><CardTitle>Upcoming</CardTitle></CardHeader>
            <CardContent>
              {loading ? <div className="grid min-h-40 place-items-center"><Loader2 className="h-5 w-5 animate-spin" /></div> : meetings.length === 0 ? (
                <div className="grid min-h-40 place-items-center text-sm text-muted-foreground">No Zoom meetings yet.</div>
              ) : (
                <div className="divide-y">
                  {meetings.map((meeting) => (
                    <div key={meeting.id} className="flex flex-wrap items-center gap-4 py-4 first:pt-0">
                      <div className="grid h-11 w-11 shrink-0 place-items-center rounded-xl bg-blue-50 text-blue-600"><Video className="h-5 w-5" /></div>
                      <div className="min-w-0 flex-1">
                        <p className="truncate font-semibold">{meeting.title}</p>
                        <p className="mt-1 text-xs text-muted-foreground">{new Date(meeting.start_at).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' })} · {Math.round((new Date(meeting.end_at).getTime() - new Date(meeting.start_at).getTime()) / 60_000)} min</p>
                      </div>
                      <div className="flex gap-2">
                        <Button size="sm" variant="outline" type="button" onClick={() => void copyLink(meeting)}>{copiedId === meeting.id ? <Check className="mr-1.5 h-4 w-4" /> : <Clipboard className="mr-1.5 h-4 w-4" />}{copiedId === meeting.id ? 'Copied' : 'Copy link'}</Button>
                        <Button size="sm" variant="outline" type="button" onClick={() => shareMeetingId === meeting.id ? setShareMeetingId(null) : openShare(meeting)}>{shareMeetingId === meeting.id ? <X className="mr-1.5 h-4 w-4" /> : <Send className="mr-1.5 h-4 w-4" />}{shareMeetingId === meeting.id ? 'Close' : 'Send link'}</Button>
                        <Button size="sm" asChild><a href={meeting.conference_join_url} target="_blank" rel="noreferrer"><ExternalLink className="mr-1.5 h-4 w-4" /> Join</a></Button>
                      </div>
                      {shareMeetingId === meeting.id ? (
                        <form className="grid w-full gap-3 rounded-lg border bg-muted/30 p-4 md:grid-cols-[1fr_1fr_auto]" onSubmit={(event) => void sendInvitations(event, meeting)}>
                          <div className="space-y-1.5"><Label htmlFor={`share-email-${meeting.id}`}>Email</Label><Input id={`share-email-${meeting.id}`} inputMode="email" placeholder="name@example.com" value={shareEmails} onChange={(event) => setShareEmails(event.target.value)} /></div>
                          <div className="space-y-1.5"><Label htmlFor={`share-phone-${meeting.id}`}>SMS</Label><Input id={`share-phone-${meeting.id}`} type="tel" inputMode="tel" placeholder="+1 647 555 0100" value={sharePhoneNumbers} onChange={(event) => setSharePhoneNumbers(event.target.value)} /></div>
                          <Button className="self-end" type="submit" disabled={shareSaving || (!shareEmails.trim() && !sharePhoneNumbers.trim())}>{shareSaving ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin" /> : <Send className="mr-1.5 h-4 w-4" />} Send</Button>
                        </form>
                      ) : null}
                    </div>
                  ))}
                </div>
              )}
            </CardContent>
          </Card>
        </div>
      )}
    </div>
  );
}
