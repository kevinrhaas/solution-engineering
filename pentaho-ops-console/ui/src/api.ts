const BASE = '/api';

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    headers: { 'Content-Type': 'application/json' },
    ...init,
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`${res.status}: ${body}`);
  }
  return res.json();
}

// ── Types ────────────────────────────────────────────────────────────────────

export interface Job {
  id: string;
  script: string;
  args: string[];
  status: 'pending' | 'running' | 'completed' | 'failed' | 'cancelled';
  exit_code: number | null;
  started_at: number | null;
  finished_at: number | null;
  output_lines: number;
}

export interface Profile {
  name: string;
  filename: string;
  config: Record<string, string>;
  state: Record<string, string> | null;
  instances: InstanceSummary[];
  raw: string;
}

export interface ProfileSummary {
  name: string;
  filename: string;
  pentaho_version: string;
  pdc_version: string;
  instance_type: string;
  environment: string;
  instance_ip: string;
  instance_id: string;
  instance_state: string;
  deploy_phase: string;
  created_date: string;
  state_file: string;
  has_state: boolean;
}

export interface SshInfo {
  instance_ssh: string | null;
  container_ssh: string | null;
  instance_ip: string | null;
  key_file: string | null;
}

export interface PdcAutomationAction {
  action: string;
  script: string;
  label: string;
  description: string;
}

export interface RunPdcAutomationRequest {
  stateFile?: string;
  payloadJson?: string;
  params?: Record<string, string>;
}

export interface InstanceSummary {
  name: string;
  state_file: string;
  instance_id: string;
  instance_ip: string;
  instance_state: string;
  created_date: string;
  db_type: string;
  deploy_phase: string;
  pentaho_url: string;
  pentaho_version: string;
  pdc_version?: string;
  instance_type: string;
  environment: string;
  has_profile: boolean;
  server_url: string;
  server_type: string;
  // EC2 discovery fields
  tracking_status?: 'tracked' | 'untracked';
  ec2_tags?: Record<string, string>;
  public_ip?: string;
}

export interface AwsDiscoveryError {
  code: 'auth_expired' | 'auth_invalid' | 'no_credentials' | 'access_denied' | 'other';
  message: string;
  detail?: string;
  profile?: string;
  region?: string;
}

export interface Ec2DiscoveryResult {
  tracked: InstanceSummary[];
  untracked: InstanceSummary[];
  aws_error?: AwsDiscoveryError | null;
}

export interface ContentPreviewStartRequest {
  server_url: string;
  server_type?: string;
  username?: string;
  password?: string;
  instance_name?: string;
}

export interface ContentPreviewSection {
  [key: string]: unknown;
}

export interface ContentPreviewReport {
  kind: 'pentaho' | 'pdc';
  target: string;
  summary: Record<string, unknown>;
  navigator: { id: string; label: string }[];
  sections: Record<string, ContentPreviewSection>;
}

export interface ContentPreviewStatus {
  id: string;
  status: 'pending' | 'running' | 'completed' | 'failed';
  phase: string;
  progress: number;
  message: string;
  error: string;
  instance_name: string;
  server_url: string;
  server_type: string;
  started_at: number;
  finished_at: number | null;
  report: ContentPreviewReport | null;
  logs: { ts: number; text: string }[];
}

// ── Jobs ─────────────────────────────────────────────────────────────────────

export const listJobs = () => request<Job[]>('/jobs');
export const getJob = (id: string) => request<Job>(`/jobs/${id}`);
export const cancelJob = (id: string) =>
  request<{ cancelled: boolean }>(`/jobs/${id}/cancel`, { method: 'POST' });

export function streamJob(
  jobId: string,
  onLine: (line: { stream: string; text: string }) => void,
  onDone?: () => void,
) {
  const es = new EventSource(`${BASE}/jobs/${jobId}/stream`);
  es.onmessage = (e) => {
    if (e.data === '[DONE]') {
      es.close();
      onDone?.();
      return;
    }
    try {
      onLine(JSON.parse(e.data));
    } catch {
      // ignore parse errors
    }
  };
  es.onerror = () => {
    es.close();
    onDone?.();
  };
  return () => es.close();
}

// ── Profiles ─────────────────────────────────────────────────────────────────

export const listProfiles = () => request<ProfileSummary[]>('/profiles');
export const listInstances = () => request<InstanceSummary[]>('/profiles/instances');
export const discoverEc2Instances = () => request<Ec2DiscoveryResult>('/profiles/instances/ec2');
export const getProfile = (name: string) => request<Profile>(`/profiles/${name}`);
export const createProfile = (name: string, raw: string) =>
  request<Profile>('/profiles', {
    method: 'POST',
    body: JSON.stringify({ name, raw }),
  });
export const updateProfile = (name: string, raw: string) =>
  request<Profile>(`/profiles/${name}`, {
    method: 'PUT',
    body: JSON.stringify({ raw }),
  });
export const duplicateProfile = (name: string, newName: string) =>
  request<Profile>(`/profiles/${name}/duplicate`, {
    method: 'POST',
    body: JSON.stringify({ new_name: newName }),
  });
export const renameProfile = (name: string, newName: string) =>
  request<Profile>(`/profiles/${name}/rename`, {
    method: 'PUT',
    body: JSON.stringify({ new_name: newName }),
  });
export const deleteProfile = (name: string) =>
  request<{ status: string }>(`/profiles/${name}`, { method: 'DELETE' });

export const deleteInstance = (stateFile: string) =>
  request<{ status: string }>(`/profiles/instances/${encodeURIComponent(stateFile)}`, { method: 'DELETE' });

export const checkHealth = (url: string) =>
  request<{ url: string; reachable: boolean; status_code: number | null }>(`/profiles/instances/health?url=${encodeURIComponent(url)}`);

export const startContentPreview = (payload: ContentPreviewStartRequest) =>
  request<{ report_id: string }>('/profiles/instances/content-preview/start', {
    method: 'POST',
    body: JSON.stringify(payload),
  });

export const getContentPreviewStatus = (reportId: string) =>
  request<ContentPreviewStatus>(`/profiles/instances/content-preview/${encodeURIComponent(reportId)}`);

// ── Provision ────────────────────────────────────────────────────────────────

function provisionAction(action: string, profile: string, stateFile?: string) {
  const body: Record<string, string> = { profile };
  if (stateFile) body.state_file = stateFile;
  return request<{ job_id: string }>(`/provision/${action}`, {
    method: 'POST',
    body: JSON.stringify(body),
  });
}

export const preflight = (p: string) => provisionAction('preflight', p);
export const fullDeploy = (p: string) => provisionAction('full-deploy', p);
export const authenticate = (p: string) => provisionAction('auth', p);
export const createEc2 = (p: string) => provisionAction('create-ec2', p);
export const checkEc2 = (p: string, sf?: string) => provisionAction('check-ec2', p, sf);
export const deployPentaho = (p: string, sf?: string) => provisionAction('deploy-pentaho', p, sf);
export const deployPlugins = (p: string, sf?: string) => provisionAction('deploy-plugins', p, sf);
export const fullDeployPdc = (p: string) => provisionAction('full-deploy-pdc', p);
export const deployPdc = (p: string, sf?: string) => provisionAction('deploy-pdc', p, sf);
export const startEc2Instance = (p: string, sf?: string) => provisionAction('start-ec2', p, sf);
export const stopEc2Instance = (p: string, sf?: string) => provisionAction('stop-ec2', p, sf);
export const teardown = (p: string, sf?: string) => provisionAction('teardown', p, sf);

// ── SSH Key ──────────────────────────────────────────────────────────────────

export interface SshKeyStatus {
  keys: { name: string; size: number }[];
}

export const uploadSshKey = (filename: string, content: string) =>
  request<{ status: string; path: string }>('/config/ssh-key', {
    method: 'POST',
    body: JSON.stringify({ filename, content }),
  });

export const getSshKeyStatus = () =>
  request<SshKeyStatus>('/config/ssh-key/status');

// ── AWS Credentials ──────────────────────────────────────────────────────────

export interface AwsCredPaste {
  raw: string;
  region?: string;
}

export interface AwsCredStatus {
  configured: boolean;
  profiles: { name: string; has_key: boolean; has_session_token: boolean }[];
}

export interface AwsProfileVerifyResult {
  status: string;
  profile: string;
  account: string;
  arn: string;
  user_id: string;
}

export const syncAwsCredentials = (paste: AwsCredPaste) =>
  request<{ status: string; profiles: string[]; region: string }>('/config/aws-credentials', {
    method: 'POST',
    body: JSON.stringify(paste),
  });

export const getAwsCredStatus = () =>
  request<AwsCredStatus>('/config/aws-credentials/status');

export const verifyAwsProfile = (profile: string) =>
  request<AwsProfileVerifyResult>('/config/aws-credentials/verify', {
    method: 'POST',
    body: JSON.stringify({ profile }),
  });

export const purgeAwsCredentials = () =>
  request<{ status: string; removed: string[] }>('/config/aws-credentials', { method: 'DELETE' });

export const deleteAwsProfile = (profile: string) =>
  request<{ status: string; profile: string; removed_from: string[] }>(
    `/config/aws-credentials/${encodeURIComponent(profile)}`,
    { method: 'DELETE' },
  );

export const purgeSshKeys = () =>
  request<{ status: string; removed: string[] }>('/config/ssh-key', { method: 'DELETE' });

export const deleteSshKey = (filename: string) =>
  request<{ status: string; filename: string }>(
    `/config/ssh-key/${encodeURIComponent(filename)}`,
    { method: 'DELETE' },
  );

export const deleteGitToken = () =>
  request<{ status: string }>('/config/github-token', { method: 'DELETE' });

// ── Git Sync & App Management ────────────────────────────────────────────────

export interface GitTokenStatus {
  configured: boolean;
}

export interface GitStatus {
  branch: string;
  commit: string;
  commit_message: string;
  dirty: boolean;
}

export interface SyncResult {
  dry_run: boolean;
  results: { step: string; ok: boolean; output: string }[];
  restarted: boolean;
}

export const getGitStatus = () =>
  request<GitStatus>('/config/git/status');

export const getGitTokenStatus = () =>
  request<GitTokenStatus>('/config/github-token/status');

export const saveGitToken = (token: string) =>
  request<{ status: string }>('/config/github-token', {
    method: 'POST',
    body: JSON.stringify({ token }),
  });

export const syncApp = (dryRun: boolean = false) =>
  request<SyncResult>('/config/sync', {
    method: 'POST',
    body: JSON.stringify({ dry_run: dryRun }),
  });

export const restartApp = () =>
  request<{ status: string }>('/config/restart', { method: 'POST' });

// ── Migration ────────────────────────────────────────────────────────────────

export interface PdcFullMigrationRequest {
  source_ip: string;
  target_ip: string;
  source_env_file: string;
  target_env_file?: string;
  source_user?: string;
  target_user?: string;
  dry_run?: boolean;
  stop_source?: boolean;
}

export const pdcFullMigration = (payload: PdcFullMigrationRequest) =>
  request<{ job_id: string }>('/migrate/pdc/full', {
    method: 'POST',
    body: JSON.stringify(payload),
  });

// ── Bulk Job Delete ──────────────────────────────────────────────────────────

export const bulkDeleteJobs = (ids: string[]) =>
  request<{ deleted: string[]; skipped: string[] }>('/jobs/bulk-delete', {
    method: 'POST',
    body: JSON.stringify({ ids }),
  });

// ── Import / Export ───────────────────────────────────────────────────────────

export type ExportInclude = 'profiles' | 'instances' | 'jobs' | 'secrets' | 'settings';
export type ImportStrategy = 'merge' | 'overwrite';

export interface ExportBundle {
  exported_at: string;
  app_version: string;
  include: ExportInclude[];
  profiles?: unknown[];
  instances?: unknown[];
  jobs?: unknown[];
  secrets?: unknown[];
  settings?: unknown[];
}

export interface ImportStats {
  profiles?: number;
  instances?: number;
  secrets?: number;
  settings?: number;
}

export const exportData = (include: ExportInclude[]) =>
  request<ExportBundle>('/config/export', {
    method: 'POST',
    body: JSON.stringify({ include }),
  });

export const importData = (bundle: ExportBundle, strategy: ImportStrategy) =>
  request<{ status: string; strategy: string; stats: ImportStats }>('/config/import', {
    method: 'POST',
    body: JSON.stringify({ bundle, strategy }),
  });


// ── Manage ───────────────────────────────────────────────────────────────────

function manageAction(action: string, profile: string, stateFile?: string) {
  const body: Record<string, string> = { profile };
  if (stateFile) body.state_file = stateFile;
  return request<{ job_id: string }>(`/manage/${action}`, {
    method: 'POST',
    body: JSON.stringify(body),
  });
}

export const restartContainer = (p: string, sf?: string) => manageAction('restart', p, sf);
export const startContainer = (p: string, sf?: string) => manageAction('up', p, sf);
export const stopContainer = (p: string, sf?: string) => manageAction('down', p, sf);
export const pdcRestart = (p: string, sf?: string) => manageAction('pdc-restart', p, sf);
export const tailCatalina = (p: string, lines?: string, stateFile?: string) => {
  const body: Record<string, string> = { profile: p };
  if (lines) body.lines = lines;
  if (stateFile) body.state_file = stateFile;
  return request<{ job_id: string }>('/manage/logs/catalina', {
    method: 'POST',
    body: JSON.stringify(body),
  });
};
export const dockerLogs = (p: string, duration?: string, stateFile?: string) => {
  const body: Record<string, string> = { profile: p };
  if (duration) body.duration = duration;
  if (stateFile) body.state_file = stateFile;
  return request<{ job_id: string }>('/manage/logs/docker', {
    method: 'POST',
    body: JSON.stringify(body),
  });
};
export const monitorResources = (p: string, sf?: string) => manageAction('monitor', p, sf);
export const diagnoseContainer = (p: string, sf?: string) => manageAction('diagnose', p, sf);
export const getSshInfo = (profile: string, stateFile?: string) =>
  request<SshInfo>(`/manage/ssh-command/${profile}${stateFile ? `?state_file=${encodeURIComponent(stateFile)}` : ''}`);

export const listPdcAutomationActions = () =>
  request<PdcAutomationAction[]>('/manage/pdc-automation/actions');

export interface PdcDatasource {
  _id: string;
  resourceName: string;
  databaseType: string;
  pId: string | number;
}

export interface ResolvedPdcDatasource {
  _id: string;
  resourceName: string;
  databaseType: string;
  matches: PdcDatasource[];
}

export const listPdcDatasources = (profile: string, stateFile?: string, query?: string) =>
  request<PdcDatasource[]>(
    `/manage/pdc-datasources?profile=${encodeURIComponent(profile)}${stateFile ? `&state_file=${encodeURIComponent(stateFile)}` : ''}${query ? `&query=${encodeURIComponent(query)}` : ''}`,
  );

export const resolvePdcDatasource = (profile: string, name: string, stateFile?: string) =>
  request<ResolvedPdcDatasource>(
    `/manage/pdc-datasource-resolve?profile=${encodeURIComponent(profile)}&name=${encodeURIComponent(name)}${stateFile ? `&state_file=${encodeURIComponent(stateFile)}` : ''}`,
  );

export const runPdcAutomationAction = (
  profile: string,
  action: string,
  req: RunPdcAutomationRequest = {},
) => {
  const body: Record<string, unknown> = { profile, action };
  if (req.stateFile) body.state_file = req.stateFile;
  if (req.payloadJson) body.payload_json = req.payloadJson;
  if (req.params && Object.keys(req.params).length > 0) body.params = req.params;
  return request<{ job_id: string }>('/manage/pdc-automation/run', {
    method: 'POST',
    body: JSON.stringify(body),
  });
};

// ── Migrate ──────────────────────────────────────────────────────────────────

export interface MigrateFullParams {
  source_url: string;
  target_url: string;
  source_user?: string;
  source_pass?: string;
  target_user?: string;
  target_pass?: string;
  dry_run?: boolean;
  skip_home?: boolean;
  skip_content?: boolean;
  skip_ds?: boolean;
}

export const fullMigration = (params: MigrateFullParams) =>
  request<{ job_id: string }>('/migrate/full', {
    method: 'POST',
    body: JSON.stringify(params),
  });

export interface ContentParams {
  server_url: string;
  user?: string;
  password?: string;
  path?: string;
}

export const pullContent = (p: ContentParams) =>
  request<{ job_id: string }>('/migrate/content/pull', {
    method: 'POST',
    body: JSON.stringify(p),
  });

export const pushContent = (p: ContentParams) =>
  request<{ job_id: string }>('/migrate/content/push', {
    method: 'POST',
    body: JSON.stringify(p),
  });

export interface ServerParams {
  server_url: string;
  user?: string;
  password?: string;
}

export const pullDatasources = (p: ServerParams) =>
  request<{ job_id: string }>('/migrate/datasources/pull', {
    method: 'POST',
    body: JSON.stringify(p),
  });

export const pushDatasources = (p: ServerParams) =>
  request<{ job_id: string }>('/migrate/datasources/push', {
    method: 'POST',
    body: JSON.stringify(p),
  });

export const pullHome = (p: ServerParams) =>
  request<{ job_id: string }>('/migrate/home/pull', {
    method: 'POST',
    body: JSON.stringify(p),
  });

export const pushHome = (p: ServerParams) =>
  request<{ job_id: string }>('/migrate/home/push', {
    method: 'POST',
    body: JSON.stringify(p),
  });
