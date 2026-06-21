import { supabase } from '../supabase'
import type { UserStats } from '../types/userStats'

type StatsRow = Record<string, unknown>

function numberValue(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : 0
}

function leadKey(row: StatsRow): string {
  const address = String(row.address ?? '').trim().toLowerCase()
  return address || String(row.id ?? '').toLowerCase()
}

function appointmentKey(row: StatsRow): string {
  const timestamp = Date.parse(String(row.timestamp ?? ''))
  const seconds = Number.isFinite(timestamp) ? Math.round(timestamp / 1000) : 0
  return [
    String(row.contact_id ?? '').toLowerCase(),
    String(seconds),
    String(row.note ?? '').trim().toLowerCase(),
  ].join('|')
}

function defaultStats(userId: string): UserStats {
  return {
    id: '',
    user_id: userId,
    day_streak: 0,
    best_streak: 0,
    doors_knocked: 0,
    flyers: 0,
    conversations: 0,
    leads_created: 0,
    appointments: 0,
    qr_codes_scanned: 0,
    distance_walked: 0,
    time_tracked: 0,
    conversation_per_door: 0,
    conversation_lead_rate: 0,
    qr_code_scan_rate: 0,
    qr_code_lead_rate: 0,
    streak_days: null,
    xp: 0,
    updated_at: new Date().toISOString(),
    created_at: null,
  }
}

function mapRow(row: Record<string, unknown>): UserStats {
  return {
    id: String(row.id ?? ''),
    user_id: String(row.user_id ?? ''),
    day_streak: numberValue(row.day_streak),
    best_streak: numberValue(row.best_streak),
    doors_knocked: numberValue(row.doors_knocked),
    flyers: numberValue(row.flyers),
    conversations: numberValue(row.conversations),
    leads_created: numberValue(row.leads_created),
    appointments: numberValue(row.appointments),
    qr_codes_scanned: numberValue(row.qr_codes_scanned),
    distance_walked: numberValue(row.distance_walked),
    time_tracked: numberValue(row.time_tracked),
    conversation_per_door: numberValue(row.conversation_per_door),
    conversation_lead_rate: numberValue(row.conversation_lead_rate),
    qr_code_scan_rate: numberValue(row.qr_code_scan_rate),
    qr_code_lead_rate: numberValue(row.qr_code_lead_rate),
    streak_days: Array.isArray(row.streak_days) ? (row.streak_days as string[]) : null,
    xp: numberValue(row.xp),
    updated_at: String(row.updated_at ?? ''),
    created_at: row.created_at != null ? String(row.created_at) : null,
  }
}

async function refreshUserStatsFromSessions(userId: string): Promise<void> {
  if (!supabase) return

  const { error } = await supabase.rpc('refresh_user_stats_from_sessions', {
    p_user_id: userId,
  })
  if (error) {
    // Keep the page usable if an older environment has not deployed the RPC yet.
    console.warn('Failed to refresh user stats from sessions', error)
  }
}

async function fetchLiveLeadCount(userId: string): Promise<number> {
  if (!supabase) return 0

  const leadKeys = new Set<string>()
  const { data: contacts, error: contactsError } = await supabase
    .from('contacts')
    .select('id,address')
    .eq('user_id', userId)
  if (contactsError) throw contactsError
  ;((contacts ?? []) as StatsRow[]).forEach((row) => leadKeys.add(leadKey(row)))

  const { data: legacyLeads, error: legacyLeadsError } = await supabase
    .from('field_leads')
    .select('id,address')
    .eq('user_id', userId)
  if (legacyLeadsError) throw legacyLeadsError
  ;((legacyLeads ?? []) as StatsRow[]).forEach((row) => leadKeys.add(leadKey(row)))

  return leadKeys.size
}

async function fetchLiveAppointmentCount(userId: string): Promise<number> {
  if (!supabase) return 0

  const appointmentKeys = new Set<string>()
  const { data, error } = await supabase
    .from('contact_activities')
    .select('id,contact_id,note,timestamp,contacts!inner(id,user_id)')
    .eq('type', 'meeting')
    .eq('contacts.user_id', userId)
  if (error) throw error
  ;((data ?? []) as StatsRow[]).forEach((row) => appointmentKeys.add(appointmentKey(row)))

  return appointmentKeys.size
}

async function mergedWithLiveLeadAndAppointmentCounts(stats: UserStats, userId: string): Promise<UserStats> {
  const [liveLeadCount, liveAppointmentCount] = await Promise.all([
    fetchLiveLeadCount(userId),
    fetchLiveAppointmentCount(userId),
  ])
  const leadsCreated = Math.max(stats.leads_created, liveLeadCount)
  const appointments = Math.max(stats.appointments, liveAppointmentCount)

  return {
    ...stats,
    leads_created: leadsCreated,
    appointments,
    conversation_lead_rate:
      stats.conversations > 0 ? leadsCreated / stats.conversations : stats.conversation_lead_rate,
  }
}

/**
 * Fetches the current user's stats from public.user_stats, refreshed from sessions
 * and merged with live lead/appointment counts to match the iOS stats surface.
 */
export async function fetchUserStats(userId: string): Promise<UserStats> {
  if (!supabase) {
    throw new Error('Supabase client not configured')
  }
  await refreshUserStatsFromSessions(userId)

  const { data, error } = await supabase
    .from('user_stats')
    .select()
    .eq('user_id', userId)
    .limit(1)
    .maybeSingle()
  if (error) throw error
  const base = data ? mapRow(data as Record<string, unknown>) : defaultStats(userId)
  return mergedWithLiveLeadAndAppointmentCounts(base, userId)
}
