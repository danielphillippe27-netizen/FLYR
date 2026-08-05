import { NextRequest, NextResponse } from 'next/server';
import { createAdminClient } from '@/lib/supabase/server';
import {
  ensureCachedCampaignAccess,
  resolveCachedTileUser,
} from '@/app/api/campaigns/_utils/tile-cache';
import {
  CampaignParcelNotFoundError,
  resolveCampaignParcels,
} from '@/lib/services/CampaignParcelFeatureService';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ campaignId: string }> }
) {
  const { campaignId } = await params;
  const requestUser = await resolveCachedTileUser(request);
  if (!requestUser) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const supabase = createAdminClient();
  const allowed = await ensureCachedCampaignAccess(supabase, campaignId, requestUser.id);
  if (!allowed) {
    return NextResponse.json({ error: 'Campaign not found or access denied' }, { status: 404 });
  }

  try {
    const resolved = await resolveCampaignParcels(supabase, campaignId);
    const headers: Record<string, string> = {
      'Cache-Control': 'private, max-age=60',
    };
    if (resolved.source === 'campaign_parcels') {
      headers['X-WolfGrid-Parcels-Source'] = 'campaign_parcels';
    }
    if (resolved.suppressedReason) {
      headers['X-WolfGrid-Parcels-Suppressed'] = resolved.suppressedReason;
    }
    return NextResponse.json(resolved.features, { headers });
  } catch (error) {
    if (error instanceof CampaignParcelNotFoundError) {
      return NextResponse.json({ error: 'Campaign not found' }, { status: 404 });
    }
    const errorMessage = error instanceof Error ? error.message : String(error);
    console.error('[CampaignParcels] Failed to extract scoped parcels:', {
      campaignId,
      error: errorMessage,
    });
    return NextResponse.json({ error: 'Failed to extract campaign parcels' }, { status: 500 });
  }
}
