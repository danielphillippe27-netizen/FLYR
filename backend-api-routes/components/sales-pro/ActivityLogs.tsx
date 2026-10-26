'use client';
import { useEffect, useState } from 'react';
import { Phone, Mail, MessageSquare, Calendar, FileText, RefreshCw } from 'lucide-react';
import type { ActivityLogItem } from '@/lib/dialer/activity-log';
export function ActivityLogs({ workspaceId, leadId }: { workspaceId: string; leadId: string }) {
  const [items, setItems] = useState<ActivityLogItem[]>([]);
  const [limit, setLimit] = useState(25);
  const [more, setMore] = useState(false);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [revision, setRevision] = useState(0);
  useEffect(() => { setItems([]); setLimit(25); setLoading(true); setError(''); }, [leadId, workspaceId]);
  useEffect(() => {
    let cancelled = false;
    const controller = new AbortController();
    async function load() {
      try {
        const collected: ActivityLogItem[] = [];
        let hasMore = true;
        while (hasMore && collected.length < limit) {
          const response = await fetch(`/api/crm/timeline?${new URLSearchParams({ workspaceId, leadId, limit: '25', offset: String(collected.length) })}`, { cache: 'no-store', signal: controller.signal });
          const data = await response.json();
          if (!response.ok) throw new Error(data.error || 'Unable to load logs.');
          collected.push(...(data.timeline ?? []));
          hasMore = Boolean(data.hasMore) && Boolean(data.timeline?.length);
        }
        if (!cancelled) { setItems(collected); setMore(hasMore); setError(''); }
      } catch (reason) { if (!cancelled) setError(reason instanceof Error ? reason.message : 'Unable to load logs.'); }
      finally { if (!cancelled) setLoading(false); }
    }
    void load();
    const timer = window.setInterval(() => { if (document.visibilityState === 'visible') void load(); }, 5000);
    return () => { cancelled = true; controller.abort(); window.clearInterval(timer); };
  }, [workspaceId, leadId, limit, revision]);
  return <section aria-label="Contact logs" className="space-y-3 rounded-xl border bg-card p-4">
    <div className="flex items-center justify-between"><h3 className="font-semibold">Logs</h3><button type="button" aria-label="Refresh logs" className="rounded-md p-2 hover:bg-muted" onClick={() => setRevision(value => value + 1)}><RefreshCw className="h-4 w-4" /></button></div>
    {error && <p role="alert" className="text-sm text-red-600">{error}</p>}
    {loading && !items.length ? <p className="text-sm text-muted-foreground">Loading logs…</p> : !items.length && !error ? <p className="text-sm text-muted-foreground">No activity yet.</p> : null}
    {items.map(item => {
      const Icon = item.channel === 'call' ? Phone : item.channel === 'email' ? Mail : item.channel === 'sms' ? MessageSquare : ['task', 'meeting'].includes(item.channel) ? Calendar : FileText;
      return <article key={item.id} className="flex items-start gap-3 border-t pt-3"><Icon className="mt-1 h-4 w-4 shrink-0 text-muted-foreground" /><div className="min-w-0"><p className="text-sm font-medium">{item.subject}</p><time dateTime={item.occurred_at} className="text-xs text-muted-foreground">{new Date(item.occurred_at).toLocaleString()}</time>{item.body && <p className="mt-1 whitespace-pre-wrap break-words text-sm text-muted-foreground">{item.body}</p>}</div></article>;
    })}
    {more && <button type="button" className="text-sm underline" onClick={() => { setLoading(true); setLimit(value => value + 25); }}>Show older activity</button>}
  </section>;
}
