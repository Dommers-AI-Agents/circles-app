// The routes. Paths match the links the iOS app shares (/place/<id>,
// /circle/<id>, /user/<id>), so a shared link opens the same thing here.
// The server serves this page only for the paths in backend/routes/webAppRoutes.js:
// add a path there when adding one here.
import { Navigate, Route, Routes } from 'react-router-dom';
import { useAuth } from './auth/AuthContext';
import { Layout } from './ui/Layout';
import { LoginPage } from './pages/LoginPage';
import { MePage } from './pages/MePage';
import { CirclePage } from './pages/CirclePage';

export function App() {
  const { session } = useAuth();
  if (!session) return <LoginPage />;
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route path="/" element={<MePage />} />
        <Route path="/circle/:circleId" element={<CirclePage />} />
        <Route path="/login" element={<Navigate to="/" replace />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
  );
}
