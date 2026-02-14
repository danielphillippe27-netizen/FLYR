import { METRICS, TIMEFRAMES } from '../lib/leaderboard'
import type { LeaderboardMetric, LeaderboardTimeframe } from '../types/leaderboard'

const ACCENT = '#ff4f4f'

interface LeaderboardTableHeaderProps {
  metric: LeaderboardMetric
  timeframe: LeaderboardTimeframe
  onMetricChange: (m: LeaderboardMetric) => void
  onTimeframeChange: (t: LeaderboardTimeframe) => void
}

export default function LeaderboardTableHeader({
  metric,
  timeframe,
  onMetricChange,
  onTimeframeChange,
}: LeaderboardTableHeaderProps) {
  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 12,
        padding: '12px 16px',
        background: 'var(--bg)',
      }}
    >
      <span
        style={{
          fontSize: 15,
          fontWeight: 500,
          color: 'var(--muted)',
          width: 36,
        }}
      >
        #
      </span>
      <span
        style={{
          fontSize: 15,
          fontWeight: 500,
          color: 'var(--muted)',
          flex: 1,
        }}
      >
        Name
      </span>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        <select
          value={timeframe}
          onChange={(e) => onTimeframeChange(e.target.value as LeaderboardTimeframe)}
          style={{
            minWidth: 80,
            fontSize: 15,
            fontWeight: 600,
            color: ACCENT,
            background: 'transparent',
            border: 'none',
            cursor: 'pointer',
            padding: '4px 8px',
          }}
        >
          {TIMEFRAMES.map((t) => (
            <option key={t.value} value={t.value}>
              {t.label}
            </option>
          ))}
        </select>
        <select
          value={metric}
          onChange={(e) => onMetricChange(e.target.value as LeaderboardMetric)}
          style={{
            minWidth: 100,
            fontSize: 15,
            fontWeight: 700,
            color: ACCENT,
            background: 'transparent',
            border: 'none',
            cursor: 'pointer',
            padding: '4px 8px',
          }}
        >
          {METRICS.map((m) => (
            <option key={m.value} value={m.value}>
              {m.label}
            </option>
          ))}
        </select>
      </div>
    </div>
  )
}
