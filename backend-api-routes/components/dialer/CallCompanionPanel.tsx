'use client';

import { ActivityLogs } from '@/components/sales-pro/ActivityLogs';
import { useEffect, useRef, useState } from 'react';
import { Loader2, Mail, MessageSquare, Save, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { ContactDetailsDialog } from '@/components/sales-pro/ContactDetailsDialog';
import { SendDemoDialog } from './SendDemoDialog';
import { EmailComposer } from '@/components/sales-pro/EmailComposer';
import type { SharedActiveCall } from '@/lib/dialer/active-call';
import type { SalesLead } from '@/types/database';

type CompanionLead = Pick<SalesLead, 'id' | 'name' | 'company' | 'phone' | 'email' | 'address' | 'notes' | 'updated_at'>;

export function CallCompanionPanel({ call, active, workspaceId, onClose }: {
  call: SharedActiveCall; active: boolean; workspaceId: string; onClose: () => void;
}) {
  const [candidates, setCandidates] = useState<CompanionLead[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [lead, setLead] = useState<CompanionLead | null>(null);
  const [notes, setNotes] = useState('');
  const [baseline, setBaseline] = useState<CompanionLead | null>(null);
  const [conflict, setConflict] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [editing, setEditing] = useState(false);
  const [demoChannel, setDemoChannel] = useState<'sms' | 'email' | null>(null);
  const [emailOpen, setEmailOpen] = useState(false);
  const [title, setTitle] = useState('');
  const [due, setDue] = useState('');
  const [savingTask, setSavingTask] = useState(false);
  const draft = useRef({ notes, baseline, saving });
  useEffect(() => { draft.current = { notes, baseline, saving }; }, [notes, baseline, saving]);
  const dirty = Boolean(baseline && notes !== (baseline.notes ?? ''));

  useEffect(() => {
    let disposed = false;
    let timer: ReturnType<typeof setTimeout>;
    let controller: AbortController;
    async function refresh() {
      controller = new AbortController();
      try {
        const params = new URLSearchParams({ workspaceId });
        if (selectedId) params.set('leadId', selectedId);
        else if (call.phone) params.set('phone', call.phone);
        const response = await fetch(`/api/dialer/companion?${params}`, { cache: 'no-store', signal: controller.signal });
        const data = await response.json();
        if (!response.ok) throw new Error(data.error || 'Unable to load contact.');
        if (disposed) return;
        const rows = data.leads as CompanionLead[];
        setCandidates(rows);
        if (rows.length === 1) {
          const next = rows[0];
          setLead(next);
          const current = draft.current;
          if (!current.saving) {
            const localDirty = current.baseline && current.notes !== (current.baseline.notes ?? '');
            if (!localDirty) {
              setNotes(next.notes ?? ''); setBaseline(next); setConflict(false);
            } else if (next.notes !== current.baseline?.notes) setConflict(true);
          }
        }
        setError(null);
      } catch (reason) {
        if (!disposed) setError(reason instanceof Error ? reason.message : 'Contact sync unavailable.');
      } finally {
        if (!disposed) { setLoading(false); timer = setTimeout(refresh, 3000); }
      }
    }
    void refresh();
    return () => { disposed = true; clearTimeout(timer); controller?.abort(); };
  }, [workspaceId, call.phone, selectedId]);

  async function saveNotes() {
    if (!lead || !baseline || saving || conflict) return;
    setSaving(true); setError(null); setMessage(null);
    try {
      const response = await fetch(`/api/salesperson/leads/${lead.id}`, {
        method: 'PATCH', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ workspaceId, notes, expectedUpdatedAt: baseline.updated_at }),
      });
      const data = await response.json();
      if (response.status === 409) setConflict(true);
      if (!response.ok) throw new Error(data.error || 'Unable to save notes.');
      setLead(data.lead); setBaseline(data.lead); setNotes(data.lead.notes ?? '');
      setMessage('Notes saved. Your iPhone will refresh them.');
    } catch (reason) { setError(reason instanceof Error ? reason.message : 'Unable to save notes.'); }
    finally { setSaving(false); }
  }

  async function followUp(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!lead || !due || !title.trim() || savingTask) return;
    setSavingTask(true); setError(null); setMessage(null);
    try {
      const response = await fetch(`/api/tasks?workspaceId=${encodeURIComponent(workspaceId)}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ leadId: lead.id, title: title.trim(), dueAt: new Date(due).toISOString(), taskType: 'follow_up' }),
      });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || 'Unable to save follow-up.');
      setTitle(''); setDue(''); setMessage('Follow-up saved.');
    } catch (reason) { setError(reason instanceof Error ? reason.message : 'Unable to save follow-up.'); }
    finally { setSavingTask(false); }
  }

  function close() {
    if (saving || savingTask) return;
    if (dirty && !window.confirm('Close this contact and discard your unsaved notes?')) return;
    onClose();
  }

  return <section aria-label="iPhone call workspace" className="fixed bottom-4 right-4 top-20 z-50 flex w-[min(calc(100vw-2rem),26rem)] flex-col overflow-hidden rounded-xl border bg-white text-neutral-950 shadow-2xl">
    <style>{`
      @media (min-width: 1024px) {
        [data-sales-workspace-content] { margin-right: 28rem; }
      }
    `}</style>
    <header className="flex items-start justify-between border-b p-4">
      <div><p className="text-xs font-medium text-red-600">Calling on iPhone · Audio stays on iPhone</p><h2 className="mt-1 font-semibold">{lead?.name ?? call.name}</h2><p className="text-sm text-neutral-500">{!active ? 'Call ended' : call.phase === 'connected' ? 'Connected' : 'Connecting'} · {call.phone}{active && call.connectedAt ? ` · ${Math.floor(Math.max(0, Date.now() - Date.parse(call.connectedAt)) / 60000)}:${String(Math.floor(Math.max(0, Date.now() - Date.parse(call.connectedAt)) / 1000) % 60).padStart(2, '0')}` : ''}</p></div>
      <Button variant="ghost" size="icon" onClick={close} disabled={saving || savingTask} aria-label="Close call workspace"><X className="h-4 w-4" /></Button>
    </header>
    <div className="space-y-4 overflow-y-auto p-4">
      {loading && <p role="status" className="text-sm">Loading contact…</p>}
      {error && <p role="alert" className="text-sm text-red-700">{error}</p>}
      {message && <p role="status" className="text-sm text-green-700">{message}</p>}
      {!loading && !lead && candidates.length > 1 && <div><p className="mb-2 text-sm">This number matches multiple contacts. Choose the correct one.</p>{candidates.map(item => <Button key={item.id} variant="outline" className="mb-2 w-full" onClick={() => setSelectedId(item.id)}>{item.name} {item.company}</Button>)}</div>}
      {!loading && !lead && !candidates.length && !error && <p className="text-sm">No saved contact matches this number. You can add it from Contacts.</p>}
      {lead && <>
        <div className="space-y-1 text-sm text-neutral-600"><p>{lead.company}</p><p>{lead.email}</p><p>{lead.address}</p></div>
        <div className="flex gap-2"><Button variant="outline" onClick={() => setEditing(true)}>Contact details</Button><Button variant="outline" onClick={() => setEmailOpen(true)}>Email</Button></div>
        <div className="rounded-lg border p-3">
          <h3 className="mb-2 text-sm font-semibold">Send WolfGrid demo</h3>
          <div className="grid grid-cols-2 gap-2">
            <Button variant="outline" onClick={() => setDemoChannel('sms')}><MessageSquare className="h-4 w-4" /> Text demo</Button>
            <Button variant="outline" onClick={() => setDemoChannel('email')}><Mail className="h-4 w-4" /> Email demo</Button>
          </div>
        </div>
        <label className="grid gap-2 text-sm font-medium">Contact notes<Textarea rows={7} value={notes} disabled={saving} onChange={event => setNotes(event.target.value)} /></label>
        {conflict && <div role="status" className="space-y-2 rounded-lg bg-amber-50 p-3 text-sm"><p>Notes changed on your other screen. Your draft is kept here.</p><p className="whitespace-pre-wrap text-neutral-600">Saved notes: {lead.notes || '(empty)'}</p><Button variant="outline" onClick={() => { if (window.confirm('Replace your draft with the saved notes?')) { setNotes(lead.notes ?? ''); setBaseline(lead); setConflict(false); } }}>Reload saved notes</Button></div>}
        <Button onClick={() => void saveNotes()} disabled={!dirty || saving || conflict}>{saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />} Save notes</Button>
        <form className="space-y-3 border-t pt-4" onSubmit={followUp}><h3 className="font-semibold">Follow-up</h3><label className="grid gap-1 text-sm">Title<Input value={title} onChange={event => setTitle(event.target.value)} required disabled={savingTask} /></label><label className="grid gap-1 text-sm">Date and time<Input type="datetime-local" value={due} onChange={event => setDue(event.target.value)} required disabled={savingTask} /></label><Button type="submit" disabled={savingTask || !title.trim() || !due}>{savingTask && <Loader2 className="h-4 w-4 animate-spin" />} Add follow-up</Button></form>
        <ActivityLogs key={lead.id} workspaceId={workspaceId} leadId={lead.id} />
      </>}
    </div>
    {editing && lead && <ContactDetailsDialog key={lead.id} contact={lead} workspaceId={workspaceId} onClose={() => setEditing(false)} onSaved={updated => { setLead(updated); if (!dirty) { setBaseline(updated); setNotes(updated.notes ?? ''); } }} />}
    {demoChannel && lead && <SendDemoDialog key={`${lead.id}:${demoChannel}`} channel={demoChannel} lead={lead} workspaceId={workspaceId} onClose={() => setDemoChannel(null)} onSent={setMessage} />}
    {emailOpen && lead && <EmailComposer open initialTo={lead.email ?? ''} leadId={lead.id} onOpenChange={setEmailOpen} />}
  </section>;
}
