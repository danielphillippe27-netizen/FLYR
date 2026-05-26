import { createAdminClient } from '@/lib/supabase/server';
import { sendApnsNotification } from '@/lib/notifications/apns';

type PushEnvironment = 'sandbox' | 'production';

type PushTokenRow = {
  token: string;
  environment: PushEnvironment;
};

function readableCampaignName(value: unknown): string {
  if (typeof value !== 'string') return 'Campaign';
  const trimmed = value.trim();
  return trimmed.length > 0 && trimmed.toLowerCase() !== 'untitled campaign'
    ? trimmed
    : 'Campaign';
}

function isDuplicateKeyError(error: { code?: string } | null): boolean {
  return error?.code === '23505';
}

export async function sendCampaignReadyNotificationOnce(campaignId: string) {
  const supabase = createAdminClient();
  const { data: campaign, error: campaignError } = await supabase
    .from('campaigns')
    .select('id,owner_id,name,title,provision_status,provision_phase')
    .eq('id', campaignId)
    .single();

  if (campaignError || !campaign) {
    console.warn('[CampaignReadyPush] Campaign not found for notification.', {
      campaignId,
      error: campaignError?.message,
    });
    return;
  }

  if (campaign.provision_status !== 'ready' || campaign.provision_phase !== 'linked') {
    return;
  }

  const campaignName = readableCampaignName(campaign.name ?? campaign.title);
  const { data: marker, error: markerError } = await supabase
    .from('campaign_ready_notifications')
    .insert({
      campaign_id: campaignId,
      user_id: campaign.owner_id,
      campaign_name: campaignName,
      attempted_at: new Date().toISOString(),
    })
    .select('campaign_id')
    .maybeSingle();

  if (isDuplicateKeyError(markerError)) {
    return;
  }

  if (markerError || !marker) {
    console.warn('[CampaignReadyPush] Failed to create send marker.', {
      campaignId,
      error: markerError?.message,
    });
    return;
  }

  const { data: tokens, error: tokenError } = await supabase
    .from('user_push_tokens')
    .select('token,environment')
    .eq('user_id', campaign.owner_id)
    .eq('platform', 'ios')
    .eq('enabled', true);

  if (tokenError) {
    await supabase
      .from('campaign_ready_notifications')
      .update({ error: tokenError.message })
      .eq('campaign_id', campaignId);
    return;
  }

  const activeTokens = (tokens ?? []) as PushTokenRow[];
  if (activeTokens.length === 0) {
    await supabase
      .from('campaign_ready_notifications')
      .update({ device_count: 0, sent_at: new Date().toISOString() })
      .eq('campaign_id', campaignId);
    return;
  }

  const payload = {
    aps: {
      alert: {
        title: `${campaignName} is ready`,
        body: 'Open FLYR to start working the campaign.',
      },
      sound: 'default',
      'thread-id': `campaign:${campaignId}`,
    },
    type: 'campaign_ready',
    campaign_id: campaignId,
    campaign_name: campaignName,
  };

  const results = await Promise.allSettled(
    activeTokens.map((row) =>
      sendApnsNotification({
        token: row.token,
        environment: row.environment,
        payload,
      })
    )
  );

  const failed = results.filter((result) => result.status === 'rejected');
  await supabase
    .from('campaign_ready_notifications')
    .update({
      device_count: activeTokens.length,
      sent_at: failed.length < activeTokens.length ? new Date().toISOString() : null,
      error: failed.length > 0 ? `${failed.length}/${activeTokens.length} APNs sends failed` : null,
    })
    .eq('campaign_id', campaignId);

  if (failed.length > 0) {
    console.warn('[CampaignReadyPush] Some APNs sends failed.', {
      campaignId,
      failed: failed.length,
      total: activeTokens.length,
    });
  }
}
