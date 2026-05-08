import { useEffect, useMemo, useState } from 'react';
import { listJobs, cancelJob, bulkDeleteJobs } from '../api';
import type { Job } from '../api';
import Terminal from '../components/Terminal';
import CancelJobDialog from '../components/CancelJobDialog';

const STATUS_OPTIONS = ['all', 'running', 'completed', 'failed', 'cancelled'] as const;
type SortKey = 'id' | 'script' | 'status' | 'exit' | 'lines' | 'started';

function scriptName(j: Job): string {
  return j.script.split('/').pop() || j.script;
}

function formatCt(ts: number | null): string {
  if (!ts) return '—';
  const d = new Date(ts * 1000);
  if (Number.isNaN(d.getTime())) return '—';
  return `${new Intl.DateTimeFormat('en-US', {
    timeZone: 'America/Chicago',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  }).format(d).replace(',', '')} CT`;
}

export default function JobsPage() {
  const [jobs, setJobs] = useState<Job[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [idFilter, setIdFilter] = useState('');
  const [scriptFilter, setScriptFilter] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [exitFilter, setExitFilter] = useState('');
  const [linesFilter, setLinesFilter] = useState('');
  const [startedFilter, setStartedFilter] = useState('');
  const [sortKey, setSortKey] = useState<SortKey>('started');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('desc');
  const [checked, setChecked] = useState<Set<string>>(new Set());
  const [cancelTarget, setCancelTarget] = useState<Job | null>(null);
  const [cancelingId, setCancelingId] = useState<string | null>(null);
  const [cancelError, setCancelError] = useState<string | null>(null);

  useEffect(() => {
    load();
    const interval = setInterval(() => {
      void load({ silent: true });
    }, 3000);
    return () => clearInterval(interval);
  }, []);

  async function load(options?: { silent?: boolean }) {
    const silent = options?.silent ?? false;
    if (!silent) setLoading(true);
    if (!silent) setLoadError(null);

    try {
      const data = await listJobs();
      setJobs(data);
      setLoadError(null);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Could not load processes.';
      console.error('Failed to load processes list', error);
      setLoadError(message);
    } finally {
      if (!silent) setLoading(false);
    }
  }

  const filtered = useMemo(() => {
    return jobs.filter((j) => {
      const idText = j.id.toLowerCase();
      const scriptText = scriptName(j).toLowerCase();
      const statusText = j.status.toLowerCase();
      const exitText = j.exit_code == null ? '' : String(j.exit_code);
      const linesText = String(j.output_lines ?? '');
      const startedText = formatCt(j.started_at).toLowerCase();

      if (idFilter.trim() && !idText.includes(idFilter.trim().toLowerCase())) return false;
      if (scriptFilter.trim() && !scriptText.includes(scriptFilter.trim().toLowerCase())) return false;
      if (statusFilter !== 'all' && statusText !== statusFilter) return false;
      if (exitFilter.trim() && !exitText.includes(exitFilter.trim())) return false;
      if (linesFilter.trim() && !linesText.includes(linesFilter.trim())) return false;
      if (startedFilter.trim() && !startedText.includes(startedFilter.trim().toLowerCase())) return false;

      return true;
    });
  }, [jobs, idFilter, scriptFilter, statusFilter, exitFilter, linesFilter, startedFilter]);

  const filteredSorted = useMemo(() => {
    const arr = [...filtered];
    arr.sort((a, b) => {
      let cmp = 0;
      switch (sortKey) {
        case 'id':
          cmp = a.id.localeCompare(b.id);
          break;
        case 'script':
          cmp = scriptName(a).localeCompare(scriptName(b));
          break;
        case 'status':
          cmp = a.status.localeCompare(b.status);
          break;
        case 'exit':
          cmp = (a.exit_code ?? -999999) - (b.exit_code ?? -999999);
          break;
        case 'lines':
          cmp = (a.output_lines ?? 0) - (b.output_lines ?? 0);
          break;
        case 'started':
          cmp = (a.started_at ?? 0) - (b.started_at ?? 0);
          break;
      }
      return sortDir === 'asc' ? cmp : -cmp;
    });
    return arr;
  }, [filtered, sortKey, sortDir]);

  function toggleSort(key: SortKey) {
    if (sortKey === key) {
      setSortDir((d) => (d === 'asc' ? 'desc' : 'asc'));
    } else {
      setSortKey(key);
      setSortDir(key === 'started' ? 'desc' : 'asc');
    }
  }

  function sortMarker(key: SortKey) {
    if (sortKey !== key) return '↕';
    return sortDir === 'asc' ? '▲' : '▼';
  }

  function toggleCheck(id: string) {
    setChecked((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  function toggleAll() {
    if (checked.size === filteredSorted.length) {
      setChecked(new Set());
    } else {
      setChecked(new Set(filteredSorted.map((j) => j.id)));
    }
  }

  async function handleBulkDelete() {
    if (checked.size === 0) return;
    if (!window.confirm(`Delete ${checked.size} selected process(es)? This cannot be undone.`)) return;
    const ids = Array.from(checked);
    await bulkDeleteJobs(ids);
    setChecked(new Set());
    await load();
  }

  async function handleConfirmCancel() {
    if (!cancelTarget) return;
    setCancelingId(cancelTarget.id);
    setCancelError(null);
    try {
      await cancelJob(cancelTarget.id);
      setCancelTarget(null);
      await load();
    } catch (error) {
      setCancelError(error instanceof Error ? error.message : 'Could not cancel the process.');
    } finally {
      setCancelingId(null);
    }
  }

  function statusColor(status: string) {
    switch (status) {
      case 'running': return '#f39c12';
      case 'completed': return '#27ae60';
      case 'failed': return '#e74c3c';
      case 'cancelled': return '#95a5a6';
      default: return '#bdc3c7';
    }
  }

  return (
    <div>
      <h2>Processes</h2>
      <p style={{ color: '#8e9eab', marginBottom: 16, fontSize: 13 }}>
        Every action you run creates a process. Track progress, view output, or clean up completed tasks.
      </p>

      <div style={{ display: 'flex', gap: 12, marginBottom: 12, alignItems: 'center', flexWrap: 'wrap' }}>
        <button
          onClick={() => {
            setIdFilter('');
            setScriptFilter('');
            setStatusFilter('all');
            setExitFilter('');
            setLinesFilter('');
            setStartedFilter('');
          }}
          style={clearBtn}
          title="Clear all column filters"
        >
          Clear Filters
        </button>
        {checked.size > 0 && (
          <button onClick={handleBulkDelete} style={deleteBtn} title="Delete all selected process records">
            Delete {checked.size} selected
          </button>
        )}
      </div>

      {loading && (
        <div style={loadingNotice}>
          Loading processes...
        </div>
      )}

      {loadError && (
        <div style={errorNotice}>
          <span>Could not load process list: {loadError}</span>
          <button onClick={() => void load()} style={retryBtn} title="Retry loading processes">
            Retry
          </button>
        </div>
      )}

      <div style={splitContainer}>
        <div style={listPanel}>
          <div style={panelHeader}>Process List</div>
          <div style={tableWrap}>
            <table style={{ width: '100%', borderCollapse: 'collapse', background: 'var(--panel-bg)', borderRadius: 6 }}>
              <thead>
                <tr>
                  <th style={thStyle}>
                    <input
                      type="checkbox"
                      checked={filteredSorted.length > 0 && checked.size === filteredSorted.length}
                      onChange={toggleAll}
                    />
                  </th>
                  <th style={thStyle}><button onClick={() => toggleSort('id')} style={sortBtn}>ID {sortMarker('id')}</button></th>
                  <th style={thStyle}><button onClick={() => toggleSort('script')} style={sortBtn}>Script {sortMarker('script')}</button></th>
                  <th style={thStyle}><button onClick={() => toggleSort('status')} style={sortBtn}>Status {sortMarker('status')}</button></th>
                  <th style={thStyle}><button onClick={() => toggleSort('exit')} style={sortBtn}>Exit {sortMarker('exit')}</button></th>
                  <th style={thStyle}><button onClick={() => toggleSort('lines')} style={sortBtn}>Lines {sortMarker('lines')}</button></th>
                  <th style={thStyle}><button onClick={() => toggleSort('started')} style={sortBtn}>Started (CT) {sortMarker('started')}</button></th>
                  <th style={thStyle}>Actions</th>
                </tr>
                <tr>
                  <th style={thFilterStyle}></th>
                  <th style={thFilterStyle}><input value={idFilter} onChange={(e) => setIdFilter(e.target.value)} placeholder="Filter" style={columnInput} /></th>
                  <th style={thFilterStyle}><input value={scriptFilter} onChange={(e) => setScriptFilter(e.target.value)} placeholder="Filter" style={columnInput} /></th>
                  <th style={thFilterStyle}>
                    <select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} style={columnSelect}>
                      {STATUS_OPTIONS.map((s) => (
                        <option key={s} value={s}>{s === 'all' ? 'All' : s.charAt(0).toUpperCase() + s.slice(1)}</option>
                      ))}
                    </select>
                  </th>
                  <th style={thFilterStyle}><input value={exitFilter} onChange={(e) => setExitFilter(e.target.value)} placeholder="Filter" style={columnInput} /></th>
                  <th style={thFilterStyle}><input value={linesFilter} onChange={(e) => setLinesFilter(e.target.value)} placeholder="Filter" style={columnInput} /></th>
                  <th style={thFilterStyle}><input value={startedFilter} onChange={(e) => setStartedFilter(e.target.value)} placeholder="MM/DD or time" style={columnInput} /></th>
                  <th style={thFilterStyle}></th>
                </tr>
              </thead>
              <tbody>
                {filteredSorted.map((j) => (
                  <tr
                    key={j.id}
                    style={checked.has(j.id) || selectedId === j.id ? { background: 'var(--panel-selected-bg)' } : undefined}
                  >
                    <td style={tdStyle}>
                      <input
                        type="checkbox"
                        checked={checked.has(j.id)}
                        onChange={() => toggleCheck(j.id)}
                      />
                    </td>
                    <td style={tdStyle}>
                      <code>{j.id}</code>
                    </td>
                    <td style={tdStyle}>{scriptName(j)}</td>
                    <td style={tdStyle}>
                      <span style={{ color: statusColor(j.status), fontWeight: 600 }}>
                        {j.status}
                      </span>
                    </td>
                    <td style={tdStyle}>{j.exit_code ?? '—'}</td>
                    <td style={tdStyle}>{j.output_lines}</td>
                    <td style={tdStyle}>{formatCt(j.started_at)}</td>
                    <td style={tdStyle}>
                      <button onClick={() => setSelectedId(j.id)} style={linkBtn} title="View process output">
                        View
                      </button>
                      {j.status === 'running' && (
                        <button
                          onClick={() => {
                            setCancelTarget(j);
                            setCancelError(null);
                          }}
                          style={{ ...linkBtn, color: '#c0392b' }}
                          title="Review cancellation warning"
                        >
                          Cancel
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
                {filteredSorted.length === 0 && (
                  <tr>
                    <td colSpan={8} style={{ ...tdStyle, textAlign: 'center', color: '#999' }}>
                      {loading && jobs.length === 0
                        ? 'Loading processes...'
                        : jobs.length === 0
                          ? (loadError ? 'Could not load processes. Try Retry above.' : 'No processes yet.')
                          : 'No matching processes.'}
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </div>

        <div style={detailPanel}>
          <div style={panelHeader}>Process Output</div>
          <div style={detailBody}>
            {selectedId ? (
              <Terminal jobId={selectedId} onClose={() => setSelectedId(null)} embedded />
            ) : (
              <div style={placeholderStyle}>Select a process from the list to view output here.</div>
            )}
          </div>
        </div>
      </div>

      <CancelJobDialog
        open={Boolean(cancelTarget)}
        jobId={cancelTarget?.id ?? null}
        canceling={cancelingId === cancelTarget?.id}
        error={cancelError}
        onDismiss={() => {
          setCancelTarget(null);
          setCancelError(null);
        }}
        onConfirm={handleConfirmCancel}
      />
    </div>
  );
}

const clearBtn: React.CSSProperties = {
  background: '#3f5062',
  color: '#fff',
  border: 'none',
  padding: '6px 12px',
  borderRadius: 4,
  cursor: 'pointer',
  fontSize: 13,
};

const deleteBtn: React.CSSProperties = {
  background: '#c0392b',
  color: '#fff',
  border: 'none',
  padding: '6px 14px',
  borderRadius: 4,
  cursor: 'pointer',
  fontSize: 13,
};

const loadingNotice: React.CSSProperties = {
  background: '#eaf2ff',
  border: '1px solid #c9dcfb',
  color: '#1f4c8f',
  padding: '8px 10px',
  borderRadius: 6,
  marginBottom: 10,
  fontSize: 13,
  fontWeight: 600,
};

const errorNotice: React.CSSProperties = {
  background: '#fff3f2',
  border: '1px solid #f1b8b2',
  color: '#a12a1f',
  padding: '8px 10px',
  borderRadius: 6,
  marginBottom: 10,
  display: 'flex',
  justifyContent: 'space-between',
  alignItems: 'center',
  gap: 12,
  fontSize: 13,
  fontWeight: 600,
  flexWrap: 'wrap',
};

const retryBtn: React.CSSProperties = {
  background: '#a12a1f',
  color: '#fff',
  border: 'none',
  borderRadius: 4,
  padding: '4px 10px',
  cursor: 'pointer',
  fontSize: 12,
};

const splitContainer: React.CSSProperties = {
  display: 'grid',
  gridTemplateRows: 'minmax(260px, 54vh) minmax(220px, 34vh)',
  gap: 12,
};

const listPanel: React.CSSProperties = {
  background: 'var(--panel-bg)',
  border: '1px solid var(--panel-border)',
  borderRadius: 8,
  overflow: 'hidden',
  display: 'flex',
  flexDirection: 'column',
};

const detailPanel: React.CSSProperties = {
  background: 'var(--panel-bg)',
  border: '1px solid var(--panel-border)',
  borderRadius: 8,
  overflow: 'hidden',
  display: 'flex',
  flexDirection: 'column',
};

const panelHeader: React.CSSProperties = {
  fontSize: 12,
  fontWeight: 700,
  textTransform: 'uppercase',
  letterSpacing: 0.5,
  color: 'var(--text-muted)',
  background: 'var(--panel-header-bg)',
  padding: '8px 12px',
  borderBottom: '1px solid var(--panel-header-border)',
};

const tableWrap: React.CSSProperties = {
  overflow: 'auto',
  flex: 1,
};

const detailBody: React.CSSProperties = {
  padding: 10,
  flex: 1,
  minHeight: 0,
};

const placeholderStyle: React.CSSProperties = {
  height: '100%',
  minHeight: 120,
  border: '1px dashed var(--placeholder-border)',
  borderRadius: 6,
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  color: 'var(--text-muted)',
  fontSize: 13,
  background: 'var(--placeholder-bg)',
};

const thStyle: React.CSSProperties = {
  textAlign: 'left',
  padding: '8px 12px',
  background: 'var(--panel-header-bg)',
  fontSize: 13,
};

const thFilterStyle: React.CSSProperties = {
  textAlign: 'left',
  padding: '6px 12px',
  background: 'var(--panel-subtle-bg)',
  fontSize: 12,
};

const tdStyle: React.CSSProperties = {
  padding: '8px 12px',
  borderBottom: '1px solid #eee',
  fontSize: 13,
};

const sortBtn: React.CSSProperties = {
  background: 'none',
  border: 'none',
  padding: 0,
  margin: 0,
  fontSize: 13,
  cursor: 'pointer',
  color: '#1f2d3d',
  fontWeight: 600,
};

const columnInput: React.CSSProperties = {
  width: '100%',
  boxSizing: 'border-box',
  padding: '5px 8px',
  borderRadius: 4,
  border: '1px solid var(--field-border)',
  background: 'var(--field-bg)',
  color: 'var(--text-primary)',
  fontSize: 12,
};

const columnSelect: React.CSSProperties = {
  width: '100%',
  boxSizing: 'border-box',
  padding: '5px 8px',
  borderRadius: 4,
  border: '1px solid #d0d7de',
  fontSize: 12,
};

const linkBtn: React.CSSProperties = {
  background: 'none',
  border: 'none',
  color: '#0073e7',
  cursor: 'pointer',
  fontSize: 13,
  marginRight: 8,
  padding: 0,
};
