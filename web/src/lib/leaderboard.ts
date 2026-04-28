import { supabase } from '../supabase'
import type { LeaderboardUser, MetricSnapshot, LeaderboardMetric, LeaderboardTimeframe } from '../types/leaderboard'

export const METRICS: { value: LeaderboardMetric; label: string }[] = [
  { value: 'doorknocks', label: 'Doors' },
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
      doorknocks: typeof o.doorknocks === 'number' ? o.doorknocks : 0,
      leads: typeof o.leads === 'number' ? o.leads : 0,
      conversations: typeof o.conversations === 'number' ? o.conversations : 0,
      distance: typeof o.distance === 'number' ? o.distance : 0,
    }
  }
  return { doorknocks: 0, leads: 0, conversations: 0, distance: 0 }
}

function emptySnapshot(): MetricSnapshot {
  return { doorknocks: 0, leads: 0, conversations: 0, distance: 0 }
}

function parseSnapshotWithFallback(raw: unknown, fallback: MetricSnapshot): MetricSnapshot {
  const parsed = parseSnapshot(raw)
  const hasData =
    parsed.doorknocks > 0 ||
    parsed.leads > 0 ||
    parsed.conversations > 0 ||
    parsed.distance > 0

  return hasData ? parsed : fallback
}

function mapRow(row: Record<string, unknown>): LeaderboardUser {
  const doorknocks = typeof row.doorknocks === 'number' ? row.doorknocks : 0
  const topLevelSnapshot: MetricSnapshot = {
    doorknocks,
    leads: typeof row.leads === 'number' ? row.leads : 0,
    conversations: typeof row.conversations === 'number' ? row.conversations : 0,
    distance: typeof row.distance === 'number' ? row.distance : 0,
  }

  return {
    id: typeof row.id === 'string' ? row.id : String(row.id ?? ''),
    name: typeof row.name === 'string' ? row.name : 'User',
    avatar_url: typeof row.avatar_url === 'string' ? row.avatar_url : null,
    rank: typeof row.rank === 'number' ? row.rank : 0,
    doorknocks,
    leads: topLevelSnapshot.leads,
    conversations: topLevelSnapshot.conversations,
    distance: topLevelSnapshot.distance,
    daily: parseSnapshotWithFallback(row.daily, emptySnapshot()),
    weekly: parseSnapshotWithFallback(row.weekly, emptySnapshot()),
    monthly: parseSnapshotWithFallback(row.monthly, topLevelSnapshot),
    all_time: parseSnapshotWithFallback(row.all_time, emptySnapshot()),
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
    case 'doorknocks':
      return snapshot.doorknocks
    case 'conversations':
      return snapshot.conversations
    case 'distance':
      return snapshot.distance
    default:
      return snapshot.doorknocks
  }
}

function getSnapshotForTimeframe(user: LeaderboardUser, timeframe: LeaderboardTimeframe): MetricSnapshot {
  switch (timeframe) {
    case 'daily':
      return user.daily
    case 'weekly':
      return user.weekly
    case 'monthly':
      return user.monthly
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

/** Subtitle for row (e.g. "X doors", "X convo's", "X.X km"). */
export function getSubtitle(
  user: LeaderboardUser,
  metric: LeaderboardMetric,
  timeframe: LeaderboardTimeframe
): string | null {
  const snapshot = getSnapshotForTimeframe(user, timeframe)
  switch (metric) {
    case 'doorknocks':
      return snapshot.doorknocks > 0 ? `${snapshot.doorknocks} doors` : null
    case 'conversations':
      return snapshot.conversations > 0 ? `${snapshot.conversations} convo's` : null
    case 'distance':
      return snapshot.distance > 0 ? `${snapshot.distance.toFixed(1)} km` : null
    default:
      return null
  }
}
