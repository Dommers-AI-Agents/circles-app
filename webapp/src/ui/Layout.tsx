import { NavLink, Outlet } from 'react-router-dom';
import { ToastHost } from './kit';

const icon = (path: string) => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d={path} />
  </svg>
);

// One row per tab. A screen joins this list when it is built; nothing that
// isn't there yet is ever shown as a tab.
export const TABS = [
  { to: '/', label: 'Me', end: true, icon: icon('M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8Zm-7 9a7 7 0 0 1 14 0') }
];

export function Layout() {
  return (
    <div className="app with-tabs">
      <Outlet />
      {TABS.length > 1 ? (
        <nav className="tabs" aria-label="Main">
          {TABS.map((tab) => (
            <NavLink key={tab.to} to={tab.to} end={tab.end} className={({ isActive }) => (isActive ? 'active' : undefined)}>
              {tab.icon}
              <span>{tab.label}</span>
            </NavLink>
          ))}
        </nav>
      ) : null}
      <ToastHost />
    </div>
  );
}
