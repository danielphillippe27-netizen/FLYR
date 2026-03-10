import { useState } from 'react'
import { useAuth } from '../contexts/AuthContext'
import { startFUBOAuth } from '../lib/integrations'

interface ConnectFUBModalProps {
  onSuccess: () => void
  onCancel: () => void
}

export default function ConnectFUBModal({ onSuccess, onCancel }: ConnectFUBModalProps) {
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const { getAccessToken } = useAuth()

  async function handleConnect() {
    setError(null)
    setLoading(true)
    try {
      const token = await getAccessToken()
      if (!token) throw new Error('Not signed in')
      const authorizeUrl = await startFUBOAuth(token)
      onSuccess()
      window.location.assign(authorizeUrl)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Connection failed')
      setLoading(false)
    }
  }

  return (
    <div style={{ padding: 20 }}>
      <h2 style={{ fontSize: 20, marginBottom: 16 }}>Connect Follow Up Boss</h2>
      <p style={{ marginBottom: 16, color: 'var(--text)' }}>
        Connect with OAuth. You will sign in to Follow Up Boss and approve access.
      </p>

      <div style={{ marginBottom: 16, fontSize: 14, color: 'var(--muted)' }}>
        <p style={{ fontWeight: 600, color: 'var(--text)', marginBottom: 8 }}>How it works</p>
        <ol style={{ margin: 0, paddingLeft: 20 }}>
          <li>Click Continue</li>
          <li>Sign in to Follow Up Boss</li>
          <li>Approve FLYR access</li>
          <li>Return to Integrations automatically</li>
        </ol>
      </div>

      {error && <p style={{ color: 'var(--accent)', marginBottom: 12 }}>{error}</p>}

      <div style={{ display: 'flex', gap: 12, justifyContent: 'flex-end' }}>
        <button
          type="button"
          onClick={onCancel}
          disabled={loading}
          style={{
            padding: '10px 18px',
            background: 'var(--bg-secondary)',
            border: '1px solid #333',
            borderRadius: 10,
            color: 'var(--text)',
            cursor: 'pointer',
          }}
        >
          Cancel
        </button>
        <button
          type="button"
          onClick={handleConnect}
          disabled={loading}
          style={{
            padding: '10px 18px',
            background: 'var(--accent)',
            border: 'none',
            borderRadius: 10,
            color: 'white',
            fontWeight: 600,
            cursor: loading ? 'not-allowed' : 'pointer',
          }}
        >
          {loading ? 'Redirecting…' : 'Continue with OAuth'}
        </button>
      </div>
    </div>
  )
}
