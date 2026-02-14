import { Routes, Route, Navigate } from 'react-router-dom'
import AppNav from './components/AppNav'
import LeaderboardPage from './components/LeaderboardPage'
import LoginPage from './components/LoginPage'
import ProtectedRoute from './components/ProtectedRoute'
import LeadsPage from './components/LeadsPage'
import LeadDetailPage from './components/LeadDetailPage'
import IntegrationsPage from './components/IntegrationsPage'
import StatsPage from './components/StatsPage'

function App() {
  return (
    <>
      <AppNav />
      <Routes>
      <Route path="/" element={<LeaderboardPage />} />
      <Route path="/leaderboard" element={<LeaderboardPage />} />
      <Route path="/stats" element={<StatsPage />} />
      <Route path="/login" element={<LoginPage />} />
      <Route path="/leads" element={<ProtectedRoute><LeadsPage /></ProtectedRoute>} />
      <Route path="/leads/:id" element={<ProtectedRoute><LeadDetailPage /></ProtectedRoute>} />
      <Route path="/integrations" element={<ProtectedRoute><IntegrationsPage /></ProtectedRoute>} />
      <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </>
  )
}

export default App
