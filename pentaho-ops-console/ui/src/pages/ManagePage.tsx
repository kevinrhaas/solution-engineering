import { useEffect, useMemo, useState } from 'react';
import {
  listInstances,
  restartContainer,
  startContainer,
  stopContainer,
  tailCatalina,
  dockerLogs,
  monitorResources,
  diagnoseContainer,
  getSshInfo,
  pdcRestart,
  runPdcAutomationAction,
  listPdcDatasources,
  resolvePdcDatasource,
} from '../api';
import type { InstanceSummary, SshInfo, PdcDatasource } from '../api';
import Terminal from '../components/Terminal';

const OPTIONAL_JOBS = new Set(['discovery', 'identification', 'pii', 'trust-score']);
const PDC_OBJECT_ID = /^[a-f0-9]{24}$/i;

const WORKFLOW_ACTIONS = [
  { action: 'preflight',      label: 'Preflight',       description: 'Validate tooling, credentials, and API connectivity before running jobs.' },
  { action: 'ingest',         label: 'Ingest',          description: 'Pull metadata from the configured datasource into PDC.' },
  { action: 'collection',     label: 'Collection',      description: 'Create or update a dataset collection for profiling.' },
  { action: 'profile',        label: 'Profile',         description: 'Run data profiling on a collection (by Collection ID) or scoped entities (by Scope IDs).' },
  { action: 'aggregate',      label: 'Aggregate',       description: 'Aggregate profiling results at the collection level.' },
  { action: 'results',        label: 'Results',         description: 'Fetch profiling and aggregation results for a collection.' },
  { action: 'discovery',      label: 'Discovery',       description: 'Run data discovery analysis on scoped entities.' },
  { action: 'identification', label: 'Identification',  description: 'Run data identification analysis on scoped entities.' },
  { action: 'pii',            label: 'PII Detection',   description: 'Detect personally identifiable information in scoped entities.' },
  { action: 'trust-score',    label: 'Trust Score',     description: 'Calculate trust scores for scoped entities.' },
  { action: 'tagging',        label: 'Tagging',         description: 'Apply governance tags to a PDC entity.' },
];

export default function ManagePage() {
  const [instances, setInstances] = useState<InstanceSummary[]>([]);
  const [selectedIdx, setSelectedIdx] = useState(0);
  const [jobId, setJobId] = useState<string | null>(null);
  const [sshInfo, setSshInfo] = useState<SshInfo | null>(null);
  const [logDuration, setLogDuration] = useState('30m');
  const [catalinaLines, setCatalinaLines] = useState('200');
  const [selectedPdcAction, setSelectedPdcAction] = useState('preflight');
  const [datasourceId, setDatasourceId] = useState('');
  const [datasourceName, setDatasourceName] = useState('');
  const [collectionId, setCollectionId] = useState('');
  const [collectionName, setCollectionName] = useState('');
  const [scopeIds, setScopeIds] = useState('');
  const [entityId, setEntityId] = useState('');
  const [tagsCsv, setTagsCsv] = useState('');
  const [dryRun, setDryRun] = useState(false);
  const [useAdvancedPayload, setUseAdvancedPayload] = useState(false);
  const [pdcPayloadJson, setPdcPayloadJson] = useState('');
  const [pdcError, setPdcError] = useState('');
  const [dsPickerOpen, setDsPickerOpen] = useState(false);
  const [dsPickerLoading, setDsPickerLoading] = useState(false);
  const [dsPickerError, setDsPickerError] = useState('');
  const [dsPickerItems, setDsPickerItems] = useState<PdcDatasource[]>([]);

  useEffect(() => {
    listInstances().then((i) => {
      setInstances(i);
    });
  }, []);

  const inst = instances[selectedIdx] as InstanceSummary | undefined;
  const profile = inst?.name || '';
  const stateFile = inst?.state_file || '';
  const isPdc = inst?.server_type === 'pdc';

  async function run(action: (p: string, sf?: string) => Promise<{ job_id: string }>, confirmMsg?: string) {
    if (!profile) return;
    if (confirmMsg && !window.confirm(confirmMsg)) return;
    const { job_id } = await action(profile, stateFile);
    setJobId(job_id);
  }

  async function runDockerLogs() {
    if (!profile) return;
    const { job_id } = await dockerLogs(profile, logDuration || undefined, stateFile);
    setJobId(job_id);
  }

  async function runCatalinaLogs() {
    if (!profile) return;
    const { job_id } = await tailCatalina(profile, catalinaLines || undefined, stateFile);
    setJobId(job_id);
  }

  async function fetchSsh() {
    if (!profile) return;
    const info = await getSshInfo(profile, stateFile);
    setSshInfo(info);
  }

  function splitCsv(value: string): string[] {
    return value.split(',').map((v) => v.trim()).filter(Boolean);
  }

  function buildPayload(action: string, ingestResourceId?: string): Record<string, unknown> | null {
    if (useAdvancedPayload && pdcPayloadJson.trim()) {
      return JSON.parse(pdcPayloadJson.trim()) as Record<string, unknown>;
    }

    const scopes = splitCsv(scopeIds);

    switch (action) {
      case 'ingest':
        return ingestResourceId ? { resourceId: ingestResourceId } : {};
      case 'collection':
        return {
          name: collectionName || 'automation-collection',
          type: 'dataset',
          ...(collectionId ? { parentId: collectionId } : {}),
        };
      case 'profile':
        if (collectionId) return { collectionId };
        if (scopes.length > 0) return { scope: scopes, configs: {} };
        return {};
      case 'aggregate':
        return collectionId ? { collectionId } : {};
      case 'results':
        return collectionId ? { ids: [collectionId] } : {};
      case 'tagging':
        return {
          attributes: {
            tags: splitCsv(tagsCsv).map((name) => ({ name })),
          },
        };
      case 'trust-score':
        return { scope: scopes };
      case 'identification':
        return { scope: scopes, dictionaryIds: [], dataPatternIds: [] };
      case 'pii':
        return { scope: scopes, configs: { language: 'ENGLISH' } };
      case 'discovery':
        return { scope: scopes, configs: {} };
      default:
        return null;
    }
  }

  async function runPdc() {
    if (!profile) return;
    const action = selectedPdcAction;
    const backendAction = OPTIONAL_JOBS.has(action) ? 'optional' : action;
    setPdcError('');

    if (action === 'tagging' && !entityId.trim()) {
      setPdcError('Tagging requires an Entity ID.');
      return;
    }

    let resolvedDatasourceId = datasourceId.trim();

    if (action === 'ingest' && !resolvedDatasourceId && datasourceName.trim()) {
      try {
        const resolved = await resolvePdcDatasource(profile, datasourceName.trim(), stateFile);
        resolvedDatasourceId = resolved._id;
        setDatasourceId(resolved._id);
      } catch (error) {
        setPdcError(error instanceof Error ? error.message : 'Failed to resolve datasource name to Object ID.');
        return;
      }
    }

    if (action === 'ingest' && !dryRun && !resolvedDatasourceId) {
      setPdcError('Ingest requires either a datasource Object ID or a datasource name to resolve.');
      return;
    }

    if (action === 'ingest' && !dryRun && resolvedDatasourceId && !PDC_OBJECT_ID.test(resolvedDatasourceId)) {
      setPdcError('Ingest requires the PDC datasource Object ID (_id), not the visible numeric Data Source ID shown in the PDC form.');
      return;
    }

    if (OPTIONAL_JOBS.has(action) && splitCsv(scopeIds).length === 0) {
      setPdcError('This process requires at least one Scope ID.');
      return;
    }

    let payload: Record<string, unknown> | null = null;
    try {
      payload = buildPayload(action, resolvedDatasourceId);
    } catch {
      setPdcError('Advanced payload JSON is invalid.');
      return;
    }

    const params: Record<string, string> = {};
    if (resolvedDatasourceId) params['datasource-id'] = resolvedDatasourceId;
    if (collectionId.trim()) params['collection-id'] = collectionId.trim();
    if (entityId.trim()) params['entity-id'] = entityId.trim();
    if (tagsCsv.trim()) params.tags = tagsCsv.trim();
    if (OPTIONAL_JOBS.has(action)) params['job-type'] = action;
    if (dryRun) params['dry-run'] = 'true';

    try {
      const { job_id } = await runPdcAutomationAction(profile, backendAction, {
        stateFile,
        payloadJson: payload ? JSON.stringify(payload) : undefined,
        params,
      });
      setJobId(job_id);
    } catch (error) {
      setPdcError(error instanceof Error ? error.message : 'Failed to run PDC automation action.');
    }
  }

  const pdcFields = useMemo(() => {
    const a = selectedPdcAction;
    return {
      datasourceId: a === 'ingest',
      collectionId: ['collection', 'profile', 'aggregate', 'results'].includes(a),
      collectionName: a === 'collection',
      scopeIds: a === 'profile' || OPTIONAL_JOBS.has(a),
      entityId: a === 'tagging',
      tags: a === 'tagging',
    };
  }, [selectedPdcAction]);

  const selectedActionMeta = WORKFLOW_ACTIONS.find((a) => a.action === selectedPdcAction);

  return (
    <div>
      <h2 style={{ margin: '0 0 4px' }}>Manage</h2>
      <p style={{ color: '#8e9eab', margin: '0 0 20px', fontSize: 13 }}>
        Select a running instance to manage its container, view logs, or run diagnostics.
      </p>

      <div style={{ marginBottom: 20 }}>
        <label style={fieldLabelStyle}>Instance</label>
        <select
          value={selectedIdx}
          onChange={(e) => { setSelectedIdx(Number(e.target.value)); setSshInfo(null); }}
          style={selectStyle}
        >
          {instances.length === 0 && <option>No instances found</option>}
          {instances.map((inst, idx) => (
            <option key={inst.state_file} value={idx}>
              {inst.name} — {inst.instance_ip || 'no IP'} ({inst.instance_state || 'unknown'})
            </option>
          ))}
        </select>
      </div>

      {/* Container Lifecycle — Pentaho */}
      {!isPdc && (
      <div style={card}>
        <div style={cardHeader}>Container</div>
        <p style={{ color: '#8e9eab', fontSize: 12, margin: '0 0 0', padding: '4px 16px 0' }}>Start, stop, or restart the Pentaho Docker container on this instance.</p>
        <div style={cardBody}>
          <button onClick={() => run(restartContainer, 'Restart the Pentaho container? This will cause brief downtime.')} title="Restart the Docker container (docker-compose restart). Expect ~30–60s downtime." style={{ ...btn, background: '#e67e22' }}>
            <span style={iconCircle}>⟳</span> Restart
          </button>
          <button onClick={() => run(startContainer)} title="Start the container environment (docker-compose up). Use after a Stop." style={{ ...btn, background: '#27ae60' }}>
            <span style={iconCircle}>▶</span> Start
          </button>
          <button onClick={() => run(stopContainer, 'Stop (docker-compose down) the Pentaho container? The server will go offline.')} title="Stop and remove containers (docker-compose down). Server goes offline." style={{ ...btn, background: '#c0392b' }}>
            <span style={iconCircle}>■</span> Stop
          </button>
        </div>
      </div>
      )}

      {/* PDC Services */}
      {isPdc && (
      <div style={card}>
        <div style={cardHeader}>PDC Services</div>
        <p style={{ color: '#8e9eab', fontSize: 12, margin: '0 0 0', padding: '4px 16px 0' }}>Restart all PDC Docker Compose services (pdc.sh down + up). Use when services fail to start or need a clean restart.</p>
        <div style={cardBody}>
          <button onClick={() => run(pdcRestart, 'Restart all PDC services? This runs pdc.sh down then pdc.sh up. Expect several minutes of downtime.')} title="Stop and restart all PDC services via pdc.sh down + pdc.sh up" style={{ ...btn, background: '#e67e22' }}>
            <span style={iconCircle}>⟳</span> Restart PDC
          </button>
        </div>
      </div>
      )}

      {/* Logs */}
      <div style={card}>
        <div style={cardHeader}>Logs</div>
        <p style={{ color: '#8e9eab', fontSize: 12, margin: '0 0 0', padding: '4px 16px 0' }}>{isPdc ? 'View Docker log output from the PDC services.' : 'View Tomcat and Docker log output from the server.'}</p>
        <div style={cardBody}>
          {!isPdc && (
          <div style={comboGroup}>
            <button onClick={runCatalinaLogs} title="Tail the Tomcat catalina.out log. Shows server startup messages and request logs." style={{ ...btn, background: '#005bb5', borderRadius: '6px 0 0 6px' }}>
              <span style={iconCircle}>☰</span> Catalina
            </button>
            <select value={catalinaLines} onChange={(e) => setCatalinaLines(e.target.value)} title="Number of lines to tail" style={comboSelect}>
              <option value="50">50 lines</option>
              <option value="200">200 lines</option>
              <option value="500">500 lines</option>
              <option value="1000">1,000 lines</option>
              <option value="5000">5,000 lines</option>
              <option value="all">All</option>
            </select>
          </div>
          )}
          <div style={comboGroup}>
            <button onClick={runDockerLogs} title="Fetch Docker container stdout/stderr logs. Use the duration filter to limit output." style={{ ...btn, background: '#005bb5', borderRadius: '6px 0 0 6px' }}>
              <span style={iconCircle}>◆</span> Docker
            </button>
            <select value={logDuration} onChange={(e) => setLogDuration(e.target.value)} title="Time window for docker logs" style={comboSelect}>
              <option value="5m">5 min</option>
              <option value="15m">15 min</option>
              <option value="30m">30 min</option>
              <option value="1h">1 hour</option>
              <option value="6h">6 hours</option>
              <option value="24h">24 hours</option>
              <option value="">All</option>
            </select>
          </div>
        </div>
      </div>

      {/* Diagnostics */}
      <div style={card}>
        <div style={cardHeader}>Diagnostics</div>
        <p style={{ color: '#8e9eab', fontSize: 12, margin: '0 0 0', padding: '4px 16px 0' }}>Check resource usage, troubleshoot issues, or get SSH connection details.</p>
        <div style={cardBody}>
          <button onClick={() => run(monitorResources)} title="Show CPU, memory, disk, and JVM heap usage for the container and host." style={{ ...btn, background: '#8e44ad' }}>
            <span style={iconCircle}>◉</span> Monitor
          </button>
          <button onClick={() => run(diagnoseContainer)} title="Run comprehensive diagnostics — container state, ports, disk, Docker health." style={{ ...btn, background: '#8e44ad' }}>
            <span style={iconCircle}>⚙</span> Diagnose
          </button>
          <button onClick={fetchSsh} title="Show SSH commands to connect directly to the EC2 instance or Docker container." style={{ ...btn, background: '#5d6d7e' }}>
            <span style={iconCircle}>⌘</span> SSH Info
          </button>
        </div>
      </div>

      {isPdc && (
      <div style={card}>
        <div style={{ ...cardHeader, display: 'flex', alignItems: 'center', gap: 8 }}>
          <span>PDC Automation</span>
          <span
            style={{
              fontSize: 10,
              fontWeight: 700,
              textTransform: 'uppercase',
              letterSpacing: 0.5,
              color: '#7a3e00',
              background: '#ffe8cc',
              border: '1px solid #ffd199',
              borderRadius: 999,
              padding: '2px 7px',
            }}
          >
            Experimental
          </span>
        </div>
        <p style={{ color: '#8e9eab', fontSize: 12, margin: 0, padding: '4px 16px 0' }}>
          Run profiling and governance workflows for any PDC-supported source, including S3.
        </p>
        <div
          style={{
            margin: '10px 16px 0',
            padding: '8px 10px',
            borderRadius: 6,
            background: '#fff6e5',
            border: '1px solid #ffe2ad',
            fontSize: 12,
            color: '#7a4b00',
          }}
        >
          Experimental: API behavior can vary by PDC version and some actions may require manual verification.
        </div>
        <div style={{ display: 'flex', borderTop: '1px solid #f0f2f4', marginTop: 8 }}>

          {/* Left tab nav */}
          <div style={{ width: 148, flexShrink: 0, background: '#f8f9fa', borderRight: '1px solid #e8eaed', padding: '6px 0 12px' }}>
            {([
              { group: 'Workflow', items: WORKFLOW_ACTIONS.filter((a) => !OPTIONAL_JOBS.has(a.action) && a.action !== 'tagging') },
              { group: 'Analysis', items: WORKFLOW_ACTIONS.filter((a) => OPTIONAL_JOBS.has(a.action)) },
              { group: 'Governance', items: WORKFLOW_ACTIONS.filter((a) => a.action === 'tagging') },
            ] as { group: string; items: typeof WORKFLOW_ACTIONS }[]).map(({ group, items }) => (
              <div key={group}>
                <div style={{ fontSize: 10, fontWeight: 700, color: '#9aabb8', textTransform: 'uppercase', letterSpacing: 0.8, padding: '10px 12px 3px' }}>
                  {group}
                </div>
                {items.map((a) => (
                  <button
                    key={a.action}
                    onClick={() => setSelectedPdcAction(a.action)}
                    title={a.description}
                    style={{
                      display: 'block', width: '100%', textAlign: 'left',
                      padding: '7px 12px 7px 13px',
                      background: selectedPdcAction === a.action ? '#fff' : 'transparent',
                      border: 'none',
                      borderLeft: `3px solid ${selectedPdcAction === a.action ? '#1f6feb' : 'transparent'}`,
                      color: selectedPdcAction === a.action ? '#1f6feb' : '#374151',
                      fontWeight: selectedPdcAction === a.action ? 600 : 400,
                      fontSize: 13,
                      cursor: 'pointer',
                      lineHeight: 1.4,
                    }}
                  >
                    {a.label}
                  </button>
                ))}
              </div>
            ))}
          </div>

          {/* Right form panel */}
          <div style={{ flex: 1, padding: '14px 18px 18px', display: 'grid', gap: 12, alignContent: 'start' }}>
            <div>
              <div style={{ fontWeight: 600, fontSize: 15, color: '#1a2332', marginBottom: 3 }}>
                {selectedActionMeta?.label}
              </div>
              <div style={helpStyle}>{selectedActionMeta?.description}</div>
            </div>

            {(Object.values(pdcFields).some(Boolean)) && (
              <div style={formGridStyle}>
                {pdcFields.datasourceId && (
                  <div>
                    <label style={fieldLabelStyle}>{selectedPdcAction === 'ingest' ? 'Datasource Object ID' : 'Datasource ID'}</label>
                    <div style={{ display: 'flex', gap: 6 }}>
                      <input
                        value={datasourceId}
                        onChange={(e) => setDatasourceId(e.target.value)}
                        style={{ ...inputStyle, flex: 1 }}
                        placeholder={selectedPdcAction === 'ingest' ? '24-char PDC _id required for live ingest' : 'Optional — auto-generated if blank'}
                      />
                      <button
                        type="button"
                        style={{ padding: '6px 12px', fontSize: 12, border: '1px solid #c5cdd6', borderRadius: 4, background: '#f5f8fb', cursor: 'pointer', whiteSpace: 'nowrap' }}
                        onClick={() => {
                          if (!inst) return;
                          const q = datasourceName.trim();
                          setDsPickerOpen(true);
                          setDsPickerError('');
                          setDsPickerItems([]);
                          setDsPickerLoading(true);
                          listPdcDatasources(inst.name, inst.state_file || undefined, q || undefined)
                            .then((items) => setDsPickerItems(items))
                            .catch((e) => setDsPickerError(String(e)))
                            .finally(() => setDsPickerLoading(false));
                        }}
                      >
                        Search
                      </button>
                    </div>
                    {selectedPdcAction === 'ingest' && (
                      <div style={{ marginTop: 8 }}>
                        <label style={fieldLabelStyle}>Datasource Name (optional)</label>
                        <div style={{ display: 'flex', gap: 6 }}>
                          <input
                            value={datasourceName}
                            onChange={(e) => setDatasourceName(e.target.value)}
                            style={{ ...inputStyle, flex: 1 }}
                            placeholder="Example: Demo Sources"
                          />
                          <button
                            type="button"
                            style={{ padding: '6px 12px', fontSize: 12, border: '1px solid #c5cdd6', borderRadius: 4, background: '#f5f8fb', cursor: 'pointer', whiteSpace: 'nowrap' }}
                            onClick={async () => {
                              if (!inst || !datasourceName.trim()) return;
                              setDsPickerError('');
                              setDsPickerLoading(true);
                              try {
                                const resolved = await resolvePdcDatasource(inst.name, datasourceName.trim(), inst.state_file || undefined);
                                setDatasourceId(resolved._id);
                                setDsPickerItems(resolved.matches || []);
                                setDsPickerOpen(true);
                              } catch (e) {
                                setDsPickerError(String(e));
                                setDsPickerOpen(true);
                              } finally {
                                setDsPickerLoading(false);
                              }
                            }}
                          >
                            Resolve ID
                          </button>
                        </div>
                      </div>
                    )}
                    {dsPickerOpen && (
                      <div style={{ marginTop: 6, border: '1px solid #c5cdd6', borderRadius: 6, background: '#fff', boxShadow: '0 2px 8px rgba(0,0,0,0.08)', maxHeight: 220, overflowY: 'auto' }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '6px 10px', borderBottom: '1px solid #eef0f3', fontSize: 12, color: '#5a6c7d' }}>
                          <span>Select a datasource — click a row to use its <strong>_id</strong></span>
                          <button type="button" onClick={() => setDsPickerOpen(false)} style={{ background: 'none', border: 'none', cursor: 'pointer', fontSize: 14, color: '#5a6c7d' }}>✕</button>
                        </div>
                        {dsPickerLoading && <div style={{ padding: '10px 12px', fontSize: 13, color: '#5a6c7d' }}>Loading…</div>}
                        {dsPickerError && <div style={{ padding: '10px 12px', fontSize: 12, color: '#c0392b' }}>{dsPickerError}</div>}
                        {!dsPickerLoading && !dsPickerError && dsPickerItems.length === 0 && (
                          <div style={{ padding: '10px 12px', fontSize: 13, color: '#5a6c7d' }}>No datasources found.</div>
                        )}
                        {dsPickerItems.map((ds) => (
                          <div
                            key={ds._id}
                            onClick={() => { setDatasourceId(ds._id); setDsPickerOpen(false); }}
                            style={{ padding: '8px 12px', cursor: 'pointer', borderBottom: '1px solid #f0f2f5', fontSize: 13 }}
                            onMouseEnter={(e) => (e.currentTarget.style.background = '#f5f8fb')}
                            onMouseLeave={(e) => (e.currentTarget.style.background = '')}
                          >
                            <strong>{ds.resourceName}</strong>
                            <span style={{ color: '#5a6c7d', marginLeft: 8 }}>{ds.databaseType}</span>
                            <span style={{ color: '#8fa3b1', marginLeft: 8, fontFamily: 'monospace', fontSize: 11 }}>{ds._id}</span>
                            {ds.pId && <span style={{ color: '#b0bec5', marginLeft: 6, fontSize: 11 }}>pId={ds.pId}</span>}
                          </div>
                        ))}
                      </div>
                    )}
                    {selectedPdcAction === 'ingest' && !dsPickerOpen && (
                      <div style={helpStyle}>The numeric Data Source ID shown in PDC is not accepted — use <strong>_id</strong>. You can resolve by name (for example, Demo Sources) without DB access.</div>
                    )}
                  </div>
                )}
                {pdcFields.collectionId && (
                  <div>
                    <label style={fieldLabelStyle}>Collection ID</label>
                    <input value={collectionId} onChange={(e) => setCollectionId(e.target.value)} style={inputStyle} placeholder={selectedPdcAction === 'collection' ? 'Optional parent ID' : 'Optional'} />
                  </div>
                )}
                {pdcFields.collectionName && (
                  <div>
                    <label style={fieldLabelStyle}>Collection Name</label>
                    <input value={collectionName} onChange={(e) => setCollectionName(e.target.value)} style={inputStyle} placeholder="automation-collection" />
                  </div>
                )}
                {pdcFields.scopeIds && (
                  <div>
                    <label style={fieldLabelStyle}>Scope IDs (comma-separated){OPTIONAL_JOBS.has(selectedPdcAction) ? ' *' : ''}</label>
                    <input value={scopeIds} onChange={(e) => setScopeIds(e.target.value)} style={inputStyle} placeholder="uuid1,uuid2" />
                  </div>
                )}
                {pdcFields.entityId && (
                  <div>
                    <label style={fieldLabelStyle}>Entity ID *</label>
                    <input value={entityId} onChange={(e) => setEntityId(e.target.value)} style={inputStyle} placeholder="Required" />
                  </div>
                )}
                {pdcFields.tags && (
                  <div>
                    <label style={fieldLabelStyle}>Tags (comma-separated)</label>
                    <input value={tagsCsv} onChange={(e) => setTagsCsv(e.target.value)} style={inputStyle} placeholder="pii,sensitive" />
                  </div>
                )}
              </div>
            )}

            <div style={{ display: 'flex', alignItems: 'center', gap: 20, flexWrap: 'wrap' }}>
              <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, color: '#5a6c7d', cursor: 'pointer' }}>
                <input type="checkbox" checked={dryRun} onChange={(e) => setDryRun(e.target.checked)} />
                Dry Run
              </label>
              <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, color: '#5a6c7d', cursor: 'pointer' }}>
                <input type="checkbox" checked={useAdvancedPayload} onChange={(e) => setUseAdvancedPayload(e.target.checked)} />
                Override payload JSON
              </label>
            </div>

            {useAdvancedPayload && (
              <textarea
                value={pdcPayloadJson}
                onChange={(e) => setPdcPayloadJson(e.target.value)}
                style={textareaStyle}
                placeholder={'{"scope": ["uuid"], "configs": {}}'}
              />
            )}

            {pdcError && <div style={{ color: '#c0392b', fontSize: 12 }}>{pdcError}</div>}

            <div>
              <button
                onClick={() => runPdc()}
                style={{ ...btn, background: '#1f6feb', padding: '10px 22px', fontSize: 14 }}
                title={selectedActionMeta?.description}
              >
                <span style={iconCircle}>▶</span> Run {selectedActionMeta?.label}
              </button>
            </div>
          </div>
        </div>
      </div>
      )}

      {sshInfo && (
        <div style={card}>
          <div style={cardHeader}>SSH Commands</div>
          <div style={{ padding: '12px 16px' }}>
            {sshInfo.instance_ssh && (
              <div style={{ marginBottom: 8 }}>
                <span style={{ fontSize: 11, fontWeight: 600, color: '#888', textTransform: 'uppercase' }}>Instance</span>
                <code style={codeStyle}>{sshInfo.instance_ssh}</code>
              </div>
            )}
            {sshInfo.container_ssh && (
              <div>
                <span style={{ fontSize: 11, fontWeight: 600, color: '#888', textTransform: 'uppercase' }}>Container</span>
                <code style={codeStyle}>{sshInfo.container_ssh}</code>
              </div>
            )}
            {!sshInfo.instance_ssh && <div style={{ color: '#999', fontSize: 13 }}>No SSH info available.</div>}
          </div>
        </div>
      )}

      <Terminal jobId={jobId} onClose={() => setJobId(null)} />
    </div>
  );
}

/* ── Styles ──────────────────────────────────────────────────────────────── */

const fieldLabelStyle: React.CSSProperties = {
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
  border: '1px solid #ddd',
  fontSize: 14,
  background: '#fff',
};

const card: React.CSSProperties = {
  background: '#fff',
  borderRadius: 8,
  boxShadow: '0 1px 3px rgba(0,0,0,0.08)',
  marginBottom: 16,
  overflow: 'hidden',
};

const cardHeader: React.CSSProperties = {
  fontSize: 11,
  fontWeight: 700,
  color: '#8e9eab',
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

const comboGroup: React.CSSProperties = {
  display: 'inline-flex',
  borderRadius: 6,
  overflow: 'hidden',
};

const comboSelect: React.CSSProperties = {
  border: 'none',
  borderLeft: '1px solid rgba(255,255,255,0.25)',
  background: '#004999',
  color: '#fff',
  fontSize: 12,
  padding: '0 10px',
  cursor: 'pointer',
  outline: 'none',
};

const codeStyle: React.CSSProperties = {
  display: 'block',
  background: '#f4f5f7',
  padding: '6px 10px',
  borderRadius: 4,
  fontFamily: 'Menlo, Monaco, monospace',
  fontSize: 12,
  marginTop: 4,
  wordBreak: 'break-all',
};

const helpStyle: React.CSSProperties = {
  color: '#7b8a97',
  fontSize: 12,
  marginTop: -2,
};

const inputStyle: React.CSSProperties = {
  display: 'block',
  width: '100%',
  padding: '8px 12px',
  borderRadius: 6,
  border: '1px solid #ddd',
  fontSize: 13,
  background: '#fff',
};

const formGridStyle: React.CSSProperties = {
  display: 'grid',
  gridTemplateColumns: 'repeat(auto-fit, minmax(260px, 1fr))',
  gap: 10,
};

const textareaStyle: React.CSSProperties = {
  width: '100%',
  minHeight: 90,
  padding: '8px 10px',
  borderRadius: 6,
  border: '1px solid #ddd',
  fontFamily: 'Menlo, Monaco, "Courier New", monospace',
  fontSize: 12,
  lineHeight: 1.4,
  resize: 'vertical',
};
