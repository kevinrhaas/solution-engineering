import { useEffect, useState } from 'react';
import { NavLink, Outlet } from 'react-router-dom';

type UiTheme = 'light' | 'dark';
const THEME_STORAGE_KEY = 'ops-console-ui-theme';
const THEME_COOKIE_KEY = 'ops_console_ui_theme';

function readThemeCookie(): UiTheme | null {
  const cookies = document.cookie ? document.cookie.split(';') : [];
  for (const c of cookies) {
    const [k, ...rest] = c.trim().split('=');
    if (k === THEME_COOKIE_KEY) {
      const v = decodeURIComponent(rest.join('='));
      if (v === 'light' || v === 'dark') return v;
    }
  }
  return null;
}

/* ── SVG icon wrapper ── */
const I = ({ children }: { children: React.ReactNode }) => (
  <span style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', width: 20, height: 20, flexShrink: 0 }}>
    {children}
  </span>
);

const sv = { viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: 2, strokeLinecap: 'round' as const, strokeLinejoin: 'round' as const, width: 20, height: 20 };

/* ── Nav items with Feather-style SVG icons ── */
const links = [
  { to: '/', label: 'Instances', icon: (
    <I><svg {...sv}><rect x="2" y="2" width="20" height="8" rx="2" ry="2"/><rect x="2" y="14" width="20" height="8" rx="2" ry="2"/><circle cx="6" cy="6" r="1" fill="currentColor" stroke="none"/><circle cx="6" cy="18" r="1" fill="currentColor" stroke="none"/></svg></I>
  )},
  { to: '/profiles', label: 'Profiles', icon: (
    <I><svg {...sv}><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/></svg></I>
  )},
  { to: '/provision', label: 'Provision', icon: (
    <I><svg {...sv}><path d="M20.39 18.39A5 5 0 0 0 18 9h-1.26A8 8 0 1 0 3 16.3"/><polyline points="16 16 12 12 8 16"/><line x1="12" y1="12" x2="12" y2="21"/></svg></I>
  )},
  { to: '/manage', label: 'Manage', icon: (
    <I><svg {...sv}><line x1="4" y1="21" x2="4" y2="14"/><line x1="4" y1="10" x2="4" y2="3"/><line x1="12" y1="21" x2="12" y2="12"/><line x1="12" y1="8" x2="12" y2="3"/><line x1="20" y1="21" x2="20" y2="16"/><line x1="20" y1="12" x2="20" y2="3"/><line x1="1" y1="14" x2="7" y2="14"/><line x1="9" y1="8" x2="15" y2="8"/><line x1="17" y1="16" x2="23" y2="16"/></svg></I>
  )},
  { to: '/migrate', label: 'Migrate', icon: (
    <I><svg {...sv}><polyline points="17 1 21 5 17 9"/><path d="M3 11V9a4 4 0 0 1 4-4h14"/><polyline points="7 23 3 19 7 15"/><path d="M21 13v2a4 4 0 0 1-4 4H3"/></svg></I>
  )},
  { to: '/config', label: 'Config', icon: (
    <I><svg {...sv}><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06A1.65 1.65 0 0 0 19.32 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg></I>
  )},
  { to: '/jobs', label: 'Processes', icon: (
    <I><svg {...sv}><line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><line x1="3" y1="6" x2="3.01" y2="6"/><line x1="3" y1="12" x2="3.01" y2="12"/><line x1="3" y1="18" x2="3.01" y2="18"/></svg></I>
  )},
];

function formatBuildTime(): string {
  const raw = typeof __BUILD_TIME__ !== 'undefined' ? __BUILD_TIME__ : '';
  const date = new Date(raw);
  if (!raw || Number.isNaN(date.getTime())) return '';
  return `${new Intl.DateTimeFormat('en-US', {
    timeZone: 'America/Chicago',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  }).format(date).replace(',', '')} CT`;
}

export default function Layout() {
  const [collapsed, setCollapsed] = useState(false);
  const [theme, setTheme] = useState<UiTheme>('light');
  const w = collapsed ? 60 : 220;
  const buildTime = formatBuildTime();

  useEffect(() => {
    const local = localStorage.getItem(THEME_STORAGE_KEY);
    if (local === 'light' || local === 'dark') {
      setTheme(local);
      return;
    }
    const cookie = readThemeCookie();
    if (cookie) {
      setTheme(cookie);
      return;
    }
    const prefersDark = window.matchMedia?.('(prefers-color-scheme: dark)').matches;
    setTheme(prefersDark ? 'dark' : 'light');
  }, []);

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem(THEME_STORAGE_KEY, theme);
    document.cookie = `${THEME_COOKIE_KEY}=${encodeURIComponent(theme)}; path=/; max-age=31536000; samesite=lax`;
  }, [theme]);

  function toggleTheme() {
    setTheme((t) => (t === 'light' ? 'dark' : 'light'));
  }

  return (
    <div style={{ display: 'flex', height: '100vh', overflow: 'hidden' }}>
      {/* ── Sidebar ── */}
      <nav className="pentaho-sidebar" style={{ width: w, minWidth: w }}>
        {/* Brand */}
        <div className="pentaho-brand" style={{ padding: collapsed ? '12px 10px' : '12px 20px' }}>
          <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor" style={{ flexShrink: 0 }}>
            <rect x="2" y="2" width="5" height="5" rx="1"/><rect x="9.5" y="2" width="5" height="5" rx="1"/><rect x="17" y="2" width="5" height="5" rx="1"/>
            <rect x="2" y="9.5" width="5" height="5" rx="1"/><rect x="9.5" y="9.5" width="5" height="5" rx="1"/><rect x="17" y="9.5" width="5" height="5" rx="1"/>
            <rect x="2" y="17" width="5" height="5" rx="1"/><rect x="9.5" y="17" width="5" height="5" rx="1"/><rect x="17" y="17" width="5" height="5" rx="1"/>
          </svg>
          {!collapsed && (
            <div style={{ lineHeight: 1.1 }}>
              <div style={{ fontSize: 16, fontWeight: 700, color: '#fff' }}>Pentaho</div>
              <div style={{ fontSize: 8, color: 'var(--sidebar-subtle)', letterSpacing: 2, textTransform: 'uppercase', marginTop: 2 }}>Solution Engineering</div>
              <div style={{ fontSize: 12, fontWeight: 400, color: 'var(--sidebar-subtle)', marginTop: 2 }}>Ops Console</div>
            </div>
          )}
        </div>

        {/* Nav links */}
        <div className="pentaho-nav-list">
          {links.map((l) => (
            <NavLink
              key={l.to}
              to={l.to}
              end={l.to === '/'}
              className={({ isActive }) => `pentaho-nav-link${isActive ? ' active' : ''}`}
              style={{ padding: collapsed ? '10px 0' : '10px 14px', justifyContent: collapsed ? 'center' : 'flex-start' }}
              title={l.label}
            >
              {l.icon}
              {!collapsed && <span>{l.label}</span>}
            </NavLink>
          ))}
        </div>

        {/* Theme toggle */}
        <div className="pentaho-theme-area">
          <button
            className="pentaho-theme-btn"
            onClick={toggleTheme}
            style={{ padding: collapsed ? '10px 0' : '10px 14px', justifyContent: collapsed ? 'center' : 'flex-start' }}
            title={theme === 'dark' ? 'Switch to Light Mode' : 'Switch to Dark Mode'}
          >
            {theme === 'dark' ? (
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0 }}>
                <circle cx="12" cy="12" r="5" />
                <line x1="12" y1="1" x2="12" y2="3" />
                <line x1="12" y1="21" x2="12" y2="23" />
                <line x1="4.22" y1="4.22" x2="5.64" y2="5.64" />
                <line x1="18.36" y1="18.36" x2="19.78" y2="19.78" />
                <line x1="1" y1="12" x2="3" y2="12" />
                <line x1="21" y1="12" x2="23" y2="12" />
                <line x1="4.22" y1="19.78" x2="5.64" y2="18.36" />
                <line x1="18.36" y1="5.64" x2="19.78" y2="4.22" />
              </svg>
            ) : (
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0 }}>
                <path d="M21 12.79A9 9 0 1 1 11.21 3c.5 0 .99.04 1.47.12a1 1 0 0 1 .49 1.79A7 7 0 0 0 19.09 13a1 1 0 0 1 1.79.49c.08.48.12.97.12 1.47z" />
              </svg>
            )}
            {!collapsed && <span>{theme === 'dark' ? 'Dark Mode' : 'Light Mode'}</span>}
          </button>
        </div>

        {/* Collapse toggle — pinned to bottom */}
        <div className="pentaho-collapse-area">
          <button
            className="pentaho-collapse-btn"
            onClick={() => setCollapsed(!collapsed)}
            style={{ padding: collapsed ? '10px 0' : '10px 14px', justifyContent: collapsed ? 'center' : 'flex-start' }}
            title={collapsed ? 'Expand Menu' : 'Collapse Menu'}
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0, transform: collapsed ? 'rotate(180deg)' : 'none', transition: 'transform 0.2s' }}>
              <polyline points="15 18 9 12 15 6"/>
            </svg>
            {!collapsed && <span>Collapse Menu</span>}
          </button>
        </div>
      </nav>

      {/* ── Main content ── */}
      <main style={{ flex: 1, padding: 24, background: 'var(--app-bg)', overflow: 'auto', display: 'flex', flexDirection: 'column' }}>
        <div style={{ flex: 1 }}>
          <Outlet />
        </div>
        <div style={{ textAlign: 'right', padding: '12px 0 0', fontSize: 10, color: 'var(--text-muted)', letterSpacing: 0.3 }}>
          {buildTime && <>build {buildTime}</>}
        </div>
      </main>
    </div>
  );
}
