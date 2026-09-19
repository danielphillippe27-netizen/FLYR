import { NextRequest, NextResponse } from 'next/server';
import { createAdminClient } from '@/lib/supabase/server';
import { publishSocialTarget } from '@/lib/social/publisher';

export const runtime = 'nodejs';
export const maxDuration = 300;

export async function GET(request: NextRequest) {
  if (!process.env.CRON_SECRET || request.headers.get('authorization') !== `Bearer ${process.env.CRON_SECRET}`) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const admin = createAdminClient();
  const { data: targets, error } = await admin.rpc('claim_due_social_targets', { batch_size: 12 });
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  const results: unknown[] = [];
  const queue = [...(targets || [])];
  async function worker() {
    while (queue.length) {
      const target = queue.shift();
      if (!target) return;
      try { results.push({ id: target.id, ...(await publishSocialTarget(target.id, admin)) }); }
      catch (publishError) { results.push({ id: target.id, status: 'failed', error: publishError instanceof Error ? publishError.message : 'Unknown error' }); }
    }
  }
  await Promise.all(Array.from({ length: Math.min(3, queue.length) }, () => worker()));
  return NextResponse.json({ claimed: (targets || []).length, results });
}
