import { NextRequest, NextResponse } from 'next/server';
import { resolveUserFromRequest } from '@/app/api/_utils/request-user';
import { ensureCampaignAccess } from '@/app/api/campaigns/_utils/access';
import { createAdminClient } from '@/lib/supabase/server';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export const revalidate = 0;

type RouteContext = { params: Promise<{ campaignId: string }> };

type CampaignTimingRow = {
  provision_status: string | null;
  provision_phase: string | null;
  provision_source: string | null;
  provision_timings: unknown;
  provision_error: string | null;
  provision_message: string | null;
};

export async function GET(request: NextRequest, context: RouteContext): Promise<Response> {
  try {
    const requestUser = await resolveUserFromRequest(request);
    if (!requestUser) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const { campaignId } = await context.params;
    const supabase = createAdminClient();
    const allowed = await ensureCampaignAccess(supabase, campaignId, requestUser.id);
    if (!allowed) {
      return NextResponse.json({ error: 'Forbidden' }, { status: 403 });
    }

    const { data, error } = await supabase
      .from('campaigns')
      .select('provision_status, provision_phase, provision_source, provision_timings, provision_error, provision_message')
      .eq('id', campaignId)
      .maybeSingle();

    if (error) {
      console.error('[provision-timings] read failed:', error);
      return NextResponse.json({ error: 'Failed to read provision timings' }, { status: 500 });
    }

    if (!data) {
      return NextResponse.json({ error: 'Campaign not found' }, { status: 404 });
    }

    const row = data as CampaignTimingRow;
    return NextResponse.json(
      {
        campaign_id: campaignId,
        provision_status: row.provision_status,
        provision_phase: row.provision_phase,
        provision_source: row.provision_source,
        provision_timings: row.provision_timings ?? {},
        provision_error: row.provision_error,
        provision_message: row.provision_message,
      },
      {
        headers: {
          'Cache-Control': 'no-store, max-age=0',
        },
      }
    );
  } catch (error) {
    console.error('[provision-timings] GET error:', error);
    return NextResponse.json({ error: 'Failed to read provision timings' }, { status: 500 });
  }
}
