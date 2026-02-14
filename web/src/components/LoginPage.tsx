import { useState } from 'react'
import { useNavigate, useLocation } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'

export default function LoginPage() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [mode, setMode] = useState<'signin' | 'signup' | 'magic'>('signin')
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)
  const { signInWithPassword, signUp, signInWithMagicLink } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()
  const from = (location.state as { from?: { pathname: string } })?.from?.pathname ?? '/'

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    setMessage(null)
    setSubmitting(true)
    try {
      if (mode === 'magic') {
        const { error } = await signInWithMagicLink(email)
        if (error) setError(error.message)
        else setMessage('Check your email for the login link.')
      } else if (mode === 'signup') {
        const { error } = await signUp(email, password)
        if (error) setError(error.message)
        else setMessage('Check your email to confirm your account.')
      } else {
        const { error } = await signInWithPassword(email, password)
        if (error) setError(error.message)
        else navigate(from, { replace: true })
      }
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div style={{ maxWidth: 400, margin: '80px auto', padding: 24 }}>
      <h1 style={{ fontSize: 24, marginBottom: 8 }}>FLYR</h1>
      <p style={{ color: 'var(--muted)', marginBottom: 24 }}>Sign in to continue</p>
      <form onSubmit={handleSubmit}>
        <div style={{ marginBottom: 16 }}>
          <label htmlFor="email" style={{ display: 'block', marginBottom: 6, fontSize: 14, color: 'var(--muted)' }}>
            Email
          </label>
          <input
            id="email"
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
            autoComplete="email"
            style={{
              width: '100%',
              padding: '12px 14px',
              borderRadius: 10,
              border: '1px solid #333',
              background: 'var(--bg-secondary)',
              color: 'var(--text)',
              fontSize: 16,
            }}
          />
        </div>
        {mode !== 'magic' && (
          <div style={{ marginBottom: 16 }}>
            <label htmlFor="password" style={{ display: 'block', marginBottom: 6, fontSize: 14, color: 'var(--muted)' }}>
              Password
            </label>
            <input
              id="password"
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required={mode === 'signin' || mode === 'signup'}
              autoComplete={mode === 'signup' ? 'new-password' : 'current-password'}
              style={{
                width: '100%',
                padding: '12px 14px',
                borderRadius: 10,
                border: '1px solid #333',
                background: 'var(--bg-secondary)',
                color: 'var(--text)',
                fontSize: 16,
              }}
            />
          </div>
        )}
        {error && <p style={{ color: 'var(--accent)', marginBottom: 12, fontSize: 14 }}>{error}</p>}
        {message && <p style={{ color: 'var(--muted)', marginBottom: 12, fontSize: 14 }}>{message}</p>}
        <button
          type="submit"
          disabled={submitting}
          style={{
            width: '100%',
            padding: 14,
            borderRadius: 10,
            border: 'none',
            background: 'var(--accent)',
            color: 'white',
            fontSize: 16,
            fontWeight: 600,
            cursor: submitting ? 'not-allowed' : 'pointer',
          }}
        >
          {submitting ? 'Please wait...' : mode === 'magic' ? 'Send magic link' : mode === 'signup' ? 'Sign up' : 'Sign in'}
        </button>
      </form>
      <div style={{ marginTop: 16, display: 'flex', gap: 12, flexWrap: 'wrap' }}>
        <button
          type="button"
          onClick={() => { setMode('signin'); setError(null); setMessage(null); }}
          style={{ background: 'none', border: 'none', color: 'var(--muted)', fontSize: 14, cursor: 'pointer', textDecoration: mode === 'signin' ? 'underline' : 'none' }}
        >
          Sign in
        </button>
        <button
          type="button"
          onClick={() => { setMode('signup'); setError(null); setMessage(null); }}
          style={{ background: 'none', border: 'none', color: 'var(--muted)', fontSize: 14, cursor: 'pointer', textDecoration: mode === 'signup' ? 'underline' : 'none' }}
        >
          Sign up
        </button>
        <button
          type="button"
          onClick={() => { setMode('magic'); setError(null); setMessage(null); }}
          style={{ background: 'none', border: 'none', color: 'var(--muted)', fontSize: 14, cursor: 'pointer', textDecoration: mode === 'magic' ? 'underline' : 'none' }}
        >
          Magic link
        </button>
      </div>
    </div>
  )
}
