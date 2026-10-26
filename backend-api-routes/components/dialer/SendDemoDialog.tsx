'use client';

import { useEffect, useRef, useState } from 'react';
import { Loader2, Send } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { STORMS_DEMO_URL, STORMS_DEMO_TITLE, STORMS_DEMO_SUBJECT, stormsDemoBody } from '@/lib/email/storms-demo';
import { SALES_DEMO_URL } from '@/lib/email/demo';

type DemoLead = { id: string; name: string; phone?: string | null; email?: string | null };

export function SendDemoDialog({ channel, lead, workspaceId, onClose, onSent }: {
  channel: 'sms' | 'email'; lead: DemoLead; workspaceId: string;
  onClose: () => void; onSent: (message: string) => void;
}) {
  const isEmail = channel === 'email';
  const [demoKind, setDemoKind] = useState<'general' | 'storms'>('general');
  const [recipient, setRecipient] = useState(isEmail ? lead.email ?? '' : lead.phone ?? '');
  const [preview, setPreview] = useState<{ textBody: string; emailSubject: string; emailBody: string } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [sending, setSending] = useState(false);
  const inFlight = useRef(false);

  useEffect(() => {
    const controller = new AbortController();
    void (async () => {
      try {
        const response = await fetch(`/api/dialer/leads/${lead.id}/demo-message`, {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ workspaceId }), signal: controller.signal,
        });
        const data = await response.json();
        if (!response.ok) throw new Error(data.error || 'Unable to prepare the demo.');
        if (!controller.signal.aborted) setPreview(data);
      } catch (reason) {
        if (!controller.signal.aborted) setError(reason instanceof Error ? reason.message : 'Unable to prepare the demo.');
      }
    })();
    return () => controller.abort();
  }, [lead.id, workspaceId]);

  async function send(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!preview || inFlight.current || !recipient.trim()) return;
    inFlight.current = true; setSending(true); setError(null);
    try {
      const isGeneralEmail = isEmail && demoKind === 'general';
      const response = await fetch(isGeneralEmail ? '/api/dialer/leads' : `/api/inbox?workspaceId=${encodeURIComponent(workspaceId)}`, {
        method: isGeneralEmail ? 'PATCH' : 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(isGeneralEmail
          ? { workspaceId, id: lead.id, email: recipient.trim(), sendDemoEmail: true }
          : isEmail ? { channel: 'email', leadId: lead.id, email: recipient.trim(), subject: STORMS_DEMO_SUBJECT, body: stormsDemoBody(lead.name) }
          : { channel: 'sms', leadId: lead.id, phone: recipient.trim(), body: demoKind === 'storms' ? stormsDemoBody(lead.name) : preview.textBody }),
      });
      const data = await response.json();
      if (!response.ok || (isGeneralEmail && data.demoEmailSent !== true)) throw new Error(data.error || 'Delivery could not be confirmed. Check your Inbox before retrying.');
      onSent(data.warning || (isEmail ? 'WolfGrid demo email sent.' : 'WolfGrid demo text sent.'));
      onClose();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Delivery could not be confirmed. Check your Inbox before retrying.');
    } finally { inFlight.current = false; setSending(false); }
  }

  return <Dialog open onOpenChange={open => { if (!open && !inFlight.current) onClose(); }}>
    <DialogContent>
      <DialogHeader><DialogTitle>{isEmail ? 'Email demo' : 'Text demo'}</DialogTitle></DialogHeader>
      <form onSubmit={send} className="space-y-4">
        <p className="text-sm text-muted-foreground">Send the WolfGrid demo to {lead.name}.</p>
        <label className="grid gap-1 text-sm">{isEmail ? 'Email address' : 'Phone number'}<Input type={isEmail ? 'email' : 'tel'} value={recipient} onChange={event => setRecipient(event.target.value)} required disabled={sending} /></label>
        <label className="grid gap-1 text-sm">Template<select className="rounded-md border bg-background p-2" value={demoKind} onChange={event => setDemoKind(event.target.value as 'general' | 'storms')} disabled={sending}><option value="general">WolfGrid Demo</option><option value="storms">{STORMS_DEMO_TITLE}</option></select></label>
        <a href={demoKind === 'storms' ? STORMS_DEMO_URL : SALES_DEMO_URL} target="_blank" rel="noopener noreferrer" className="block text-sm font-medium underline">{demoKind === 'storms' ? STORMS_DEMO_URL : SALES_DEMO_URL}</a>
        {preview ? <div className="rounded-lg border bg-muted/30 p-3 text-sm">
          {isEmail && <p className="mb-2 font-semibold">{demoKind === 'storms' ? STORMS_DEMO_SUBJECT : preview.emailSubject}</p>}
          <p className="whitespace-pre-wrap">{demoKind === 'storms' ? stormsDemoBody(lead.name) : isEmail ? preview.emailBody : preview.textBody}</p>
        </div> : !error && <p role="status" className="text-sm">Preparing demo…</p>}
        {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
        <div className="flex justify-end gap-2"><Button type="button" variant="outline" disabled={sending} onClick={onClose}>Cancel</Button><Button type="submit" disabled={!preview || !recipient.trim() || sending}>{sending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />} {isEmail ? 'Send email demo' : 'Send text demo'}</Button></div>
      </form>
    </DialogContent>
  </Dialog>;
}
