import { NextRequest, NextResponse } from 'next/server';
import { createAdminClient } from '@/lib/supabase/server';
import {
  loadSalespersonStripeRevenue,
  saveRevenueSnapshot,
} from '@/lib/salesperson/revenue-snapshots';

export const runtime = 'nodejs';
export const maxDuration = 300;

type SalespersonRow = {
  id: string;
  user_id: string | null;
};

export async function GET(request: NextRequest) {
  if (
    !process.env.CRON_SECRET ||
    request.headers.get('authorization') !== `Bearer ${process.env.CRON_SECRET}`
  ) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const admin = createAdminClient();
  const { data, error } = await admin
    .from('salespeople')
    .select('id,user_id')
    .eq('status', 'active')
    .not('user_id', 'is', null)
    .limit(1000);
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });

  const salespeople = (data ?? []) as SalespersonRow[];
  const results: Array<{ id: string; status: 'saved' | 'failed'; error?: string }> = [];
  for (let index = 0; index < salespeople.length; index += 5) {
    const batch = salespeople.slice(index, index + 5);
    results.push(
      ...(await Promise.all(
        batch.map(async (salesperson) => {
          try {
            const revenue = await loadSalespersonStripeRevenue(admin, salesperson.id, salesperson.user_id!);
            await saveRevenueSnapshot(admin, {
              salespersonId: salesperson.id,
              userId: salesperson.user_id!,
              revenue,
            });
            return { id: salesperson.id, status: 'saved' as const };
          } catch (snapshotError) {
            return {
              id: salesperson.id,
              status: 'failed' as const,
              error: snapshotError instanceof Error ? snapshotError.message : 'Unknown error',
            };
          }
        })
      ))
    );
  }

  return NextResponse.json({
    processed: results.length,
    saved: results.filter((result) => result.status === 'saved').length,
    failed: results.filter((result) => result.status === 'failed').length,
    results,
  });
}
