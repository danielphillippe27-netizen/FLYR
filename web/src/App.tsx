import { Navigate, Route, Routes, useLocation, useNavigate } from 'react-router-dom'
import { useEffect } from 'react'
import AppNav from './components/AppNav'
import LeaderboardPage from './components/LeaderboardPage'
import LoginPage from './components/LoginPage'
import ProtectedRoute from './components/ProtectedRoute'
import LeadsPage from './components/LeadsPage'
import LeadDetailPage from './components/LeadDetailPage'
import IntegrationsPage from './components/IntegrationsPage'
import StatsPage from './components/StatsPage'
import BeaconViewerPage from './components/BeaconViewerPage'
import PasswordResetPage from './components/PasswordResetPage'

function RecoveryRootRedirect() {
  const location = useLocation()
  const navigate = useNavigate()

  useEffect(() => {
    const search = new URLSearchParams(location.search)
    const hash = location.hash.startsWith('#') ? location.hash.slice(1) : location.hash
    const fragment = new URLSearchParams(hash)
    const type = search.get('type') ?? fragment.get('type')
    const hasRecoverySignal = ['code', 'token', 'token_hash', 'access_token', 'refresh_token']
      .some((key) => search.has(key) || fragment.has(key))

    if (type === 'recovery' || hasRecoverySignal) {
      navigate(
        {
          pathname: '/password/reset',
          search: location.search,
          hash: location.hash,
        },
        { replace: true }
      )
    }
  }, [location.hash, location.search, navigate])

  return <LeaderboardPage />
}

function App() {
  const location = useLocation()
  const hideNav = location.pathname.startsWith('/beacon/')
    || location.pathname === '/password/reset'

  return (
    <>
      {!hideNav && <AppNav />}
      <Routes>
      <Route path="/" element={<RecoveryRootRedirect />} />
      <Route path="/leaderboard" element={<LeaderboardPage />} />
      <Route path="/stats" element={<StatsPage />} />
      <Route path="/login" element={<LoginPage />} />
      <Route path="/password/reset" element={<PasswordResetPage />} />
      <Route path="/beacon/:token" element={<BeaconViewerPage />} />
      <Route path="/leads" element={<ProtectedRoute><LeadsPage /></ProtectedRoute>} />
      <Route path="/leads/:id" element={<ProtectedRoute><LeadDetailPage /></ProtectedRoute>} />
      <Route path="/integrations" element={<ProtectedRoute><IntegrationsPage /></ProtectedRoute>} />
      <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </>
  )
}

export default App
