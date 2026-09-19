import type { SupabaseClient } from '@supabase/supabase-js';
import { researchCompanyWithOpenAI } from './openai';
import { resolveCompanyById } from './identity';

type AdminClient = SupabaseClient<any, 'public', any>;

function retryAt(attempt: number): string {
  return new Date(Date.now() + Math.min(60, 2 ** Math.max(0, attempt - 1) * 5) * 60_000).toISOString();
}

async function refreshBatch(admin: AdminClient, batchId: string | null | undefined) {
  if (!batchId) return;
  const { data: jobs, error } = await admin.from('sales_company_research').select('status').eq('batch_id', batchId);
  if (error) throw error;
  const statuses = (jobs ?? []).map((job) => String(job.status));
  const hasActive = statuses.some((status) => status === 'queued' || status === 'researching');
  const hasSuccess = statuses.some((status) => status === 'completed' || status === 'partial');
  const hasFailure = statuses.some((status) => status === 'failed');
  const status = hasActive ? 'researching' : hasFailure ? (hasSuccess ? 'partial' : 'failed') : 'completed';
  await admin.from('sales_company_research_batches').update({
    status,
    completed_at: hasActive ? null : new Date().toISOString(),
  }).eq('id', batchId);
}

async function processClaimedJob(admin: AdminClient, job: any) {
  try {
    const company = await resolveCompanyById(admin, job.workspace_id, job.company_id);
    const researched = await researchCompanyWithOpenAI(company);
    const partial = researched.sources.length === 0 || researched.result.overallConfidence === 'low';
    const completedAt = new Date();
    const { error } = await admin.from('sales_company_research').update({
      status: partial ? 'partial' : 'completed',
      result: researched.result,
      sources: researched.sources,
      overall_confidence: researched.result.overallConfidence,
      model: researched.model,
      openai_response_id: researched.responseId,
      input_tokens: researched.inputTokens,
      output_tokens: researched.outputTokens,
      total_tokens: researched.totalTokens,
      web_search_calls: researched.webSearchCalls,
      completed_at: completedAt.toISOString(),
      expires_at: new Date(completedAt.getTime() + 30 * 24 * 60 * 60 * 1_000).toISOString(),
      error_code: null,
      error_message: null,
    }).eq('id', job.id);
    if (error) throw error;
    await refreshBatch(admin, job.batch_id);
    return { id: job.id, status: partial ? 'partial' : 'completed' };
  } catch (cause) {
    const message = cause instanceof Error ? cause.message : 'Unknown company research failure.';
    const code = typeof cause === 'object' && cause && 'code' in cause ? String(cause.code) : 'research_failed';
    const retryable = !['openai_not_configured', 'invalid_api_key'].includes(code) && Number(job.attempt_count) < 3;
    await admin.from('sales_company_research').update({
      status: retryable ? 'queued' : 'failed',
      next_attempt_at: retryable ? retryAt(Number(job.attempt_count)) : new Date().toISOString(),
      completed_at: retryable ? null : new Date().toISOString(),
      error_code: code,
      error_message: message.slice(0, 1_000),
    }).eq('id', job.id);
    await refreshBatch(admin, job.batch_id);
    return { id: job.id, status: retryable ? 'queued' : 'failed', error: message };
  }
}

export async function processCompanyResearchQueue(admin: AdminClient, batchSize = 2) {
  const { data: claimed, error } = await admin.rpc('claim_due_company_research_jobs', { batch_size: Math.min(2, Math.max(1, batchSize)) });
  if (error) throw error;
  return Promise.all((claimed ?? []).map((job: any) => processClaimedJob(admin, job)));
}

