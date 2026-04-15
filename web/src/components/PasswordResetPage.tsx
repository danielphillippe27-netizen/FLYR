import { useEffect, useMemo, useState } from 'react'
import { Link, useLocation } from 'react-router-dom'
import { supabase } from '../supabase'

type RecoveryState = 'validating' | 'ready' | 'success' | 'error'
type RecoveryLocation = {
  search: string
  hash: string
}

function readRecoveryValue(name: string, location: RecoveryLocation) {
  const search = new URLSearchParams(location.search)
  const fromSearch = search.get(name)
  if (fromSearch) return fromSearch

  const hash = location.hash.startsWith('#') ? location.hash.slice(1) : location.hash
  const fragment = new URLSearchParams(hash)
  return fragment.get(name)
}

export default function PasswordResetPage() {
  const location = useLocation()
  const [state, setState] = useState<RecoveryState>('validating')
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [submitting, setSubmitting] = useState(false)

  const recoveryDetails = useMemo(() => {
    const type = readRecoveryValue('type', location) ?? 'recovery'
    return {
      code: readRecoveryValue('code', location),
      tokenHash: readRecoveryValue('token_hash', location),
      token: readRecoveryValue('token', location),
      type,
    }
  }, [location])

  useEffect(() => {
    let cancelled = false

    async function initializeRecovery() {
      if (!supabase) {
        if (!cancelled) {
          setState('error')
          setError('Password reset is not configured on this site right now.')
        }
        return
      }

      const { code, tokenHash, token, type } = recoveryDetails

      if (!code && !tokenHash && !token) {
        if (!cancelled) {
          setState('error')
          setError('This password reset link is missing recovery details. Request a new email and try again.')
        }
        return
      }

      try {
        if (code) {
          const { error } = await supabase.auth.exchangeCodeForSession(code)
          if (error) throw error
        } else if (tokenHash) {
          const { error } = await supabase.auth.verifyOtp({
            token_hash: tokenHash,
            type: type as 'recovery' | 'email' | 'magiclink' | 'invite' | 'signup' | 'email_change',
          })
          if (error) throw error
        } else if (token) {
          throw new Error('This recovery link format is not supported yet. Request a fresh reset email and try again.')
        }

        if (!cancelled) {
          setState('ready')
          setError(null)
        }
      } catch (err) {
        if (!cancelled) {
          setState('error')
          setError(err instanceof Error ? err.message : 'This reset link is invalid or expired.')
        }
      }
    }

    void initializeRecovery()

    return () => {
      cancelled = true
    }
  }, [recoveryDetails])

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setError(null)
    setMessage(null)

    if (!supabase) {
      setError('Password reset is not configured on this site right now.')
      return
    }

    if (!password.trim()) {
      setError('Enter a new password.')
      return
    }

    if (password !== confirmPassword) {
      setError('Passwords do not match.')
      return
    }

    setSubmitting(true)

    try {
      const { error } = await supabase.auth.updateUser({ password })
      if (error) throw error

      setState('success')
      setMessage('Your password has been updated. You can return to the app and sign in.')
      setPassword('')
      setConfirmPassword('')
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unable to update your password.')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="auth-shell">
      <div className="auth-card">
        <p className="auth-eyebrow">FLYR</p>
        <h1>Reset your password</h1>

        {state === 'validating' && (
          <p className="auth-copy">Validating your recovery link...</p>
        )}

        {state === 'ready' && (
          <>
            <p className="auth-copy">Choose a new password for your account.</p>
            <form className="auth-form" onSubmit={handleSubmit}>
              <label className="auth-field">
                <span>New password</span>
                <input
                  type="password"
                  autoComplete="new-password"
                  value={password}
                  onChange={(event) => setPassword(event.target.value)}
                  required
                />
              </label>
              <label className="auth-field">
                <span>Confirm password</span>
                <input
                  type="password"
                  autoComplete="new-password"
                  value={confirmPassword}
                  onChange={(event) => setConfirmPassword(event.target.value)}
                  required
                />
              </label>
              <button className="auth-button" type="submit" disabled={submitting}>
                {submitting ? 'Saving...' : 'Save new password'}
              </button>
            </form>
          </>
        )}

        {state === 'success' && <p className="auth-success">{message}</p>}
        {state === 'error' && <p className="auth-error">{error}</p>}
        {state === 'ready' && error && <p className="auth-error">{error}</p>}

        {(state === 'error' || state === 'success') && (
          <p className="auth-footer">
            <Link to="/login">Back to sign in</Link>
          </p>
        )}
      </div>
    </div>
  )
}
