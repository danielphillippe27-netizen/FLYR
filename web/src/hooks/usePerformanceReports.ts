import { useCallback, useEffect, useState } from 'react'
import {
  fetchLatestPerformanceReports,
  generateMyPerformanceReports,
} from '../lib/performanceReports'
import type { PerformanceReport } from '../types/performanceReports'

export interface UsePerformanceReportsResult {
  reports: PerformanceReport[]
  isLoading: boolean
  error: string | null
  reload: () => Promise<void>
}

export function usePerformanceReports(userId: string | null): UsePerformanceReportsResult {
  const [reports, setReports] = useState<PerformanceReport[]>([])
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    if (!userId) {
      setReports([])
      setError(null)
      return
    }

    setIsLoading(true)
    setError(null)

    try {
      // Best effort: generate fresh weekly/monthly/yearly rows if RPC is deployed.
      try {
        await generateMyPerformanceReports(null, false)
      } catch {
        // Ignore generation errors and still attempt to load existing report rows.
      }

      const rows = await fetchLatestPerformanceReports(userId, null)
      setReports(rows)
    } catch (e) {
      const message = e instanceof Error ? e.message : 'Failed to load reports'
      if (message.toLowerCase().includes('does not exist') || message.toLowerCase().includes('column')) {
        // Hide schema errors in environments where reports infra is not deployed yet.
        setReports([])
        setError(null)
      } else {
        setError(message)
      }
    } finally {
      setIsLoading(false)
    }
  }, [userId])

  useEffect(() => {
    void load()
  }, [load])

  return {
    reports,
    isLoading,
    error,
    reload: load,
  }
}
