import { Routes, Route } from 'react-router-dom'
import Layout from './components/Layout'
import InstancesPage from './pages/InstancesPage'
import ProfilesPage from './pages/ProfilesPage'
import ProvisionPage from './pages/ProvisionPage'
import MigratePage from './pages/MigratePage'
import ManagePage from './pages/ManagePage'
import ConfigPage from './pages/ConfigPage'
import JobsPage from './pages/JobsPage'

function App() {
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route path="/" element={<InstancesPage />} />
        <Route path="/profiles" element={<ProfilesPage />} />
        <Route path="/provision" element={<ProvisionPage />} />
        <Route path="/migrate" element={<MigratePage />} />
        <Route path="/manage" element={<ManagePage />} />
        <Route path="/config" element={<ConfigPage />} />
        <Route path="/jobs" element={<JobsPage />} />
      </Route>
    </Routes>
  )
}

export default App
