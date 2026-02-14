/** User stats row from public.user_stats (Supabase). */
export interface UserStats {
  id: string
  user_id: string
  day_streak: number
  best_streak: number
  doors_knocked: number
  flyers: number
  conversations: number
  leads_created: number
  qr_codes_scanned: number
  distance_walked: number
  time_tracked: number
  conversation_per_door: number
  conversation_lead_rate: number
  qr_code_scan_rate: number
  qr_code_lead_rate: number
  streak_days: string[] | null
  xp: number
  updated_at: string
  created_at: string | null
}

/** Format distance for display (e.g. "12.1"). */
export function formatDistanceWalked(distanceWalked: number): string {
  return distanceWalked.toFixed(1)
}

/** Format time tracked (minutes) as "Xh Ym" or "Ym". */
export function formatTimeTracked(minutes: number): string {
  const hours = Math.floor(minutes / 60)
  const mins = minutes % 60
  if (hours > 0) {
    return `${hours}h ${mins}m`
  }
  return `${mins}m`
}

/** Format conversation-per-door for display. */
export function formatConversationPerDoor(value: number): string {
  return value.toFixed(1)
}
