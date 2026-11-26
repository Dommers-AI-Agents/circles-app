import { NavLink, Outlet } from 'react-router-dom';
import { useUnreadMessages } from '../realtime/badges';
import { ToastHost } from './kit';

const icon = (path: string) => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d={path} />
  </svg>
);

const TABS = [
  { to: '/', label: 'Map', end: true, icon: icon('M9 4 3 6.5v13L9 17l6 3 6-2.5v-13L15 7 9 4Zm0 0v13m6-10v13') },
  { to: '/feed', label: 'Activity', icon: icon('M12 3l2.6 5.6 6 .7-4.5 4.1 1.2 6L12 16.5 6.700 19.4l1.200-6L3.400 9.300l6-.700L12 3Z') },
  { to: '/locals', label: 'Locals', icon: icon('M4 10 5.500 4h13L20 10M4 10v10h16V10M4 10h16M9 20v-6h6v6') },
  { to: '/messages', label: 'Messages', badge: 'messages' as const, icon: icon('M4 5h16v11H9l-5 4V5Z') },
  { to: '/me', label: 'Me', icon: icon('M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8Zm-7 9a7 7 0 0 1 14 0') }
];

export function Layout() {
  const unreadMessages = useUnreadMessages();
  return (
    <div className="app with-tabs">
      <Outlet />
      <nav className="tabs" aria-label="Main">
        {TABS.map((tab) => (
          <NavLink key={tab.to} to={tab.to} end={tab.end} className={({ isActive }) => (isActive ? 'active' : undefined)}>
            {tab.icon}
            <span>{tab.label}</span>
            {tab.badge === 'messages' && unreadMessages > 0
              ? <span className="badge" aria-label={`${unreadMessages} unread`}>{unreadMessages > 99 ? '99+' : unreadMessages}</span>
              : null}
          </NavLink>
        ))}
      </nav>
      <ToastHost />
    </div>
  );
}
