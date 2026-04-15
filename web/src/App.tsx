import { Routes, Route, Navigate, useLocation } from 'react-router-dom'
import AppNav from './components/AppNav'
import LeaderboardPage from './components/LeaderboardPage'
import LoginPage from './components/LoginPage'
import ProtectedRoute from './components/ProtectedRoute'
import LeadsPage from './components/LeadsPage'
import LeadDetailPage from './components/LeadDetailPage'
import IntegrationsPage from './components/IntegrationsPage'
import StatsPage from './components/StatsPage'
import BeaconViewerPage from './components/BeaconViewerPage'

function App() {
  const location = useLocation()
  const hideNav = location.pathname.startsWith('/beacon/')

  return (
    <>
      {!hideNav && <AppNav />}
      <Routes>
      <Route path="/" element={<LeaderboardPage />} />
      <Route path="/leaderboard" element={<LeaderboardPage />} />
      <Route path="/stats" element={<StatsPage />} />
      <Route path="/login" element={<LoginPage />} />
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
