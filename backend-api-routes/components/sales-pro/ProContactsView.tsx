'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { ArrowLeft, ExternalLink, Globe2, List, Loader2, Plus, Search, UserRound } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { useWorkspace } from '@/lib/workspace-context';
import type { SalesLead } from '@/types/database';

type TimelineItem = {
  id: string;
  timelineKind: string;
  activity_type?: string;
  note?: string;
  subject?: string;
  body?: string;
  occurred_at: string;
  channel?: string;
};

type LeadList = {
  id: string;
  title: string;
  leads: SalesLead[];
  newestAt: string;
};

type ViewMode = 'contacts' | 'lists';

const searchableLeadValues = (lead: SalesLead) => [
  lead.name,
  lead.company,
  lead.phone,
  lead.email,
  lead.website,
  lead.website_domain,
  lead.address,
  lead.city,
  lead.region,
  lead.country_code,
  lead.source,
  lead.list_name,
  lead.lead_state,
  lead.disposition,
  lead.notes,
];

function matchesLead(lead: SalesLead, query: string) {
  return searchableLeadValues(lead).some((value) => value?.toLowerCase().includes(query));
}

function listTitle(lead: SalesLead) {
  if (lead.list_name?.trim()) return lead.list_name.trim();
  const location = [lead.city, lead.region].filter(Boolean).join(', ') || 'Imported leads';
  const source = lead.source?.trim() || 'WolfGrid';
  return `${location} - ${source} - ${new Date(lead.created_at).toLocaleDateString()}`;
}

function leadSummary(lead: SalesLead) {
  return lead.address || lead.company || lead.email || lead.phone || lead.notes || lead.lead_state.replaceAll('_', ' ');
}

function hasListIdentity(lead: SalesLead) {
  return Boolean(lead.list_id?.trim() || lead.list_name?.trim());
}

function isContact(lead: SalesLead) {
  return Boolean(lead.sales_contact_id) || (!hasListIdentity(lead) && lead.source?.trim().toLowerCase() === 'manual');
}

function leadWebsiteLink(lead: SalesLead): { href: string; label: string } | null {
  const value = lead.website?.trim() || lead.website_domain?.trim();
  if (!value) return null;

  try {
    const url = new URL(/^https?:\/\//i.test(value) ? value : `https://${value}`);
    if (url.protocol !== 'http:' && url.protocol !== 'https:') return null;
    return {
      href: url.toString(),
      label: lead.website_domain?.trim() || url.hostname.replace(/^www\./i, ''),
    };
  } catch {
    return null;
  }
}

export function ProContactsView() {
  const { currentWorkspaceId } = useWorkspace();
  const [leads, setLeads] = useState<SalesLead[]>([]);
  const [selected, setSelected] = useState<SalesLead | null>(null);
  const [timeline, setTimeline] = useState<TimelineItem[]>([]);
  const [query, setQuery] = useState('');
  const [mode, setMode] = useState<ViewMode>('contacts');
  const [selectedListId, setSelectedListId] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [loading, setLoading] = useState(true);
  const [converting, setConverting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!currentWorkspaceId) {
      setLeads([]);
      setLoading(false);
      return;
    }

    setLoading(true);
    try {
      const params = new URLSearchParams({ workspaceId: currentWorkspaceId });
      const response = await fetch(`/api/salesperson/leads?${params}`, { cache: 'no-store' });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || 'Unable to load contacts.');
      const nextLeads = (data.leads ?? []) as SalesLead[];
      setLeads(nextLeads);
      setSelected((current) => nextLeads.find((lead) => lead.id === current?.id) ?? null);
      setError(null);
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'Unable to load contacts.');
    } finally {
      setLoading(false);
    }
  }, [currentWorkspaceId]);

  useEffect(() => {
    void load();
  }, [load]);

  const normalizedQuery = query.trim().toLowerCase();
  const contacts = useMemo(() => leads.filter(isContact), [leads]);
  const filteredContacts = useMemo(
    () => normalizedQuery ? contacts.filter((lead) => matchesLead(lead, normalizedQuery)) : contacts,
    [contacts, normalizedQuery]
  );

  const leadLists = useMemo(() => {
    const grouped = new Map<string, LeadList>();
    for (const lead of leads.filter((item) => hasListIdentity(item) && !isContact(item))) {
      const title = listTitle(lead);
      const id = lead.list_id?.trim() || title.toLowerCase();
      const existing = grouped.get(id);
      if (existing) {
        existing.leads.push(lead);
        if (Date.parse(lead.created_at) > Date.parse(existing.newestAt)) existing.newestAt = lead.created_at;
      } else {
        grouped.set(id, { id, title, leads: [lead], newestAt: lead.created_at });
      }
    }
    return [...grouped.values()]
      .map((group) => ({ ...group, leads: group.leads.sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at)) }))
      .sort((a, b) => Date.parse(b.newestAt) - Date.parse(a.newestAt));
  }, [leads]);

  const visibleLists = useMemo(() => {
    if (!normalizedQuery) return leadLists;
    return leadLists.filter((group) =>
      group.title.toLowerCase().includes(normalizedQuery) || group.leads.some((lead) => matchesLead(lead, normalizedQuery))
    );
  }, [leadLists, normalizedQuery]);

  const selectedList = leadLists.find((group) => group.id === selectedListId) ?? null;
  const visibleListLeads = selectedList
    ? normalizedQuery ? selectedList.leads.filter((lead) => matchesLead(lead, normalizedQuery)) : selectedList.leads
    : [];
  const selectedWebsite = selected ? leadWebsiteLink(selected) : null;

  async function open(lead: SalesLead) {
    setSelected(lead);
    setTimeline([]);
    if (!currentWorkspaceId) return;
    const params = new URLSearchParams({ workspaceId: currentWorkspaceId, leadId: lead.id });
    const response = await fetch(`/api/crm/timeline?${params}`);
    const data = await response.json();
    if (response.ok) setTimeline(data.timeline ?? []);
  }

  async function create() {
    if (!currentWorkspaceId || !name.trim()) return;
    const response = await fetch('/api/salesperson/leads', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ workspaceId: currentWorkspaceId, name: name.trim(), email: email.trim() || null }),
    });
    const data = await response.json();
    if (!response.ok) {
      setError(data.error || 'Unable to create contact.');
      return;
    }
    setCreating(false);
    setName('');
    setEmail('');
    await load();
  }

  async function createContactFromLead(lead: SalesLead) {
    if (!currentWorkspaceId || converting) return;
    setConverting(true);
    try {
      const response = await fetch('/api/salesperson/leads', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ workspaceId: currentWorkspaceId, leadId: lead.id }),
      });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || 'Unable to create contact.');
      setSelected(data.lead as SalesLead);
      await load();
      setMode('contacts');
      setSelectedListId(null);
      setError(null);
    } catch (conversionError) {
      setError(conversionError instanceof Error ? conversionError.message : 'Unable to create contact.');
    } finally {
      setConverting(false);
    }
  }

  function changeMode(nextMode: ViewMode) {
    setMode(nextMode);
    setSelectedListId(null);
    setSelected(null);
    setTimeline([]);
    setCreating(false);
    setQuery('');
  }

  const renderLead = (lead: SalesLead, kind: 'contact' | 'lead') => (
    <button
      key={lead.id}
      onClick={() => void open(lead)}
      className={`w-full rounded-lg p-3 text-left ${selected?.id === lead.id ? 'bg-primary text-primary-foreground' : 'hover:bg-muted'}`}
    >
      <div className="flex items-center justify-between gap-3">
        <p className="font-semibold">{lead.name}</p>
        {kind === 'lead' ? (
          <span className="rounded-full bg-orange-500/15 px-2 py-0.5 text-[10px] font-bold tracking-wide text-orange-600">
            LEAD
          </span>
        ) : null}
      </div>
      <p className="truncate text-xs capitalize opacity-70">{leadSummary(lead)}</p>
    </button>
  );

  return (
    <div className="grid min-h-[calc(100vh-4rem)] lg:grid-cols-[380px_1fr]">
      <aside className="border-r bg-background p-4">
        <div className="mb-4 flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-semibold">{mode === 'contacts' ? 'Contacts' : 'Lead Lists'}</h1>
            <p className="text-xs text-muted-foreground">WolfGrid Sales</p>
          </div>
          {mode === 'contacts' ? (
            <Button size="sm" onClick={() => setCreating((value) => !value)}><Plus className="h-4 w-4" /> New contact</Button>
          ) : null}
        </div>

        <div className="mb-4 grid grid-cols-2 border-b">
          {(['contacts', 'lists'] as const).map((item) => (
            <button
              key={item}
              onClick={() => changeMode(item)}
              className={`border-b-2 px-3 py-2 text-sm font-medium capitalize ${mode === item ? 'border-primary text-foreground' : 'border-transparent text-muted-foreground'}`}
            >
              {item}
            </button>
          ))}
        </div>

        {creating && mode === 'contacts' ? (
          <div className="mb-4 space-y-2 rounded-lg border p-3">
            <Input value={name} onChange={(event) => setName(event.target.value)} placeholder="Full name" />
            <Input value={email} onChange={(event) => setEmail(event.target.value)} placeholder="Email" type="email" />
            <Button className="w-full" onClick={() => void create()}>Create contact</Button>
          </div>
        ) : null}

        <div className="relative mb-3">
          <Search className="absolute left-3 top-3 h-4 w-4 text-muted-foreground" />
          <Input
            className="pl-9"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder={mode === 'contacts' ? 'Search contacts' : selectedList ? 'Search leads in this list' : 'Search lead lists'}
          />
        </div>

        {error ? <p className="mb-3 text-sm text-destructive">{error}</p> : null}
        {loading ? (
          <div className="grid min-h-48 place-items-center text-muted-foreground"><Loader2 className="h-5 w-5 animate-spin" /></div>
        ) : mode === 'contacts' ? (
          <div className="space-y-1">
            {filteredContacts.length ? filteredContacts.map((lead) => renderLead(lead, 'contact')) : <EmptyList icon="contact" label={normalizedQuery ? 'No matching contacts' : 'No contacts'} />}
          </div>
        ) : selectedList ? (
          <div>
            <button className="mb-2 flex items-center gap-2 text-sm font-medium" onClick={() => { setSelectedListId(null); setQuery(''); }}>
              <ArrowLeft className="h-4 w-4" /> Lists
            </button>
            <p className="mb-2 font-semibold">{selectedList.title}</p>
            <div className="space-y-1">
              {visibleListLeads.length ? visibleListLeads.map((lead) => renderLead(lead, 'lead')) : <EmptyList icon="list" label={normalizedQuery ? 'No matching leads' : 'No leads in this list'} />}
            </div>
          </div>
        ) : (
          <div className="space-y-2">
            {visibleLists.length ? visibleLists.map((group) => (
              <button key={group.id} onClick={() => { setSelectedListId(group.id); setSelected(null); setTimeline([]); setQuery(''); }} className="w-full rounded-lg border p-3 text-left hover:bg-muted">
                <p className="font-semibold">{group.title}</p>
                <p className="mt-1 text-xs text-muted-foreground">
                  {group.leads.length} leads · {group.leads.filter((lead) => Boolean(lead.phone)).length} dialable · {new Date(group.newestAt).toLocaleDateString()}
                </p>
              </button>
            )) : <EmptyList icon="list" label={normalizedQuery ? 'No matching lists' : 'No lead lists'} />}
          </div>
        )}
      </aside>

      <main className="p-6">
        {selected ? (
          <>
            <div className="mb-6">
              <h2 className="text-2xl font-semibold">{selected.name}</h2>
              <p className="text-sm text-muted-foreground">{selected.email || selected.phone || selected.address || 'No contact details'}</p>
              {selectedWebsite ? (
                <a
                  className="mt-3 inline-flex max-w-full items-center gap-2 rounded-md border px-3 py-2 text-sm font-medium text-primary hover:bg-muted hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                  href={selectedWebsite.href}
                  target="_blank"
                  rel="noopener noreferrer"
                  title={`Open ${selected.name} website`}
                >
                  <Globe2 className="h-4 w-4 shrink-0" />
                  <span className="truncate">{selectedWebsite.label}</span>
                  <ExternalLink className="h-3.5 w-3.5 shrink-0" />
                </a>
              ) : null}
              {!isContact(selected) ? (
                <Button className="mt-4" disabled={converting} onClick={() => void createContactFromLead(selected)}>
                  {converting ? <Loader2 className="h-4 w-4 animate-spin" /> : <Plus className="h-4 w-4" />}
                  Create contact
                </Button>
              ) : null}
              <div className="mt-3 flex flex-wrap gap-4 text-xs text-muted-foreground">
                <span>Last touch: {selected.last_attempted_at ? new Date(selected.last_attempted_at).toLocaleString() : 'Never'}</span>
                <span>Next follow-up: {selected.next_follow_up_at ? new Date(selected.next_follow_up_at).toLocaleString() : 'Not set'}</span>
              </div>
            </div>
            <h3 className="mb-3 font-semibold">Timeline</h3>
            <div className="space-y-3">
              {timeline.length ? timeline.map((item) => (
                <div key={`${item.timelineKind}-${item.id}`} className="rounded-lg border bg-card p-3">
                  <div className="flex justify-between gap-3">
                    <p className="font-medium">{item.subject || item.channel || item.activity_type || item.timelineKind}</p>
                    <time className="text-xs text-muted-foreground">{new Date(item.occurred_at).toLocaleString()}</time>
                  </div>
                  {item.body || item.note ? <p className="mt-1 whitespace-pre-wrap text-sm text-muted-foreground">{item.body || item.note}</p> : null}
                </div>
              )) : <p className="text-sm text-muted-foreground">No activity yet.</p>}
            </div>
          </>
        ) : (
          <div className="grid min-h-96 place-items-center text-muted-foreground">
            {mode === 'contacts'
              ? 'Choose a contact to see calls, messages, meetings, tasks, and stage changes.'
              : 'Choose a lead to review it and create a contact when you are ready.'}
          </div>
        )}
      </main>
    </div>
  );
}

function EmptyList({ icon, label }: { icon: 'contact' | 'list'; label: string }) {
  const Icon = icon === 'contact' ? UserRound : List;
  return <div className="grid min-h-48 place-items-center text-sm text-muted-foreground"><div className="text-center"><Icon className="mx-auto mb-2 h-6 w-6" /><p>{label}</p></div></div>;
}
