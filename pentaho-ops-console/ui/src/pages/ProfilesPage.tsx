import { useEffect, useState } from 'react';
import { useSearchParams, useNavigate } from 'react-router-dom';
import {
  listProfiles,
  listInstances,
  getProfile,
  createProfile,
  updateProfile,
  duplicateProfile,
  renameProfile,
  deleteProfile,
} from '../api';
import type { ProfileSummary, InstanceSummary, Profile } from '../api';

export default function ProfilesPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const navigate = useNavigate();
  const [profiles, setProfiles] = useState<ProfileSummary[]>([]);
  const [instances, setInstances] = useState<InstanceSummary[]>([]);
  const [profilesLoading, setProfilesLoading] = useState(true);
  const [profilesLoadError, setProfilesLoadError] = useState('');
  const [selected, setSelected] = useState<Profile | null>(null);
  const [editRaw, setEditRaw] = useState('');
  const [saving, setSaving] = useState(false);
  const [dirty, setDirty] = useState(false);
  const [error, setError] = useState('');
  const [successMsg, setSuccessMsg] = useState('');

  // Filters
  const [filterText, setFilterText] = useState('');
  const [sortKey, setSortKey] = useState<'name' | 'version' | 'state'>('name');

  // Create dialog
  const [showCreate, setShowCreate] = useState(false);
  const [newName, setNewName] = useState('');
  const [newRaw, setNewRaw] = useState(DEFAULT_ENV_TEMPLATE);

  // Duplicate dialog
  const [showDuplicate, setShowDuplicate] = useState(false);
  const [dupName, setDupName] = useState('');

  // Rename dialog
  const [showRename, setShowRename] = useState(false);
  const [renameName, setRenameName] = useState('');

  // Delete confirmation
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);

  function flash(msg: string) {
    setSuccessMsg(msg);
    setTimeout(() => setSuccessMsg(''), 3000);
  }

  async function refresh(options?: { showLoading?: boolean }) {
    const showLoading = options?.showLoading ?? false;
    if (showLoading) setProfilesLoading(true);

    try {
      const [p, i] = await Promise.all([listProfiles(), listInstances()]);
      setProfiles(p);
      setInstances(i);
      setProfilesLoadError('');
    } catch (e: unknown) {
      const message = e instanceof Error ? e.message : String(e);
      console.error('Failed to load profiles page list data', e);
      setProfilesLoadError(message || 'Could not load profiles.');
    } finally {
      if (showLoading) setProfilesLoading(false);
    }
  }

  useEffect(() => {
    async function init() {
      await refresh({ showLoading: true });
      const selectName = searchParams.get('select');
      if (selectName) {
        await select(selectName);
        setSearchParams({}, { replace: true });
      }
    }
    void init();
  }, []);

  async function select(name: string) {
    try {
      const p = await getProfile(name);
      setSelected(p);
      setEditRaw(p.raw);
      setDirty(false);
      setError('');
    } catch (e: unknown) {
      setError(String(e));
    }
  }

  async function save() {
    if (!selected) return;
    setSaving(true);
    setError('');
    try {
      const p = await updateProfile(selected.name, editRaw);
      setSelected(p);
      setEditRaw(p.raw);
      setDirty(false);
      await refresh();
      flash('Profile saved');
    } catch (e: unknown) {
      setError(String(e));
    } finally {
      setSaving(false);
    }
  }

  async function handleCreate() {
    if (!newName.trim()) return;
    setError('');
    try {
      const p = await createProfile(newName.trim(), newRaw);
      setShowCreate(false);
      setNewName('');
      setNewRaw(DEFAULT_ENV_TEMPLATE);
      await refresh();
      setSelected(p);
      setEditRaw(p.raw);
      setDirty(false);
      flash(`Profile "${p.name}" created`);
    } catch (e: unknown) {
      setError(String(e));
    }
  }

  async function handleDuplicate() {
    if (!selected || !dupName.trim()) return;
    setError('');
    try {
      const p = await duplicateProfile(selected.name, dupName.trim());
      setShowDuplicate(false);
      setDupName('');
      await refresh();
      setSelected(p);
      setEditRaw(p.raw);
      setDirty(false);
      flash(`Profile duplicated as "${p.name}"`);
    } catch (e: unknown) {
      setError(String(e));
    }
  }

  async function handleRename() {
    if (!selected || !renameName.trim()) return;
    setError('');
    try {
      const p = await renameProfile(selected.name, renameName.trim());
      setShowRename(false);
      setRenameName('');
      await refresh();
      setSelected(p);
      setEditRaw(p.raw);
      setDirty(false);
      flash(`Profile renamed to "${p.name}"`);
    } catch (e: unknown) {
      setError(String(e));
    }
  }

  async function handleDelete() {
    if (!selected) return;
    setError('');
    try {
      await deleteProfile(selected.name);
      setShowDeleteConfirm(false);
      setSelected(null);
      setEditRaw('');
      setDirty(false);
      await refresh();
      flash('Profile deleted');
    } catch (e: unknown) {
      setError(String(e));
    }
  }

  // Count instances for a profile
  function instanceCount(profileName: string) {
    return instances.filter((i) => i.name === profileName).length;
  }

  const selectedInstances = selected
    ? (selected.instances?.length ? selected.instances : instances.filter((i) => i.name === selected.name))
    : [];

  // Filter + sort profiles
  const filteredProfiles = profiles
    .filter((p) => {
      if (!filterText) return true;
      const q = filterText.toLowerCase();
      return (
        p.name.toLowerCase().includes(q) ||
        p.pentaho_version.toLowerCase().includes(q) ||
        p.environment.toLowerCase().includes(q) ||
        p.instance_ip.toLowerCase().includes(q)
      );
    })
    .sort((a, b) => {
      if (sortKey === 'version') return a.pentaho_version.localeCompare(b.pentaho_version);
      if (sortKey === 'state') return (b.has_state ? 1 : 0) - (a.has_state ? 1 : 0);
      return a.name.localeCompare(b.name);
    });

  return (
    <div>
      <h2 style={{ margin: '0 0 4px' }}>Server Profiles</h2>
      <p style={{ color: '#8e9eab', margin: '0 0 16px', fontSize: 13 }}>
        Profiles define how a server is configured. Instances are the running servers created from them.
      </p>

      {error && (
        <div style={errorBanner}>
          {error}
          <span onClick={() => setError('')} style={{ cursor: 'pointer', marginLeft: 8 }} title="Dismiss">✕</span>
        </div>
      )}
      {successMsg && <div style={successBanner}>{successMsg}</div>}

      {profilesLoading && (
        <div style={loadingBanner}>Loading profiles and instances...</div>
      )}

      {profilesLoadError && (
        <div style={loadErrorBanner}>
          <span>Could not load profiles list: {profilesLoadError}</span>
          <button onClick={() => void refresh({ showLoading: true })} style={retryBtn} title="Retry loading profiles">
            Retry
          </button>
        </div>
      )}

      {/* ── Toolbar ──────────────────────────────────────────────────── */}
      <div style={{ display: 'flex', gap: 10, alignItems: 'center', marginBottom: 14 }}>
        <input
          value={filterText}
          onChange={(e) => setFilterText(e.target.value)}
          placeholder="Filter profiles…"
          style={searchInput}
        />
        <select value={sortKey} onChange={(e) => setSortKey(e.target.value as typeof sortKey)} style={sortSelect}>
          <option value="name">Sort: Name</option>
          <option value="version">Sort: Version</option>
          <option value="state">Sort: Running first</option>
        </select>
        <button onClick={() => setShowCreate(true)} style={primaryBtn} title="Create new profile">
          + New Profile
        </button>
        <button onClick={() => void refresh({ showLoading: true })} style={secondaryBtn} title="Refresh">⟳</button>
      </div>

      <div style={{ display: 'flex', gap: 24 }}>
          {/* Profile list */}
          <div style={{ minWidth: 300, maxWidth: 340 }}>
            {filteredProfiles.map((p) => {
              const iCount = instanceCount(p.name);
              return (
                <div
                  key={p.name}
                  onClick={() => select(p.name)}
                  style={{
                    ...cardStyle,
                    border: selected?.name === p.name ? '2px solid #0073e7' : '2px solid transparent',
                    cursor: 'pointer',
                  }}
                >
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <div style={{ fontWeight: 600, fontSize: 14 }}>{p.name}</div>
                    {iCount > 0 && (
                      <span
                        onClick={(e) => { e.stopPropagation(); navigate(`/?profile=${encodeURIComponent(p.name)}`); }}
                        style={instanceLink}
                        title={`${iCount} instance(s) — click to view`}
                      >
                        {iCount} instance{iCount > 1 ? 's' : ''}
                      </span>
                    )}
                  </div>
                  <div style={{ fontSize: 12, color: '#888', marginTop: 2 }}>
                    {p.pentaho_version && <span>v{p.pentaho_version}</span>}
                    {p.instance_type && <span> · {p.instance_type}</span>}
                    {p.environment && <span> · {p.environment}</span>}
                  </div>
                  {(() => {
                    const profileInstances = instances.filter((i) => i.name === p.name);
                    if (profileInstances.length === 0) {
                      return <div style={{ fontSize: 12, color: '#bbb', marginTop: 4 }}>○ no instance</div>;
                    }
                    return profileInstances.map((inst) => (
                      <div key={inst.state_file} style={{ fontSize: 12, marginTop: 4 }}>
                        <span style={{ color: inst.instance_state === 'running' ? '#27ae60' : '#e67e22' }}>
                          {inst.instance_state === 'running' ? '●' : '○'} {inst.instance_ip || 'no IP'}
                        </span>
                        <span style={{ color: '#888', marginLeft: 6 }}>{inst.instance_state || 'unknown'}</span>
                      </div>
                    ));
                  })()}
                </div>
              );
            })}
            {filteredProfiles.length === 0 && (
              <div style={{ color: '#999', padding: 12 }}>
                {profilesLoading
                  ? 'Loading profiles...'
                  : filterText
                    ? 'No profiles match filter.'
                    : (profilesLoadError ? 'Could not load profiles. Try Retry above.' : 'No profiles found.')}
              </div>
            )}
          </div>

          {/* Detail panel */}
          {selected && (
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 12 }}>
                <h3 style={{ margin: 0 }}>{selected.name}</h3>
                <button
                  onClick={() => {
                    setRenameName(selected.name);
                    setShowRename(true);
                  }}
                  style={secondaryBtn}
                  title="Rename this profile and related files"
                >
                  Rename
                </button>
                <button
                  onClick={() => {
                    setDupName(selected.name + '-copy');
                    setShowDuplicate(true);
                  }}
                  style={secondaryBtn}
                  title="Duplicate this profile"
                >
                  Duplicate
                </button>
                <button
                  onClick={() => setShowDeleteConfirm(true)}
                  style={dangerBtn}
                  title="Delete this profile"
                >
                  Delete
                </button>
              </div>

              {/* Config variables */}
              <details open style={{ marginBottom: 16 }}>
                <summary style={{ cursor: 'pointer', fontWeight: 600, marginBottom: 8 }}>
                  Configuration ({Object.keys(selected.config).length} variables)
                </summary>
                <div style={{ maxHeight: 300, overflow: 'auto' }}>
                  <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                    <thead>
                      <tr>
                        <th style={thStyle}>Variable</th>
                        <th style={thStyle}>Value</th>
                      </tr>
                    </thead>
                    <tbody>
                      {Object.entries(selected.config).map(([k, v]) => (
                        <tr key={k}>
                          <td style={{ ...tdStyle, fontFamily: 'Menlo, Monaco, monospace', fontSize: 12 }}>{k}</td>
                          <td style={{ ...tdStyle, fontFamily: 'Menlo, Monaco, monospace', fontSize: 12, wordBreak: 'break-all' }}>{v}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </details>

              {/* Raw editor */}
              <div style={{ marginBottom: 8, display: 'flex', alignItems: 'center', gap: 10 }}>
                <span style={{ fontWeight: 600 }}>Edit .env</span>
                {dirty && <span style={{ fontSize: 12, color: '#e67e22' }}>• unsaved changes</span>}
              </div>
              <textarea
                value={editRaw}
                onChange={(e) => {
                  setEditRaw(e.target.value);
                  setDirty(true);
                }}
                style={textareaStyle}
                rows={18}
                spellCheck={false}
              />
              <div style={{ display: 'flex', gap: 8, marginTop: 8 }}>
                <button onClick={save} disabled={saving || !dirty} style={primaryBtn} title="Save changes to the .env profile file">
                  {saving ? 'Saving…' : 'Save Changes'}
                </button>
                {dirty && (
                  <button
                    onClick={() => {
                      setEditRaw(selected.raw);
                      setDirty(false);
                    }}
                    style={secondaryBtn}
                    title="Revert to the last saved version"
                  >
                    Discard
                  </button>
                )}
              </div>

              <div style={runtimeSectionStyle}>
                <div style={runtimeHeaderStyle}>
                  <div>
                    <div style={{ fontWeight: 600 }}>Runtime Instances</div>
                    <div style={{ fontSize: 12, color: '#7b8a99', marginTop: 2 }}>
                      State files linked to this profile. These cards summarize runtime metadata; the full fleet view lives on Instances.
                    </div>
                  </div>
                  <button
                    onClick={() => navigate(`/?profile=${encodeURIComponent(selected.name)}`)}
                    style={secondaryBtn}
                    title="Open the Instances page filtered to this profile"
                  >
                    View in Instances
                  </button>
                </div>

                {selectedInstances.length > 0 ? (
                  <div style={runtimeGridStyle}>
                    {selectedInstances.map((inst) => {
                      const serverLabel = inst.server_type === 'pdc'
                        ? 'PDC Server'
                        : inst.server_type === 'ops-console'
                          ? 'Ops Console'
                          : inst.server_type === 'pentaho'
                            ? 'Pentaho Server'
                            : 'Unknown Server';
                      const isRunning = inst.instance_state === 'running';
                      return (
                        <div key={inst.state_file || inst.instance_id} style={runtimeCardStyle}>
                          <div style={runtimeCardTopStyle}>
                            <div style={{ minWidth: 0 }}>
                              <div style={{ fontWeight: 600, fontSize: 13, color: '#1f2d3d' }}>
                                {inst.instance_ip || 'No IP address'}
                              </div>
                              <div style={{ color: '#7b8a99', fontSize: 11, marginTop: 2 }}>
                                {inst.state_file || 'untracked runtime'}
                              </div>
                            </div>
                            <span style={{
                              ...runtimeBadgeStyle,
                              background: isRunning ? '#e8f8f0' : '#fef3e2',
                              color: isRunning ? '#1e8449' : '#b45f06',
                            }}>
                              {isRunning ? '● running' : `○ ${inst.instance_state || 'unknown'}`}
                            </span>
                          </div>

                          <div style={runtimeFieldsStyle}>
                            <div style={fieldLabelMini}>Type</div>
                            <div style={fieldValueMini}>{serverLabel}</div>
                            <div style={fieldLabelMini}>Instance ID</div>
                            <div style={fieldValueMini}>{inst.instance_id || '—'}</div>
                            <div style={fieldLabelMini}>Phase</div>
                            <div style={fieldValueMini}>{inst.deploy_phase || '—'}</div>
                            <div style={fieldLabelMini}>Created</div>
                            <div style={fieldValueMini}>{inst.created_date ? new Date(inst.created_date).toLocaleDateString() : '—'}</div>
                            <div style={fieldLabelMini}>Database</div>
                            <div style={fieldValueMini}>{inst.db_type || '—'}</div>
                            <div style={fieldLabelMini}>Instance</div>
                            <div style={fieldValueMini}>{inst.instance_type || '—'}</div>
                          </div>

                          <div style={runtimeActionsStyle}>
                            {inst.server_url && (
                              <a href={inst.server_url} target="_blank" rel="noopener noreferrer" style={runtimeLinkStyle}>
                                Open server ↗
                              </a>
                            )}
                            <button
                              onClick={() => navigate(`/?profile=${encodeURIComponent(selected.name)}`)}
                              style={runtimeTextButtonStyle}
                              title="Open this profile on the Instances page"
                            >
                              Instances view
                            </button>
                          </div>
                        </div>
                      );
                    })}
                  </div>
                ) : (
                  <div style={emptyRuntimeStyle}>
                    No runtime state files are currently associated with this profile.
                  </div>
                )}
              </div>
            </div>
          )}
        </div>

      {/* ── Create dialog ────────────────────────────────────────────── */}
      {showCreate && (
        <div style={overlay}>
          <div style={dialog}>
            <h3 style={{ marginTop: 0 }}>Create New Profile</h3>
            <label style={labelStyle}>
              Profile Name
              <input
                value={newName}
                onChange={(e) => setNewName(e.target.value)}
                placeholder="e.g. pentaho-my-server"
                style={inputStyle}
                autoFocus
              />
            </label>
            <label style={labelStyle}>
              .env Content
              <textarea
                value={newRaw}
                onChange={(e) => setNewRaw(e.target.value)}
                style={textareaStyle}
                rows={14}
                spellCheck={false}
              />
            </label>
            <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
              <button onClick={handleCreate} style={primaryBtn} disabled={!newName.trim()} title="Create a new .env profile">
                Create
              </button>
              <button onClick={() => setShowCreate(false)} style={secondaryBtn} title="Cancel without creating">
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── Duplicate dialog ─────────────────────────────────────────── */}
      {showDuplicate && selected && (
        <div style={overlay}>
          <div style={{ ...dialog, maxWidth: 420 }}>
            <h3 style={{ marginTop: 0 }}>Duplicate Profile</h3>
            <p style={{ color: '#666', fontSize: 14 }}>
              Create a copy of <strong>{selected.name}</strong> with a new name.
            </p>
            <label style={labelStyle}>
              New Profile Name
              <input
                value={dupName}
                onChange={(e) => setDupName(e.target.value)}
                style={inputStyle}
                autoFocus
              />
            </label>
            <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
              <button onClick={handleDuplicate} style={primaryBtn} disabled={!dupName.trim()} title="Create a copy of this profile">
                Duplicate
              </button>
              <button onClick={() => setShowDuplicate(false)} style={secondaryBtn} title="Cancel without duplicating">
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── Rename dialog ───────────────────────────────────────────── */}
      {showRename && selected && (
        <div style={overlay}>
          <div style={{ ...dialog, maxWidth: 460 }}>
            <h3 style={{ marginTop: 0 }}>Rename Profile</h3>
            <p style={{ color: '#666', fontSize: 14 }}>
              Rename <strong>{selected.name}</strong>. This also renames its .env file and related runtime state files.
            </p>
            <label style={labelStyle}>
              New Profile Name
              <input
                value={renameName}
                onChange={(e) => setRenameName(e.target.value)}
                style={inputStyle}
                autoFocus
              />
            </label>
            <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
              <button onClick={handleRename} style={primaryBtn} disabled={!renameName.trim()} title="Rename this profile">
                Rename
              </button>
              <button onClick={() => setShowRename(false)} style={secondaryBtn} title="Cancel without renaming">
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── Delete confirmation ──────────────────────────────────────── */}
      {showDeleteConfirm && selected && (
        <div style={overlay}>
          <div style={{ ...dialog, maxWidth: 420 }}>
            <h3 style={{ marginTop: 0, color: '#c0392b' }}>Delete Profile</h3>
            <p>
              Delete <strong>{selected.name}</strong>? This will remove the .env file
              and any associated runtime state. This cannot be undone.
            </p>
            <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
              <button onClick={handleDelete} style={dangerBtn} title="Permanently delete this profile">
                Delete
              </button>
              <button onClick={() => setShowDeleteConfirm(false)} style={secondaryBtn} title="Cancel without deleting">
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}
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

const cardStyle: React.CSSProperties = {
  background: 'var(--panel-bg)',
  border: '1px solid var(--panel-border)',
  padding: 12,
  borderRadius: 6,
  marginBottom: 8,
  boxShadow: 'var(--panel-shadow)',
};

const instanceLink: React.CSSProperties = {
  fontSize: 11,
  color: '#0073e7',
  cursor: 'pointer',
  padding: '2px 8px',
  borderRadius: 10,
  background: '#e8f1fc',
};

const thStyle: React.CSSProperties = {
  textAlign: 'left',
  padding: '6px 10px',
  background: 'var(--panel-header-bg)',
  fontSize: 13,
  position: 'sticky',
  top: 0,
};

const tdStyle: React.CSSProperties = {
  padding: '5px 10px',
  borderBottom: '1px solid #eee',
  fontSize: 13,
};

const textareaStyle: React.CSSProperties = {
  width: '100%',
  fontFamily: 'Menlo, Monaco, monospace',
  fontSize: 12,
  lineHeight: '1.5',
  padding: 10,
  borderRadius: 4,
  border: '1px solid var(--field-border)',
  boxSizing: 'border-box',
  resize: 'vertical',
  background: 'var(--field-bg)',
  color: 'var(--text-primary)',
};

const inputStyle: React.CSSProperties = {
  display: 'block',
  width: '100%',
  padding: '8px 10px',
  borderRadius: 4,
  border: '1px solid var(--field-border)',
  fontSize: 14,
  boxSizing: 'border-box',
  marginTop: 4,
  background: 'var(--field-bg)',
  color: 'var(--text-primary)',
};

const labelStyle: React.CSSProperties = {
  display: 'block',
  marginBottom: 12,
  fontSize: 14,
  fontWeight: 500,
};

const primaryBtn: React.CSSProperties = {
  background: '#0073e7',
  color: '#fff',
  border: 'none',
  padding: '8px 20px',
  borderRadius: 4,
  cursor: 'pointer',
  fontSize: 14,
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

const dangerBtn: React.CSSProperties = {
  background: '#e74c3c',
  color: '#fff',
  border: 'none',
  padding: '8px 16px',
  borderRadius: 4,
  cursor: 'pointer',
  fontSize: 14,
};

const runtimeSectionStyle: React.CSSProperties = {
  marginTop: 18,
  padding: 14,
  borderRadius: 6,
  border: '1px solid var(--panel-subtle-border)',
  background: 'var(--panel-subtle-bg)',
};

const runtimeHeaderStyle: React.CSSProperties = {
  display: 'flex',
  justifyContent: 'space-between',
  alignItems: 'flex-start',
  gap: 12,
  marginBottom: 12,
};

const runtimeGridStyle: React.CSSProperties = {
  display: 'grid',
  gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))',
  gap: 10,
};

const runtimeCardStyle: React.CSSProperties = {
  background: 'var(--panel-bg)',
  borderRadius: 6,
  border: '1px solid var(--panel-border)',
  borderLeft: '4px solid #7b8a99',
  padding: 12,
  boxShadow: 'var(--panel-shadow)',
};

const runtimeCardTopStyle: React.CSSProperties = {
  display: 'flex',
  justifyContent: 'space-between',
  alignItems: 'flex-start',
  gap: 10,
  marginBottom: 10,
};

const runtimeBadgeStyle: React.CSSProperties = {
  fontSize: 11,
  borderRadius: 999,
  padding: '3px 8px',
  fontWeight: 600,
  whiteSpace: 'nowrap',
};

const runtimeFieldsStyle: React.CSSProperties = {
  display: 'grid',
  gridTemplateColumns: '92px 1fr',
  gap: '4px 10px',
  fontSize: 12,
};

const fieldLabelMini: React.CSSProperties = {
  color: 'var(--text-muted)',
};

const fieldValueMini: React.CSSProperties = {
  color: 'var(--text-primary)',
  minWidth: 0,
  overflowWrap: 'anywhere',
};

const runtimeActionsStyle: React.CSSProperties = {
  display: 'flex',
  justifyContent: 'space-between',
  alignItems: 'center',
  gap: 10,
  marginTop: 10,
  paddingTop: 9,
  borderTop: '1px solid #edf1f5',
};

const runtimeLinkStyle: React.CSSProperties = {
  color: '#005bb5',
  textDecoration: 'none',
  fontSize: 12,
  overflowWrap: 'anywhere',
};

const runtimeTextButtonStyle: React.CSSProperties = {
  background: 'transparent',
  border: 'none',
  color: '#5a6c7d',
  cursor: 'pointer',
  fontSize: 12,
  padding: 0,
  whiteSpace: 'nowrap',
};

const emptyRuntimeStyle: React.CSSProperties = {
  border: '1px dashed var(--placeholder-border)',
  borderRadius: 6,
  padding: 14,
  color: 'var(--text-muted)',
  fontSize: 13,
  background: 'var(--placeholder-bg)',
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

const successBanner: React.CSSProperties = {
  background: '#e8f8f0',
  color: '#27ae60',
  padding: '8px 14px',
  borderRadius: 4,
  marginBottom: 12,
  fontSize: 13,
};


const loadingBanner: React.CSSProperties = {
  background: '#eaf2ff',
  color: '#1f4c8f',
  border: '1px solid #c9dcfb',
  padding: '8px 12px',
  borderRadius: 6,
  marginBottom: 12,
  fontSize: 13,
  fontWeight: 600,
};

const loadErrorBanner: React.CSSProperties = {
  background: '#fff3f2',
  color: '#a12a1f',
  border: '1px solid #f1b8b2',
  padding: '8px 12px',
  borderRadius: 6,
  marginBottom: 12,
  fontSize: 13,
  fontWeight: 600,
  display: 'flex',
  justifyContent: 'space-between',
  alignItems: 'center',
  gap: 10,
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
const DEFAULT_ENV_TEMPLATE = `#!/usr/bin/env bash
# ─── Pentaho Server Profile ──────────────────────────────────────────────────
# Copy and customize this template for a new deployment.

# ── Identity ──────────────────────────────────────────────────────────────────
export PROJECT_NAME="my-pentaho-server"
export INSTANCE_NAME="\${PROJECT_NAME}"
export ENVIRONMENT="dev"

# ── AWS / EC2 ─────────────────────────────────────────────────────────────────
export AWS_PROFILE="khaas"
export AWS_REGION="us-east-1"
export INSTANCE_TYPE="t3.large"
export AMI_ID="ami-0a0e5d9c7acc336f1"
export KEY_NAME="pentaho+_se_keypair"
export KEY_FILE="$HOME/.ssh/pentaho+_se_keypair.pem"
export SECURITY_GROUP_ID=""
export SUBNET_ID=""
export EBS_SIZE="100"

# ── Pentaho ───────────────────────────────────────────────────────────────────
export PENTAHO_VERSION="11.1.0.0-198"
export PORT="80"
export PENTAHO_ADMIN_USER="admin"
export PENTAHO_ADMIN_PASSWORD="password"

# ── Container Resources ──────────────────────────────────────────────────────
export PENTAHO_CPU_LIMIT="2.0"
export PENTAHO_MEM_LIMIT="6g"
export DB_CPU_LIMIT="0.5"
export DB_MEM_LIMIT="1g"
export JVM_MIN_MEM="1024m"
export JVM_MAX_MEM="4096m"
`;
