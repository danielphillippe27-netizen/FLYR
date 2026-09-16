import type { createAdminClient } from '@/lib/supabase/server';
import { adzunaSearchURL, hiringSourceConfigured, parseAdzunaPage, postingFingerprint } from './postings';

type Admin = ReturnType<typeof createAdminClient>;
const MAX_PAGES_PER_COUNTRY = 10;

export async function collectHiringLeads(admin: Admin, fetchPage: typeof fetch = fetch) {
  if (!hiringSourceConfigured()) return { configured: false, runs: [] };
  const runs: Array<Record<string, unknown>> = [];
  for (const country of ['CA', 'US'] as const) {
    const { data: runId, error: claimError } = await admin.rpc('claim_hiring_collection', { p_country: country });
    if (claimError) throw new Error('Could not claim hiring collection.');
    if (!runId) { runs.push({ country, status: 'already_claimed' }); continue; }
    let fetched = 0;
    let rejected = 0;
    let received = 0;
    let available = 0;
    let complete = false;
    let failure: string | null = null;
    try {
      for (let page = 1; page <= MAX_PAGES_PER_COUNTRY; page++) {
        const response = await fetchPage(adzunaSearchURL(country, page), {
          headers: { Accept: 'application/json' }, cache: 'no-store',
          signal: AbortSignal.timeout(10000), redirect: 'error',
        });
        // Never include request URLs, credentials, or provider response bodies in logs.
        if (!response.ok) throw new Error(`Job provider returned HTTP ${response.status}.`);
        const parsed = parseAdzunaPage(await response.json(), country);
        available = parsed.count;
        rejected += parsed.rejected;
        received += parsed.received;
        if (parsed.postings.length) {
          const { error } = await admin.rpc('ingest_hiring_postings', {
            p_postings: parsed.postings.map(posting => ({ ...posting, fingerprint: postingFingerprint(posting) })),
          });
          if (error) throw new Error('Could not save hiring postings.');
          fetched += parsed.postings.length;
        }
        if (received >= available) { complete = true; break; }
        // A short/empty page before count is reached is incomplete, not success.
        if (parsed.received < 50) break;
      }
    } catch (error) {
      failure = error instanceof Error && /^(Job provider returned HTTP \d+\.|Could not save hiring postings\.)$/.test(error.message)
        ? error.message : 'Job collection failed. Check source access and retry.';
    }
    const status = failure ? 'failed' : complete && rejected === 0 ? 'complete' : 'partial';
    const summary = {
      status, fetched, rejected, available, finished_at: new Date().toISOString(),
      error_message: failure ?? (status === 'partial' ? 'Some results were not collected. Coverage is incomplete.' : null),
    };
    const { error } = await admin.from('hiring_collection_runs').update(summary).eq('id', runId).eq('status', 'running');
    if (error) throw new Error('Could not save hiring collection status.');
    runs.push({ country, ...summary });
  }
  return { configured: true, runs };
}
