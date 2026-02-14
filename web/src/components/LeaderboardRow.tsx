import type { LeaderboardUser, LeaderboardMetric } from '../types/leaderboard'
import {
  getUserValue,
  formatLeaderboardValue,
  getSubtitle,
} from '../lib/leaderboard'
import type { LeaderboardTimeframe } from '../types/leaderboard'

const ACCENT = '#ff4f4f'
const GOLD = '#ffd700'
const SILVER = '#c0c0c0'
const BRONZE = '#cd7f32'

function getPodiumColor(rank: number): string | null {
  if (rank === 1) return GOLD
  if (rank === 2) return SILVER
  if (rank === 3) return BRONZE
  return null
}

function getInitials(name: string): string {
  return name
    .trim()
    .split(/\s+/)
    .map((s) => s[0])
    .join('')
    .toUpperCase()
    .slice(0, 2)
}

interface LeaderboardRowProps {
  user: LeaderboardUser
  metric: LeaderboardMetric
  timeframe: LeaderboardTimeframe
  isCurrentUser: boolean
}

export default function LeaderboardRow({
  user,
  metric,
  timeframe,
  isCurrentUser,
}: LeaderboardRowProps) {
  const value = getUserValue(user, metric, timeframe)
  const formatted = formatLeaderboardValue(value, metric)
  const subtitle = getSubtitle(user, metric, timeframe)
  const podiumColor = getPodiumColor(user.rank)

  const rankEl =
    user.rank === 1 ? (
      <span style={{ fontSize: 20 }} title="1st">👑</span>
    ) : user.rank <= 3 ? (
      <span
        style={{
          width: 28,
          height: 28,
          borderRadius: '50%',
          background: podiumColor ? `${podiumColor}26` : 'transparent',
          color: podiumColor ?? 'var(--muted)',
          display: 'inline-flex',
          alignItems: 'center',
          justifyContent: 'center',
          fontSize: 14,
          fontWeight: 700,
        }}
      >
        {user.rank}
      </span>
    ) : (
      <span style={{ fontSize: 15, fontWeight: 600, color: 'var(--muted)' }}>
        {user.rank}
      </span>
    )

  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 12,
        padding: '10px 16px',
        minHeight: 60,
        background: isCurrentUser ? 'rgba(255, 79, 79, 0.08)' : podiumColor ? `${podiumColor}0f` : 'transparent',
      }}
    >
      <div style={{ width: 36, flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'flex-start' }}>
        {rankEl}
      </div>
      <div
        style={{
          width: 36,
          height: 36,
          borderRadius: '50%',
          overflow: 'hidden',
          background: 'var(--bg-secondary)',
          flexShrink: 0,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          fontSize: 12,
          fontWeight: 600,
          color: 'var(--muted)',
        }}
      >
        {user.avatar_url ? (
          <img
            src={user.avatar_url}
            alt=""
            style={{ width: '100%', height: '100%', objectFit: 'cover' }}
          />
        ) : (
          getInitials(user.name || '?')
        )}
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap' }}>
          <span
            style={{
              fontSize: 16,
              fontWeight: 600,
              color: 'var(--text)',
              overflow: 'hidden',
              textOverflow: 'ellipsis',
              whiteSpace: 'nowrap',
            }}
          >
            {user.name || 'User'}
          </span>
          {isCurrentUser && (
            <span
              style={{
                fontSize: 11,
                fontWeight: 600,
                color: 'white',
                background: ACCENT,
                padding: '2px 6px',
                borderRadius: 4,
              }}
            >
              You
            </span>
          )}
        </div>
        {subtitle && (
          <div
            style={{
              fontSize: 13,
              color: 'var(--muted)',
              marginTop: 2,
              overflow: 'hidden',
              textOverflow: 'ellipsis',
              whiteSpace: 'nowrap',
            }}
          >
            {subtitle}
          </div>
        )}
      </div>
      <div
        style={{
          fontSize: 18,
          fontWeight: 700,
          color: ACCENT,
          fontVariantNumeric: 'tabular-nums',
          minWidth: 44,
          textAlign: 'right',
        }}
      >
        {formatted}
      </div>
    </div>
  )
}
