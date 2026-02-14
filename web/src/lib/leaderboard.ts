import { supabase } from '../supabase'
import type { LeaderboardUser, MetricSnapshot, LeaderboardMetric, LeaderboardTimeframe } from '../types/leaderboard'

export const METRICS: { value: LeaderboardMetric; label: string }[] = [
  { value: 'flyers', label: 'Flyers' },
  { value: 'conversations', label: "Convo's" },
  { value: 'distance', label: 'Distance' },
]

export const TIMEFRAMES: { value: LeaderboardTimeframe; label: string }[] = [
  { value: 'daily', label: 'Daily' },
  { value: 'weekly', label: 'Weekly' },
  { value: 'monthly', label: 'Monthly' },
  { value: 'all_time', label: 'All Time' },
]

function parseSnapshot(raw: unknown): MetricSnapshot {
  if (raw && typeof raw === 'object' && !Array.isArray(raw)) {
    const o = raw as Record<string, unknown>
    return {
      flyers: typeof o.flyers === 'number' ? o.flyers : 0,
      leads: typeof o.leads === 'number' ? o.leads : 0,
      conversations: typeof o.conversations === 'number' ? o.conversations : 0,
      distance: typeof o.distance === 'number' ? o.distance : 0,
      doorknocks: typeof o.doorknocks === 'number' ? o.doorknocks : 0,
    }
  }
  return { flyers: 0, leads: 0, conversations: 0, distance: 0, doorknocks: 0 }
}

function mapRow(row: Record<string, unknown>): LeaderboardUser {
  return {
    id: typeof row.id === 'string' ? row.id : String(row.id ?? ''),
    name: typeof row.name === 'string' ? row.name : 'User',
    avatar_url: typeof row.avatar_url === 'string' ? row.avatar_url : null,
    rank: typeof row.rank === 'number' ? row.rank : 0,
    flyers: typeof row.flyers === 'number' ? row.flyers : 0,
    leads: typeof row.leads === 'number' ? row.leads : 0,
    conversations: typeof row.conversations === 'number' ? row.conversations : 0,
    distance: typeof row.distance === 'number' ? row.distance : 0,
    daily: parseSnapshot(row.daily),
    weekly: parseSnapshot(row.weekly),
    all_time: parseSnapshot(row.all_time),
  }
}

/**
 * Fetches leaderboard from Supabase RPC get_leaderboard(p_metric, p_timeframe).
 */
export async function fetchLeaderboard(
  metric: LeaderboardMetric,
  timeframe: LeaderboardTimeframe
): Promise<LeaderboardUser[]> {
  if (!supabase) {
    throw new Error('Supabase client not configured')
  }
  const { data, error } = await supabase.rpc('get_leaderboard', {
    p_metric: metric,
    p_timeframe: timeframe,
  })
  if (error) throw error
  if (!Array.isArray(data)) return []
  return data.map((row: Record<string, unknown>) => mapRow(row))
}

/** Get display value for a user for the given metric and timeframe. */
export function getUserValue(
  user: LeaderboardUser,
  metric: LeaderboardMetric,
  timeframe: LeaderboardTimeframe
): number {
  const snapshot = getSnapshotForTimeframe(user, timeframe)
  switch (metric) {
    case 'flyers':
      return snapshot.flyers
    case 'conversations':
      return snapshot.conversations
    case 'distance':
      return snapshot.distance
    default:
      return snapshot.flyers
  }
}

/** Snapshot for timeframe; monthly uses weekly until backend supports it. */
function getSnapshotForTimeframe(user: LeaderboardUser, timeframe: LeaderboardTimeframe): MetricSnapshot {
  switch (timeframe) {
    case 'daily':
      return user.daily
    case 'weekly':
      return user.weekly
    case 'monthly':
      return user.weekly
    case 'all_time':
      return user.all_time
    default:
      return user.all_time
  }
}

/** Format value for display (integer or "X.X" for distance). */
export function formatLeaderboardValue(value: number, metric: LeaderboardMetric): string {
  if (metric === 'distance') {
    return value % 1 === 0 ? `${value}.0 km` : `${value.toFixed(1)} km`
  }
  return value % 1 === 0 ? String(Math.round(value)) : value.toFixed(1)
}

/** Subtitle for row (e.g. "X flyers", "X convo's", "X.X km"). */
export function getSubtitle(
  user: LeaderboardUser,
  metric: LeaderboardMetric,
  timeframe: LeaderboardTimeframe
): string | null {
  const snapshot = getSnapshotForTimeframe(user, timeframe)
  switch (metric) {
    case 'flyers':
      return snapshot.flyers > 0 ? `${snapshot.flyers} flyers` : null
    case 'conversations':
      return snapshot.conversations > 0 ? `${snapshot.conversations} convo's` : null
    case 'distance':
      return snapshot.distance > 0 ? `${snapshot.distance.toFixed(1)} km` : null
    default:
      return null
  }
}
