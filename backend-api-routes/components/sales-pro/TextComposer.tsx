'use client';

import { useRef, useState } from 'react';
import { Loader2, Send } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { WOLFGRID_DEMO_TITLE, wolfgridDemoBody, RECEPTION_TEMPLATE_TITLE, receptionBody } from '@/lib/email/wolfgrid-demo';
import { STORMS_DEMO_TITLE, STORMS_DEMO_URL } from '@/lib/email/storms-demo';
import { formatPhoneDisplay } from '@/lib/dialer/phone';

export type TextRecipient = { leadId: string; workspaceId: string; phone: string; name: string | null };

export function TextComposer({ recipient, onClose, onSent }: {
  recipient: TextRecipient;
  onClose: () => void;
  onSent?: (message: string) => void;
}) {
  const [body, setBody] = useState(wolfgridDemoBody);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState('');
  const sendingRef = useRef(false);

  async function send(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (sendingRef.current || !body.trim()) return;
    sendingRef.current = true;
    setSending(true);
    setError('');
    try {
      const response = await fetch(`/api/dialer/leads/${encodeURIComponent(recipient.leadId)}/sms`, {
        method: 'POST', credentials: 'include', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ workspaceId: recipient.workspaceId, phone: recipient.phone, body: body.trim() }),
      });
      const result = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(result.error || 'Unable to send text.');
      onClose();
      onSent?.(result.warning || 'Text sent.');
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Unable to send text.');
    } finally {
      sendingRef.current = false;
      setSending(false);
    }
  }

  return <Dialog open onOpenChange={(open) => { if (!open && !sendingRef.current) onClose(); }}>
    <DialogContent className="max-h-[85vh] overflow-y-auto" onInteractOutside={(event) => { if (sendingRef.current) event.preventDefault(); }}
      onEscapeKeyDown={(event) => { if (sendingRef.current) event.preventDefault(); }}>
      <DialogHeader>
        <DialogTitle>New text</DialogTitle>
        <DialogDescription>Review your message, then press Send text.</DialogDescription>
      </DialogHeader>
      <form onSubmit={send} className="space-y-4">
        <label className="grid gap-1 text-sm">To
          <Input value={[recipient.name, formatPhoneDisplay(recipient.phone)].filter(Boolean).join(' · ')} readOnly />
        </label>
        <div className="flex flex-wrap gap-2" aria-label="Message templates">
          <Button type="button" variant="outline" size="sm" disabled={sending} onClick={() => setBody(wolfgridDemoBody())}>{WOLFGRID_DEMO_TITLE}</Button>
          <Button type="button" variant="outline" size="sm" disabled={sending}
            onClick={() => setBody(`Hey there, here’s the WolfGrid Storms demo: ${STORMS_DEMO_URL}\n\nTake a look and let me know if you have any questions!`)}>{STORMS_DEMO_TITLE}</Button>
          <Button type="button" variant="outline" size="sm" disabled={sending} onClick={() => setBody(receptionBody())}>{RECEPTION_TEMPLATE_TITLE}</Button>
        </div>
        <label className="grid gap-1 text-sm">Message
          <Textarea value={body} onChange={(event) => setBody(event.target.value)} required rows={7} maxLength={1600} disabled={sending} />
        </label>
        {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
        <div className="flex justify-end gap-2">
          <Button type="button" variant="outline" disabled={sending} onClick={onClose}>Cancel</Button>
          <Button type="submit" disabled={sending || !recipient.phone.trim() || !body.trim()}>
            {sending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />} Send text
          </Button>
        </div>
      </form>
    </DialogContent>
  </Dialog>;
}
