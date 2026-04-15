/** Snapshot of metrics for a timeframe (daily, weekly, all_time). */
export interface MetricSnapshot {
  doorknocks: number
  flyers: number
  leads: number
  conversations: number
  distance: number
}

/** Leaderboard user from get_leaderboard RPC. */
export interface LeaderboardUser {
  id: string
  name: string
  avatar_url: string | null
  rank: number
  doorknocks: number
  flyers: number
  leads: number
  conversations: number
  distance: number
  daily: MetricSnapshot
  weekly: MetricSnapshot
  monthly: MetricSnapshot
  all_time: MetricSnapshot
}

export type LeaderboardMetric = 'doorknocks' | 'conversations' | 'distance'
export type LeaderboardTimeframe = 'daily' | 'weekly' | 'monthly' | 'all_time'
