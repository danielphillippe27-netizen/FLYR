import { useState, useEffect } from 'react'
import { useLeaderboard } from '../hooks/useLeaderboard'
import { supabase } from '../supabase'
import LeaderboardTableHeader from './LeaderboardTableHeader'
import LeaderboardRow from './LeaderboardRow'

export default function LeaderboardPage() {
  const {
    users,
    metric,
    timeframe,
    setMetric,
    setTimeframe,
    isLoading,
    error,
    retry,
  } = useLeaderboard()
  const [currentUserId, setCurrentUserId] = useState<string | null>(null)

  useEffect(() => {
    if (!supabase) return
    supabase.auth.getUser().then(({ data: { user } }) => {
      setCurrentUserId(user?.id ?? null)
    })
  }, [])

  if (isLoading) {
    return (
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          minHeight: '60vh',
          padding: 24,
        }}
      >
        <div style={{ fontSize: 18, color: 'var(--muted)' }}>Loading…</div>
      </div>
    )
  }

  if (error) {
    return (
      <div
        style={{
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          minHeight: '60vh',
          padding: 24,
          gap: 16,
        }}
      >
        <span style={{ fontSize: 48, opacity: 0.5 }}>⚠️</span>
        <p
          style={{
            fontSize: 15,
            color: 'var(--muted)',
            textAlign: 'center',
            maxWidth: 320,
          }}
        >
          {error}
        </p>
        <button
          type="button"
          onClick={retry}
          style={{
            padding: '10px 20px',
            fontSize: 15,
            fontWeight: 600,
            color: 'white',
            background: 'var(--accent)',
            border: 'none',
            borderRadius: 8,
            cursor: 'pointer',
          }}
        >
          Retry
        </button>
      </div>
    )
  }

  if (users.length === 0) {
    return (
      <div
        style={{
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          minHeight: '60vh',
          padding: 24,
          gap: 16,
        }}
      >
        <span style={{ fontSize: 48, opacity: 0.5 }}>🏆</span>
        <p style={{ fontSize: 15, color: 'var(--muted)' }}>
          No leaderboard entries yet
        </p>
      </div>
    )
  }

  return (
    <div style={{ background: 'var(--bg)', minHeight: '100vh' }}>
      <header
        style={{
          padding: '16px 16px 8px',
          borderBottom: '1px solid rgba(255,255,255,0.08)',
        }}
      >
        <h1
          style={{
            margin: 0,
            fontSize: 22,
            fontWeight: 700,
            color: 'var(--text)',
          }}
        >
          Leaderboard
        </h1>
      </header>
      <LeaderboardTableHeader
        metric={metric}
        timeframe={timeframe}
        onMetricChange={setMetric}
        onTimeframeChange={setTimeframe}
      />
      <ul style={{ listStyle: 'none', margin: 0, padding: 0 }}>
        {users.map((user) => (
          <li
            key={user.id}
            style={{
              borderBottom: '1px solid rgba(255,255,255,0.08)',
            }}
          >
            <LeaderboardRow
              user={user}
              metric={metric}
              timeframe={timeframe}
              isCurrentUser={user.id === currentUserId}
            />
          </li>
        ))}
      </ul>
    </div>
  )
}
