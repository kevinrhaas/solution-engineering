import { useEffect, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import {
  listInstances,
  discoverEc2Instances,
  startEc2Instance,
  stopEc2Instance,
  teardown,
  checkHealth,
  startContentPreview,
  getContentPreviewStatus,
} from '../api';
import type { InstanceSummary, AwsDiscoveryError, ContentPreviewStatus } from '../api';
import Terminal from '../components/Terminal';

const FAVORITES_STORAGE_KEY = 'ops-console-instance-favorites-v1';
const COMMENTS_STORAGE_KEY = 'ops-console-instance-comments-v1';

function safeParseStringArray(raw: string | null): string[] {
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed.filter((v): v is string => typeof v === 'string') : [];
  } catch {
    return [];
  }
}

function safeParseCommentMap(raw: string | null): Record<string, string> {
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object') return {};
    const out: Record<string, string> = {};
    for (const [k, v] of Object.entries(parsed)) {
      if (typeof v === 'string') out[k] = v;
    }
    return out;
  } catch {
    return {};
  }
}

function normalizeComment(value: string): string {
  const lines = value.replace(/\r/g, '').split('\n').slice(0, 2);
  return lines.map((line) => line.slice(0, 110)).join('\n');
}

function lastIp3(ip: string): string {
  const last = (ip || '').trim().split('.').pop() || '';
  const digits = last.replace(/\D/g, '');
  return (digits || '000').slice(-3).padStart(3, '0');
}

function lastId5(instanceId: string): string {
  const cleaned = (instanceId || '').trim().replace(/[^A-Za-z0-9]/g, '');
  return (cleaned || '00000').slice(-5).toUpperCase().padStart(5, '0');
}

/** Build deterministic teardown code: last 3 of IP + last 5 of instance id. */
function teardownCodeFor(inst: InstanceSummary): string {
  return `${lastIp3(inst.instance_ip)}-${lastId5(inst.instance_id)}`;
}

export default function InstancesPage() {
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const [instances, setInstances] = useState<InstanceSummary[]>([]);
  const [filterText, setFilterText] = useState(searchParams.get('profile') || '');
  const [sortKey, setSortKey] = useState<'name-asc' | 'name-desc' | 'ip-asc' | 'created-desc' | 'created-asc' | 'state' | 'favorites'>('favorites');
  const [statusFilters, setStatusFilters] = useState<Set<'running' | 'untracked' | 'unreachable' | 'orphan' | 'reachable'>>(new Set());
  const [serverFilters, setServerFilters] = useState<Set<'pentaho' | 'pdc'>>(new Set());
  const [favoriteOnly, setFavoriteOnly] = useState(false);
  const [favorites, setFavorites] = useState<Set<string>>(() => new Set(safeParseStringArray(localStorage.getItem(FAVORITES_STORAGE_KEY))));
  const [instanceComments, setInstanceComments] = useState<Record<string, string>>(() => safeParseCommentMap(localStorage.getItem(COMMENTS_STORAGE_KEY)));
  const [focusedCommentKey, setFocusedCommentKey] = useState<string | null>(null);

  // Health status for server URLs
  const [healthMap, setHealthMap] = useState<Record<string, boolean | null>>({});

  // EC2 Discovery
  const [discovering, setDiscovering] = useState(false);
  const [discoveryError, setDiscoveryError] = useState('');
  const [awsAuthError, setAwsAuthError] = useState<AwsDiscoveryError | null>(null);
  const [lastDiscoveryTime, setLastDiscoveryTime] = useState<Date | null>(null);

  // Teardown
  const [teardownJobId, setTeardownJobId] = useState<string | null>(null);
  const [tearingDown, setTearingDown] = useState<Set<string>>(new Set());
  const [tornDown, setTornDown] = useState<Set<string>>(new Set());
  const [teardownTarget, setTeardownTarget] = useState<InstanceSummary | null>(null);
  const [teardownCode, setTeardownCode] = useState('');
  const [teardownInput, setTeardownInput] = useState('');

  // EC2 lifecycle actions (start/stop)
  const [lifecycleJobId, setLifecycleJobId] = useState<string | null>(null);
  const [starting, setStarting] = useState<Set<string>>(new Set());
  const [stopping, setStopping] = useState<Set<string>>(new Set());
  const [activeLifecycleAction, setActiveLifecycleAction] = useState<{ stateKey: string; action: 'start' | 'stop' } | null>(null);

  // Card actions menu
  const [menuOpenFor, setMenuOpenFor] = useState<string | null>(null);
  const [hoveredTitleFor, setHoveredTitleFor] = useState<string | null>(null);

  // Content preview report
  const [contentModalOpen, setContentModalOpen] = useState(false);
  const [contentReportId, setContentReportId] = useState<string | null>(null);
  const [contentStatus, setContentStatus] = useState<ContentPreviewStatus | null>(null);
  const [contentError, setContentError] = useState('');
  const [contentTab, setContentTab] = useState('overview');

  async function launchContentPreview(inst: InstanceSummary) {
    if (!inst.server_url) {
      setContentError('No server URL found for this instance.');
      setContentModalOpen(true);
      return;
    }
    setContentError('');
    setContentStatus(null);
    setContentTab('overview');
    setContentModalOpen(true);
    try {
      const started = await startContentPreview({
        server_url: inst.server_url,
        server_type: inst.server_type,
        instance_name: inst.name,
      });
      setContentReportId(started.report_id);
    } catch (e: unknown) {
      setContentError(String(e));
    }
  }

  useEffect(() => {
    if (!contentReportId) return;
    const timer = setInterval(async () => {
      try {
        const status = await getContentPreviewStatus(contentReportId);
        setContentStatus(status);
        if (status.status === 'completed' || status.status === 'failed') {
          clearInterval(timer);
        }
      } catch (e: unknown) {
        setContentError(String(e));
      }
    }, 1200);
    return () => clearInterval(timer);
  }, [contentReportId]);

  function runHealthChecks(list: InstanceSummary[]) {
    const urls = new Set(list.filter((inst) => inst.server_url).map((inst) => inst.server_url));
    urls.forEach((url) => {
      checkHealth(url)
        .then((r) => setHealthMap((prev) => ({ ...prev, [url]: r.reachable })))
        .catch(() => setHealthMap((prev) => ({ ...prev, [url]: false })));
    });
  }

  async function refreshWithDiscovery() {
    setDiscovering(true);
    setDiscoveryError('');
    setAwsAuthError(null);
    try {
      // Fetch tracked instances first, then discover from EC2
      const [, discovery] = await Promise.all([
        listInstances(),
        discoverEc2Instances(),
      ]);
      // Discovery result already contains enriched tracked + untracked
      const all = [...discovery.tracked, ...discovery.untracked];
      setInstances(all);
      setLastDiscoveryTime(new Date());
      if (discovery.aws_error) setAwsAuthError(discovery.aws_error);
      runHealthChecks(all);
    } catch (e: unknown) {
      // If discovery fails, fall back to just tracked instances
      try {
        const tracked = await listInstances();
        setInstances(tracked);
        runHealthChecks(tracked);
      } catch { /* ignore */ }
      setDiscoveryError(String(e));
    } finally {
      setDiscovering(false);
    }
  }

  // Auto-discover on page load
  useEffect(() => {
    refreshWithDiscovery();
  }, []);

  useEffect(() => {
    const profileFilter = searchParams.get('profile');
    if (profileFilter) setFilterText(profileFilter);
  }, [searchParams]);

  useEffect(() => {
    const onDocMouseDown = (evt: MouseEvent) => {
      if (!menuOpenFor) return;
      const target = evt.target as HTMLElement | null;
      if (!target) return;
      if (target.closest('[data-card-menu]') || target.closest('[data-card-menu-toggle]')) return;
      setMenuOpenFor(null);
    };

    document.addEventListener('mousedown', onDocMouseDown);
    return () => document.removeEventListener('mousedown', onDocMouseDown);
  }, [menuOpenFor]);

  // Navigate to profile detail
  function goToProfile(name: string) {
    navigate(`/profiles?select=${encodeURIComponent(name)}`);
  }

  function cardStateKey(inst: InstanceSummary): string {
    return inst.state_file || inst.instance_id;
  }

  function toggleFavorite(inst: InstanceSummary) {
    const key = cardStateKey(inst);
    setFavorites((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      localStorage.setItem(FAVORITES_STORAGE_KEY, JSON.stringify(Array.from(next)));
      return next;
    });
  }

  function setCommentFor(inst: InstanceSummary, value: string) {
    const key = cardStateKey(inst);
    const normalized = normalizeComment(value);
    setInstanceComments((prev) => {
      const next = { ...prev };
      if (normalized.trim()) next[key] = normalized;
      else delete next[key];
      localStorage.setItem(COMMENTS_STORAGE_KEY, JSON.stringify(next));
      return next;
    });
  }

  async function runEc2Lifecycle(inst: InstanceSummary, action: 'start' | 'stop') {
    const key = cardStateKey(inst);
    const actionLabel = action === 'start' ? 'start' : 'stop';
    const ok = window.confirm(`Confirm ${actionLabel} for EC2 instance ${inst.instance_id || inst.name}?`);
    if (!ok) return;

    setMenuOpenFor(null);
    try {
      if (action === 'start') {
        const { job_id } = await startEc2Instance(inst.name, inst.state_file);
        setStarting((prev) => new Set(prev).add(key));
        setActiveLifecycleAction({ stateKey: key, action: 'start' });
        setLifecycleJobId(job_id);
      } else {
        const { job_id } = await stopEc2Instance(inst.name, inst.state_file);
        setStopping((prev) => new Set(prev).add(key));
        setActiveLifecycleAction({ stateKey: key, action: 'stop' });
        setLifecycleJobId(job_id);
      }
    } catch (e) {
      alert(`${action === 'start' ? 'Start' : 'Stop'} failed: ${e}`);
    }
  }

  // Filter instances
  const filteredInstances = instances.filter((i) => {
    const key = cardStateKey(i);
    if (favoriteOnly && !favorites.has(key)) return false;

    const q = filterText.toLowerCase();
    const textMatch = !q || (
      i.name.toLowerCase().includes(q) ||
      i.instance_ip.toLowerCase().includes(q) ||
      i.instance_id.toLowerCase().includes(q) ||
      i.pentaho_version.toLowerCase().includes(q) ||
      (i.ec2_tags?.Name || '').toLowerCase().includes(q) ||
      (i.public_ip || '').toLowerCase().includes(q) ||
      (i.tracking_status || '').toLowerCase().includes(q)
    );

    if (!textMatch) return false;

    const serverKind = i.server_type === 'pdc' ? 'pdc' : i.server_type === 'pentaho' ? 'pentaho' : '';
    if (serverFilters.size > 0 && (!serverKind || !serverFilters.has(serverKind))) {
      return false;
    }

    if (statusFilters.size > 0) {
      const isRunning = i.instance_state === 'running';
      const isUntracked = i.tracking_status === 'untracked';
      const isUnreachable = Boolean(i.server_url) && healthMap[i.server_url] === false;
      const isReachable = Boolean(i.server_url) && healthMap[i.server_url] === true;
      const isOrphan = !i.has_profile && !isUntracked;

      const matchesAnyFilter =
        (statusFilters.has('running') && isRunning) ||
        (statusFilters.has('untracked') && isUntracked) ||
        (statusFilters.has('unreachable') && isUnreachable) ||
        (statusFilters.has('reachable') && isReachable) ||
        (statusFilters.has('orphan') && isOrphan);

      if (!matchesAnyFilter) return false;
    }

    return true;
  }).sort((a, b) => {
    const aKey = cardStateKey(a);
    const bKey = cardStateKey(b);
    const aFav = favorites.has(aKey);
    const bFav = favorites.has(bKey);
    const aUntracked = a.tracking_status === 'untracked';
    const bUntracked = b.tracking_status === 'untracked';

    if (sortKey === 'favorites') {
      if (aFav !== bFav) return aFav ? -1 : 1;
      if (aUntracked !== bUntracked) return aUntracked ? 1 : -1;
      return a.name.localeCompare(b.name);
    }
    if (sortKey === 'name-asc') return a.name.localeCompare(b.name);
    if (sortKey === 'name-desc') return b.name.localeCompare(a.name);
    if (sortKey === 'ip-asc') return (a.instance_ip || '').localeCompare(b.instance_ip || '');
    if (sortKey === 'created-desc') return new Date(b.created_date || 0).getTime() - new Date(a.created_date || 0).getTime();
    if (sortKey === 'created-asc') return new Date(a.created_date || 0).getTime() - new Date(b.created_date || 0).getTime();
    if (sortKey === 'state') {
      const rank = (inst: InstanceSummary) => {
        if (inst.instance_state === 'running') return 0;
        if (inst.instance_state === 'stopped') return 1;
        return 2;
      };
      const r = rank(a) - rank(b);
      if (r !== 0) return r;
      return a.name.localeCompare(b.name);
    }
    return 0;
  });

  const runningCount = instances.filter((i) => i.instance_state === 'running').length;
  const untrackedCount = instances.filter((i) => i.tracking_status === 'untracked').length;
  const unreachableCount = instances.filter((i) => i.server_url && healthMap[i.server_url] === false).length;
  const reachableCount = instances.filter((i) => i.server_url && healthMap[i.server_url] === true).length;
  const orphanCount = instances.filter((i) => !i.has_profile && i.tracking_status !== 'untracked').length;
  const pentahoCount = instances.filter((i) => i.server_type === 'pentaho').length;
  const pdcCount = instances.filter((i) => i.server_type === 'pdc').length;
  const favoritesCount = instances.filter((i) => favorites.has(cardStateKey(i))).length;

  function toggleStatusFilter(k: 'running' | 'untracked' | 'unreachable' | 'orphan' | 'reachable') {
    setStatusFilters((prev) => {
      const next = new Set(prev);
      if (next.has(k)) next.delete(k);
      else next.add(k);
      return next;
    });
  }

  function toggleServerFilter(k: 'pentaho' | 'pdc') {
    setServerFilters((prev) => {
      const next = new Set(prev);
      if (next.has(k)) next.delete(k);
      else next.add(k);
      return next;
    });
  }

  function fmtBytes(v: unknown): string {
    if (typeof v !== 'number' || Number.isNaN(v)) return '—';
    if (v < 1024) return `${v} B`;
    if (v < 1024 * 1024) return `${(v / 1024).toFixed(1)} KB`;
    if (v < 1024 * 1024 * 1024) return `${(v / (1024 * 1024)).toFixed(1)} MB`;
    return `${(v / (1024 * 1024 * 1024)).toFixed(2)} GB`;
  }

  function statValue(value: unknown): string {
    if (typeof value === 'number') return value.toLocaleString();
    if (typeof value === 'string') return value;
    if (value == null) return '—';
    return JSON.stringify(value);
  }

  return (
    <div>
      <h2 style={{ margin: '0 0 4px' }}>Instances</h2>
      <p style={{ color: '#8e9eab', margin: '0 0 16px', fontSize: 13 }}>
        Live view of running EC2 instances — tracked deployments and discovered instances.
      </p>

      {discoveryError && (
        <div style={errorBanner}>
          EC2 discovery failed: {discoveryError}
          <span onClick={() => setDiscoveryError('')} style={{ cursor: 'pointer', marginLeft: 8 }} title="Dismiss">✕</span>
        </div>
      )}

      {awsAuthError && (
        <div style={authBanner(awsAuthError.code)}>
          <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
            <span style={{ fontSize: 20, lineHeight: 1 }}>
              {awsAuthError.code === 'auth_expired' || awsAuthError.code === 'auth_invalid' || awsAuthError.code === 'no_credentials' ? '🔒' : '⚠'}
            </span>
            <div style={{ flex: 1 }}>
              <div style={{ fontWeight: 700, fontSize: 14, marginBottom: 4 }}>
                {awsAuthError.code === 'auth_expired' && 'AWS session expired'}
                {awsAuthError.code === 'auth_invalid' && 'AWS credentials invalid'}
                {awsAuthError.code === 'no_credentials' && 'AWS credentials missing'}
                {awsAuthError.code === 'access_denied' && 'AWS access denied'}
                {awsAuthError.code === 'other' && 'AWS discovery failed'}
              </div>
              <div style={{ fontSize: 13, marginBottom: 6 }}>
                {awsAuthError.message}
                {awsAuthError.profile && (
                  <span style={{ marginLeft: 6, color: '#7a4a00' }}>
                    (profile <code style={{ fontSize: 12 }}>{awsAuthError.profile}</code>{awsAuthError.region ? `, ${awsAuthError.region}` : ''})
                  </span>
                )}
              </div>
              <div style={{ fontSize: 12, color: '#7a4a00', marginBottom: 8 }}>
                Showing only locally-tracked instances. EC2 discovery is unavailable until credentials are refreshed.
              </div>
              <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
                <button
                  onClick={() => navigate('/config')}
                  style={authBtnPrimary}
                  title="Go to Config to sync AWS credentials"
                >
                  → Sync AWS Credentials
                </button>
                <button
                  onClick={() => refreshWithDiscovery()}
                  style={authBtnSecondary}
                  title="Try the discovery again"
                  disabled={discovering}
                >
                  {discovering ? '⟳ Retrying…' : '⟳ Retry'}
                </button>
                {awsAuthError.detail && (
                  <details style={{ fontSize: 11, color: '#7a4a00', alignSelf: 'center' }}>
                    <summary style={{ cursor: 'pointer' }}>Details</summary>
                    <pre style={{ background: 'rgba(0,0,0,0.05)', padding: 8, borderRadius: 4, marginTop: 4, whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>{awsAuthError.detail}</pre>
                  </details>
                )}
              </div>
            </div>
            <span onClick={() => setAwsAuthError(null)} style={{ cursor: 'pointer', color: '#7a4a00' }} title="Dismiss">✕</span>
          </div>
        </div>
      )}

      {/* ── Toolbar ──────────────────────────────────────────────────── */}
      <div style={{ display: 'flex', gap: 10, alignItems: 'center', marginBottom: 14 }}>
        <input
          value={filterText}
          onChange={(e) => {
            setFilterText(e.target.value);
            if (searchParams.get('profile')) setSearchParams({}, { replace: true });
          }}
          placeholder="Filter instances…"
          style={searchInput}
        />
        <select value={sortKey} onChange={(e) => setSortKey(e.target.value as typeof sortKey)} style={sortSelect} title="Sort instances">
          <option value="favorites">Sort: Favorites first</option>
          <option value="name-asc">Sort: Name A-Z</option>
          <option value="name-desc">Sort: Name Z-A</option>
          <option value="state">Sort: Running first</option>
          <option value="ip-asc">Sort: IP</option>
          <option value="created-desc">Sort: Created newest</option>
          <option value="created-asc">Sort: Created oldest</option>
        </select>
        <button
          onClick={() => refreshWithDiscovery()}
          disabled={discovering}
          style={secondaryBtn}
          title="Refresh instances and discover EC2"
        >
          {discovering ? '⟳ Discovering…' : '⟳ Refresh'}
        </button>
        <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
          {runningCount > 0 && (
            <span style={{ ...countBadge, background: 'var(--badge-green-bg)', color: 'var(--badge-green-fg)' }}>
              {runningCount} running
            </span>
          )}
          {untrackedCount > 0 && (
            <span style={{ ...countBadge, background: 'var(--badge-yellow-bg)', color: 'var(--badge-yellow-fg)' }}>
              {untrackedCount} untracked
            </span>
          )}
        </div>
        <div style={{ flex: 1 }} />
        {lastDiscoveryTime && (
          <span style={{ fontSize: 11, color: '#999' }}>
            Last scan: {lastDiscoveryTime.toLocaleTimeString()}
          </span>
        )}
      </div>

      {searchParams.get('profile') && (
        <div style={profileFilterBanner}>
          <span>
            Showing instances related to profile <b>{searchParams.get('profile')}</b>.
          </span>
          <button
            onClick={() => {
              setSearchParams({}, { replace: true });
              setFilterText('');
            }}
            style={clearProfileFilterBtn}
            title="Clear profile filter"
          >
            Clear
          </button>
        </div>
      )}

      <div style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: 8, marginBottom: 14 }}>
        <span style={{ fontSize: 11, color: '#8e9eab', fontWeight: 700, letterSpacing: 0.5, textTransform: 'uppercase' }}>Status</span>
        <button onClick={() => toggleStatusFilter('running')} style={{ ...filterChipBtn, ...(statusFilters.has('running') ? filterChipBtnActive : {}) }}>
          Running {runningCount > 0 ? `(${runningCount})` : ''}
        </button>
        <button onClick={() => toggleStatusFilter('untracked')} style={{ ...filterChipBtn, ...(statusFilters.has('untracked') ? filterChipBtnActive : {}) }}>
          Untracked {untrackedCount > 0 ? `(${untrackedCount})` : ''}
        </button>
        <button onClick={() => toggleStatusFilter('unreachable')} style={{ ...filterChipBtn, ...(statusFilters.has('unreachable') ? filterChipBtnActive : {}) }}>
          Unreachable {unreachableCount > 0 ? `(${unreachableCount})` : ''}
        </button>
        <button onClick={() => toggleStatusFilter('reachable')} style={{ ...filterChipBtn, ...(statusFilters.has('reachable') ? filterChipBtnActive : {}) }}>
          Reachable {reachableCount > 0 ? `(${reachableCount})` : ''}
        </button>
        <button onClick={() => toggleStatusFilter('orphan')} style={{ ...filterChipBtn, ...(statusFilters.has('orphan') ? filterChipBtnActive : {}) }}>
          Orphan {orphanCount > 0 ? `(${orphanCount})` : ''}
        </button>

        <span style={{ width: 1, height: 16, background: '#dfe5ea', margin: '0 4px' }} />
        <span style={{ fontSize: 11, color: '#8e9eab', fontWeight: 700, letterSpacing: 0.5, textTransform: 'uppercase' }}>Server</span>
        <button onClick={() => toggleServerFilter('pentaho')} style={{ ...filterChipBtn, ...(serverFilters.has('pentaho') ? filterChipBtnActive : {}) }}>
          Pentaho Server {pentahoCount > 0 ? `(${pentahoCount})` : ''}
        </button>
        <button onClick={() => toggleServerFilter('pdc')} style={{ ...filterChipBtn, ...(serverFilters.has('pdc') ? filterChipBtnActive : {}) }}>
          PDC Server {pdcCount > 0 ? `(${pdcCount})` : ''}
        </button>
        <button
          onClick={() => setFavoriteOnly((prev) => !prev)}
          style={{ ...filterChipBtn, ...(favoriteOnly ? filterChipBtnActive : {}) }}
          title="Show only favorited instances"
        >
          Favorites {favoritesCount > 0 ? `(${favoritesCount})` : ''}
        </button>

        {(statusFilters.size > 0 || serverFilters.size > 0 || favoriteOnly) && (
          <button
            onClick={() => {
              setStatusFilters(new Set());
              setServerFilters(new Set());
              setFavoriteOnly(false);
            }}
            style={clearChipBtn}
            title="Clear all quick filters"
          >
            Clear Filters
          </button>
        )}
      </div>

      {/* ── Instance Grid ────────────────────────────────────────────── */}
      {filteredInstances.length === 0 ? (
        <div style={{ color: '#999', padding: 20, textAlign: 'center' }}>
          {discovering ? 'Discovering instances…' : filterText ? 'No instances match filter.' : 'No running instances found.'}
        </div>
      ) : (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(320px, 1fr))', gap: 14 }}>
          {filteredInstances.map((inst) => {
            const stateKey = cardStateKey(inst);
            const isUntracked = inst.tracking_status === 'untracked';
            const phaseColors: Record<string, { bg: string; fg: string }> = {
              'ec2-created': { bg: 'var(--badge-orange-bg)', fg: 'var(--badge-orange-fg)' },
              'ec2-ready': { bg: 'var(--badge-blue-bg)', fg: 'var(--badge-blue-fg)' },
              'pentaho-deployed': { bg: 'var(--badge-green-bg)', fg: 'var(--badge-green-fg)' },
              'plugins-deployed': { bg: 'var(--badge-green-bg)', fg: 'var(--badge-green-fg)' },
            };
            const phaseStyle = phaseColors[inst.deploy_phase] || { bg: 'var(--badge-gray-bg)', fg: 'var(--badge-gray-fg)' };
            const phaseLabel = inst.deploy_phase ? inst.deploy_phase.replace(/-/g, ' ') : '';
            const displayName = isUntracked
              ? (inst.ec2_tags?.Name || inst.instance_id || 'Unknown Instance')
              : inst.name;
            const serverLabel = inst.server_type === 'pdc' ? 'PDC Server' : inst.server_type === 'pentaho' ? 'Pentaho Server' : inst.server_type === 'ops-console' ? 'Ops Console' : 'Unknown Server';
            const serverBadgeStyle = inst.server_type === 'pdc'
              ? { background: 'var(--badge-purple-bg)', color: 'var(--badge-purple-fg)' }
              : inst.server_type === 'pentaho' || inst.server_type === 'ops-console'
                ? { background: 'var(--badge-blue-bg)', color: 'var(--badge-blue-fg)' }
                : { background: 'var(--badge-muted-bg)', color: 'var(--badge-muted-fg)' };
            const isOrphan = !inst.has_profile && !isUntracked;
            const canManageTracked = !isUntracked && inst.has_profile && !tornDown.has(stateKey);
            const canStart = canManageTracked && inst.instance_state !== 'running' && !starting.has(stateKey) && !stopping.has(stateKey) && !tearingDown.has(stateKey);
            const canStop = canManageTracked && inst.instance_state === 'running' && !starting.has(stateKey) && !stopping.has(stateKey) && !tearingDown.has(stateKey);
            const canTeardown = canManageTracked && !tearingDown.has(stateKey) && !starting.has(stateKey) && !stopping.has(stateKey);
            const menuOpen = menuOpenFor === stateKey;
            const isReachable = Boolean(inst.server_url) && healthMap[inst.server_url] === true;
            const isUnreachable = Boolean(inst.server_url) && healthMap[inst.server_url] === false;
            const showPhaseTag = Boolean(phaseLabel) && !(inst.deploy_phase === 'ec2-ready' && inst.instance_state === 'running' && isReachable);
            const showTitleTooltip = hoveredTitleFor === stateKey && displayName.length > 28;
            const isFavorite = favorites.has(stateKey);
            const commentText = instanceComments[stateKey] || '';

            return (
            <div key={stateKey} style={{
              ...instanceCard,
              ...(tornDown.has(stateKey) ? { opacity: 0.55 } : {}),
              borderLeft: isUntracked ? '4px solid var(--card-untracked-side)' : '4px solid var(--card-tracked-side)',
              ...(isUntracked ? { background: 'var(--card-untracked-bg)' } : {}),
            }}>
              <div style={cardTitleBar}>
                <div
                  style={{ minWidth: 0, flex: 1, position: 'relative' }}
                  onMouseEnter={() => setHoveredTitleFor(stateKey)}
                  onMouseLeave={() => setHoveredTitleFor((prev) => (prev === stateKey ? null : prev))}
                >
                  <div style={cardTitleText}>{displayName}</div>
                  {showTitleTooltip && (
                    <div style={titleTooltip}>
                      {displayName}
                    </div>
                  )}
                </div>
                <button
                  onClick={() => toggleFavorite(inst)}
                  style={starBtn}
                  title={isFavorite ? 'Remove favorite' : 'Add favorite'}
                >
                  <span style={{ color: isFavorite ? '#f39c12' : '#aeb8c2' }}>{isFavorite ? '★' : '☆'}</span>
                </button>
                <div style={{ position: 'relative', marginLeft: 8 }}>
                  <button
                    onClick={() => setMenuOpenFor(menuOpen ? null : stateKey)}
                    style={menuToggleBtn}
                    title="Card actions"
                    data-card-menu-toggle
                  >
                    ⋯
                  </button>
                  {menuOpen && (
                    <div style={cardMenu} data-card-menu>
                      {!isUntracked && inst.has_profile && (
                        <button
                          onClick={() => {
                            setMenuOpenFor(null);
                            goToProfile(inst.name);
                          }}
                          style={menuItemBtn}
                        >
                          View Profile
                        </button>
                      )}

                      {inst.server_url && (
                        <button
                          onClick={() => {
                            setMenuOpenFor(null);
                            launchContentPreview(inst);
                          }}
                          style={menuItemBtn}
                        >
                          Preview Content
                        </button>
                      )}

                      {!isUntracked && inst.has_profile && (
                        <>
                          <div style={menuDivider} />
                          <button
                            onClick={() => runEc2Lifecycle(inst, 'start')}
                            disabled={!canStart}
                            style={{ ...menuItemBtn, ...menuActionStartBtn, opacity: canStart ? 1 : 0.45, cursor: canStart ? 'pointer' : 'not-allowed' }}
                          >
                            Start EC2 Instance
                          </button>
                          <button
                            onClick={() => runEc2Lifecycle(inst, 'stop')}
                            disabled={!canStop}
                            style={{ ...menuItemBtn, ...menuActionStopBtn, opacity: canStop ? 1 : 0.45, cursor: canStop ? 'pointer' : 'not-allowed' }}
                          >
                            Stop EC2 Instance
                          </button>
                          <button
                            onClick={() => {
                              setMenuOpenFor(null);
                              setTeardownTarget(inst);
                              setTeardownCode(teardownCodeFor(inst));
                              setTeardownInput('');
                            }}
                            disabled={!canTeardown}
                            style={{ ...menuItemBtn, ...menuActionDangerBtn, opacity: canTeardown ? 1 : 0.45, cursor: canTeardown ? 'pointer' : 'not-allowed' }}
                          >
                            Teardown Instance
                          </button>
                        </>
                      )}
                    </div>
                  )}
                </div>
              </div>

              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'stretch', marginTop: 8, gap: 10, minHeight: 42 }}>
                <div style={{ display: 'flex', flexDirection: 'column', justifyContent: 'space-between', minWidth: 0 }}>
                  <div style={{ fontSize: 12, color: 'var(--text-muted)', lineHeight: 1.3 }}>
                    {inst.pentaho_version ? `v${inst.pentaho_version}` : 'version unknown'}
                  </div>
                  <div style={{ fontSize: 12, color: 'var(--text-muted)', lineHeight: 1.3 }}>
                    {inst.instance_type || 'instance type unknown'}
                  </div>
                </div>

                <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', justifyContent: 'space-between', minWidth: 150 }}>
                  <div style={{ display: 'flex', gap: 6, alignItems: 'center', justifyContent: 'flex-end' }}>
                    <span style={{ ...stateBadge, ...serverBadgeStyle, fontSize: 10 }}>{serverLabel}</span>
                    <span style={{
                      ...stateBadge,
                      background: tornDown.has(stateKey) ? 'var(--badge-gray-bg)'
                        : isUnreachable ? 'var(--badge-orange-bg)'
                        : (isUntracked && !Boolean(inst.server_url)) ? 'var(--badge-yellow-bg)'
                        : inst.instance_state === 'running' ? 'var(--badge-green-bg)' : 'var(--badge-orange-bg)',
                      color: tornDown.has(stateKey) ? 'var(--badge-gray-fg)'
                        : isUnreachable ? 'var(--badge-orange-fg)'
                        : (isUntracked && !Boolean(inst.server_url)) ? 'var(--badge-yellow-fg)'
                        : inst.instance_state === 'running' ? 'var(--badge-green-fg)' : 'var(--badge-orange-fg)',
                    }}>
                      {tornDown.has(stateKey) ? '✕ terminated'
                        : isUnreachable ? `○ stopped`
                        : (isUntracked && !Boolean(inst.server_url)) ? '? unknown'
                        : inst.instance_state === 'running' ? `● ${inst.instance_state}`
                        : `○ ${inst.instance_state || 'unknown'}`}
                    </span>
                  </div>

                  <div style={{ display: 'flex', gap: 6, alignItems: 'center', justifyContent: 'flex-end', minHeight: 20 }}>
                    {showPhaseTag && (
                      <span style={{ ...stateBadge, background: phaseStyle.bg, color: phaseStyle.fg, fontSize: 10 }}>
                        {phaseLabel}
                      </span>
                    )}
                    {isUntracked && (
                      <span style={{ ...stateBadge, background: 'var(--badge-yellow-bg)', color: 'var(--badge-yellow-fg)', fontSize: 10 }}>untracked</span>
                    )}
                    {isOrphan && (
                      <span style={{ ...stateBadge, background: 'var(--badge-amber-bg)', color: 'var(--badge-amber-fg)', fontSize: 10 }}>orphan</span>
                    )}
                  </div>
                </div>
              </div>

              <div style={{ marginTop: 10, display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '4px 12px', fontSize: 12 }}>
                <div style={fieldLabel}>IP Address</div>
                <div style={fieldValue}>{inst.instance_ip || '—'}</div>
                {inst.public_ip && (
                  <>
                    <div style={fieldLabel}>Public IP</div>
                    <div style={fieldValue}>{inst.public_ip}</div>
                  </>
                )}
                <div style={fieldLabel}>Instance ID</div>
                <div style={{ ...fieldValue, fontFamily: 'Menlo, Monaco, monospace', fontSize: 11 }}>{inst.instance_id || '—'}</div>
                <div style={fieldLabel}>Created</div>
                <div style={fieldValue}>{inst.created_date ? new Date(inst.created_date).toLocaleDateString() : '—'}</div>
                <div style={fieldLabel}>Database</div>
                <div style={fieldValue}>{inst.db_type || '—'}</div>
                {isUntracked && inst.ec2_tags?.['instance-type'] && (
                  <>
                    <div style={fieldLabel}>Instance Type</div>
                    <div style={fieldValue}>{inst.ec2_tags['instance-type']}</div>
                  </>
                )}
              </div>

              {inst.server_url && (
                <div style={{
                  marginTop: 8,
                  padding: '6px 10px',
                  background: healthMap[inst.server_url] === true ? 'var(--health-ok-bg)' : healthMap[inst.server_url] === false ? 'var(--health-warn-bg)' : 'var(--health-null-bg)',
                  borderRadius: 6,
                  border: `1px solid ${healthMap[inst.server_url] === true ? 'var(--health-ok-border)' : healthMap[inst.server_url] === false ? 'var(--health-warn-border)' : 'var(--health-null-border)'}`,
                }}>
                  <div style={{ fontSize: 11, color: 'var(--text-muted)', marginBottom: 2, display: 'flex', alignItems: 'center', gap: 6 }}>
                    {serverLabel}
                    {healthMap[inst.server_url] === true && <span style={{ color: 'var(--badge-green-fg)' }}>● reachable</span>}
                    {healthMap[inst.server_url] === false && <span style={{ color: 'var(--badge-orange-fg)' }}>○ unreachable</span>}
                    {healthMap[inst.server_url] == null && <span style={{ color: 'var(--text-muted)' }}>… checking</span>}
                  </div>
                  <a
                    href={inst.server_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    style={{ fontSize: 12, color: healthMap[inst.server_url] === false ? 'var(--text-muted)' : 'var(--badge-blue-fg)', textDecoration: 'none', wordBreak: 'break-all' }}
                  >
                    {inst.server_url} ↗
                  </a>
                </div>
              )}

              <div style={commentBox}>
                {!commentText && focusedCommentKey !== stateKey && (
                  <span style={commentHint}>Add note</span>
                )}
                {commentText && (
                  <button
                    onClick={() => setCommentFor(inst, '')}
                    style={clearNoteBtn}
                    title="Clear note"
                  >
                    clear
                  </button>
                )}
                <textarea
                  value={commentText}
                  onChange={(e) => setCommentFor(inst, e.target.value)}
                  onFocus={() => setFocusedCommentKey(stateKey)}
                  onBlur={() => setFocusedCommentKey((prev) => (prev === stateKey ? null : prev))}
                  placeholder=""
                  rows={2}
                  style={commentInput}
                />
              </div>

              <div style={cardFooter}>
                <div style={cardFooterMessageRow}>
                  {isUntracked ? (
                    <span style={{ fontSize: 12, color: '#856404' }}>
                      Discovered via EC2 — not managed by ops console
                    </span>
                  ) : !inst.has_profile ? (
                    <span style={{ fontSize: 12, color: '#e67e22' }}>⚠ No .env profile (orphan instance)</span>
                  ) : (
                    <span style={{ fontSize: 12, color: '#9aa7b3' }}>Managed by ops console profile</span>
                  )}
                </div>

                <div style={cardFooterButtonsRow}>
                  <div style={{ marginLeft: 'auto', flexShrink: 0 }}>
                    {!isUntracked && tornDown.has(stateKey) ? (
                      <span style={{ fontSize: 12, color: '#95a5a6', fontWeight: 600 }}>✓ Terminated</span>
                    ) : !isUntracked && tearingDown.has(stateKey) ? (
                      <span style={{ fontSize: 12, color: '#e67e22', fontWeight: 600 }}>⟳ Tearing down…</span>
                    ) : !isUntracked && starting.has(stateKey) ? (
                      <span style={{ fontSize: 12, color: '#005bb5', fontWeight: 600 }}>⟳ Starting EC2…</span>
                    ) : !isUntracked && stopping.has(stateKey) ? (
                      <span style={{ fontSize: 12, color: '#856404', fontWeight: 600 }}>⟳ Stopping EC2…</span>
                    ) : null}
                  </div>
                </div>
              </div>
            </div>
            );
          })}
        </div>
      )}

      {contentModalOpen && (
        <div style={overlay}>
          <div style={{ ...dialog, maxWidth: 1040 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10 }}>
              <h3 style={{ margin: 0, fontSize: 18 }}>Content Preview Report</h3>
              <button
                onClick={() => {
                  setContentModalOpen(false);
                  setContentReportId(null);
                }}
                style={{ ...secondaryBtn, padding: '6px 12px', fontSize: 12 }}
                title="Close"
              >
                Close
              </button>
            </div>

            {contentError && (
              <div style={{ ...errorBanner, marginBottom: 10 }}>
                {contentError}
              </div>
            )}

            {!contentStatus && !contentError && (
              <div style={{ padding: '20px 0', color: '#666', fontSize: 14 }}>Starting preview…</div>
            )}

            {contentStatus && (
              <>
                <div style={{ marginBottom: 10 }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 4, fontSize: 12, color: '#666' }}>
                    <span>{contentStatus.message} ({contentStatus.phase})</span>
                    <span>{contentStatus.progress}%</span>
                  </div>
                  <div style={{ height: 10, background: '#e9ecef', borderRadius: 8, overflow: 'hidden' }}>
                    <div style={{ width: `${contentStatus.progress}%`, height: '100%', background: contentStatus.status === 'failed' ? '#e74c3c' : '#0073e7', transition: 'width 0.3s' }} />
                  </div>
                </div>

                {contentStatus.status === 'failed' && (
                  <div style={{ background: '#fceaea', color: '#a93226', border: '1px solid #efb4ad', borderRadius: 6, padding: '8px 10px', marginBottom: 10, fontSize: 12 }}>
                    {contentStatus.error || 'Report generation failed.'}
                  </div>
                )}

                {contentStatus.report && (
                  <>
                    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(190px, 1fr))', gap: 10, marginBottom: 12 }}>
                      {Object.entries(contentStatus.report.summary).slice(0, 6).map(([k, v]) => (
                        <div key={k} style={statCard}>
                          <div style={{ fontSize: 11, color: '#8a98a8', textTransform: 'uppercase', letterSpacing: 0.6 }}>{k.replace(/_/g, ' ')}</div>
                          <div style={{ marginTop: 5, fontSize: 18, fontWeight: 700, color: '#1f2d3d' }}>
                            {k.includes('bytes') ? fmtBytes(v) : statValue(v)}
                          </div>
                        </div>
                      ))}
                    </div>

                    <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', marginBottom: 10 }}>
                      {contentStatus.report.navigator.map((nav) => (
                        <button
                          key={nav.id}
                          onClick={() => setContentTab(nav.id)}
                          style={{
                            ...tabBtn,
                            ...(contentTab === nav.id ? activeTabBtn : {}),
                          }}
                        >
                          {nav.label}
                        </button>
                      ))}
                    </div>

                    <div style={reportBody}>
                      {contentTab === 'overview' && (
                        <div>
                          <div style={{ fontSize: 13, color: '#5a6c7d', marginBottom: 8 }}>
                            Type: <b>{contentStatus.report.kind.toUpperCase()}</b> · Target: <b>{contentStatus.report.target}</b>
                          </div>
                          <div style={{ fontSize: 12, color: '#7b8a99' }}>
                            Use the navigator tabs to review repository content, datasources, Mondrian catalogs, and raw diagnostics.
                          </div>
                        </div>
                      )}

                      {contentTab === 'content' && (
                        <ContentTable
                          items={(contentStatus.report.sections.content as { items?: Array<{ path?: string; size?: number; ext?: string }> })?.items || []}
                        />
                      )}

                      {contentTab === 'datasources' && (
                        <>
                          <div style={{ marginBottom: 8, fontSize: 12, color: '#5a6c7d' }}>
                            {JSON.stringify((contentStatus.report.sections.datasources as { counts?: unknown })?.counts || {}, null, 2)}
                          </div>
                          <ContentTable
                            items={(contentStatus.report.sections.datasources as { items?: Array<{ path?: string; size?: number; ext?: string }> })?.items || []}
                          />
                        </>
                      )}

                      {contentTab === 'mondrian' && (
                        <pre style={reportPre}>{JSON.stringify((contentStatus.report.sections.mondrian as { catalogs?: unknown })?.catalogs || [], null, 2)}</pre>
                      )}

                      {contentTab === 'home' && (
                        <pre style={reportPre}>{JSON.stringify(contentStatus.report.sections.home || {}, null, 2)}</pre>
                      )}

                      {contentTab === 'probes' && (
                        <pre style={reportPre}>{JSON.stringify((contentStatus.report.sections.probes as { items?: unknown })?.items || [], null, 2)}</pre>
                      )}

                      {contentTab === 'signals' && (
                        <pre style={reportPre}>{JSON.stringify(contentStatus.report.sections.signals || {}, null, 2)}</pre>
                      )}

                      {contentTab === 'raw' && (
                        <pre style={reportPre}>{JSON.stringify(contentStatus.logs || [], null, 2)}</pre>
                      )}
                    </div>
                  </>
                )}
              </>
            )}
          </div>
        </div>
      )}

      <Terminal
        jobId={lifecycleJobId}
        onDone={() => {
          if (activeLifecycleAction?.action === 'start') {
            setStarting((prev) => {
              const next = new Set(prev);
              next.delete(activeLifecycleAction.stateKey);
              return next;
            });
          }
          if (activeLifecycleAction?.action === 'stop') {
            setStopping((prev) => {
              const next = new Set(prev);
              next.delete(activeLifecycleAction.stateKey);
              return next;
            });
          }
          setActiveLifecycleAction(null);
          refreshWithDiscovery();
        }}
        onClose={() => {
          setLifecycleJobId(null);
          setActiveLifecycleAction(null);
          setStarting(new Set());
          setStopping(new Set());
          refreshWithDiscovery();
        }}
      />

      <Terminal
        jobId={teardownJobId}
        onDone={() => {
          setTornDown((prev) => new Set([...prev, ...tearingDown]));
          setTearingDown(new Set());
          refreshWithDiscovery();
        }}
        onClose={() => { setTeardownJobId(null); setTornDown(new Set()); refreshWithDiscovery(); }}
      />

      {/* ── Teardown confirmation modal ──────────────────────────────── */}
      {teardownTarget && (
        <div style={overlay}>
          <div style={{ ...dialog, maxWidth: 480 }}>
            <h3 style={{ margin: '0 0 12px', color: '#e74c3c', fontSize: 16 }}>
              ⚠ Confirm Instance Teardown
            </h3>
            <p style={{ margin: '0 0 12px', fontSize: 13, color: '#5a6c7d' }}>
              This will <b>permanently terminate</b> the following EC2 instance and delete its state file.
              This action cannot be undone.
            </p>
            <div style={{
              background: '#fdf2f2', border: '1px solid #f5c6cb', borderRadius: 6,
              padding: '10px 14px', marginBottom: 14, fontSize: 13, lineHeight: 1.7,
            }}>
              <div><b>Profile:</b> {teardownTarget.name}</div>
              <div><b>Instance ID:</b> {teardownTarget.instance_id || '—'}</div>
              <div><b>IP Address:</b> {teardownTarget.instance_ip || '—'}</div>
              <div><b>Instance Type:</b> {teardownTarget.instance_type || '—'}</div>
              <div><b>Deploy Phase:</b> {teardownTarget.deploy_phase || '—'}</div>
              <div><b>Environment:</b> {teardownTarget.environment || '—'}</div>
              {teardownTarget.pentaho_version && (
                <div><b>Pentaho Version:</b> {teardownTarget.pentaho_version}</div>
              )}
              {teardownTarget.server_url && (
                <div><b>Server URL:</b> {teardownTarget.server_url}</div>
              )}
              <div><b>State File:</b> {teardownTarget.state_file}</div>
            </div>
            <div style={{ marginBottom: 14 }}>
              <label style={{ display: 'block', fontSize: 13, color: '#2c3e50', marginBottom: 6 }}>
                Type <span style={{
                  fontFamily: 'monospace', fontWeight: 700, fontSize: 15,
                  background: '#2c3e50', color: '#fff', padding: '2px 8px',
                  borderRadius: 4, letterSpacing: 2,
                }}>{teardownCode}</span> to confirm:
              </label>
              <input
                value={teardownInput}
                onChange={(e) => setTeardownInput(e.target.value.toUpperCase())}
                placeholder="Enter code"
                style={{
                  width: '100%', padding: '8px 12px', borderRadius: 6,
                  border: '1px solid #ddd', fontSize: 15, fontFamily: 'monospace',
                  letterSpacing: 2, textTransform: 'uppercase', boxSizing: 'border-box',
                }}
                autoFocus
                onKeyDown={(e) => {
                  if (e.key === 'Escape') setTeardownTarget(null);
                }}
              />
            </div>
            <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
              <button
                onClick={() => setTeardownTarget(null)}
                style={{ padding: '8px 18px', borderRadius: 6, border: '1px solid var(--field-border)', background: 'var(--field-bg)', color: 'var(--text-primary)', cursor: 'pointer', fontSize: 13 }}
                title="Cancel teardown"
              >
                Cancel
              </button>
              <button
                disabled={teardownInput !== teardownCode}
                title="Permanently terminate this EC2 instance"
                onClick={async () => {
                  const inst = teardownTarget;
                  setTeardownTarget(null);
                  try {
                    const { job_id } = await teardown(inst.name, inst.state_file);
                    setTearingDown((prev) => new Set(prev).add(cardStateKey(inst)));
                    setTeardownJobId(job_id);
                  } catch (e) {
                    alert(`Teardown failed: ${e}`);
                  }
                }}
                style={{
                  padding: '8px 18px', borderRadius: 6, border: 'none',
                  background: teardownInput === teardownCode ? '#e74c3c' : '#ccc',
                  color: '#fff', cursor: teardownInput === teardownCode ? 'pointer' : 'not-allowed',
                  fontSize: 13, fontWeight: 600,
                }}
              >
                Destroy Instance
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function ContentTable({ items }: { items: Array<{ path?: string; size?: number; ext?: string }> }) {
  if (!items.length) {
    return <div style={{ color: '#8a98a8', fontSize: 12 }}>No items returned.</div>;
  }
  return (
    <div style={{ maxHeight: 360, overflow: 'auto', border: '1px solid #e6ebf0', borderRadius: 6 }}>
      <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 12 }}>
        <thead>
          <tr style={{ background: '#f7fafc', color: '#5a6c7d' }}>
            <th style={thStyle}>Path</th>
            <th style={thStyle}>Type</th>
            <th style={thStyle}>Size</th>
          </tr>
        </thead>
        <tbody>
          {items.slice(0, 1200).map((it, idx) => (
            <tr key={`${it.path || 'item'}-${idx}`}>
              <td style={tdStyle}>{it.path || '—'}</td>
              <td style={tdStyle}>{it.ext || '—'}</td>
              <td style={{ ...tdStyle, whiteSpace: 'nowrap' }}>{typeof it.size === 'number' ? it.size.toLocaleString() : '—'}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// ── Styles ────────────────────────────────────────────────────────────────────

const searchInput: React.CSSProperties = {
  padding: '7px 12px',
  borderRadius: 6,
  border: '1px solid var(--field-border)',
  fontSize: 13,
  width: 220,
  background: 'var(--field-bg)',
  color: 'var(--text-primary)',
};

const sortSelect: React.CSSProperties = {
  padding: '7px 10px',
  borderRadius: 6,
  border: '1px solid var(--field-border)',
  fontSize: 13,
  background: 'var(--field-bg)',
  color: 'var(--text-primary)',
};

const countBadge: React.CSSProperties = {
  fontSize: 11,
  padding: '2px 10px',
  borderRadius: 10,
  fontWeight: 600,
};

const profileFilterBanner: React.CSSProperties = {
  display: 'flex',
  justifyContent: 'space-between',
  alignItems: 'center',
  gap: 10,
  margin: '-4px 0 14px',
  padding: '8px 12px',
  border: '1px solid #cfe0f4',
  borderRadius: 6,
  background: '#eef6ff',
  color: '#315f8d',
  fontSize: 12,
};

const clearProfileFilterBtn: React.CSSProperties = {
  border: 'none',
  background: '#dcecff',
  color: '#005bb5',
  borderRadius: 4,
  padding: '4px 9px',
  cursor: 'pointer',
  fontSize: 12,
};

const instanceCard: React.CSSProperties = {
  background: 'var(--panel-bg)',
  border: '1px solid var(--panel-border)',
  padding: 12,
  borderRadius: 8,
  boxShadow: 'var(--panel-shadow)',
  display: 'flex',
  flexDirection: 'column',
  minHeight: 290,
};

const cardTitleBar: React.CSSProperties = {
  background: 'var(--panel-subtle-bg)',
  border: '1px solid var(--panel-subtle-border)',
  borderRadius: 6,
  padding: '7px 10px',
  display: 'flex',
  alignItems: 'center',
};

const cardTitleText: React.CSSProperties = {
  fontWeight: 700,
  fontSize: 13,
  color: 'var(--text-primary)',
  whiteSpace: 'nowrap',
  overflow: 'hidden',
  textOverflow: 'ellipsis',
};

const titleTooltip: React.CSSProperties = {
  position: 'absolute',
  left: 0,
  top: 'calc(100% + 6px)',
  maxWidth: 460,
  padding: '6px 10px',
  borderRadius: 6,
  background: '#1f2d3d',
  color: '#fff',
  fontSize: 12,
  lineHeight: 1.35,
  whiteSpace: 'normal',
  wordBreak: 'break-word',
  boxShadow: '0 6px 16px rgba(0,0,0,0.2)',
  zIndex: 15,
};

const stateBadge: React.CSSProperties = {
  fontSize: 11,
  padding: '2px 10px',
  borderRadius: 10,
  fontWeight: 600,
};

const fieldLabel: React.CSSProperties = {
  color: 'var(--text-muted)',
  fontSize: 12,
};

const fieldValue: React.CSSProperties = {
  fontSize: 12,
  color: 'var(--text-primary)',
};

const menuToggleBtn: React.CSSProperties = {
  border: '1px solid var(--panel-border)',
  background: 'var(--panel-bg)',
  color: 'var(--text-muted)',
  borderRadius: 6,
  width: 28,
  height: 28,
  cursor: 'pointer',
  fontSize: 18,
  lineHeight: 1,
  display: 'inline-flex',
  alignItems: 'center',
  justifyContent: 'center',
};

const starBtn: React.CSSProperties = {
  border: '1px solid var(--panel-border)',
  background: 'var(--panel-bg)',
  borderRadius: 6,
  width: 28,
  height: 28,
  cursor: 'pointer',
  fontSize: 16,
  lineHeight: 1,
  display: 'inline-flex',
  alignItems: 'center',
  justifyContent: 'center',
  marginLeft: 8,
};

const cardMenu: React.CSSProperties = {
  position: 'absolute',
  top: 32,
  right: 0,
  minWidth: 190,
  background: 'var(--panel-bg)',
  border: '1px solid var(--panel-border)',
  borderRadius: 8,
  boxShadow: '0 8px 24px rgba(15, 23, 42, 0.16)',
  padding: 6,
  zIndex: 20,
};

const menuItemBtn: React.CSSProperties = {
  width: '100%',
  textAlign: 'left',
  background: 'transparent',
  border: 'none',
  borderRadius: 6,
  padding: '8px 10px',
  color: 'var(--text-primary)',
  fontSize: 12,
  cursor: 'pointer',
};

const menuDivider: React.CSSProperties = {
  height: 1,
  background: 'var(--panel-subtle-border)',
  margin: '6px 2px',
};

const menuActionStartBtn: React.CSSProperties = {
  color: 'var(--badge-green-fg)',
  background: 'var(--badge-green-bg)',
};

const menuActionStopBtn: React.CSSProperties = {
  color: 'var(--badge-orange-fg)',
  background: 'var(--badge-orange-bg)',
};

const menuActionDangerBtn: React.CSSProperties = {
  color: '#e05548',
  background: 'rgba(224, 85, 72, 0.12)',
};

const secondaryBtn: React.CSSProperties = {
  background: 'var(--button-subtle-bg)',
  color: 'var(--button-subtle-text)',
  border: 'none',
  padding: '8px 16px',
  borderRadius: 4,
  cursor: 'pointer',
  fontSize: 14,
};

const overlay: React.CSSProperties = {
  position: 'fixed',
  inset: 0,
  background: 'rgba(0,0,0,0.4)',
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  zIndex: 1000,
};

const dialog: React.CSSProperties = {
  background: 'var(--panel-bg)',
  border: '1px solid var(--panel-border)',
  borderRadius: 8,
  padding: 24,
  maxWidth: 640,
  width: '90%',
  maxHeight: '85vh',
  overflow: 'auto',
  boxShadow: '0 8px 32px rgba(0,0,0,0.2)',
};

const errorBanner: React.CSSProperties = {
  background: '#fceaea',
  color: '#c0392b',
  padding: '8px 14px',
  borderRadius: 4,
  marginBottom: 12,
  fontSize: 13,
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'space-between',
};

function authBanner(code: AwsDiscoveryError['code']): React.CSSProperties {
  const isAuth = code === 'auth_expired' || code === 'auth_invalid' || code === 'no_credentials';
  return {
    background: isAuth ? '#fff8e1' : '#fef3e2',
    color: '#5a3a00',
    border: `1px solid ${isAuth ? '#f1c40f' : '#f39c12'}`,
    borderLeft: `5px solid ${isAuth ? '#f39c12' : '#e67e22'}`,
    padding: '12px 14px',
    borderRadius: 6,
    marginBottom: 14,
    fontSize: 13,
    boxShadow: '0 1px 3px rgba(0,0,0,0.06)',
  };
}

const authBtnPrimary: React.CSSProperties = {
  background: '#005bb5',
  color: '#fff',
  border: 'none',
  padding: '7px 14px',
  borderRadius: 4,
  cursor: 'pointer',
  fontSize: 13,
  fontWeight: 600,
};

const authBtnSecondary: React.CSSProperties = {
  background: 'var(--panel-bg)',
  color: '#5a3a00',
  border: '1px solid #d4a01a',
  padding: '7px 14px',
  borderRadius: 4,
  cursor: 'pointer',
  fontSize: 13,
};

const statCard: React.CSSProperties = {
  border: '1px solid var(--panel-border)',
  borderRadius: 8,
  padding: '10px 12px',
  background: 'var(--panel-bg)',
};

const tabBtn: React.CSSProperties = {
  border: '1px solid var(--panel-border)',
  background: 'var(--panel-bg)',
  color: 'var(--text-muted)',
  borderRadius: 14,
  padding: '4px 10px',
  fontSize: 12,
  cursor: 'pointer',
};

const activeTabBtn: React.CSSProperties = {
  border: '1px solid #0073e7',
  color: '#005bb5',
  background: '#e8f1fc',
  fontWeight: 600,
};

const reportBody: React.CSSProperties = {
  border: '1px solid var(--panel-border)',
  borderRadius: 8,
  padding: 10,
  background: 'var(--panel-bg)',
};

const reportPre: React.CSSProperties = {
  margin: 0,
  whiteSpace: 'pre-wrap',
  wordBreak: 'break-word',
  maxHeight: 360,
  overflow: 'auto',
  fontSize: 12,
  fontFamily: 'Menlo, Monaco, monospace',
  background: 'var(--code-bg)',
  color: 'var(--text-primary)',
  padding: 10,
  borderRadius: 6,
};

const thStyle: React.CSSProperties = {
  textAlign: 'left',
  fontWeight: 600,
  padding: '8px 10px',
  borderBottom: '1px solid var(--panel-subtle-border)',
};

const tdStyle: React.CSSProperties = {
  padding: '7px 10px',
  borderBottom: '1px solid var(--panel-subtle-border)',
  verticalAlign: 'top',
};

const cardFooter: React.CSSProperties = {
  marginTop: 'auto',
  borderTop: '1px solid var(--panel-subtle-border)',
  paddingTop: 8,
  display: 'flex',
  flexDirection: 'column',
  gap: 8,
};

const commentBox: React.CSSProperties = {
  marginTop: 8,
  minHeight: 46,
  position: 'relative',
};

const commentInput: React.CSSProperties = {
  width: '100%',
  minHeight: 46,
  maxHeight: 46,
  resize: 'none',
  border: '1px solid var(--field-border)',
  borderRadius: 6,
  padding: '6px 8px',
  boxSizing: 'border-box',
  fontSize: 13,
  color: 'var(--text-primary)',
  background: 'var(--field-bg)',
  lineHeight: 1.35,
};

const commentHint: React.CSSProperties = {
  position: 'absolute',
  top: 8,
  left: 9,
  fontSize: 11,
  color: 'var(--text-muted)',
  pointerEvents: 'none',
};

const clearNoteBtn: React.CSSProperties = {
  position: 'absolute',
  top: 4,
  right: 6,
  border: 'none',
  background: 'transparent',
  color: 'var(--text-muted)',
  fontSize: 10,
  cursor: 'pointer',
  textTransform: 'lowercase',
  padding: 0,
  lineHeight: 1,
};

const cardFooterMessageRow: React.CSSProperties = {
  minHeight: 18,
  lineHeight: 1.35,
};

const cardFooterButtonsRow: React.CSSProperties = {
  display: 'flex',
  alignItems: 'center',
  gap: 8,
  flexWrap: 'nowrap',
};

const filterChipBtn: React.CSSProperties = {
  border: '1px solid var(--panel-border)',
  background: 'var(--panel-bg)',
  color: 'var(--text-primary)',
  borderRadius: 14,
  padding: '4px 10px',
  fontSize: 12,
  cursor: 'pointer',
  whiteSpace: 'nowrap',
};

const filterChipBtnActive: React.CSSProperties = {
  border: '1px solid #0073e7',
  background: '#e8f1fc',
  color: '#005bb5',
  fontWeight: 600,
};

const clearChipBtn: React.CSSProperties = {
  border: '1px solid #efb4ad',
  background: '#fff6f5',
  color: '#c0392b',
  borderRadius: 14,
  padding: '4px 10px',
  fontSize: 12,
  cursor: 'pointer',
  whiteSpace: 'nowrap',
};
