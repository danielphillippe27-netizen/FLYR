import { Link, useLocation } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'

export default function AppNav() {
  const { user, signOut } = useAuth()
  const location = useLocation()

  const linkStyle = (path: string) => ({
    padding: '8px 12px',
    borderRadius: 8,
    color: location.pathname === path ? 'var(--text)' : 'var(--muted)',
    textDecoration: 'none',
    fontSize: 15,
    fontWeight: location.pathname === path ? 600 : 400,
  })

  return (
    <nav
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 8,
        padding: '12px 20px',
        borderBottom: '1px solid #222',
        background: 'var(--bg)',
      }}
    >
      <Link to="/" style={{ ...linkStyle('/'), marginRight: 8 }}>FLYR</Link>
      <Link to="/leaderboard" style={linkStyle('/leaderboard')}>Leaderboard</Link>
      <Link to="/stats" style={linkStyle('/stats')}>Stats</Link>
      <Link to="/leads" style={linkStyle('/leads')}>Leads</Link>
      <Link to="/integrations" style={linkStyle('/integrations')}>Integrations</Link>
      <div style={{ flex: 1 }} />
      {user ? (
        <button
          type="button"
          onClick={() => signOut()}
          style={{ padding: '8px 12px', background: 'transparent', border: '1px solid #333', borderRadius: 8, color: 'var(--muted)', cursor: 'pointer', fontSize: 14 }}
        >
          Sign out
        </button>
      ) : (
        <Link to="/login" style={{ padding: '8px 14px', background: 'var(--accent)', color: 'white', borderRadius: 8, textDecoration: 'none', fontSize: 14 }}>Sign in</Link>
      )}
    </nav>
  )
}
