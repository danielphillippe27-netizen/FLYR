'use client';

import { useState } from 'react';
import { STORMS_DEMO_TITLE, STORMS_DEMO_SUBJECT, stormsDemoBody } from '@/lib/email/storms-demo';
import { WOLFGRID_DEMO_TITLE, WOLFGRID_DEMO_SUBJECT, wolfgridDemoBody, RECEPTION_TEMPLATE_TITLE, RECEPTION_TEMPLATE_SUBJECT, receptionBody } from '@/lib/email/wolfgrid-demo';
import { Loader2, Send } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';

export function EmailComposer({ open, onOpenChange, initialTo = '', leadId, onSent }: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  initialTo?: string;
  leadId?: string;
  onSent?: () => void;
}) {
  const [to, setTo] = useState(initialTo);
  const [subject, setSubject] = useState('');
  const [body, setBody] = useState('');
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function send(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (sending) return;
    setSending(true);
    setError(null);
    try {
      const response = await fetch('/api/inbox', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ channel: 'email', email: to.trim(), subject: subject.trim(), body: body.trim(), leadId }),
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || 'Unable to send email.');
      onOpenChange(false);
      onSent?.();
    } catch (sendError) {
      setError(sendError instanceof Error ? sendError.message : 'Unable to send email.');
    } finally { setSending(false); }
  }

  return (
    <Dialog open={open} onOpenChange={(value) => { if (!sending) onOpenChange(value); }}>
      <DialogContent onInteractOutside={(event) => { if (sending) event.preventDefault(); }}>
        <DialogHeader><DialogTitle>New email</DialogTitle></DialogHeader>
        <form onSubmit={send} className="space-y-4">
          <label className="grid gap-1 text-sm">To<Input type="email" value={to} onChange={(event) => setTo(event.target.value)} required disabled={sending} autoFocus /></label>
          <label className="grid gap-1 text-sm">Subject<Input value={subject} onChange={(event) => setSubject(event.target.value)} required disabled={sending} /></label>
          <div className="flex flex-wrap gap-2" aria-label="Message templates">
            <Button type="button" variant="outline" size="sm" disabled={sending} onClick={() => { setSubject(WOLFGRID_DEMO_SUBJECT); setBody(wolfgridDemoBody()); }}>{WOLFGRID_DEMO_TITLE}</Button>
            <Button type="button" variant="outline" size="sm" disabled={sending} onClick={() => { setSubject(STORMS_DEMO_SUBJECT); setBody(stormsDemoBody()); }}>{STORMS_DEMO_TITLE}</Button>
            <Button type="button" variant="outline" size="sm" disabled={sending} onClick={() => { setSubject(RECEPTION_TEMPLATE_SUBJECT); setBody(receptionBody()); }}>{RECEPTION_TEMPLATE_TITLE}</Button>
          </div>
          <label className="grid gap-1 text-sm">Message<Textarea value={body} onChange={(event) => setBody(event.target.value)} required rows={8} disabled={sending} /></label>
          {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
          <div className="flex justify-end gap-2">
            <Button type="button" variant="outline" disabled={sending} onClick={() => onOpenChange(false)}>Cancel</Button>
            <Button type="submit" disabled={sending || !to.trim() || !subject.trim() || !body.trim()}>{sending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />} Send email</Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}
