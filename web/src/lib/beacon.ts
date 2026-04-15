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
}

export type BeaconHeartbeat = {
  lat: number
  lon: number
  battery_level?: number | null
  movement_state?: string | null
  device_status?: Record<string, unknown> | null
  recorded_at: string
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
  breadcrumbs?: BeaconBreadcrumb[]
  safety_events?: BeaconSafetyEvent[]
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
