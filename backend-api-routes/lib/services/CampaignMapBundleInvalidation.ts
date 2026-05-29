import type { SupabaseClient } from '@supabase/supabase-js';

export async function invalidateCampaignMapBundle(
  supabase: SupabaseClient,
  campaignId: string
): Promise<void> {
  const { error } = await supabase.rpc('invalidate_campaign_map_bundle', {
    p_campaign_id: campaignId,
  });

  if (!error) return;

  console.warn('[CampaignMapBundle] Bundle invalidation RPC failed; falling back to direct stale mark:', {
    campaignId,
    message: error.message,
  });

  const { error: fallbackError } = await supabase
    .from('campaign_map_bundles')
    .update({
      is_current: false,
      expires_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    })
    .eq('campaign_id', campaignId)
    .eq('is_current', true);

  if (fallbackError) {
    console.warn('[CampaignMapBundle] Bundle invalidation fallback failed:', {
      campaignId,
      message: fallbackError.message,
    });
  }
}
