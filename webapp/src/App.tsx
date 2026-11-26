// The routes. Paths match the links the iOS app shares (/place/<id>,
// /circle/<id>, /user/<id>), so a shared link opens the same thing here.
// The server serves this page only for the first path segments listed in
// backend/routes/webAppRoutes.js (APP_PATHS): add one there when adding one here.
import { Navigate, Route, Routes } from 'react-router-dom';
import { useAuth } from './auth/AuthContext';
import { Layout } from './ui/Layout';
import { LoginPage } from './pages/LoginPage';
import { MePage } from './pages/MePage';
import { CirclePage } from './pages/CirclePage';
import { MapPage } from './pages/MapPage';
import { AddPlacePage } from './pages/AddPlacePage';
import { SearchPage } from './pages/SearchPage';
import { PlacePage } from './pages/PlacePage';
import { UserPage } from './pages/UserPage';
import { PeoplePage } from './pages/PeoplePage';
import { EditProfilePage } from './pages/EditProfilePage';
import { SettingsPage } from './pages/SettingsPage';
import { FeedPage } from './pages/FeedPage';
import { NotificationsPage } from './pages/NotificationsPage';
import { MessagesPage } from './pages/MessagesPage';
import { ConversationPage } from './pages/ConversationPage';
import { LocalsPage } from './pages/LocalsPage';
import { RewardsPage } from './pages/RewardsPage';
import { StoreRewardsPage } from './pages/StoreRewardsPage';

export function App() {
  const { session } = useAuth();
  if (!session) return <LoginPage />;
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route path="/" element={<MapPage />} />
        <Route path="/map" element={<Navigate to="/" replace />} />
        <Route path="/add" element={<AddPlacePage />} />
        <Route path="/search" element={<SearchPage />} />
        <Route path="/place/:placeId" element={<PlacePage />} />
        <Route path="/circle/:circleId" element={<CirclePage />} />
        <Route path="/user/:userId" element={<UserPage />} />
        <Route path="/people" element={<PeoplePage />} />
        <Route path="/me" element={<MePage />} />
        <Route path="/me/edit" element={<EditProfilePage />} />
        <Route path="/settings" element={<SettingsPage />} />
        <Route path="/feed" element={<FeedPage />} />
        <Route path="/notifications" element={<NotificationsPage />} />
        <Route path="/messages" element={<MessagesPage />} />
        <Route path="/messages/:conversationId" element={<ConversationPage />} />
        <Route path="/locals" element={<LocalsPage />} />
        <Route path="/rewards" element={<RewardsPage />} />
        <Route path="/rewards/:venueId" element={<StoreRewardsPage />} />
        <Route path="/login" element={<Navigate to="/" replace />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
  );
}
