import { useState, useEffect, useCallback } from 'react'
import { fetchLeaderboard } from '../lib/leaderboard'
import type { LeaderboardUser, LeaderboardMetric, LeaderboardTimeframe } from '../types/leaderboard'

export interface UseLeaderboardResult {
  users: LeaderboardUser[]
  metric: LeaderboardMetric
  timeframe: LeaderboardTimeframe
  setMetric: (m: LeaderboardMetric) => void
  setTimeframe: (t: LeaderboardTimeframe) => void
  isLoading: boolean
  error: string | null
  retry: () => void
}

export function useLeaderboard(): UseLeaderboardResult {
  const [users, setUsers] = useState<LeaderboardUser[]>([])
  const [metric, setMetric] = useState<LeaderboardMetric>('flyers')
  const [timeframe, setTimeframe] = useState<LeaderboardTimeframe>('weekly')
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    setIsLoading(true)
    setError(null)
    try {
      const data = await fetchLeaderboard(metric, timeframe)
      setUsers(data)
    } catch (e) {
      const message = e instanceof Error ? e.message : 'Failed to load leaderboard'
      if (message.includes('401') || message.includes('Unauthorized') || message.includes('JWT')) {
        setError('Please sign in to view the leaderboard')
      } else if (message.includes('get_leaderboard') || message.includes('function')) {
        setError('Leaderboard service unavailable. Please try again later.')
      } else {
        setError(message)
      }
    } finally {
      setIsLoading(false)
    }
  }, [metric, timeframe])

  useEffect(() => {
    load()
  }, [load])

  return {
    users,
    metric,
    timeframe,
    setMetric,
    setTimeframe,
    isLoading,
    error,
    retry: load,
  }
}
