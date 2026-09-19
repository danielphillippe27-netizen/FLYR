import { after, NextRequest, NextResponse } from 'next/server';
import { z } from 'zod';
import { requireSalesProContext } from '@/lib/sales-pro/context';
import {
  enqueueCompanyResearch,
  enqueueListResearch,
  getResearchBatch,
  latestCompanyResearch,
  retryResearchBatch,
} from '@/lib/company-research/queue';
import { processCompanyResearchQueue } from '@/lib/company-research/worker';
import { resolveCompanyById } from '@/lib/company-research/identity';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export const maxDuration = 300;

const requestSchema = z.object({
  companyId: z.string().uuid().optional(),
  leadId: z.string().uuid().optional(),
  contactId: z.string().uuid().optional(),
  listId: z.string().uuid().optional(),
  retryBatchId: z.string().uuid().optional(),
  refreshAll: z.boolean().default(false),
}).refine((body) => [body.companyId, body.leadId, body.contactId, body.listId, body.retryBatchId].filter(Boolean).length === 1, {
  message: 'Provide exactly one companyId, leadId, contactId, listId, or retryBatchId.',
});

async function leadIdForContact(admin: any, workspaceId: string, contactId: string): Promise<string | null> {
  const { data, error } = await admin.from('sales_leads').select('id')
    .eq('workspace_id', workspaceId)
    .or(`sales_contact_id.eq.${contactId},contact_id.eq.${contactId},legacy_contact_id.eq.${contactId}`)
    .order('updated_at', { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  return data?.id ?? null;
}

function queueImmediateWork(admin: any) {
  after(async () => {
    try {
      await processCompanyResearchQueue(admin, 2);
    } catch (error) {
      console.error('[company-research] immediate worker failed', error);
    }
  });
}

export async function GET(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  try {
    const batchId = request.nextUrl.searchParams.get('batchId');
    if (batchId) return NextResponse.json(await getResearchBatch(context.admin, context.workspaceId, batchId));

    let companyId = request.nextUrl.searchParams.get('companyId');
    let leadId = request.nextUrl.searchParams.get('leadId');
    const contactId = request.nextUrl.searchParams.get('contactId');
    if (!leadId && contactId) leadId = await leadIdForContact(context.admin, context.workspaceId, contactId);
    if (!companyId && leadId) {
      const { data: lead, error } = await context.admin.from('sales_leads').select('company_id')
        .eq('workspace_id', context.workspaceId).eq('id', leadId).maybeSingle();
      if (error) throw error;
      companyId = lead?.company_id ?? null;
    }
    if (!companyId) return NextResponse.json({ company: null, active: null, latest: null, history: [] });
    const company = await resolveCompanyById(context.admin, context.workspaceId, companyId);
    return NextResponse.json({ company, ...(await latestCompanyResearch(context.admin, context.workspaceId, companyId)) });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Failed to load company research.';
    return NextResponse.json({ error: message }, { status: message.includes('not found') ? 404 : 500 });
  }
}

export async function POST(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  if (!process.env.OPENAI_API_KEY?.trim()) {
    return NextResponse.json({
      error: 'Company research is not configured. Add OPENAI_API_KEY to the backend environment.',
      code: 'openai_not_configured',
    }, { status: 503 });
  }
  const parsed = requestSchema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) return NextResponse.json({ error: parsed.error.issues[0]?.message ?? 'Invalid research request.' }, { status: 400 });
  try {
    if (parsed.data.retryBatchId) {
      const retried = await retryResearchBatch(context.admin, context.workspaceId, parsed.data.retryBatchId);
      queueImmediateWork(context.admin);
      return NextResponse.json({ batchId: parsed.data.retryBatchId, retried }, { status: 202 });
    }
    if (parsed.data.listId) {
      const queued = await enqueueListResearch(context.admin, {
        workspaceId: context.workspaceId,
        userId: context.userId,
        listId: parsed.data.listId,
        refreshAll: parsed.data.refreshAll,
      });
      if (queued.queued > 0) queueImmediateWork(context.admin);
      return NextResponse.json(queued, { status: 202 });
    }
    const leadId = parsed.data.leadId ?? (parsed.data.contactId
      ? await leadIdForContact(context.admin, context.workspaceId, parsed.data.contactId)
      : undefined);
    if (parsed.data.contactId && !leadId) throw new Error('A shared sales lead is required before researching this contact.');
    const queued = await enqueueCompanyResearch(context.admin, {
      workspaceId: context.workspaceId,
      userId: context.userId,
      companyId: parsed.data.companyId,
      leadId,
    });
    queueImmediateWork(context.admin);
    return NextResponse.json(queued, { status: 202 });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Failed to queue company research.';
    const status = message.includes('not found') ? 404 : message.includes('required') || message.includes('Add a company') ? 400 : 500;
    return NextResponse.json({ error: message }, { status });
  }
}
