export type PerformanceReportPeriod = 'weekly' | 'monthly' | 'yearly'

export interface PerformanceMetricDelta {
  abs: number
  pct: number
  trend: 'up' | 'down' | 'flat'
}

export interface PerformanceReport {
  id: string
  period: PerformanceReportPeriod
  period_start: string
  period_end: string
  generated_at: string
  summary: string | null
  recommendations: string[]
  metrics: Record<string, number>
  deltas: Record<string, PerformanceMetricDelta>
}
