'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { Check, Clock, Mail, MessageCircle, Phone, Play } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { useWorkspace } from '@/lib/workspace-context';
import { demoMatchesFilter, type DemoDueFilter, type DemoFollowUp } from '@/lib/sales-pro/demo-follow-ups';

const filters: { value: DemoDueFilter; label: string }[] = [
  { value: 'today', label: 'Today' }, { value: 'overdue', label: 'Overdue' },
  { value: 'upcoming', label: 'Upcoming' }, { value: 'all', label: 'All demos' },
];
type SendEvent = { id: string; channel: string; subject: string | null; body: string | null; status: string; occurred_at: string; to_addresses: string[] };
const date = (value?: string | null) => value ? new Date(value).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' }) : 'Not scheduled';

export function DemoFollowUpTab() {
  const { currentWorkspaceId } = useWorkspace();
  const [tasks, setTasks] = useState<DemoFollowUp[]>([]);
  const [filter, setFilter] = useState<DemoDueFilter>('today');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [pending, setPending] = useState<string | null>(null);
  const [compose, setCompose] = useState<{ task: DemoFollowUp; channel: 'sms' | 'email' } | null>(null);
  const generation = useRef(0);
  const load = useCallback(async (signal?: AbortSignal) => {
    if (!currentWorkspaceId) return;
    const requestGeneration = ++generation.current;
    try {
      const rows: DemoFollowUp[] = [];
      for (let offset = 0; ; offset += 100) {
        const response = await fetch(`/api/demo-follow-ups?workspaceId=${encodeURIComponent(currentWorkspaceId)}&offset=${offset}`, { signal });
        const data = await response.json();
        if (!response.ok) throw new Error(data.error || 'Unable to load demos.');
        rows.push(...data.tasks);
        if (!data.hasMore) break;
      }
      if (!signal?.aborted && requestGeneration === generation.current) { setTasks(rows); setError(null); }
    } catch (reason) {
      if (!signal?.aborted && requestGeneration === generation.current) setError(reason instanceof Error ? reason.message : 'Unable to load demos.');
    } finally { if (!signal?.aborted) setLoading(false); }
  }, [currentWorkspaceId]);
  useEffect(() => {
    const controller = new AbortController();
    setTasks([]); setLoading(true);
    void load(controller.signal);
    const refresh = () => { if (document.visibilityState === 'visible') void load(controller.signal); };
    const timer = window.setInterval(refresh, 15000);
    window.addEventListener('focus', refresh);
    return () => { controller.abort(); generation.current++; window.clearInterval(timer); window.removeEventListener('focus', refresh); };
  }, [load]);

  async function update(task: DemoFollowUp, changes: Record<string, string>) {
    if (!currentWorkspaceId || pending) return;
    setPending(task.id); setError(null);
    try {
      const response = await fetch(`/api/tasks?workspaceId=${encodeURIComponent(currentWorkspaceId)}`, {
        method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ id: task.id, ...changes }),
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || 'Unable to update demo follow-up.');
      await load();
    } catch (reason) { setError(reason instanceof Error ? reason.message : 'Unable to update demo follow-up.'); }
    finally { setPending(null); }
  }
  function snooze(task: DemoFollowUp, days: number) {
    const next = new Date(); next.setDate(next.getDate() + days);
    void update(task, { dueAt: next.toISOString() });
  }
  const visible = tasks.filter(task => demoMatchesFilter(task, filter));
  return <section className="space-y-4 pt-3" aria-label="Demo follow-ups">
    <div className="flex items-start gap-3 rounded-xl border bg-card p-4"><Play className="mt-1 h-5 w-5 shrink-0 text-primary" /><div><h2 className="font-semibold">Every demo has a next step</h2><p className="text-sm text-muted-foreground">Email or text a demo and a follow-up appears here automatically, due seven days later. Repeat sends keep the existing due date.</p></div></div>
    <div className="flex flex-wrap gap-2" aria-label="Demo due dates">{filters.map(option => <Button key={option.value} variant={filter === option.value ? 'default' : 'outline'} onClick={() => setFilter(option.value)} aria-pressed={filter === option.value}>{option.label} <span className="text-xs">{tasks.filter(task => demoMatchesFilter(task, option.value)).length}</span></Button>)}</div>
    {error ? <p role="alert" className="text-sm text-destructive">{error}</p> : null}
    {notice ? <p role="status" className="text-sm text-emerald-600">{notice}</p> : null}
    {loading ? <p role="status" className="p-8 text-center text-sm text-muted-foreground">Loading demos…</p> : visible.length ? <div className="space-y-3">{visible.map(task => <article key={task.id} className="rounded-xl border bg-card p-4">
      <div className="flex flex-wrap items-start justify-between gap-3"><div className="min-w-0"><h3 className="break-words font-semibold">{task.metadata.recipientName || task.title}</h3><p className="break-words text-xs text-muted-foreground">{[task.metadata.recipientEmail, task.metadata.recipientPhone ? `+${task.metadata.recipientPhone}` : null].filter(Boolean).join(' · ')}</p></div><span className="rounded-full bg-muted px-2 py-1 text-xs">{task.metadata.outcome === 'signed_up' ? 'Signed up' : task.metadata.outcome === 'delivery_failed' ? 'Delivery failed' : task.status === 'completed' ? 'Completed' : task.status === 'dismissed' ? 'Stopped' : demoMatchesFilter(task, 'overdue') ? 'Overdue' : 'Follow-up scheduled'}</span></div>
      <p className="mt-3 text-sm">Sent by {task.metadata.lastChannel === 'sms' ? 'text' : 'email'} · {date(task.metadata.lastSentAt)}{(task.metadata.sendCount ?? 1) > 1 ? ` · ${task.metadata.sendCount} sends` : ''}</p>
      <p className="text-sm font-medium">Follow up {date(task.due_at)}</p>
      {task.metadata.replyReceivedAt ? <p className="mt-1 text-sm font-medium text-emerald-600">Reply received · {date(task.metadata.replyReceivedAt)}</p> : null}
      <p className="mt-1 text-xs text-muted-foreground">Sent is recorded; viewing is not confirmed.</p>
      {task.status === 'open' ? <div className="mt-3 flex flex-wrap gap-2">
        {task.metadata.recipientPhone ? <><Button variant="outline" size="sm" asChild><a href={`tel:+${task.metadata.recipientPhone}`}><Phone className="h-4 w-4" /> Call</a></Button><Button variant="outline" size="sm" onClick={() => setCompose({ task, channel: 'sms' })}><MessageCircle className="h-4 w-4" /> Text</Button></> : null}
        {task.metadata.recipientEmail ? <Button variant="outline" size="sm" onClick={() => setCompose({ task, channel: 'email' })}><Mail className="h-4 w-4" /> Email</Button> : null}
        <Button variant="outline" size="sm" disabled={!!pending} onClick={() => snooze(task, 1)}><Clock className="h-4 w-4" /> Tomorrow</Button>
        <Button variant="outline" size="sm" disabled={!!pending} onClick={() => snooze(task, 7)}>In a week</Button>
        <Button size="sm" disabled={!!pending} onClick={() => void update(task, { status: 'completed' })}><Check className="h-4 w-4" /> Mark done</Button>
        <Button variant="ghost" size="sm" disabled={!!pending} onClick={() => void update(task, { status: 'dismissed' })}>Stop</Button>
      </div> : null}
      {currentWorkspaceId ? <DemoSendHistory taskId={task.id} workspaceId={currentWorkspaceId} /> : null}
    </article>)}</div> : <div className="rounded-xl border p-10 text-center"><p className="font-medium">{filter === 'all' ? 'No demos sent yet' : 'No demos in this view'}</p><p className="mt-1 text-sm text-muted-foreground">Demos sent through WolfGrid appear here automatically. Open Upcoming to see scheduled follow-ups.</p></div>}
    {compose && currentWorkspaceId ? <DemoReplyComposer key={`${compose.task.id}:${compose.channel}`} {...compose} workspaceId={currentWorkspaceId} onClose={() => setCompose(null)} onSent={() => { setCompose(null); setNotice('Follow-up sent. Mark done when you’re finished.'); void load(); }} /> : null}
  </section>;
}

function DemoSendHistory({ taskId, workspaceId }: { taskId: string; workspaceId: string }) {
  const [open, setOpen] = useState(false);
  const [events, setEvents] = useState<SendEvent[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  useEffect(() => {
    if (!open) return;
    const controller = new AbortController();
    setLoading(true); setError(null);
    void (async () => {
      try {
        const rows: SendEvent[] = [];
        for (let offset = 0; ; offset += 100) {
          const response = await fetch(`/api/demo-follow-ups?workspaceId=${encodeURIComponent(workspaceId)}&taskId=${encodeURIComponent(taskId)}&offset=${offset}`, { signal: controller.signal });
          const data = await response.json();
          if (!response.ok) throw new Error(data.error || 'Unable to load history.');
          rows.push(...data.events); if (!data.hasMore) break;
        }
        if (!controller.signal.aborted) setEvents(rows);
      } catch (reason) { if (!controller.signal.aborted) setError(reason instanceof Error ? reason.message : 'Unable to load history.'); }
      finally { if (!controller.signal.aborted) setLoading(false); }
    })();
    return () => controller.abort();
  }, [open, taskId, workspaceId]);
  return <div className="mt-3 border-t pt-2"><Button variant="ghost" size="sm" aria-expanded={open} onClick={() => setOpen(value => !value)}>{open ? 'Hide' : 'View'} send history</Button>{open ? <div className="space-y-3 pt-2">{loading ? <p role="status" className="text-sm">Loading history…</p> : error ? <p role="alert" className="text-sm text-destructive">{error}</p> : events.map(event => <div key={event.id} className="rounded-lg bg-muted/40 p-3 text-sm"><p className="font-medium">{event.channel === 'sms' ? 'Text' : 'Email'} · {date(event.occurred_at)} · {event.status}</p><p className="text-xs text-muted-foreground">To {event.to_addresses.join(', ')}</p>{event.subject ? <p className="mt-2 font-medium">{event.subject}</p> : null}<p className="mt-1 whitespace-pre-wrap break-words">{event.body}</p></div>)}</div> : null}</div>;
}

function DemoReplyComposer({ task, channel, workspaceId, onClose, onSent }: { task: DemoFollowUp; channel: 'sms' | 'email'; workspaceId: string; onClose: () => void; onSent: () => void }) {
  const [recipient, setRecipient] = useState(channel === 'email' ? task.metadata.recipientEmail ?? '' : `+${task.metadata.recipientPhone ?? ''}`);
  const [subject, setSubject] = useState('Checking in about WolfGrid');
  const [body, setBody] = useState('Hi, just checking in to see if you had a chance to look at WolfGrid. Any questions I can help with?');
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const inFlight = useRef(false);
  async function send(event: React.FormEvent) {
    event.preventDefault(); if (inFlight.current) return;
    inFlight.current = true; setSending(true); setError(null);
    try {
      const response = await fetch(`/api/inbox?workspaceId=${encodeURIComponent(workspaceId)}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ channel, leadId: task.sales_lead_id, contactId: task.sales_contact_id, email: recipient.trim(), phone: recipient.trim(), subject, body: body.trim() }) });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || 'Unable to send.');
      onSent();
    } catch (reason) { setError(reason instanceof Error ? reason.message : 'Unable to send.'); }
    finally { inFlight.current = false; setSending(false); }
  }
  return <Dialog open onOpenChange={value => { if (!value && !inFlight.current) onClose(); }}><DialogContent onInteractOutside={event => { if (sending) event.preventDefault(); }}><DialogHeader><DialogTitle>{channel === 'email' ? 'Email' : 'Text'} demo follow-up</DialogTitle></DialogHeader><form onSubmit={send} className="space-y-4"><label className="grid gap-1 text-sm">To<Input value={recipient} onChange={event => setRecipient(event.target.value)} type={channel === 'email' ? 'email' : 'tel'} required disabled={sending} /></label>{channel === 'email' ? <label className="grid gap-1 text-sm">Subject<Input value={subject} onChange={event => setSubject(event.target.value)} required disabled={sending} /></label> : null}<label className="grid gap-1 text-sm">Message<Textarea value={body} onChange={event => setBody(event.target.value)} rows={6} maxLength={channel === 'sms' ? 1600 : undefined} required disabled={sending} /></label>{error ? <p role="alert" className="text-sm text-destructive">{error}</p> : null}<div className="flex justify-end gap-2"><Button type="button" variant="outline" disabled={sending} onClick={onClose}>Cancel</Button><Button type="submit" disabled={sending || !body.trim() || !recipient.trim()}>{sending ? 'Sending…' : 'Send follow-up'}</Button></div></form></DialogContent></Dialog>;
}
