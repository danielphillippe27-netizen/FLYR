import { useState } from 'react'
import { useAuth } from '../contexts/AuthContext'
import { connectFUB } from '../lib/integrations'

interface ConnectFUBModalProps {
  onSuccess: () => void
  onCancel: () => void
}

export default function ConnectFUBModal({ onSuccess, onCancel }: ConnectFUBModalProps) {
  const [apiKey, setApiKey] = useState('')
  const [showKey, setShowKey] = useState(false)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const { getAccessToken } = useAuth()
  const trimmed = apiKey.trim()
  const valid = trimmed.length >= 20

  async function handleConnect() {
    if (!valid) {
      setError('API key is too short.')
      return
    }
    setError(null)
    setLoading(true)
    try {
      const token = await getAccessToken()
      if (!token) throw new Error('Not signed in')
      const result = await connectFUB(trimmed, token)
      if (result.connected) onSuccess()
      else setError(result.error ?? 'Could not connect')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Connection failed')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div style={{ padding: 20 }}>
      <h2 style={{ fontSize: 20, marginBottom: 16 }}>Connect Follow Up Boss</h2>
      <p style={{ marginBottom: 16, color: 'var(--text)' }}>Enter your Follow Up Boss API key</p>
      <div style={{ marginBottom: 16, display: 'flex', gap: 12, alignItems: 'center' }}>
        <input
          type={showKey ? 'text' : 'password'}
          value={apiKey}
          onChange={(e) => setApiKey(e.target.value)}
          placeholder="API Key"
          disabled={loading}
          autoComplete="off"
          style={{
            flex: 1,
            padding: '12px 14px',
            borderRadius: 12,
            border: '1px solid #333',
            background: 'var(--bg-secondary)',
            color: 'var(--text)',
            fontSize: 16,
          }}
        />
        <button
          type="button"
          onClick={() => setShowKey((s) => !s)}
          style={{ padding: '8px 12px', background: 'var(--bg-secondary)', border: '1px solid #333', borderRadius: 8, color: 'var(--muted)', cursor: 'pointer', fontSize: 14 }}
        >
          {showKey ? 'Hide' : 'Show'}
        </button>
      </div>
      <button
        type="button"
        onClick={() => navigator.clipboard.readText().then((t) => setApiKey(t.trim()))}
        style={{ marginBottom: 16, background: 'none', border: 'none', color: 'var(--muted)', fontSize: 14, cursor: 'pointer' }}
      >
        Paste
      </button>
      <div style={{ marginBottom: 16, fontSize: 14, color: 'var(--muted)' }}>
        <p style={{ fontWeight: 600, color: 'var(--text)', marginBottom: 8 }}>How to get your API key</p>
        <ol style={{ margin: 0, paddingLeft: 20 }}>
          <li>Open Follow Up Boss (desktop works best)</li>
          <li>Go to Settings → Integrations / API</li>
          <li>Generate API Key (or &quot;Create Key&quot;)</li>
          <li>Copy and paste it here</li>
          <li>Click Connect</li>
        </ol>
      </div>
      {error && <p style={{ color: 'var(--accent)', marginBottom: 12 }}>{error}</p>}
      <p style={{ fontSize: 12, color: 'var(--muted)', marginBottom: 16 }}>
        We encrypt your key and only use it to sync leads/notes you create in FLYR.
      </p>
      <div style={{ display: 'flex', gap: 12, justifyContent: 'flex-end' }}>
        <button
          type="button"
          onClick={onCancel}
          disabled={loading}
          style={{ padding: '10px 18px', background: 'var(--bg-secondary)', border: '1px solid #333', borderRadius: 10, color: 'var(--text)', cursor: 'pointer' }}
        >
          Cancel
        </button>
        <button
          type="button"
          onClick={handleConnect}
          disabled={!valid || loading}
          style={{ padding: '10px 18px', background: 'var(--accent)', border: 'none', borderRadius: 10, color: 'white', fontWeight: 600, cursor: loading ? 'not-allowed' : 'pointer' }}
        >
          {loading ? 'Connecting...' : 'Connect'}
        </button>
      </div>
    </div>
  )
}
