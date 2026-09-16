import { NextRequest, NextResponse } from 'next/server';
import { z } from 'zod';
import { resolveUserFromRequest } from '@/app/api/_utils/request-user';
import { createAdminClient } from '@/lib/supabase/server';
import { resolveSalespersonForUser } from '@/lib/dialer/salesperson-settings';
import { feedQuerySchema, reviewSchema } from '@/lib/hiring/postings';
import { hiringSource } from '@/lib/hiring/source';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

async function authorize(request: NextRequest) {
  const user = await resolveUserFromRequest(request);
  if (!user) return { response: NextResponse.json({ error: 'Unauthorized' }, { status: 401 }) };
  const admin = createAdminClient();
  const salesperson = await resolveSalespersonForUser(admin, { userId: user.id, email: user.email });
  if (!salesperson) return { response: NextResponse.json({ error: 'Salesperson access required.' }, { status: 403 }) };
  return { user, admin };
}

export async function GET(request: NextRequest) {
  try {
    const auth = await authorize(request);
    if (auth.response) return auth.response;
    const parsed = feedQuerySchema.safeParse(Object.fromEntries(request.nextUrl.searchParams));
    if (!parsed.success) return NextResponse.json({ error: 'Invalid hiring feed filters.' }, { status: 400 });
    const { country, status, q, days, offset } = parsed.data;
    const [feed, runs, delivery] = await Promise.all([
      auth.admin.rpc('list_hiring_leads', {
        p_user_id: auth.user.id, p_country: country, p_status: status,
        p_search: q, p_days: days, p_offset: offset,
      }),
      auth.admin.from('hiring_collection_runs').select('id,country,status,started_at,finished_at,fetched,rejected,available,error_message')
        .order('started_at', { ascending: false }).limit(10),
      auth.admin.rpc('hiring_delivery_summary'),
    ]);
    if (feed.error || runs.error || delivery.error) {
      return NextResponse.json({ error: 'Hiring Leads is not ready. The server setup needs to be completed.' }, { status: 503 });
    }
    return NextResponse.json({
      ...feed.data,
      source: { ...hiringSource(), ...delivery.data },
      runs: runs.data ?? [],
    }, { headers: { 'Cache-Control': 'private, no-store' } });
  } catch {
    return NextResponse.json({ error: 'Could not load hiring leads.' }, { status: 500 });
  }
}

export async function PATCH(request: NextRequest) {
  try {
    const auth = await authorize(request);
    if (auth.response) return auth.response;
    const body = await request.json().catch(() => null);
    const parsed = z.object({ leadId: z.string().uuid(), status: reviewSchema }).strict().safeParse(body);
    if (!parsed.success) return NextResponse.json({ error: 'Invalid lead update.' }, { status: 400 });
    const { leadId, status } = parsed.data;
    const { data: lead, error: lookupError } = await auth.admin.from('hiring_leads').select('id').eq('id', leadId).maybeSingle();
    if (lookupError) throw lookupError;
    if (!lead) return NextResponse.json({ error: 'Hiring lead not found.' }, { status: 404 });
    const { error } = await auth.admin.from('hiring_lead_reviews').upsert({
      user_id: auth.user.id, lead_id: leadId, status, updated_at: new Date().toISOString(),
    }, { onConflict: 'user_id,lead_id' });
    if (error) throw error;
    return NextResponse.json({ leadId, status });
  } catch {
    return NextResponse.json({ error: 'Could not update hiring lead.' }, { status: 500 });
  }
}
