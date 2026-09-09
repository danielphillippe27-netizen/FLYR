import { NextRequest, NextResponse } from 'next/server';
import { createAdminClient } from '@/lib/supabase/server';
import { processCompanyResearchQueue } from '@/lib/company-research/worker';

export const runtime = 'nodejs';
export const maxDuration = 300;

export async function GET(request: NextRequest) {
  if (!process.env.CRON_SECRET || request.headers.get('authorization') !== `Bearer ${process.env.CRON_SECRET}`) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  try {
    const results = await processCompanyResearchQueue(createAdminClient(), 2);
    return NextResponse.json({ claimed: results.length, results });
  } catch (error) {
    console.error('[cron/company-research]', error);
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Company research worker failed.' }, { status: 500 });
  }
}

