'use client';

import { useCallback, useEffect, useState } from 'react';
import { Clipboard, Plus } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { useWorkspace } from '@/lib/workspace-context';

type BookingLink = { id: string; slug: string; title: string; duration_minutes: number; mode: string; is_active: boolean; timezone: string };

export function BookingLinksWorkspace() {
  const { currentWorkspaceId } = useWorkspace(); const [links, setLinks] = useState<BookingLink[]>([]); const [title, setTitle] = useState('30 minute meeting'); const [timezone, setTimezone] = useState(Intl.DateTimeFormat().resolvedOptions().timeZone); const [error, setError] = useState<string | null>(null);
  const load = useCallback(async () => { if (!currentWorkspaceId) return; const response = await fetch(`/api/booking-links?workspaceId=${encodeURIComponent(currentWorkspaceId)}`); const data = await response.json(); if (response.ok) setLinks(data.links ?? []); else setError(data.error); }, [currentWorkspaceId]);
  useEffect(() => { void load(); }, [load]);
  async function create() { if (!currentWorkspaceId) return; const response = await fetch(`/api/booking-links?workspaceId=${encodeURIComponent(currentWorkspaceId)}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ title, timezone, durationMinutes: 30, mode: 'personal' }) }); const data = await response.json(); if (!response.ok) setError(data.error); else await load(); }
  return <div className="mx-auto max-w-5xl p-6"><div className="mb-6"><h1 className="text-2xl font-semibold">Booking</h1><p className="text-sm text-muted-foreground">WolfGrid availability with Zoom conferencing.</p></div>{error ? <p className="mb-4 text-sm text-destructive">{error}</p> : null}<div className="mb-6 grid gap-3 rounded-xl border bg-card p-4 md:grid-cols-[1fr_260px_auto]"><Input value={title} onChange={(event) => setTitle(event.target.value)} placeholder="Meeting type" /><Input value={timezone} onChange={(event) => setTimezone(event.target.value)} placeholder="Timezone" /><Button onClick={() => void create()}><Plus className="h-4 w-4" /> Create link</Button></div><div className="grid gap-3 md:grid-cols-2">{links.map((link) => { const url = `/book/${link.slug}`; return <div key={link.id} className="rounded-xl border bg-card p-4"><div className="flex justify-between gap-3"><div><h2 className="font-semibold">{link.title}</h2><p className="text-xs text-muted-foreground">{link.duration_minutes} min · {link.mode.replace('_', ' ')} · {link.timezone}</p></div><span className={link.is_active ? 'text-xs text-emerald-600' : 'text-xs text-muted-foreground'}>{link.is_active ? 'Active' : 'Paused'}</span></div><div className="mt-4 flex items-center gap-2"><code className="min-w-0 flex-1 truncate rounded bg-muted px-2 py-1 text-xs">{url}</code><Button size="icon" variant="outline" onClick={() => void navigator.clipboard.writeText(`${window.location.origin}${url}`)}><Clipboard className="h-4 w-4" /></Button></div></div>; })}</div></div>;
}
