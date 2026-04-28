import { supabase } from '../supabase'

export type BeaconBreadcrumb = {
  lat: number
  lon: number
  battery_level?: number | null
  movement_state?: string | null
  recorded_at: string
}

export type BeaconSafetyEvent = {
  id: string
  event_type: string
  message?: string | null
  lat?: number | null
  lon?: number | null
  created_at: string
}

export type BeaconSession = {
  id: string
  start_time: string
  end_time?: string | null
  goal_type?: string | null
  goal_amount?: number | null
  completed_count?: number | null
  flyers_delivered?: number | null
  conversations?: number | null
  distance_meters?: number | null
  is_paused?: boolean | null
  campaign_id?: string | null
  farm_phase_id?: string | null
}

export type BeaconHeartbeat = {
  lat: number
  lon: number
  battery_level?: number | null
  movement_state?: string | null
  device_status?: Record<string, unknown> | null
  recorded_at: string
}

export type BeaconFallbackLocation = {
  lat: number
  lon: number
  recorded_at?: string | null
  event_type?: string | null
}

export type BeaconSessionDoor = {
  address_id: string
  formatted?: string | null
  house_number?: string | null
  street_name?: string | null
  lat: number
  lon: number
  status?: string | null
  map_status?: 'hot' | 'visited' | 'do_not_knock' | 'no_answer' | 'not_visited' | null
  event_type?: string | null
  created_at: string
}

export type BeaconCampaignFeatureProperties = {
  id?: string | null
  building_id?: string | null
  address_id?: string | null
  gers_id?: string | null
  source?: string | null
  feature_type?: string | null
  feature_status?: string | null
  status?: string | null
  scans_total?: number | null
  scans_today?: number | null
  height?: number | null
  height_m?: number | null
  min_height?: number | null
  address_text?: string | null
  house_number?: string | null
  street_name?: string | null
  address_count?: number | null
  units_count?: number | null
}

export type BeaconCampaignFeature = {
  type: 'Feature'
  id?: string | number | null
  geometry: {
    type: string
    coordinates: unknown
  }
  properties: BeaconCampaignFeatureProperties
}

export type BeaconCampaignFeatureCollection = {
  type: 'FeatureCollection'
  features: BeaconCampaignFeature[]
}

export type BeaconPayload = {
  active: boolean
  reason?: string
  share?: {
    id: string
    viewer_label?: string | null
    created_at: string
    check_in_interval_minutes?: number | null
    last_viewed_at?: string | null
  }
  session?: BeaconSession
  latest_heartbeat?: BeaconHeartbeat | null
  fallback_location?: BeaconFallbackLocation | null
  breadcrumbs?: BeaconBreadcrumb[]
  safety_events?: BeaconSafetyEvent[]
  session_doors?: BeaconSessionDoor[]
}

export async function fetchPublicBeacon(token: string): Promise<BeaconPayload> {
  if (!supabase) {
    throw new Error('Supabase is not configured.')
  }

  const { data, error } = await supabase.rpc('rpc_get_public_session_beacon', {
    p_share_token: token,
  })

  if (error) {
    throw error
  }

  return (data ?? { active: false, reason: 'expired' }) as BeaconPayload
}

export async function fetchPublicBeaconCampaignFeatures(
  campaignId: string,
  farmPhaseId?: string | null
): Promise<BeaconCampaignFeatureCollection> {
  if (!supabase) {
    throw new Error('Supabase is not configured.')
  }

  const { data, error } = farmPhaseId
    ? await supabase.rpc('rpc_get_campaign_full_features_for_farm_phase', {
        p_campaign_id: campaignId,
        p_farm_phase_id: farmPhaseId,
      })
    : await supabase.rpc('rpc_get_campaign_full_features', {
        p_campaign_id: campaignId,
      })

  if (error) {
    throw error
  }

  return (data ?? { type: 'FeatureCollection', features: [] }) as BeaconCampaignFeatureCollection
}
