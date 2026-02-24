import { supabase } from '../supabase'
import type {
  PerformanceMetricDelta,
  PerformanceReport,
  PerformanceReportPeriod,
} from '../types/performanceReports'

type JsonObject = Record<string, unknown>

function asString(value: unknown): string {
  return typeof value === 'string' ? value : ''
}

function asNullableString(value: unknown): string | null {
  return typeof value === 'string' ? value : null
}

function asNumber(value: unknown): number {
  if (typeof value === 'number' && Number.isFinite(value)) return value
  if (typeof value === 'string') {
    const parsed = Number(value)
    if (Number.isFinite(parsed)) return parsed
  }
  return 0
}

function parseMetrics(raw: unknown): Record<string, number> {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return {}
  const out: Record<string, number> = {}
  for (const [key, value] of Object.entries(raw as JsonObject)) {
    if (value && typeof value === 'object' && !Array.isArray(value)) {
      const nested = value as JsonObject
      if (nested.abs !== undefined) {
        out[key] = asNumber(nested.abs)
        continue
      }
    }
    out[key] = asNumber(value)
  }
  return out
}

function parseDelta(raw: unknown): PerformanceMetricDelta | null {
  if (raw == null) return null

  if (typeof raw !== 'object' || Array.isArray(raw)) {
    const numeric = asNumber(raw)
    return { abs: numeric, pct: 0, trend: numeric > 0 ? 'up' : numeric < 0 ? 'down' : 'flat' }
  }

  const obj = raw as JsonObject
  const abs = asNumber(obj.abs ?? obj.absolute)
  const pct = asNumber(obj.pct ?? obj.percent)
  const trendRaw = typeof obj.trend === 'string' ? obj.trend.toLowerCase() : ''
  const trend: PerformanceMetricDelta['trend'] =
    trendRaw === 'up' || trendRaw === 'down' || trendRaw === 'flat'
      ? trendRaw
      : abs > 0
      ? 'up'
      : abs < 0
      ? 'down'
      : 'flat'

  return { abs, pct, trend }
}

function parseDeltas(raw: unknown): Record<string, PerformanceMetricDelta> {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return {}
  const out: Record<string, PerformanceMetricDelta> = {}
  for (const [key, value] of Object.entries(raw as JsonObject)) {
    const parsed = parseDelta(value)
    if (parsed) out[key] = parsed
  }
  return out
}

function parseRecommendations(raw: unknown): string[] {
  if (!Array.isArray(raw)) return []
  return raw.filter((v): v is string => typeof v === 'string')
}

function parsePeriod(value: unknown): PerformanceReportPeriod | null {
  const raw = asString(value).toLowerCase()
  if (raw === 'weekly' || raw === 'monthly' || raw === 'yearly') return raw
  return null
}

function mapRow(row: JsonObject): PerformanceReport | null {
  const period = parsePeriod(row.period_type ?? row.period)
  if (!period) return null

  return {
    id: asString(row.id),
    period,
    period_start: asString(row.period_start),
    period_end: asString(row.period_end),
    generated_at: asString(row.generated_at ?? row.created_at),
    summary: asNullableString(row.llm_summary),
    recommendations: parseRecommendations(row.recommendations),
    metrics: parseMetrics(row.metrics),
    deltas: parseDeltas(row.deltas),
  }
}

export async function generateMyPerformanceReports(workspaceId?: string | null, force = false): Promise<void> {
  if (!supabase) throw new Error('Supabase client not configured')

  const params: Record<string, unknown> = { p_force: force }
  if (workspaceId) params.p_workspace_id = workspaceId

  const { error } = await supabase.rpc('generate_my_performance_reports', params)
  if (error) throw error
}

export async function fetchLatestPerformanceReports(
  userId: string,
  workspaceId?: string | null
): Promise<PerformanceReport[]> {
  if (!supabase) throw new Error('Supabase client not configured')

  let query = supabase
    .from('reports')
    .select(
      'id, period_type, period, period_start, period_end, generated_at, created_at, metrics, deltas, llm_summary, recommendations, subject_user_id, workspace_id'
    )
    .eq('scope', 'member')
    .eq('subject_user_id', userId)
    .order('period_end', { ascending: false })
    .limit(24)

  if (workspaceId) {
    query = query.eq('workspace_id', workspaceId)
  }

  const { data, error } = await query
  if (error) throw error

  const rows = Array.isArray(data) ? data : []
  const latestByPeriod: Partial<Record<PerformanceReportPeriod, PerformanceReport>> = {}

  for (const raw of rows) {
    const mapped = mapRow(raw as JsonObject)
    if (!mapped) continue
    if (!latestByPeriod[mapped.period]) latestByPeriod[mapped.period] = mapped
  }

  const order: PerformanceReportPeriod[] = ['weekly', 'monthly', 'yearly']
  return order.flatMap((period) => (latestByPeriod[period] ? [latestByPeriod[period] as PerformanceReport] : []))
}
