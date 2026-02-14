import { useState, useEffect, useCallback } from 'react'
import { supabase } from '../supabase'
import { fetchUserStats } from '../lib/userStats'
import type { UserStats } from '../types/userStats'

export type StatsTimeTab = 'Week' | 'All Time'

export interface UseUserStatsResult {
  stats: UserStats | null
  userId: string | null
  selectedTab: StatsTimeTab
  setSelectedTab: (tab: StatsTimeTab) => void
  isLoading: boolean
  error: string | null
  retry: () => void
}

export function useUserStats(): UseUserStatsResult {
  const [stats, setStats] = useState<UserStats | null>(null)
  const [userId, setUserId] = useState<string | null>(null)
  const [selectedTab, setSelectedTab] = useState<StatsTimeTab>('Week')
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    setIsLoading(true)
    setError(null)
    if (!supabase) {
      setError('Supabase client not configured')
      setIsLoading(false)
      return
    }
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        setUserId(null)
        setStats(null)
        setError('Please sign in to view your stats')
        return
      }
      setUserId(user.id)
      const data = await fetchUserStats(user.id)
      setStats(data)
    } catch (e) {
      const message = e instanceof Error ? e.message : 'Failed to load stats'
      if (message.includes('401') || message.includes('Unauthorized') || message.includes('JWT')) {
        setError('Please sign in to view your stats')
      } else {
        setError(message)
      }
      setStats(null)
    } finally {
      setIsLoading(false)
    }
  }, [])

  useEffect(() => {
    load()
  }, [load])

  return {
    stats,
    userId,
    selectedTab,
    setSelectedTab,
    isLoading,
    error,
    retry: load,
  }
}
