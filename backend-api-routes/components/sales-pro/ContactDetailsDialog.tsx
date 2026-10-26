'use client';

import { useState } from 'react';
import { Loader2, Save } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import type { SalesLead } from '@/types/database';

type EditableContact = { id: string; name: string; company?: string | null; email?: string | null; phone?: string | null; address?: string | null; notes?: string | null; updated_at?: string };

export function ContactDetailsDialog({ contact, workspaceId, onClose, onSaved }: {
  contact: EditableContact;
  workspaceId: string;
  onClose: () => void;
  onSaved: (lead: SalesLead) => void;
}) {
  const [draft, setDraft] = useState({ name: contact.name, company: contact.company ?? '', email: contact.email ?? '', phone: contact.phone ?? '', address: contact.address ?? '', notes: contact.notes ?? '' });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (saving) return;
    setSaving(true);
    setError(null);
    try {
      const response = await fetch(`/api/salesperson/leads/${encodeURIComponent(contact.id)}`, {
        method: 'PATCH', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ workspaceId, ...draft, expectedUpdatedAt: contact.updated_at }),
      });
      const result = await response.json();
      if (!response.ok || !result.lead) throw new Error(result.error || 'Unable to save contact.');
      onSaved(result.lead);
      onClose();
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : 'Unable to save contact.');
    } finally { setSaving(false); }
  }

  return (
    <Dialog open onOpenChange={(value) => { if (!value && !saving) onClose(); }}>
      <DialogContent className="max-h-[85vh] overflow-y-auto">
        <DialogHeader><DialogTitle>Contact details</DialogTitle></DialogHeader>
        <form onSubmit={save} className="space-y-3">
          {(['name', 'company', 'email', 'phone', 'address'] as const).map((field) => (
            <label key={field} className="grid gap-1 text-sm capitalize">{field === 'name' ? 'Contact name' : field}
              <Input value={draft[field]} onChange={(event) => setDraft((current) => ({ ...current, [field]: event.target.value }))} type={field === 'email' ? 'email' : field === 'phone' ? 'tel' : 'text'} required={field === 'name'} disabled={saving} />
            </label>
          ))}
          <label className="grid gap-1 text-sm">Notes<Textarea value={draft.notes} onChange={(event) => setDraft((current) => ({ ...current, notes: event.target.value }))} rows={4} disabled={saving} /></label>
          {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
          <div className="flex justify-end gap-2">
            <Button type="button" variant="outline" onClick={onClose} disabled={saving}>Cancel</Button>
            <Button type="submit" disabled={saving || !draft.name.trim()}>{saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />} Save details</Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}
