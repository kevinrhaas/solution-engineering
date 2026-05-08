import { useEffect, useState, useCallback, useRef } from 'react';
import {
  listProfiles,
  listInstances,
  preflight,
  fullDeploy,
  createEc2,
  checkEc2,
  deployPentaho,
  deployPlugins,
  fullDeployPdc,
  deployPdc,
} from '../api';
import type { ProfileSummary, InstanceSummary } from '../api';
import Terminal from '../components/Terminal';
import { PENTAHO_COLOR, PDC_COLOR, PENTAHO_BG, PDC_BG } from '../theme';

type Mode = 'new' | 'existing';

/* Map deploy_phase to a human-readable label */
function phaseLabel(phase: string): string {
  switch (phase) {
    case 'ec2-created':       return 'EC2 Created';
    case 'ec2-checked':       return 'EC2 Verified';
    case 'pentaho-deployed':  return 'Pentaho Deployed';
    case 'plugins-deployed':  return 'Plugins Deployed';
    case 'pdc-deployed':      return 'PDC Deployed';
    default:                  return phase || '—';
  }
}

export default function ProvisionPage() {
  const [mode, setMode] = useState<Mode>('new');
  const [profiles, setProfiles] = useState<ProfileSummary[]>([]);
  const [instances, setInstances] = useState<InstanceSummary[]>([]);
  const [selectedProfile, setSelectedProfile] = useState('');
  const [selectedInstance, setSelectedInstance] = useState('');
  const [jobId, setJobId] = useState<string | null>(null);
  const terminalRef = useRef<HTMLDivElement>(null);

  const refresh = useCallback(() => {
    listProfiles().then((p) => {
      setProfiles(p);
      if (p.length > 0 && !selectedProfile) setSelectedProfile(p[0].name);
    });
    listInstances().then((inst) => {
      setInstances(inst);
      if (inst.length > 0 && !selectedInstance) setSelectedInstance(inst[0].state_file);
    });
  }, [selectedProfile, selectedInstance]);

  useEffect(() => { refresh(); }, []);

  useEffect(() => {
    if (!jobId) return;
    terminalRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }, [jobId]);

  // Auto-switch to "existing" if the selected profile already has a running instance
  const profileHasInstance = profiles.find((p) => p.name === selectedProfile)?.has_state;

  // Derive named refs
  const activeInstance = instances.find((i) => i.state_file === selectedInstance);
  const isPdc = activeInstance
    ? activeInstance.server_type === 'pdc'
    : (profiles.find((p) => p.name === selectedProfile)?.pdc_version ? true : false);

  /* Run an action against either the selected profile or existing instance */
  async function runProfile(action: (p: string) => Promise<{ job_id: string }>, confirmMsg?: string) {
    if (!selectedProfile) return;
    if (confirmMsg && !window.confirm(confirmMsg)) return;
    try {
      setJobId(null);
      const { job_id } = await action(selectedProfile);
      setJobId(job_id);
    } catch (error) {
      window.alert(error instanceof Error ? error.message : 'Failed to start process.');
    }
  }

  async function runInstance(action: (p: string, sf?: string) => Promise<{ job_id: string }>, confirmMsg?: string) {
    if (!activeInstance) return;
    if (confirmMsg && !window.confirm(confirmMsg)) return;
    try {
      setJobId(null);
      const { job_id } = await action(activeInstance.name, activeInstance.state_file);
      setJobId(job_id);
    } catch (error) {
      window.alert(error instanceof Error ? error.message : 'Failed to start process.');
    }
  }

  function handleJobDone() {
    setJobId(null);
    refresh();
  }

  return (
    <div>
      <h2 style={{ margin: '0 0 4px' }}>Provision</h2>
      <p style={{ color: '#8e9eab', margin: '0 0 16px', fontSize: 13 }}>
        Create a new instance from a profile, or run actions against an existing instance
      </p>

      {/* ── Mode toggle ──────────────────────────────────────────────── */}
      <div style={{ display: 'flex', gap: 0, marginBottom: 20 }}>
        <button
          onClick={() => setMode('new')}
          title="Create a brand-new EC2 instance and deploy from scratch"
          style={{
            ...modeTab,
            background: mode === 'new' ? PENTAHO_COLOR : '#fff',
            color: mode === 'new' ? '#fff' : '#5a6c7d',
            borderRight: 'none',
            borderRadius: '6px 0 0 6px',
          }}
        >
          + New Instance
        </button>
        <button
          onClick={() => setMode('existing')}
          title="Run actions against an already-provisioned instance"
          style={{
            ...modeTab,
            background: mode === 'existing' ? PENTAHO_COLOR : '#fff',
            color: mode === 'existing' ? '#fff' : '#5a6c7d',
            borderRadius: '0 6px 6px 0',
          }}
        >
          Existing Instance {instances.length > 0 && <span style={{
            background: mode === 'existing' ? 'rgba(255,255,255,0.25)' : '#e8ecef',
            borderRadius: 10, padding: '1px 7px', fontSize: 11, marginLeft: 4,
          }}>{instances.length}</span>}
        </button>
      </div>

      {/* ════════════════════════════════════════════════════════════════ */}
      {/* NEW INSTANCE MODE                                               */}
      {/* ════════════════════════════════════════════════════════════════ */}
      {mode === 'new' && (
        <>
          <div style={{ marginBottom: 16 }}>
            <label style={fieldLabel}>Profile</label>
            <select
              value={selectedProfile}
              onChange={(e) => setSelectedProfile(e.target.value)}
              style={selectStyle}
            >
              {profiles.map((p) => (
                <option key={p.name} value={p.name}>{p.name}</option>
              ))}
            </select>
          </div>

          {/* Warning if profile already has instance */}
          {profileHasInstance && (() => {
            const p = profiles.find((pr) => pr.name === selectedProfile)!;
            return (
              <div style={{
                background: '#fff8e1', border: '1px solid #ffe082', borderRadius: 8,
                padding: '10px 16px', marginBottom: 16, fontSize: 13,
              }}>
                <b>⚠ This profile already has an active instance</b> ({p.instance_ip} — {p.instance_state}).
                Creating a new one will launch an <b>additional</b> EC2 instance, it will NOT overwrite the existing one.
                To work with the existing instance, switch to <button
                  onClick={() => {
                    setMode('existing');
                    const match = instances.find((i) => i.name === selectedProfile);
                    if (match) setSelectedInstance(match.state_file);
                  }}
                  style={{ background: 'none', border: 'none', color: PENTAHO_COLOR, cursor: 'pointer', fontWeight: 600, textDecoration: 'underline', padding: 0, fontSize: 13 }}
                >Existing Instance</button>.
              </div>
            );
          })()}

          {/* Pentaho Server */}
          <div style={{ ...card, border: `2px solid ${PENTAHO_COLOR}` }}>
            <div style={{ ...cardHeader, color: PENTAHO_COLOR }}>Pentaho Server</div>
            <p style={cardDesc}>Creates a <b>new</b> EC2 instance and deploys Pentaho BI Server end-to-end.</p>
            <div style={cardBody}>
              <button onClick={() => runProfile(preflight)} style={{ ...btn, background: '#16a085' }} title="Validate env config, AWS credentials, JFrog access, and SSH keys before deploying">
                <span style={iconCircle}>✓</span> Preflight Check
              </button>
              <button onClick={() => runProfile(fullDeploy, 'This will create a NEW EC2 instance and deploy Pentaho end-to-end. Continue?')} style={{ ...btn, background: PENTAHO_COLOR, padding: '11px 28px', fontSize: 14 }} title="Create EC2 + deploy Pentaho + install plugins in one step">
                <span style={{ ...iconCircle, width: 24, height: 24, fontSize: 14 }}>▲</span> Full Deploy
              </button>
              <span style={{ fontSize: 12, color: '#8e9eab', alignSelf: 'center' }}>
                Creates EC2 + deploys steps 1 → 4
              </span>
            </div>
            <div style={stepSection}>
              <div style={stepSectionLabel}>Individual Steps</div>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
                <button onClick={() => runProfile(createEc2, 'This will create a NEW EC2 instance (AWS charges apply). Continue?')} style={stepBtn} title="Launch a new EC2 instance with Docker pre-installed">
                  <span style={stepNum}>1</span> Create Instance
                </button>
                <button onClick={() => runProfile(checkEc2)} style={stepBtn} title="Verify the EC2 instance is running and SSH-ready">
                  <span style={stepNum}>2</span> Check Instance
                </button>
                <button onClick={() => runProfile(deployPentaho)} style={stepBtn} title="Download and deploy Pentaho BI Server to the instance">
                  <span style={stepNum}>3</span> Deploy Pentaho
                </button>
                <button onClick={() => runProfile(deployPlugins)} style={stepBtn} title="Install all configured plugins into Pentaho">
                  <span style={stepNum}>4</span> Deploy Plugins
                </button>
              </div>
            </div>
          </div>

          {/* PDC */}
          <div style={{ ...card, border: `2px solid ${PDC_COLOR}` }}>
            <div style={{ ...cardHeader, color: PDC_COLOR }}>Pentaho Data Catalog</div>
            <p style={cardDesc}>Creates a <b>new</b> EC2 instance and deploys Pentaho Data Catalog end-to-end.</p>
            <div style={cardBody}>
              <button onClick={() => runProfile(preflight)} style={{ ...btn, background: '#16a085' }} title="Validate env config, AWS credentials, JFrog access, and SSH keys before deploying">
                <span style={iconCircle}>✓</span> Preflight Check
              </button>
              <button onClick={() => runProfile(fullDeployPdc, 'This will create a NEW EC2 instance and deploy PDC end-to-end. Continue?')} style={{ ...btn, background: PDC_COLOR, padding: '11px 28px', fontSize: 14 }} title="Create EC2 + deploy Pentaho Data Catalog in one step">
                <span style={{ ...iconCircle, width: 24, height: 24, fontSize: 14 }}>▲</span> Full Deploy PDC
              </button>
              <span style={{ fontSize: 12, color: '#8e9eab', alignSelf: 'center' }}>
                Creates EC2 + deploys steps 1 → 3
              </span>
            </div>
            <div style={stepSection}>
              <div style={stepSectionLabel}>Individual Steps</div>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
                <button onClick={() => runProfile(createEc2, 'This will create a NEW EC2 instance (AWS charges apply). Continue?')} style={stepBtn} title="Launch a new EC2 instance with Docker pre-installed">
                  <span style={{ ...stepNum, background: PDC_COLOR }}>1</span> Create Instance
                </button>
                <button onClick={() => runProfile(checkEc2)} style={stepBtn} title="Verify the EC2 instance is running and SSH-ready">
                  <span style={{ ...stepNum, background: PDC_COLOR }}>2</span> Check Instance
                </button>
                <button onClick={() => runProfile(deployPdc)} style={stepBtn} title="Download and deploy Pentaho Data Catalog to the instance">
                  <span style={{ ...stepNum, background: PDC_COLOR }}>3</span> Deploy PDC
                </button>
              </div>
            </div>
          </div>
        </>
      )}

      {/* ════════════════════════════════════════════════════════════════ */}
      {/* EXISTING INSTANCE MODE                                          */}
      {/* ════════════════════════════════════════════════════════════════ */}
      {mode === 'existing' && (
        <>
          {instances.length === 0 ? (
            <div style={instancePanel}>
              <span style={{ fontSize: 13, color: '#8e9eab' }}>
                No instances found. Use <button onClick={() => setMode('new')} style={{ background: 'none', border: 'none', color: PENTAHO_COLOR, cursor: 'pointer', fontWeight: 600, textDecoration: 'underline', padding: 0, fontSize: 13 }}>New Instance</button> to create one.
              </span>
            </div>
          ) : (
            <>
              <div style={{ marginBottom: 16 }}>
                <label style={fieldLabel}>Instance</label>
                <select
                  value={selectedInstance}
                  onChange={(e) => setSelectedInstance(e.target.value)}
                  style={{ ...selectStyle, maxWidth: 500 }}
                >
                  {instances.map((inst) => (
                    <option key={inst.state_file} value={inst.state_file}>
                      {inst.instance_ip || '—'} — {inst.environment || inst.name} ({inst.instance_state || 'unknown'})
                    </option>
                  ))}
                </select>
              </div>

              {/* Instance detail panel */}
              {activeInstance && (
                <div style={instancePanel}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6 }}>
                    <span style={{
                      ...statusDot,
                      background: activeInstance.instance_state === 'running' ? '#27ae60' : '#e67e22',
                    }} />
                    <span style={{ fontWeight: 600, fontSize: 15, color: '#2c3e50' }}>
                      {activeInstance.instance_ip || 'No IP'}
                    </span>
                    <span style={{ fontSize: 12, color: '#8e9eab' }}>
                      {activeInstance.instance_id}
                    </span>
                    {activeInstance.server_type && (
                      <span style={{
                        fontSize: 10, fontWeight: 700, textTransform: 'uppercase', letterSpacing: 0.5,
                        background: activeInstance.server_type === 'pdc' ? PDC_BG : PENTAHO_BG,
                        color: activeInstance.server_type === 'pdc' ? PDC_COLOR : PENTAHO_COLOR,
                        padding: '2px 8px', borderRadius: 4,
                      }}>
                        {activeInstance.server_type}
                      </span>
                    )}
                  </div>
                  <div style={{ display: 'flex', flexWrap: 'wrap', gap: 16, fontSize: 12, color: '#5a6c7d' }}>
                    <span>State: <b>{activeInstance.instance_state || '—'}</b></span>
                    <span>Phase: <b>{phaseLabel(activeInstance.deploy_phase)}</b></span>
                    <span>Profile: <b>{activeInstance.name}</b></span>
                    {activeInstance.created_date && (
                      <span>Created: <b>{new Date(activeInstance.created_date).toLocaleDateString()}</b></span>
                    )}
                    {activeInstance.pentaho_version && (
                      <span>Pentaho: <b>{activeInstance.pentaho_version}</b></span>
                    )}
                    {activeInstance.server_url && (
                      <span>URL: <a href={activeInstance.server_url} target="_blank" rel="noreferrer" style={{ color: PENTAHO_COLOR }}>{activeInstance.server_url}</a></span>
                    )}
                  </div>
                </div>
              )}

              {/* Actions for existing instance — no "Create Instance" here */}
              {activeInstance && (
                <div style={{ ...card, border: `2px solid ${isPdc ? PDC_COLOR : PENTAHO_COLOR}` }}>
                  <div style={{ ...cardHeader, color: isPdc ? PDC_COLOR : PENTAHO_COLOR }}>
                    Actions for {activeInstance.instance_ip || activeInstance.name}
                  </div>
                  <p style={cardDesc}>
                    Run operations against this existing {isPdc ? 'PDC' : 'Pentaho'} instance. These actions will <b>not</b> create a new EC2.
                  </p>
                  <div style={cardBody}>
                    <button onClick={() => runInstance(preflight)} style={{ ...btn, background: '#16a085' }} title="Validate env config, AWS credentials, JFrog access, and SSH keys">
                      <span style={iconCircle}>✓</span> Preflight Check
                    </button>
                    <button onClick={() => runInstance(checkEc2)} style={{ ...btn, background: '#6c757d' }} title="Verify the EC2 instance is running and SSH-ready">
                      <span style={iconCircle}>⟳</span> Check Instance
                    </button>
                    {isPdc ? (
                      <button onClick={() => runInstance(deployPdc, `Re-deploy PDC to ${activeInstance.instance_ip}?`)} style={{ ...btn, background: PDC_COLOR }} title="Download and deploy PDC to this instance">
                        <span style={iconCircle}>▲</span> Deploy PDC
                      </button>
                    ) : (
                      <>
                        <button onClick={() => runInstance(deployPentaho, `Deploy/re-deploy Pentaho to ${activeInstance.instance_ip}?`)} style={{ ...btn, background: PENTAHO_COLOR }} title="Download and deploy Pentaho BI Server to this instance">
                          <span style={iconCircle}>▲</span> Deploy Pentaho
                        </button>
                        <button onClick={() => runInstance(deployPlugins)} style={{ ...btn, background: '#8e44ad' }} title="Install all configured plugins into Pentaho">
                          <span style={iconCircle}>⊞</span> Deploy Plugins
                        </button>
                      </>
                    )}
                  </div>
                </div>
              )}
            </>
          )}
        </>
      )}

      <div ref={terminalRef}>
        <Terminal jobId={jobId} onClose={handleJobDone} onDone={refresh} />
      </div>
    </div>
  );
}

/* ── Styles ──────────────────────────────────────────────────────────────── */

const fieldLabel: React.CSSProperties = {
  display: 'block',
  fontSize: 11,
  fontWeight: 700,
  color: '#8e9eab',
  textTransform: 'uppercase',
  letterSpacing: 0.5,
  marginBottom: 6,
};

const selectStyle: React.CSSProperties = {
  display: 'block',
  width: '100%',
  maxWidth: 340,
  padding: '8px 12px',
  borderRadius: 6,
  border: '1px solid var(--field-border)',
  fontSize: 14,
  background: 'var(--field-bg)',
  color: 'var(--text-primary)',
};

const instancePanel: React.CSSProperties = {
  background: 'var(--panel-subtle-bg)',
  border: '1px solid var(--panel-subtle-border)',
  borderRadius: 8,
  padding: '12px 16px',
  marginBottom: 16,
};

const statusDot: React.CSSProperties = {
  display: 'inline-block',
  width: 8,
  height: 8,
  borderRadius: '50%',
  flexShrink: 0,
};

const card: React.CSSProperties = {
  background: 'var(--panel-bg)',
  border: '1px solid var(--panel-border)',
  borderRadius: 8,
  boxShadow: 'var(--panel-shadow)',
  marginBottom: 16,
  overflow: 'hidden',
};

const cardHeader: React.CSSProperties = {
  fontSize: 11,
  fontWeight: 700,
  color: 'var(--text-muted)',
  textTransform: 'uppercase',
  letterSpacing: 1,
  padding: '10px 16px 0',
};

const cardBody: React.CSSProperties = {
  display: 'flex',
  flexWrap: 'wrap',
  gap: 10,
  padding: '12px 16px 16px',
};

const btn: React.CSSProperties = {
  display: 'inline-flex',
  alignItems: 'center',
  gap: 7,
  color: '#fff',
  border: 'none',
  padding: '9px 18px',
  borderRadius: 6,
  cursor: 'pointer',
  fontSize: 13,
  fontWeight: 500,
  lineHeight: 1,
};

const iconCircle: React.CSSProperties = {
  display: 'inline-flex',
  alignItems: 'center',
  justifyContent: 'center',
  width: 20,
  height: 20,
  borderRadius: '50%',
  background: 'rgba(255,255,255,0.2)',
  fontSize: 12,
  lineHeight: 1,
  flexShrink: 0,
};

const stepBtn: React.CSSProperties = {
  display: 'inline-flex',
  alignItems: 'center',
  gap: 6,
  background: 'var(--panel-bg)',
  color: 'var(--text-primary)',
  border: '1px solid var(--panel-border)',
  padding: '7px 14px',
  borderRadius: 6,
  cursor: 'pointer',
  fontSize: 13,
  fontWeight: 500,
};

const stepNum: React.CSSProperties = {
  display: 'inline-flex',
  alignItems: 'center',
  justifyContent: 'center',
  width: 20,
  height: 20,
  borderRadius: '50%',
  background: PENTAHO_COLOR,
  color: '#fff',
  fontSize: 11,
  fontWeight: 700,
  flexShrink: 0,
};

const modeTab: React.CSSProperties = {
  padding: '10px 22px',
  fontSize: 13,
  fontWeight: 600,
  border: '1px solid #d5dbe0',
  cursor: 'pointer',
  transition: 'background .15s, color .15s',
};

const cardDesc: React.CSSProperties = {
  color: 'var(--text-muted)',
  fontSize: 12,
  margin: '0 0 0',
  padding: '4px 16px 0',
};

const stepSection: React.CSSProperties = {
  borderTop: '1px solid var(--panel-header-border)',
  padding: '10px 16px 14px',
  background: 'var(--panel-subtle-bg)',
};

const stepSectionLabel: React.CSSProperties = {
  fontSize: 11,
  fontWeight: 600,
  color: 'var(--text-muted)',
  textTransform: 'uppercase',
  letterSpacing: 0.5,
  marginBottom: 8,
};
