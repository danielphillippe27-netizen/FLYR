import { supabase } from '../supabase'
import type { UserStats } from '../types/userStats'

function mapRow(row: Record<string, unknown>): UserStats {
  return {
    id: String(row.id ?? ''),
    user_id: String(row.user_id ?? ''),
    day_streak: typeof row.day_streak === 'number' ? row.day_streak : 0,
    best_streak: typeof row.best_streak === 'number' ? row.best_streak : 0,
    doors_knocked: typeof row.doors_knocked === 'number' ? row.doors_knocked : 0,
    flyers: typeof row.flyers === 'number' ? row.flyers : 0,
    conversations: typeof row.conversations === 'number' ? row.conversations : 0,
    leads_created: typeof row.leads_created === 'number' ? row.leads_created : 0,
    qr_codes_scanned: typeof row.qr_codes_scanned === 'number' ? row.qr_codes_scanned : 0,
    distance_walked: typeof row.distance_walked === 'number' ? row.distance_walked : 0,
    time_tracked: typeof row.time_tracked === 'number' ? row.time_tracked : 0,
    conversation_per_door: typeof row.conversation_per_door === 'number' ? row.conversation_per_door : 0,
    conversation_lead_rate: typeof row.conversation_lead_rate === 'number' ? row.conversation_lead_rate : 0,
    qr_code_scan_rate: typeof row.qr_code_scan_rate === 'number' ? row.qr_code_scan_rate : 0,
    qr_code_lead_rate: typeof row.qr_code_lead_rate === 'number' ? row.qr_code_lead_rate : 0,
    streak_days: Array.isArray(row.streak_days) ? (row.streak_days as string[]) : null,
    xp: typeof row.xp === 'number' ? row.xp : 0,
    updated_at: String(row.updated_at ?? ''),
    created_at: row.created_at != null ? String(row.created_at) : null,
  }
}

/**
 * Fetches the current user's stats from public.user_stats.
 * Returns null if no row (RLS restricts to own user).
 */
export async function fetchUserStats(userId: string): Promise<UserStats | null> {
  if (!supabase) {
    throw new Error('Supabase client not configured')
  }
  const { data, error } = await supabase
    .from('user_stats')
    .select()
    .eq('user_id', userId)
    .limit(1)
    .maybeSingle()
  if (error) throw error
  if (!data) return null
  return mapRow(data as Record<string, unknown>)
}
