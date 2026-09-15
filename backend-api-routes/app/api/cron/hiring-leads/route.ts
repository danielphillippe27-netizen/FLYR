import { NextRequest, NextResponse } from 'next/server';
import { createAdminClient } from '@/lib/supabase/server';
import { collectHiringLeads } from '@/lib/hiring/collector';
import { theirStackConfigured } from '@/lib/hiring/theirstack';

export const runtime = 'nodejs';
export const maxDuration = 300;

export async function GET(request: NextRequest) {
  if (!process.env.CRON_SECRET || request.headers.get('authorization') !== `Bearer ${process.env.CRON_SECRET}`) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  try {
    if (theirStackConfigured()) {
      const { data, error } = await createAdminClient().rpc('hiring_delivery_summary');
      if (error) throw error;
      return NextResponse.json({ configured: true, mode: 'webhook', ...data });
    }
    const result = await collectHiringLeads(createAdminClient());
    const failed = result.runs.some(run => run.status === 'failed');
    return NextResponse.json(result, { status: !result.configured ? 503 : failed ? 502 : 200 });
  } catch {
    return NextResponse.json({ error: 'Hiring collection failed.' }, { status: 500 });
  }
}
