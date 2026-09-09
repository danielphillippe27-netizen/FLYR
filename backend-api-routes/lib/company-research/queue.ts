import type { SupabaseClient } from '@supabase/supabase-js';
import { leadIdsForSmartList, resolveCompanyById, resolveCompanyForLead, type ResearchCompany } from './identity';
import type { CompanyResearchBatch, CompanyResearchRecord } from './types';

type AdminClient = SupabaseClient<any, 'public', any>;
const DEFAULT_MODEL = 'gpt-5.4-mini-2026-03-17';
const FRESH_WINDOW_MS = 30 * 24 * 60 * 60 * 1_000;
export const COMPANY_RESEARCH_BATCH_LIMIT = 100;

function modelName(): string {
  return process.env.OPENAI_COMPANY_RESEARCH_MODEL?.trim() || DEFAULT_MODEL;
}

export function researchIdentitySnapshot(company: ResearchCompany): Record<string, unknown> {
  return {
    name: company.name,
    website: company.website ?? null,
    websiteDomain: company.website_domain ?? null,
    phone: company.phone ?? null,
    email: company.email ?? null,
    address: company.address ?? null,
    city: company.city ?? null,
    region: company.region ?? null,
    countryCode: company.country_code ?? null,
    googlePlaceId: company.google_place_id ?? null,
  };
}

async function activeResearch(admin: AdminClient, workspaceId: string, companyId: string): Promise<CompanyResearchRecord | null> {
  const { data, error } = await admin.from('sales_company_research').select('*')
    .eq('workspace_id', workspaceId).eq('company_id', companyId)
    .in('status', ['queued', 'researching']).order('created_at', { ascending: false }).limit(1).maybeSingle();
  if (error) throw error;
  return data as CompanyResearchRecord | null;
}

export async function latestCompanyResearch(admin: AdminClient, workspaceId: string, companyId: string): Promise<{
  active: CompanyResearchRecord | null;
  latest: CompanyResearchRecord | null;
  history: CompanyResearchRecord[];
}> {
  const { data, error } = await admin.from('sales_company_research').select('*')
    .eq('workspace_id', workspaceId).eq('company_id', companyId)
    .order('created_at', { ascending: false }).limit(10);
  if (error) throw error;
  const history = (data ?? []) as CompanyResearchRecord[];
  return {
    active: history.find((row) => row.status === 'queued' || row.status === 'researching') ?? null,
    latest: history.find((row) => row.status === 'completed' || row.status === 'partial') ?? null,
    history,
  };
}

async function enqueueResolvedCompany(admin: AdminClient, input: {
  workspaceId: string;
  userId: string;
  company: ResearchCompany;
  batchId?: string | null;
  triggerKind: 'single' | 'list';
}): Promise<{ research: CompanyResearchRecord; reused: boolean }> {
  const active = await activeResearch(admin, input.workspaceId, input.company.id);
  if (active) return { research: active, reused: true };
  const { data, error } = await admin.from('sales_company_research').insert({
    workspace_id: input.workspaceId,
    company_id: input.company.id,
    batch_id: input.batchId ?? null,
    requested_by_user_id: input.userId,
    trigger_kind: input.triggerKind,
    status: 'queued',
    identity_snapshot: researchIdentitySnapshot(input.company),
    model: modelName(),
  }).select('*').single();
  if (error) {
    const raced = await activeResearch(admin, input.workspaceId, input.company.id);
    if (raced) return { research: raced, reused: true };
    throw error;
  }
  return { research: data as CompanyResearchRecord, reused: false };
}

export async function enqueueCompanyResearch(admin: AdminClient, input: {
  workspaceId: string;
  userId: string;
  companyId?: string | null;
  leadId?: string | null;
}): Promise<{ company: ResearchCompany; research: CompanyResearchRecord; reused: boolean }> {
  const company = input.companyId
    ? await resolveCompanyById(admin, input.workspaceId, input.companyId)
    : input.leadId
      ? await resolveCompanyForLead(admin, input.workspaceId, input.leadId, input.userId)
      : null;
  if (!company) throw new Error('A companyId or leadId is required.');
  const queued = await enqueueResolvedCompany(admin, {
    workspaceId: input.workspaceId,
    userId: input.userId,
    company,
    triggerKind: 'single',
  });
  return { company, ...queued };
}

async function hasFreshResearch(admin: AdminClient, workspaceId: string, companyId: string): Promise<boolean> {
  const cutoff = new Date(Date.now() - FRESH_WINDOW_MS).toISOString();
  const { data, error } = await admin.from('sales_company_research').select('id')
    .eq('workspace_id', workspaceId).eq('company_id', companyId)
    .in('status', ['completed', 'partial']).gte('completed_at', cutoff).limit(1).maybeSingle();
  if (error) throw error;
  return Boolean(data);
}

export async function enqueueListResearch(admin: AdminClient, input: {
  workspaceId: string;
  userId: string;
  listId: string;
  refreshAll: boolean;
}): Promise<{ batch: CompanyResearchBatch; queued: number; skipped: number; capped: boolean }> {
  const list = await leadIdsForSmartList(admin, input.workspaceId, input.listId, input.userId);
  const snapshotLeadIds = list.leadIds.slice(0, COMPANY_RESEARCH_BATCH_LIMIT);
  const companies: ResearchCompany[] = [];
  for (const leadId of snapshotLeadIds) {
    try {
      const company = await resolveCompanyForLead(admin, input.workspaceId, leadId, input.userId);
      if (!companies.some((candidate) => candidate.id === company.id)) companies.push(company);
    } catch (error) {
      console.warn('[company-research] skipped unresolved list lead', { leadId, error });
    }
  }
  const eligible: ResearchCompany[] = [];
  let skipped = Math.max(0, list.leadIds.length - snapshotLeadIds.length);
  for (const company of companies) {
    if (!input.refreshAll && await hasFreshResearch(admin, input.workspaceId, company.id)) skipped += 1;
    else eligible.push(company);
  }
  const { data: rawBatch, error: batchError } = await admin.from('sales_company_research_batches').insert({
    workspace_id: input.workspaceId,
    smart_list_id: input.listId,
    smart_list_name: list.listName,
    requested_by_user_id: input.userId,
    refresh_all: input.refreshAll,
    requested_count: eligible.length,
    skipped_count: skipped,
    status: eligible.length ? 'queued' : 'completed',
    completed_at: eligible.length ? null : new Date().toISOString(),
  }).select('*').single();
  if (batchError) throw batchError;
  const batch = rawBatch as CompanyResearchBatch;
  let queued = 0;
  for (const company of eligible) {
    const result = await enqueueResolvedCompany(admin, {
      workspaceId: input.workspaceId,
      userId: input.userId,
      company,
      batchId: batch.id,
      triggerKind: 'list',
    });
    if (!result.reused || result.research.batch_id === batch.id) queued += 1;
    else skipped += 1;
  }
  if (queued !== batch.requested_count || skipped !== batch.skipped_count) {
    const status = queued ? 'queued' : 'completed';
    const { data } = await admin.from('sales_company_research_batches').update({
      requested_count: queued,
      skipped_count: skipped,
      status,
      completed_at: queued ? null : new Date().toISOString(),
    }).eq('id', batch.id).select('*').single();
    if (data) Object.assign(batch, data);
  }
  return { batch, queued, skipped, capped: list.leadIds.length > COMPANY_RESEARCH_BATCH_LIMIT };
}

export async function getResearchBatch(admin: AdminClient, workspaceId: string, batchId: string) {
  const { data: batch, error } = await admin.from('sales_company_research_batches').select('*')
    .eq('workspace_id', workspaceId).eq('id', batchId).maybeSingle();
  if (error) throw error;
  if (!batch) throw new Error('Research batch was not found.');
  const { data: jobs, error: jobsError } = await admin.from('sales_company_research')
    .select('id,company_id,status,error_code,error_message,created_at,completed_at')
    .eq('workspace_id', workspaceId).eq('batch_id', batchId).order('created_at');
  if (jobsError) throw jobsError;
  const counts = { queued: 0, researching: 0, completed: 0, partial: 0, failed: 0 };
  for (const job of jobs ?? []) counts[job.status as keyof typeof counts] += 1;
  return { batch, jobs: jobs ?? [], counts };
}

export async function retryResearchBatch(admin: AdminClient, workspaceId: string, batchId: string): Promise<number> {
  const { data, error } = await admin.from('sales_company_research').update({
    status: 'queued',
    attempt_count: 0,
    next_attempt_at: new Date().toISOString(),
    error_code: null,
    error_message: null,
  }).eq('workspace_id', workspaceId).eq('batch_id', batchId).eq('status', 'failed').select('id');
  if (error) throw error;
  if ((data ?? []).length) await admin.from('sales_company_research_batches').update({ status: 'queued', completed_at: null }).eq('id', batchId);
  return (data ?? []).length;
}

