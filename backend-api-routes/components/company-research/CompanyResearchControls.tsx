'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { Brain, Copy, ExternalLink, Loader2, RefreshCw, Search } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';

type Status = 'queued' | 'researching' | 'completed' | 'partial' | 'failed';
type SourcedText = { value: string | null; confidence: 'high' | 'medium' | 'low'; sources: string[] };
type SourcedList = { values: string[]; confidence: 'high' | 'medium' | 'low'; sources: string[] };
type ResearchResult = {
  company: {
    resolvedName: SourcedText;
    summary: SourcedText;
    website: SourcedText;
    phone: SourcedText;
    publicEmail: SourcedText;
    address: SourcedText;
    foundedYear: SourcedText;
    timeInBusiness: SourcedText;
    employeeEstimate: SourcedText;
    ownership: SourcedText;
    services: SourcedList;
    serviceAreas: SourcedList;
    locations: SourcedList;
    hours: SourcedList;
  };
  decisionMakers: Array<{ name: string; role: string | null; workEmail: string | null; directPhone: string | null; linkedinUrl: string | null; confidence: string; sources: string[] }>;
  reputation: { ratingSummary: SourcedText; positiveThemes: SourcedList; negativeThemes: SourcedList };
  signals: { recentNews: Array<{ title: string; detail: string; sources: string[] }>; hiringAndGrowth: Array<{ title: string; detail: string; sources: string[] }>; competitors: SourcedList };
  callBrief: { opener: string; summary: string; conversationHooks: string[]; inferredOpportunities: string[]; caveats: string[] };
  overallConfidence: 'high' | 'medium' | 'low';
  unresolvedFields: string[];
};
type ResearchRow = { id: string; status: Status; result?: ResearchResult | null; completed_at?: string | null; expires_at?: string | null; error_message?: string | null; sources?: Array<{ url: string; title?: string | null }> };
type ResearchResponse = { company?: { id: string; name: string } | null; active?: ResearchRow | null; latest?: ResearchRow | null; history?: ResearchRow[]; error?: string };

function confidenceClass(confidence: string) {
  if (confidence === 'high') return 'border-emerald-500/30 bg-emerald-500/10 text-emerald-700 dark:text-emerald-300';
  if (confidence === 'medium') return 'border-amber-500/30 bg-amber-500/10 text-amber-700 dark:text-amber-300';
  return 'border-border bg-muted text-muted-foreground';
}

function ResearchDetails({ research }: { research: ResearchRow }) {
  const result = research.result;
  if (!result) return null;
  const sources = [...new Map((research.sources ?? []).map((source) => [source.url, source])).values()];
  return (
    <div className="grid gap-5 text-sm">
      <div className="rounded-lg border border-border bg-muted/40 p-4">
        <div className="flex flex-wrap items-center gap-2">
          <h3 className="text-base font-semibold">{result.company.resolvedName.value || 'Company research'}</h3>
          <Badge variant="outline" className={confidenceClass(result.overallConfidence)}>{result.overallConfidence} confidence</Badge>
        </div>
        <p className="mt-2 text-muted-foreground">{result.company.summary.value || result.callBrief.summary}</p>
        <div className="mt-3 flex flex-wrap gap-2 text-xs text-muted-foreground">
          {[result.company.timeInBusiness.value, result.company.employeeEstimate.value, result.company.ownership.value].filter(Boolean).map((value) => (
            <span key={value} className="rounded-full border border-border bg-background px-2.5 py-1">{value}</span>
          ))}
        </div>
      </div>

      <section>
        <div className="flex items-center justify-between gap-3">
          <h3 className="font-semibold">Call brief</h3>
          <Button type="button" size="sm" variant="outline" onClick={() => navigator.clipboard.writeText(`${result.callBrief.opener}\n\n${result.callBrief.summary}`)}>
            <Copy className="h-3.5 w-3.5" /> Copy
          </Button>
        </div>
        <p className="mt-2 rounded-lg border border-border bg-background p-3 font-medium">{result.callBrief.opener}</p>
        <p className="mt-2 text-muted-foreground">{result.callBrief.summary}</p>
        {result.callBrief.conversationHooks.length ? <ul className="mt-2 list-disc space-y-1 pl-5 text-muted-foreground">{result.callBrief.conversationHooks.map((hook) => <li key={hook}>{hook}</li>)}</ul> : null}
      </section>

      {result.decisionMakers.length ? (
        <section>
          <h3 className="font-semibold">Owners and decision-makers</h3>
          <div className="mt-2 grid gap-2">
            {result.decisionMakers.map((person) => (
              <div key={`${person.name}-${person.role}`} className="rounded-lg border border-border p-3">
                <div className="flex items-center justify-between gap-2"><span className="font-medium">{person.name}</span><Badge variant="outline" className={confidenceClass(person.confidence)}>{person.confidence}</Badge></div>
                <div className="mt-1 text-muted-foreground">{[person.role, person.workEmail, person.directPhone].filter(Boolean).join(' · ')}</div>
                {person.linkedinUrl ? <a className="mt-1 inline-flex items-center gap-1 text-xs underline" href={person.linkedinUrl} target="_blank" rel="noreferrer">LinkedIn <ExternalLink className="h-3 w-3" /></a> : null}
              </div>
            ))}
          </div>
        </section>
      ) : null}

      <section className="grid gap-3 sm:grid-cols-2">
        <div><h3 className="font-semibold">Services</h3><p className="mt-1 text-muted-foreground">{result.company.services.values.join(' · ') || 'Not confirmed'}</p></div>
        <div><h3 className="font-semibold">Reputation</h3><p className="mt-1 text-muted-foreground">{result.reputation.ratingSummary.value || 'Not confirmed'}</p></div>
        <div><h3 className="font-semibold">Growth signals</h3><p className="mt-1 text-muted-foreground">{result.signals.hiringAndGrowth.map((signal) => signal.title).join(' · ') || 'None confirmed'}</p></div>
        <div><h3 className="font-semibold">Inferred opportunities</h3><p className="mt-1 text-muted-foreground">{result.callBrief.inferredOpportunities.join(' · ') || 'None'}</p></div>
      </section>

      {sources.length ? <section><h3 className="font-semibold">Sources</h3><div className="mt-2 grid gap-1.5">{sources.map((source) => <a key={source.url} className="flex items-center gap-1 truncate text-xs text-muted-foreground underline hover:text-foreground" href={source.url} target="_blank" rel="noreferrer"><ExternalLink className="h-3 w-3 shrink-0" />{source.title || source.url}</a>)}</div></section> : null}
      {research.completed_at ? <p className="text-xs text-muted-foreground">Researched {new Date(research.completed_at).toLocaleString()}</p> : null}
    </div>
  );
}

export function CompanyResearchButton({ workspaceId, leadId, contactId, companyId, className }: { workspaceId: string | null; leadId?: string | null; contactId?: string | null; companyId?: string | null; className?: string }) {
  const [open, setOpen] = useState(false);
  const [payload, setPayload] = useState<ResearchResponse>({});
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const query = useMemo(() => {
    if (!workspaceId || (!leadId && !contactId && !companyId)) return null;
    const identity = companyId ? { companyId } : leadId ? { leadId } : { contactId: contactId! };
    return new URLSearchParams({ workspaceId, ...identity });
  }, [workspaceId, leadId, contactId, companyId]);
  const load = useCallback(async () => {
    if (!query) return;
    const response = await fetch(`/api/sales/company-research?${query}`, { credentials: 'include', cache: 'no-store' });
    const data = await response.json().catch(() => ({})) as ResearchResponse;
    if (!response.ok) throw new Error(data.error || 'Failed to load company research.');
    setPayload(data);
  }, [query]);
  useEffect(() => { setPayload({}); setError(null); if (query) void load().catch(() => undefined); }, [query, load]);
  useEffect(() => {
    if (!payload.active || !query) return;
    const timer = window.setInterval(() => void load().catch((cause) => setError(cause instanceof Error ? cause.message : 'Research status failed.')), 4_000);
    return () => window.clearInterval(timer);
  }, [payload.active, query, load]);
  const start = async () => {
    if (!workspaceId || (!leadId && !contactId && !companyId)) return;
    setOpen(true); setLoading(true); setError(null);
    try {
      const response = await fetch(`/api/sales/company-research?${new URLSearchParams({ workspaceId })}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, credentials: 'include',
        body: JSON.stringify(companyId ? { companyId } : leadId ? { leadId } : { contactId }),
      });
      const data = await response.json().catch(() => ({})) as { error?: string };
      if (!response.ok) throw new Error(data.error || 'Failed to start company research.');
      await load();
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Failed to start company research.'); }
    finally { setLoading(false); }
  };
  const active = payload.active;
  const latest = payload.latest;
  return <>
    <Button type="button" variant="outline" size="sm" disabled={!query || loading} onClick={() => latest ? setOpen(true) : void start()} className={className} title="AI company research">
      {loading || active ? <Loader2 className="h-4 w-4 animate-spin" /> : <Brain className="h-4 w-4" />}
      <span className="hidden sm:inline">{active ? 'Researching' : latest ? 'Research' : 'Research'}</span>
    </Button>
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogContent className="max-h-[85vh] max-w-2xl overflow-y-auto">
        <DialogHeader><DialogTitle>Company research</DialogTitle></DialogHeader>
        {error ? <div className="rounded-lg border border-red-500/30 bg-red-500/10 p-3 text-sm text-red-700 dark:text-red-300">{error}</div> : null}
        {active ? <div className="flex min-h-32 items-center justify-center gap-2 text-muted-foreground"><Loader2 className="h-4 w-4 animate-spin" /> Researching public sources…</div> : latest ? <ResearchDetails research={latest} /> : !error ? <div className="py-8 text-center text-sm text-muted-foreground">No research has been saved for this company yet.</div> : null}
        <DialogFooter>
          {latest && !active ? <Button type="button" variant="outline" onClick={() => void start()} disabled={loading}><RefreshCw className="h-4 w-4" /> Refresh research</Button> : null}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </>;
}

type BatchResponse = { batch?: { id: string; status: Status; requested_count: number; skipped_count: number }; counts?: Record<Status, number>; error?: string; queued?: number; skipped?: number; capped?: boolean };
export function ListResearchButton({ workspaceId, listId, listName, count }: { workspaceId: string | null; listId: string; listName: string; count: number }) {
  const [open, setOpen] = useState(false);
  const [batch, setBatch] = useState<BatchResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const load = useCallback(async (batchId: string) => {
    if (!workspaceId) return;
    const response = await fetch(`/api/sales/company-research?${new URLSearchParams({ workspaceId, batchId })}`, { credentials: 'include', cache: 'no-store' });
    const data = await response.json().catch(() => ({})) as BatchResponse;
    if (!response.ok) throw new Error(data.error || 'Failed to load research batch.');
    setBatch(data);
  }, [workspaceId]);
  useEffect(() => {
    if (!batch?.batch || !['queued', 'researching'].includes(batch.batch.status)) return;
    const timer = window.setInterval(() => void load(batch.batch!.id).catch((cause) => setError(cause instanceof Error ? cause.message : 'Batch status failed.')), 4_000);
    return () => window.clearInterval(timer);
  }, [batch?.batch, load]);
  const start = async (refreshAll = false) => {
    if (!workspaceId) return;
    if (!window.confirm(`Research up to ${Math.min(count, 100)} companies in “${listName}” using your OpenAI account?`)) return;
    setOpen(true); setLoading(true); setError(null);
    try {
      const response = await fetch(`/api/sales/company-research?${new URLSearchParams({ workspaceId })}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, credentials: 'include', body: JSON.stringify({ listId, refreshAll }),
      });
      const data = await response.json().catch(() => ({})) as BatchResponse;
      if (!response.ok || !data.batch) throw new Error(data.error || 'Failed to start list research.');
      setBatch(data);
      await load(data.batch.id);
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Failed to start list research.'); }
    finally { setLoading(false); }
  };
  const retryFailed = async () => {
    if (!workspaceId || !batch?.batch) return;
    setLoading(true); setError(null);
    try {
      const response = await fetch(`/api/sales/company-research?${new URLSearchParams({ workspaceId })}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, credentials: 'include', body: JSON.stringify({ retryBatchId: batch.batch.id }),
      });
      const data = await response.json().catch(() => ({})) as { error?: string };
      if (!response.ok) throw new Error(data.error || 'Failed to retry company research.');
      await load(batch.batch.id);
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Failed to retry company research.'); }
    finally { setLoading(false); }
  };
  const counts = batch?.counts;
  const complete = (counts?.completed ?? 0) + (counts?.partial ?? 0);
  const total = batch?.batch?.requested_count ?? batch?.queued ?? 0;
  return <>
    <Button type="button" variant="outline" size="sm" disabled={!workspaceId || loading || count === 0} onClick={() => void start(false)}>
      {loading ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Search className="h-3.5 w-3.5" />} Research list
    </Button>
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogContent className="max-w-md"><DialogHeader><DialogTitle>Researching {listName}</DialogTitle></DialogHeader>
        {error ? <div className="rounded-lg border border-red-500/30 bg-red-500/10 p-3 text-sm text-red-700 dark:text-red-300">{error}</div> : null}
        {batch?.batch ? <div className="grid gap-3 text-sm"><div className="flex justify-between"><span>Status</span><Badge variant="outline">{batch.batch.status}</Badge></div><div className="flex justify-between"><span>Completed</span><strong>{complete}/{total}</strong></div><div className="flex justify-between"><span>Skipped/current</span><strong>{batch.batch.skipped_count}</strong></div>{(counts?.failed ?? 0) > 0 ? <div className="text-red-600">{counts?.failed} failed</div> : null}</div> : null}
        <DialogFooter>
          {(counts?.failed ?? 0) > 0 ? <Button type="button" variant="outline" onClick={() => void retryFailed()} disabled={loading}><RefreshCw className="h-4 w-4" /> Retry failed</Button> : null}
          {batch?.batch && ['completed', 'partial', 'failed'].includes(batch.batch.status) ? <Button type="button" variant="outline" onClick={() => void start(true)} disabled={loading}><RefreshCw className="h-4 w-4" /> Refresh all</Button> : null}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </>;
}
