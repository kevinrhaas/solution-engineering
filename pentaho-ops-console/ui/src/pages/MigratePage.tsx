import { useEffect, useState } from 'react';
import {
  fullMigration,
  pdcFullMigration,
  pullContent,
  pushContent,
  pullDatasources,
  pushDatasources,
  pullHome,
  pushHome,
  discoverEc2Instances,
} from '../api';
import type { InstanceSummary } from '../api';
import Terminal from '../components/Terminal';
import { PENTAHO_COLOR, PDC_COLOR } from '../theme';

const quickActions = [
  { label: 'Pull Content', icon: '↓', fn: pullContent, description: 'Download /public content from the Pentaho Server to local storage.' },
  { label: 'Push Content', icon: '↑', fn: pushContent, confirmMsg: 'Push content to the target Pentaho Server? Existing content will be overwritten.', description: 'Upload local content to the Pentaho Server\'s /public folder. Overwrites existing.' },
  { label: 'Pull Datasources', icon: '↓', fn: pullDatasources, description: 'Download datasource configurations from the Pentaho Server.' },
  { label: 'Push Datasources', icon: '↑', fn: pushDatasources, confirmMsg: 'Push datasources to the target Pentaho Server? Existing datasources will be overwritten.', description: 'Upload datasource configs to the Pentaho Server. Overwrites existing.' },
  { label: 'Pull Home', icon: '↓', fn: pullHome, description: 'Download /home directory files from the Pentaho Server.' },
  { label: 'Push Home', icon: '↑', fn: pushHome, confirmMsg: 'Push home files to the target Pentaho Server? Existing home files will be overwritten.', description: 'Upload home directory files to the Pentaho Server. Overwrites existing.' },
] as const;

/** Build a Pentaho Server URL from an instance IP. */
function pentahoUrlFor(inst: InstanceSummary): string {
  const ip = inst.instance_ip || inst.public_ip || '';
  if (!ip) return '';
  return `http://${ip}:80`;
}

function ipFor(inst: InstanceSummary): string {
  return inst.instance_ip || inst.public_ip || '';
}

function envFileFor(inst: InstanceSummary): string {
  const name = (inst.name || '').trim();
  return name ? `${name}.env` : '';
}

/** True if the instance looks like a Pentaho Server (not PDC, not ops-console). */
function isPentahoServerInstance(inst: InstanceSummary): boolean {
  if (inst.server_type === 'pentaho') return true;
  if (inst.server_type === 'pdc' || inst.server_type === 'ops-console') return false;
  // Untracked / unknown — exclude any obvious PDC by name
  const lname = (inst.name || '').toLowerCase();
  if (lname.includes('pdc') || lname.includes('pdq')) return false;
  // Otherwise, treat as Pentaho only if it has an IP
  return Boolean(inst.instance_ip);
}

function isPdcInstance(inst: InstanceSummary): boolean {
  if (inst.server_type === 'pdc') return true;
  if (inst.server_type === 'pentaho' || inst.server_type === 'ops-console') return false;
  const lname = (inst.name || '').toLowerCase();
  if (lname.includes('pdc') || lname.includes('pdq')) return true;
  return Boolean(inst.pdc_version);
}

export default function MigratePage() {
  const [jobId, setJobId] = useState<string | null>(null);

  // Pentaho-server instances (loaded from the Instances API)
  const [pentahoInstances, setPentahoInstances] = useState<InstanceSummary[]>([]);
  const [pdcInstances, setPdcInstances] = useState<InstanceSummary[]>([]);
  const [instancesLoading, setInstancesLoading] = useState(false);

  useEffect(() => {
    setInstancesLoading(true);
    discoverEc2Instances()
      .then((r) => {
        const all = [...r.tracked, ...r.untracked];
        const pdc = all.filter((i) => i.tracking_status === 'tracked').filter(isPdcInstance);
        pdc.sort((a, b) => a.name.localeCompare(b.name));
        setPdcInstances(pdc);

        const allPentaho = all.filter(isPentahoServerInstance);
        // Stable order by display name
        allPentaho.sort((a, b) => a.name.localeCompare(b.name));
        setPentahoInstances(allPentaho);
      })
      .catch(() => { /* leave list empty */ })
      .finally(() => setInstancesLoading(false));
  }, []);

  // PDC migration form state
  const [pdcSourceIp, setPdcSourceIp] = useState('');
  const [pdcTargetIp, setPdcTargetIp] = useState('');
  const [pdcSourceEnvFile, setPdcSourceEnvFile] = useState('');
  const [pdcTargetEnvFile, setPdcTargetEnvFile] = useState('');
  const [pdcSourceUser, setPdcSourceUser] = useState('');
  const [pdcTargetUser, setPdcTargetUser] = useState('');
  const [pdcDryRun, setPdcDryRun] = useState(false);
  const [pdcStopSource, setPdcStopSource] = useState(false);

  const [pdcSourceChoice, setPdcSourceChoice] = useState('');
  const [pdcTargetChoice, setPdcTargetChoice] = useState('');

  // Full migration form state
  const [sourceUrl, setSourceUrl] = useState('');
  const [targetUrl, setTargetUrl] = useState('');
  const [sourceUser, setSourceUser] = useState('admin');
  const [sourcePass, setSourcePass] = useState('password');
  const [targetUser, setTargetUser] = useState('admin');
  const [targetPass, setTargetPass] = useState('password');
  const [dryRun, setDryRun] = useState(false);
  const [skipHome, setSkipHome] = useState(false);
  const [skipContent, setSkipContent] = useState(false);
  const [skipDs, setSkipDs] = useState(false);

  // Quick action form state
  const [serverUrl, setServerUrl] = useState('');
  const [user, setUser] = useState('admin');
  const [pass, setPass] = useState('password');

  async function runFullMigration() {
    const { job_id } = await fullMigration({
      source_url: sourceUrl,
      target_url: targetUrl,
      source_user: sourceUser,
      source_pass: sourcePass,
      target_user: targetUser,
      target_pass: targetPass,
      dry_run: dryRun,
      skip_home: skipHome,
      skip_content: skipContent,
      skip_ds: skipDs,
    });
    setJobId(job_id);
  }

  async function runPdcMigration() {
    const { job_id } = await pdcFullMigration({
      source_ip: pdcSourceIp,
      target_ip: pdcTargetIp,
      source_env_file: pdcSourceEnvFile,
      target_env_file: pdcTargetEnvFile,
      source_user: pdcSourceUser || undefined,
      target_user: pdcTargetUser || undefined,
      dry_run: pdcDryRun,
      stop_source: pdcStopSource,
    });
    setJobId(job_id);
  }

  async function quickAction(
    fn: (p: { server_url: string; user: string; password: string }) => Promise<{ job_id: string }>,
    confirmMsg?: string,
  ) {
    if (confirmMsg && !window.confirm(confirmMsg)) return;
    const { job_id } = await fn({ server_url: serverUrl, user, password: pass });
    setJobId(job_id);
  }

  function instanceLabel(inst: InstanceSummary): string {
    const ip = inst.instance_ip || inst.public_ip || '?';
    const ver = inst.pentaho_version ? ` v${inst.pentaho_version}` : '';
    return `${inst.name}${ver} — ${ip}`;
  }

  return (
    <div>
      <h2 style={{ margin: '0 0 4px' }}>Migrate <span style={{ fontSize: 13, fontWeight: 500, color: '#8e9eab', marginLeft: 8 }}>Pentaho Server + PDC</span></h2>
      <p style={{ color: '#8e9eab', margin: '0 0 12px', fontSize: 13 }}>
        Run guided migration flows for <strong>Pentaho Server</strong> and <strong>PDC</strong> environments.
      </p>

      {/* Full Pentaho Server Migration */}
      <div style={{ ...card, border: `2px solid ${PENTAHO_COLOR}` }}>
        <div style={{ ...cardHeader, color: PENTAHO_COLOR }}>Full Pentaho Server Migration</div>
        <p style={{ color: '#8e9eab', fontSize: 12, margin: '0 0 0', padding: '4px 16px 0' }}>Transfers all content, datasources, and user home folders from one Pentaho Server to another.</p>
        <div style={{ padding: '12px 16px 16px' }}>
          <div style={gridStyle}>
            <label style={labelStyle}>
              Source Pentaho Server
              <select
                value={sourceUrl}
                onChange={(e) => setSourceUrl(e.target.value)}
                style={inputStyle}
                title="Pick a tracked Pentaho Server instance — or leave blank to enter a URL manually below"
              >
                <option value="">{instancesLoading ? 'Loading instances…' : '— pick a Pentaho Server —'}</option>
                {pentahoInstances.map((i) => (
                  <option key={`src-${i.instance_id || i.name}`} value={pentahoUrlFor(i)}>
                    {instanceLabel(i)}
                  </option>
                ))}
              </select>
              <input value={sourceUrl} onChange={(e) => setSourceUrl(e.target.value)} style={{ ...inputStyle, marginTop: 6 }} placeholder="http://10.80.230.123:80" />
            </label>
            <label style={labelStyle}>
              Target Pentaho Server
              <select
                value={targetUrl}
                onChange={(e) => setTargetUrl(e.target.value)}
                style={inputStyle}
                title="Pick a tracked Pentaho Server instance — or leave blank to enter a URL manually below"
              >
                <option value="">{instancesLoading ? 'Loading instances…' : '— pick a Pentaho Server —'}</option>
                {pentahoInstances
                  .filter((i) => pentahoUrlFor(i) !== sourceUrl)
                  .map((i) => (
                    <option key={`tgt-${i.instance_id || i.name}`} value={pentahoUrlFor(i)}>
                      {instanceLabel(i)}
                    </option>
                  ))}
              </select>
              <input value={targetUrl} onChange={(e) => setTargetUrl(e.target.value)} style={{ ...inputStyle, marginTop: 6 }} placeholder="http://10.80.230.225:80" />
            </label>
            <label style={labelStyle}>
              Source User
              <input value={sourceUser} onChange={(e) => setSourceUser(e.target.value)} style={inputStyle} />
            </label>
            <label style={labelStyle}>
              Source Password
              <input value={sourcePass} onChange={(e) => setSourcePass(e.target.value)} style={inputStyle} type="password" />
            </label>
            <label style={labelStyle}>
              Target User
              <input value={targetUser} onChange={(e) => setTargetUser(e.target.value)} style={inputStyle} />
            </label>
            <label style={labelStyle}>
              Target Password
              <input value={targetPass} onChange={(e) => setTargetPass(e.target.value)} style={inputStyle} type="password" />
            </label>
          </div>
          <div style={{ display: 'flex', gap: 16, margin: '10px 0 12px' }}>
            <label style={{ fontSize: 13 }}><input type="checkbox" checked={dryRun} onChange={(e) => setDryRun(e.target.checked)} /> Dry Run</label>
            <label style={{ fontSize: 13 }}><input type="checkbox" checked={skipHome} onChange={(e) => setSkipHome(e.target.checked)} /> Skip Home</label>
            <label style={{ fontSize: 13 }}><input type="checkbox" checked={skipContent} onChange={(e) => setSkipContent(e.target.checked)} /> Skip Content</label>
            <label style={{ fontSize: 13 }}><input type="checkbox" checked={skipDs} onChange={(e) => setSkipDs(e.target.checked)} /> Skip Datasources</label>
          </div>
          <button onClick={() => {
            if (!window.confirm('Run a full Pentaho Server migration? This will overwrite content on the target server.')) return;
            runFullMigration();
          }} title="Migrate all content, datasources, and home files from source to target Pentaho Server" style={primaryBtn}>
            <span style={iconCircle}>⇄</span> Run Full Pentaho Server Migration
          </button>
        </div>
      </div>

      {/* Pentaho Server Quick Actions */}
      <div style={{ ...card, border: `2px solid ${PENTAHO_COLOR}` }}>
        <div style={{ ...cardHeader, color: PENTAHO_COLOR }}>Pentaho Server Quick Actions</div>
        <p style={{ color: '#8e9eab', fontSize: 12, margin: '0 0 0', padding: '4px 16px 0' }}>Run individual migration steps against a single <strong>Pentaho Server</strong> — export, import, or list content. (PDC instances are not supported.)</p>
        <div style={{ padding: '12px 16px 16px' }}>
          <div style={{ ...gridStyle, gridTemplateColumns: '1fr 1fr 1fr' }}>
            <label style={labelStyle}>
              Pentaho Server
              <select
                value={serverUrl}
                onChange={(e) => setServerUrl(e.target.value)}
                style={inputStyle}
                title="Pick a tracked Pentaho Server instance — or enter a URL manually below"
              >
                <option value="">{instancesLoading ? 'Loading instances…' : '— pick a Pentaho Server —'}</option>
                {pentahoInstances.map((i) => (
                  <option key={`qa-${i.instance_id || i.name}`} value={pentahoUrlFor(i)}>
                    {instanceLabel(i)}
                  </option>
                ))}
              </select>
              <input value={serverUrl} onChange={(e) => setServerUrl(e.target.value)} style={{ ...inputStyle, marginTop: 6 }} placeholder="http://10.80.230.225:80" />
            </label>
            <label style={labelStyle}>
              User
              <input value={user} onChange={(e) => setUser(e.target.value)} style={inputStyle} />
            </label>
            <label style={labelStyle}>
              Password
              <input value={pass} onChange={(e) => setPass(e.target.value)} style={inputStyle} type="password" />
            </label>
          </div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: 12 }}>
            {quickActions.map((a) => (
              <button
                key={a.label}
                onClick={() => quickAction(a.fn, 'confirmMsg' in a ? a.confirmMsg : undefined)}
                title={a.description}
                style={{
                  ...actionBtn,
                  background: a.icon === '↑' ? '#e67e22' : '#27ae60',
                }}
              >
                <span style={iconCircle}>{a.icon}</span> {a.label}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Full PDC Migration */}
      <div style={{ ...card, border: `2px solid ${PDC_COLOR}` }}>
        <div style={{ ...cardHeader, color: PDC_COLOR }}>Full PDC Migration</div>
        <p style={{ color: '#8e9eab', fontSize: 12, margin: '0 0 0', padding: '4px 16px 0' }}>
          Migrates PDC conf and all pdc* volumes between tracked PDC instances. Defaults are derived from each instance profile env file.
        </p>
        <div style={{ ...pdcNote, margin: '10px 16px 0' }}>
          PDC app credentials are not required here. Migration uses profile/env + SSH settings.
        </div>
        <div style={{ padding: '12px 16px 16px' }}>
          <div style={gridStyle}>
            <label style={labelStyle}>
              Source PDC Instance
              <select
                value={pdcSourceChoice}
                onChange={(e) => {
                  const key = e.target.value;
                  setPdcSourceChoice(key);
                  const inst = pdcInstances.find((i) => (i.instance_id || i.name) === key);
                  if (!inst) return;
                  setPdcSourceIp(ipFor(inst));
                  setPdcSourceEnvFile(envFileFor(inst));
                }}
                style={inputStyle}
                title="Pick a tracked PDC instance to auto-fill source IP and env file"
              >
                <option value="">{instancesLoading ? 'Loading instances…' : '— pick a PDC instance —'}</option>
                {pdcInstances.map((i) => (
                  <option key={`pdc-src-${i.instance_id || i.name}`} value={i.instance_id || i.name}>
                    {instanceLabel(i)}
                  </option>
                ))}
              </select>
            </label>
            <label style={labelStyle}>
              Target PDC Instance
              <select
                value={pdcTargetChoice}
                onChange={(e) => {
                  const key = e.target.value;
                  setPdcTargetChoice(key);
                  const inst = pdcInstances.find((i) => (i.instance_id || i.name) === key);
                  if (!inst) return;
                  setPdcTargetIp(ipFor(inst));
                  setPdcTargetEnvFile(envFileFor(inst));
                }}
                style={inputStyle}
                title="Pick a tracked PDC instance to auto-fill target IP and env file"
              >
                <option value="">{instancesLoading ? 'Loading instances…' : '— pick a PDC instance —'}</option>
                {pdcInstances
                  .filter((i) => (i.instance_id || i.name) !== pdcSourceChoice)
                  .map((i) => (
                    <option key={`pdc-tgt-${i.instance_id || i.name}`} value={i.instance_id || i.name}>
                      {instanceLabel(i)}
                    </option>
                  ))}
              </select>
            </label>
            <label style={labelStyle}>
              Source IP
              <input value={pdcSourceIp} onChange={(e) => setPdcSourceIp(e.target.value)} style={inputStyle} placeholder="10.80.230.177" />
            </label>
            <label style={labelStyle}>
              Target IP
              <input value={pdcTargetIp} onChange={(e) => setPdcTargetIp(e.target.value)} style={inputStyle} placeholder="10.80.230.186" />
            </label>
            <label style={labelStyle}>
              Source Env File
              <input value={pdcSourceEnvFile} onChange={(e) => setPdcSourceEnvFile(e.target.value)} style={inputStyle} placeholder="pdc-source.env" />
            </label>
            <label style={labelStyle}>
              Target Env File
              <input value={pdcTargetEnvFile} onChange={(e) => setPdcTargetEnvFile(e.target.value)} style={inputStyle} placeholder="pdc-target.env" />
            </label>
            <label style={labelStyle}>
              Source SSH User (optional)
              <input value={pdcSourceUser} onChange={(e) => setPdcSourceUser(e.target.value)} style={inputStyle} placeholder="ubuntu" />
            </label>
            <label style={labelStyle}>
              Target SSH User (optional)
              <input value={pdcTargetUser} onChange={(e) => setPdcTargetUser(e.target.value)} style={inputStyle} placeholder="ubuntu" />
            </label>
          </div>
          <div style={{ display: 'flex', gap: 16, margin: '10px 0 12px' }}>
            <label style={{ fontSize: 13 }}><input type="checkbox" checked={pdcDryRun} onChange={(e) => setPdcDryRun(e.target.checked)} /> Dry Run</label>
            <label style={{ fontSize: 13 }}><input type="checkbox" checked={pdcStopSource} onChange={(e) => setPdcStopSource(e.target.checked)} /> Stop Source (maintenance window)</label>
          </div>
          <button onClick={() => {
            if (!window.confirm('Run full PDC migration? Target conf and pdc* volumes will be overwritten.')) return;
            runPdcMigration();
          }} title="Run full PDC migration" style={{ ...primaryBtn, background: PDC_COLOR }}>
            <span style={iconCircle}>⇄</span> Run Full PDC Migration
          </button>
        </div>
      </div>

      <Terminal jobId={jobId} onClose={() => setJobId(null)} />
    </div>
  );
}

/* ── Styles ──────────────────────────────────────────────────────────────── */

const card: React.CSSProperties = {
  background: 'var(--panel-bg)',
  border: '1px solid var(--panel-border)',
  borderRadius: 8,
  boxShadow: 'var(--panel-shadow)',
  marginBottom: 16,
  overflow: 'hidden',
};

const pdcNote: React.CSSProperties = {
  background: '#fef9e7',
  color: '#7a4a00',
  border: '1px solid #f1c40f',
  borderLeft: '4px solid #f39c12',
  borderRadius: 6,
  padding: '8px 12px',
  marginBottom: 16,
  fontSize: 12,
  lineHeight: 1.5,
};

const cardHeader: React.CSSProperties = {
  fontSize: 11,
  fontWeight: 700,
  color: 'var(--text-muted)',
  textTransform: 'uppercase',
  letterSpacing: 1,
  padding: '10px 16px 0',
};

const gridStyle: React.CSSProperties = {
  display: 'grid',
  gridTemplateColumns: '1fr 1fr',
  gap: 12,
};

const labelStyle: React.CSSProperties = {
  fontSize: 13,
  fontWeight: 500,
  color: 'var(--text-primary)',
};

const inputStyle: React.CSSProperties = {
  display: 'block',
  width: '100%',
  padding: '7px 10px',
  borderRadius: 6,
  border: '1px solid var(--field-border)',
  fontSize: 13,
  marginTop: 4,
  boxSizing: 'border-box',
  background: 'var(--field-bg)',
  color: 'var(--text-primary)',
};

const primaryBtn: React.CSSProperties = {
  display: 'inline-flex',
  alignItems: 'center',
  gap: 7,
  background: PENTAHO_COLOR,
  color: '#fff',
  border: 'none',
  padding: '10px 24px',
  borderRadius: 6,
  cursor: 'pointer',
  fontSize: 14,
  fontWeight: 500,
};

const actionBtn: React.CSSProperties = {
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
