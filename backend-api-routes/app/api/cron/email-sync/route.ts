import { NextRequest, NextResponse } from 'next/server';
import { createAdminClient } from '@/lib/supabase/server';
import { syncConnection } from '@/lib/email/icloud-sync';
import type { ICloudEmailConnection } from '@/lib/email/icloud-client';

export const runtime = 'nodejs';
export const maxDuration = 300;

export async function GET(request: NextRequest) {
  if (!process.env.CRON_SECRET || request.headers.get('authorization') !== `Bearer ${process.env.CRON_SECRET}`) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  const admin = createAdminClient();
  const { data, error } = await admin.from('email_connections').select('*')
    .eq('provider', 'icloud').eq('is_active', true)
    .order('last_synced_at', { ascending: true, nullsFirst: true }).limit(25);
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  const results: Array<{ id: string; imported?: number; error?: string }> = [];
  for (const row of data ?? []) {
    try {
      results.push({ id: row.id, imported: await syncConnection(admin, row as ICloudEmailConnection) });
    } catch (cause) {
      results.push({ id: row.id, error: cause instanceof Error ? cause.message : 'iCloud sync failed' });
    }
  }
  return NextResponse.json({ processed: results.length, results });
}
