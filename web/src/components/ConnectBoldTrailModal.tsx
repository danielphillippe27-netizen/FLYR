import { useState } from 'react'
import { useAuth } from '../contexts/AuthContext'
import type { CRMConnection } from '../types/leads'
import { connectBoldTrail, testBoldTrailConnection } from '../lib/integrations'

interface ConnectBoldTrailModalProps {
  connection?: CRMConnection | null
  onSuccess: () => void
  onCancel: () => void
}

export default function ConnectBoldTrailModal({
  connection,
  onSuccess,
  onCancel,
}: ConnectBoldTrailModalProps) {
  const { getAccessToken } = useAuth()
  const [apiToken, setApiToken] = useState('')
  const [showToken, setShowToken] = useState(false)
  const [testing, setTesting] = useState(false)
  const [saving, setSaving] = useState(false)
  const [message, setMessage] = useState<string | null>(null)
  const [messageTone, setMessageTone] = useState<'success' | 'error'>('success')
  const [lastTestedToken, setLastTestedToken] = useState<string | null>(null)
  const [lastTestSucceeded, setLastTestSucceeded] = useState(false)

  const trimmedToken = apiToken.trim()
  const tokenHint = connection?.metadata?.tokenHint ?? null
  const hasStoredToken = connection?.status === 'connected'
  const canSave = !!trimmedToken && lastTestSucceeded && lastTestedToken === trimmedToken

  async function handleTest() {
    setMessage(null)
    setTesting(true)
    try {
      const accessToken = await getAccessToken()
      if (!accessToken) throw new Error('Not signed in')
      const result = await testBoldTrailConnection(accessToken, trimmedToken || undefined)
      if (result.success === false) {
        setLastTestSucceeded(false)
        setLastTestedToken(trimmedToken)
        setMessageTone('error')
        setMessage(result.error ?? 'Test failed')
        return
      }
      setLastTestSucceeded(true)
      setLastTestedToken(trimmedToken)
      setMessageTone('success')
      setMessage(result.message ?? 'Connection successful')
    } catch (error) {
      setLastTestSucceeded(false)
      setLastTestedToken(trimmedToken)
      setMessageTone('error')
      setMessage(error instanceof Error ? error.message : 'Unable to connect to BoldTrail')
    } finally {
      setTesting(false)
    }
  }

  async function handleSave() {
    if (!canSave) return
    setMessage(null)
    setSaving(true)
    try {
      const accessToken = await getAccessToken()
      if (!accessToken) throw new Error('Not signed in')
      const result = await connectBoldTrail(trimmedToken, accessToken)
      if (!result.connected) {
        setMessageTone('error')
        setMessage(result.error ?? 'Failed to save BoldTrail token')
        return
      }
      onSuccess()
    } catch (error) {
      setMessageTone('error')
      setMessage(error instanceof Error ? error.message : 'Failed to save BoldTrail token')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div style={{ padding: 20 }}>
      <h2 style={{ fontSize: 20, marginBottom: 16 }}>Connect BoldTrail / kvCORE</h2>
      <p style={{ marginBottom: 16, color: 'var(--text)' }}>
        Generate your API token in BoldTrail / kvCORE and paste it here.
      </p>

      {tokenHint && (
        <p style={{ marginBottom: 12, color: 'var(--muted)', fontSize: 13 }}>
          Saved token: {tokenHint}
        </p>
      )}

      <div style={{ marginBottom: 16, display: 'flex', gap: 12, alignItems: 'center' }}>
        <input
          type={showToken ? 'text' : 'password'}
          value={apiToken}
          onChange={(event) => setApiToken(event.target.value)}
          placeholder="API Token"
          disabled={testing || saving}
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
          onClick={() => setShowToken((value) => !value)}
          style={{ padding: '8px 12px', background: 'var(--bg-secondary)', border: '1px solid #333', borderRadius: 8, color: 'var(--muted)', cursor: 'pointer', fontSize: 14 }}
        >
          {showToken ? 'Hide' : 'Show'}
        </button>
      </div>

      <button
        type="button"
        onClick={() => navigator.clipboard.readText().then((value) => setApiToken(value.trim()))}
        style={{ marginBottom: 16, background: 'none', border: 'none', color: 'var(--muted)', fontSize: 14, cursor: 'pointer' }}
      >
        Paste
      </button>

      <div style={{ marginBottom: 16, fontSize: 14, color: 'var(--muted)' }}>
        <p style={{ fontWeight: 600, color: 'var(--text)', marginBottom: 8 }}>MVP sync scope</p>
        <ol style={{ margin: 0, paddingLeft: 20 }}>
          <li>Secure token validation and storage on the backend</li>
          <li>One-way FLYR → BoldTrail / kvCORE contact sync</li>
          <li>Remote contact ID persistence for later updates</li>
        </ol>
      </div>

      {message && (
        <p style={{ color: messageTone === 'success' ? '#34C759' : 'var(--accent)', marginBottom: 12 }}>
          {message}
        </p>
      )}

      <p style={{ fontSize: 12, color: 'var(--muted)', marginBottom: 16 }}>
        The raw token never comes back to the client after you save it.
      </p>

      <div style={{ display: 'flex', gap: 12, justifyContent: 'flex-end' }}>
        <button
          type="button"
          onClick={onCancel}
          disabled={testing || saving}
          style={{ padding: '10px 18px', background: 'var(--bg-secondary)', border: '1px solid #333', borderRadius: 10, color: 'var(--text)', cursor: 'pointer' }}
        >
          Cancel
        </button>
        <button
          type="button"
          onClick={handleTest}
          disabled={testing || saving || (!trimmedToken && !hasStoredToken)}
          style={{ padding: '10px 18px', background: '#0A84FF', border: 'none', borderRadius: 10, color: 'white', fontWeight: 600, cursor: testing ? 'not-allowed' : 'pointer' }}
        >
          {testing ? 'Testing...' : trimmedToken ? 'Test Connection' : 'Test Saved Token'}
        </button>
        <button
          type="button"
          onClick={handleSave}
          disabled={!canSave || testing || saving}
          style={{ padding: '10px 18px', background: canSave ? 'var(--accent)' : '#555', border: 'none', borderRadius: 10, color: 'white', fontWeight: 600, cursor: canSave ? 'pointer' : 'not-allowed' }}
        >
          {saving ? 'Saving...' : hasStoredToken ? 'Save Replacement' : 'Save'}
        </button>
      </div>
    </div>
  )
}
