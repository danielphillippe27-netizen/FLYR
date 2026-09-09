'use client';

import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react';
import {
  AlertCircle,
  CalendarClock,
  Loader2,
  MoreHorizontal,
  Plus,
  RefreshCw,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { useWorkspace } from '@/lib/workspace-context';
import { cn } from '@/lib/utils';

type Stage = {
  id: string;
  stage_key: string;
  name: string;
  color: string;
  position: number;
  terminal_kind?: 'won' | 'lost' | null;
  is_archived: boolean;
};

type Lead = {
  id: string;
  name: string;
  company?: string | null;
  email?: string | null;
  phone?: string | null;
  pipeline_stage?: string | null;
  pipeline_stage_id?: string | null;
  next_task_title?: string | null;
  next_follow_up_at?: string | null;
  last_touch_summary?: string | null;
};

type ApiError = { error?: string };
type StagesResponse = ApiError & { stages?: Stage[]; stage?: Stage };
type LeadsResponse = ApiError & { leads?: Lead[]; lead?: Lead };

const LEGACY_STAGE_KEYS: Record<string, string> = {
  new_lead: 'new',
  attempting_contact: 'contacted',
  nurture: 'contacted',
  connected: 'conversation',
  demo_sent: 'proposal',
  trial_sent: 'proposal',
  trial_active: 'proposal',
  closing: 'proposal',
  won: 'won',
  lost: 'lost',
};

async function readJson<T extends ApiError>(response: Response): Promise<T> {
  return response.json().catch(() => ({} as T));
}

function dueLabel(value?: string | null): { label: string; overdue: boolean } | null {
  if (!value) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;

  const overdue = date.getTime() < Date.now();
  return {
    label: `${overdue ? 'Overdue' : 'Due'} ${date.toLocaleDateString(undefined, {
      month: 'short',
      day: 'numeric',
    })}`,
    overdue,
  };
}

function resolvedStageId(lead: Lead, stages: Stage[]): string | null {
  if (lead.pipeline_stage_id && stages.some((stage) => stage.id === lead.pipeline_stage_id)) {
    return lead.pipeline_stage_id;
  }

  const legacyKey = lead.pipeline_stage ? LEGACY_STAGE_KEYS[lead.pipeline_stage] : null;
  return stages.find((stage) => stage.stage_key === legacyKey)?.id ?? stages[0]?.id ?? null;
}

export function ProPipelineBoard() {
  const { currentWorkspaceId, membershipsByWorkspaceId } = useWorkspace();
  const [stages, setStages] = useState<Stage[]>([]);
  const [leads, setLeads] = useState<Lead[]>([]);
  const [name, setName] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [addingStage, setAddingStage] = useState(false);
  const [movingLeadId, setMovingLeadId] = useState<string | null>(null);

  const admin = currentWorkspaceId
    ? ['owner', 'admin'].includes(membershipsByWorkspaceId[currentWorkspaceId] ?? '')
    : false;

  const load = useCallback(async () => {
    if (!currentWorkspaceId) {
      setStages([]);
      setLeads([]);
      setLoading(false);
      return;
    }

    setLoading(true);
    try {
      const suffix = `?workspaceId=${encodeURIComponent(currentWorkspaceId)}`;
      const [stageResponse, leadResponse] = await Promise.all([
        fetch(`/api/pipeline/stages${suffix}`, { cache: 'no-store' }),
        fetch(`/api/salesperson/pipeline${suffix}`, { cache: 'no-store' }),
      ]);
      const [stageData, leadData] = await Promise.all([
        readJson<StagesResponse>(stageResponse),
        readJson<LeadsResponse>(leadResponse),
      ]);

      if (!stageResponse.ok) {
        throw new Error(stageData.error || 'Pipeline stages could not be loaded.');
      }
      if (!leadResponse.ok) {
        throw new Error(leadData.error || 'Pipeline leads could not be loaded.');
      }

      setStages(
        (stageData.stages ?? [])
          .filter((stage) => !stage.is_archived)
          .sort((left, right) => left.position - right.position)
      );
      setLeads(leadData.leads ?? []);
      setError(null);
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'Pipeline could not be loaded.');
    } finally {
      setLoading(false);
    }
  }, [currentWorkspaceId]);

  useEffect(() => {
    void load();
    const timer = window.setInterval(() => void load(), 30_000);
    return () => window.clearInterval(timer);
  }, [load]);

  const grouped = useMemo(
    () => stages.map((stage) => ({
      stage,
      leads: leads.filter((lead) => resolvedStageId(lead, stages) === stage.id),
    })),
    [leads, stages]
  );

  const overdueCount = useMemo(
    () => leads.filter((lead) => {
      if (!lead.next_follow_up_at) return false;
      const date = new Date(lead.next_follow_up_at);
      return !Number.isNaN(date.getTime()) && date.getTime() < Date.now();
    }).length,
    [leads]
  );
  const noNextActionCount = useMemo(
    () => leads.filter((lead) => !lead.next_task_title || !lead.next_follow_up_at).length,
    [leads]
  );

  async function move(lead: Lead, stage: Stage) {
    const previousStageId = lead.pipeline_stage_id ?? null;
    setMovingLeadId(lead.id);
    setError(null);
    setLeads((current) => current.map((item) => (
      item.id === lead.id ? { ...item, pipeline_stage_id: stage.id } : item
    )));

    try {
      const response = await fetch(`/api/salesperson/pipeline/${lead.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ pipelineStageId: stage.id }),
      });
      const data = await readJson<LeadsResponse>(response);
      if (!response.ok) throw new Error(data.error || 'Lead could not be moved.');
      if (data.lead) {
        setLeads((current) => current.map((item) => item.id === lead.id ? data.lead! : item));
      }
    } catch (moveError) {
      setLeads((current) => current.map((item) => (
        item.id === lead.id ? { ...item, pipeline_stage_id: previousStageId } : item
      )));
      setError(moveError instanceof Error ? moveError.message : 'Lead could not be moved.');
    } finally {
      setMovingLeadId(null);
    }
  }

  async function addStage(event?: FormEvent) {
    event?.preventDefault();
    const trimmedName = name.trim();
    if (!trimmedName || !currentWorkspaceId || addingStage) return;

    setAddingStage(true);
    setError(null);
    try {
      const response = await fetch(
        `/api/pipeline/stages?workspaceId=${encodeURIComponent(currentWorkspaceId)}`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ name: trimmedName }),
        }
      );
      const data = await readJson<StagesResponse>(response);
      if (!response.ok) throw new Error(data.error || 'Pipeline stage could not be added.');
      setName('');
      await load();
    } catch (stageError) {
      setError(stageError instanceof Error ? stageError.message : 'Pipeline stage could not be added.');
    } finally {
      setAddingStage(false);
    }
  }

  async function updateStage(payload: object) {
    if (!currentWorkspaceId) return;
    setError(null);
    try {
      const response = await fetch(
        `/api/pipeline/stages?workspaceId=${encodeURIComponent(currentWorkspaceId)}`,
        {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        }
      );
      const data = await readJson<StagesResponse>(response);
      if (!response.ok) throw new Error(data.error || 'Pipeline stage could not be updated.');
      await load();
    } catch (stageError) {
      setError(stageError instanceof Error ? stageError.message : 'Pipeline stage could not be updated.');
    }
  }

  async function moveStage(stage: Stage, offset: number) {
    const index = stages.findIndex((item) => item.id === stage.id);
    const target = index + offset;
    if (target < 0 || target >= stages.length) return;
    const order = stages.map((item) => item.id);
    [order[index], order[target]] = [order[target], order[index]];
    await updateStage({ order });
  }

  return (
    <div className="min-h-full bg-slate-50 p-5 dark:bg-background">
      <div className="mb-5 flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold">Pipeline</h1>
          <p className="text-sm text-muted-foreground">Every opportunity, its current stage, and the next action.</p>
          <div className="mt-3 flex flex-wrap gap-2 text-xs">
            <span className="rounded-full border bg-background px-2.5 py-1 font-medium">{leads.length} opportunities</span>
            <span className={cn(
              'rounded-full border bg-background px-2.5 py-1 font-medium',
              overdueCount > 0 && 'border-red-200 bg-red-50 text-red-700 dark:border-red-400/30 dark:bg-red-400/10 dark:text-red-200'
            )}>
              {overdueCount} overdue
            </span>
            <span className={cn(
              'rounded-full border bg-background px-2.5 py-1 font-medium',
              noNextActionCount > 0 && 'border-amber-200 bg-amber-50 text-amber-700 dark:border-amber-400/30 dark:bg-amber-400/10 dark:text-amber-200'
            )}>
              {noNextActionCount} need a next action
            </span>
          </div>
        </div>
        <Button variant="outline" onClick={() => void load()} disabled={loading}>
          {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : <RefreshCw className="h-4 w-4" />}
          Refresh
        </Button>
      </div>

      {admin ? (
        <form className="mb-4 flex max-w-md gap-2" onSubmit={(event) => void addStage(event)}>
          <Input
            value={name}
            onChange={(event) => setName(event.target.value)}
            placeholder="Add pipeline stage"
            aria-label="Pipeline stage name"
          />
          <Button type="submit" disabled={!name.trim() || addingStage}>
            {addingStage ? <Loader2 className="h-4 w-4 animate-spin" /> : <Plus className="h-4 w-4" />}
            Add
          </Button>
        </form>
      ) : null}

      {error ? (
        <div className="mb-4 flex flex-wrap items-center gap-3 rounded-md border border-destructive/30 bg-destructive/10 p-3 text-sm text-destructive">
          <AlertCircle className="h-4 w-4 shrink-0" />
          <span className="min-w-0 flex-1">{error}</span>
          <Button type="button" variant="outline" size="sm" onClick={() => void load()} disabled={loading}>
            Try again
          </Button>
        </div>
      ) : null}

      {loading && stages.length === 0 ? (
        <div className="grid min-h-80 place-items-center rounded-xl border bg-background text-sm text-muted-foreground">
          <span className="flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading pipeline…</span>
        </div>
      ) : stages.length === 0 ? (
        <div className="grid min-h-80 place-items-center rounded-xl border border-dashed bg-background p-8 text-center">
          <div>
            <h2 className="font-semibold">No pipeline stages yet</h2>
            <p className="mt-1 text-sm text-muted-foreground">
              {admin ? 'Add the first stage above to start organizing opportunities.' : 'Ask a workspace admin to add the first stage.'}
            </p>
          </div>
        </div>
      ) : (
        <div className="flex gap-4 overflow-x-auto pb-5">
          {grouped.map(({ stage, leads: rows }, stageIndex) => (
            <section key={stage.id} className="w-72 shrink-0 rounded-xl border bg-muted/30 p-3">
              <header className="mb-3 flex items-center gap-2">
                <span className="h-2.5 w-2.5 rounded-full" style={{ backgroundColor: stage.color }} />
                <h2 className="truncate font-semibold">{stage.name}</h2>
                <span className="ml-auto rounded-full bg-background px-2 py-0.5 text-xs font-medium text-muted-foreground">
                  {rows.length}
                </span>
                {admin ? (
                  <details className="relative">
                    <summary className="grid h-7 w-7 cursor-pointer list-none place-items-center rounded-md hover:bg-muted" aria-label={`Manage ${stage.name}`}>
                      <MoreHorizontal className="h-4 w-4" />
                    </summary>
                    <div className="absolute right-0 z-10 mt-1 w-36 rounded-md border bg-background p-1 shadow-lg">
                      <button
                        type="button"
                        className="w-full rounded px-2 py-1 text-left text-xs hover:bg-muted"
                        onClick={() => {
                          const value = window.prompt('Stage name', stage.name);
                          if (value?.trim()) void updateStage({ id: stage.id, name: value.trim() });
                        }}
                      >
                        Rename
                      </button>
                      <button type="button" disabled={stageIndex === 0} className="w-full rounded px-2 py-1 text-left text-xs hover:bg-muted disabled:opacity-40" onClick={() => void moveStage(stage, -1)}>Move left</button>
                      <button type="button" disabled={stageIndex === stages.length - 1} className="w-full rounded px-2 py-1 text-left text-xs hover:bg-muted disabled:opacity-40" onClick={() => void moveStage(stage, 1)}>Move right</button>
                      <button
                        type="button"
                        className="w-full rounded px-2 py-1 text-left text-xs text-destructive hover:bg-muted"
                        onClick={() => {
                          if (window.confirm(`Archive “${stage.name}”?`)) {
                            void updateStage({ id: stage.id, isArchived: true });
                          }
                        }}
                      >
                        Archive
                      </button>
                    </div>
                  </details>
                ) : null}
              </header>

              <div className="space-y-3">
                {rows.length === 0 ? (
                  <div className="rounded-lg border border-dashed bg-background/60 px-3 py-8 text-center text-xs text-muted-foreground">
                    No opportunities in this stage
                  </div>
                ) : rows.map((lead) => {
                  const due = dueLabel(lead.next_follow_up_at);
                  return (
                    <Card key={lead.id} className="gap-3 p-3 shadow-sm">
                      <div>
                        <p className="font-semibold">{lead.name}</p>
                        <p className="truncate text-xs text-muted-foreground">
                          {lead.company || lead.email || lead.phone || 'No contact details'}
                        </p>
                      </div>

                      <div className={cn(
                        'rounded-md border p-2 text-xs',
                        lead.next_task_title && lead.next_follow_up_at
                          ? 'bg-background text-muted-foreground'
                          : 'border-amber-200 bg-amber-50 text-amber-700 dark:border-amber-400/30 dark:bg-amber-400/10 dark:text-amber-200'
                      )}>
                        <p className="font-medium">{lead.next_task_title || 'Next action needed'}</p>
                        {due ? (
                          <p className={cn('mt-1 flex items-center gap-1', due.overdue && 'font-medium text-red-600 dark:text-red-300')}>
                            <CalendarClock className="h-3.5 w-3.5" /> {due.label}
                          </p>
                        ) : (
                          <p className="mt-1">No due date</p>
                        )}
                      </div>

                      {lead.last_touch_summary ? (
                        <p className="line-clamp-2 text-xs text-muted-foreground">Last touch: {lead.last_touch_summary}</p>
                      ) : null}

                      <label className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
                        Stage
                        <select
                          className="mt-1 h-8 w-full rounded-md border bg-background px-2 text-xs font-normal normal-case tracking-normal text-foreground"
                          value={resolvedStageId(lead, stages) ?? ''}
                          disabled={movingLeadId === lead.id}
                          onChange={(event) => {
                            const target = stages.find((item) => item.id === event.target.value);
                            if (target) void move(lead, target);
                          }}
                        >
                          {stages.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}
                        </select>
                      </label>
                    </Card>
                  );
                })}
              </div>
            </section>
          ))}
        </div>
      )}
    </div>
  );
}
