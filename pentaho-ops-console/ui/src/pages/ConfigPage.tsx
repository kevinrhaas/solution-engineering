import { useEffect, useState } from 'react';
import {
  syncAwsCredentials,
  getAwsCredStatus,
  verifyAwsProfile,
  purgeAwsCredentials,
  deleteAwsProfile,
  uploadSshKey,
  getSshKeyStatus,
  purgeSshKeys,
  deleteSshKey,
  getGitStatus,
  getGitSource,
  getGitTokenStatus,
  saveGitSource,
  saveGitToken,
  deleteGitToken,
  syncApp,
  restartApp,
  exportData,
  importData,
} from '../api';
import type { AwsCredStatus, AwsProfileVerifyResult, SshKeyStatus, GitStatus, GitTokenStatus, SyncResult, ExportInclude, ExportBundle } from '../api';

export default function ConfigPage() {
  // AWS credential sync state
  const [credStatus, setCredStatus] = useState<AwsCredStatus | null>(null);
  const [showCredForm, setShowCredForm] = useState(false);
  const [credPaste, setCredPaste] = useState('');
  const [credRegion, setCredRegion] = useState('us-east-1');
  const [authProfile, setAuthProfile] = useState('khaas');
  const [credMsg, setCredMsg] = useState('');
  const [credSyncing, setCredSyncing] = useState(false);
  const [authBusy, setAuthBusy] = useState(false);
  const [authMsg, setAuthMsg] = useState('');

  // SSH key state
  const [keyStatus, setKeyStatus] = useState<SshKeyStatus | null>(null);
  const [showKeyForm, setShowKeyForm] = useState(false);
  const [keyFilename, setKeyFilename] = useState('pentaho+_se_keypair.pem');
  const [keyPaste, setKeyPaste] = useState('');
  const [keyMsg, setKeyMsg] = useState('');
  const [keyUploading, setKeyUploading] = useState(false);

  // Git sync state
  const [gitStatus, setGitStatus] = useState<GitStatus | null>(null);
  const [tokenStatus, setTokenStatus] = useState<GitTokenStatus | null>(null);
  const [gitRepo, setGitRepo] = useState('kevinrhaas/solution-engineering');
  const [gitBranch, setGitBranch] = useState('main');
  const [gitSourceSaving, setGitSourceSaving] = useState(false);
  const [gitSourceMsg, setGitSourceMsg] = useState('');
  const [showTokenForm, setShowTokenForm] = useState(false);
  const [tokenPaste, setTokenPaste] = useState('');
  const [tokenMsg, setTokenMsg] = useState('');
  const [tokenSaving, setTokenSaving] = useState(false);
  const [syncing, setSyncing] = useState(false);
  const [syncResult, setSyncResult] = useState<SyncResult | null>(null);
  const [restarting, setRestarting] = useState(false);
  const [restartMsg, setRestartMsg] = useState('');

  // Import / Export state
  const allExportItems: ExportInclude[] = ['profiles', 'instances', 'jobs', 'secrets', 'settings'];
  const [exportInclude, setExportInclude] = useState<Set<ExportInclude>>(
    new Set(['profiles', 'instances', 'secrets']),
  );
  const [exporting, setExporting] = useState(false);
  const [exportMsg, setExportMsg] = useState('');
  const [importFile, setImportFile] = useState<File | null>(null);
  const [importStrategy, setImportStrategy] = useState<'merge' | 'overwrite'>('merge');
  const [importing, setImporting] = useState(false);
  const [importMsg, setImportMsg] = useState('');

  useEffect(() => {
    getAwsCredStatus().then(setCredStatus).catch(() => {});
    getSshKeyStatus().then(setKeyStatus).catch(() => {});
    getGitStatus().then((status) => {
      setGitStatus(status);
      setGitRepo(status.source_repo);
      setGitBranch(status.source_branch);
    }).catch(() => {});
    getGitTokenStatus().then(setTokenStatus).catch(() => {});
  }, []);

  useEffect(() => {
    getGitSource()
      .then((source) => {
        setGitRepo(source.repo);
        setGitBranch(source.branch);
      })
      .catch(() => {});
  }, []);

  useEffect(() => {
    if (!authProfile && credStatus?.profiles?.length) {
      setAuthProfile(credStatus.profiles[0].name);
    }
  }, [authProfile, credStatus]);

  const oktaCommand = `okta-aws ${authProfile || 'khaas'} sts get-caller-identity`;

  async function handleCopyOktaCommand() {
    try {
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(oktaCommand);
        setAuthMsg('Authenticate copied the local Okta command. Run it in your local terminal, complete browser MFA, then sync credentials to the server.');
        return;
      }

      window.prompt('Copy and run this command in your local terminal:', oktaCommand);
      setAuthMsg('Authenticate opened the local Okta command for manual copy. Run it locally, complete browser MFA, then sync credentials to the server.');
    } catch (e: unknown) {
      setAuthMsg(`Error: ${e}`);
    }
  }

  async function handleVerifyAwsProfile() {
    if (!authProfile.trim()) return;
    setAuthBusy(true);
    setAuthMsg('');
    try {
      const result: AwsProfileVerifyResult = await verifyAwsProfile(authProfile.trim());
      const identity = [result.account, result.arn].filter(Boolean).join(' • ');
      setAuthMsg(`Verify Profile confirmed the server can use ${result.profile}: ${identity || result.profile}`);
      const status = await getAwsCredStatus();
      setCredStatus(status);
    } catch (e: unknown) {
      const message = String(e);
      if (message.includes('InvalidClientTokenId') || message.includes('security token included in the request is invalid')) {
        setAuthMsg(`Verify Profile failed because the server-side AWS session for ${authProfile.trim()} is invalid or expired. Refresh locally with okta-aws, then sync ~/.aws/credentials to the server again.`);
      } else {
        setAuthMsg(`Error: ${e}`);
      }
    } finally {
      setAuthBusy(false);
    }
  }

  async function handleCredSync() {
    if (!credPaste.trim()) return;
    setCredSyncing(true);
    setCredMsg('');
    try {
      const result = await syncAwsCredentials({ raw: credPaste, region: credRegion });
      setCredMsg(`Synced ${result.profiles.length} profile(s): ${result.profiles.join(', ')} (${result.region})`);
      setShowCredForm(false);
      setCredPaste('');
      const status = await getAwsCredStatus();
      setCredStatus(status);
    } catch (e: unknown) {
      setCredMsg(`Error: ${e}`);
    } finally {
      setCredSyncing(false);
    }
  }

  async function handleKeyUpload() {
    if (!keyPaste.trim() || !keyFilename.trim()) return;
    setKeyUploading(true);
    setKeyMsg('');
    try {
      const result = await uploadSshKey(keyFilename.trim(), keyPaste);
      setKeyMsg(`Uploaded: ${result.path}`);
      setShowKeyForm(false);
      setKeyPaste('');
      const status = await getSshKeyStatus();
      setKeyStatus(status);
    } catch (e: unknown) {
      setKeyMsg(`Error: ${e}`);
    } finally {
      setKeyUploading(false);
    }
  }

  async function handleTokenSave() {
    if (!tokenPaste.trim()) return;
    setTokenSaving(true);
    setTokenMsg('');
    try {
      const result = await saveGitToken(tokenPaste.trim());
      setTokenMsg(`Token saved — verified access as ${(result as Record<string, string>).user || 'user'}`);
      setShowTokenForm(false);
      setTokenPaste('');
      const status = await getGitTokenStatus();
      setTokenStatus(status);
    } catch (e: unknown) {
      setTokenMsg(`${e}`);
    } finally {
      setTokenSaving(false);
    }
  }

  async function handleGitSourceSave() {
    if (!gitRepo.trim() || !gitBranch.trim()) return;
    setGitSourceSaving(true);
    setGitSourceMsg('');
    try {
      const result = await saveGitSource(gitRepo.trim(), gitBranch.trim());
      setGitRepo(result.repo);
      setGitBranch(result.branch);
      setGitSourceMsg(`App sync source saved: ${result.repo}@${result.branch}`);
      const status = await getGitStatus();
      setGitStatus(status);
    } catch (e: unknown) {
      setGitSourceMsg(`Error: ${e}`);
    } finally {
      setGitSourceSaving(false);
    }
  }

  async function handleSync(dryRun: boolean) {
    setSyncing(true);
    setSyncResult(null);
    try {
      const result = await syncApp(dryRun);
      setSyncResult(result);
      // Refresh git status after sync
      getGitStatus().then((status) => {
        setGitStatus(status);
        setGitRepo(status.source_repo);
        setGitBranch(status.source_branch);
      }).catch(() => {});
    } catch (e: unknown) {
      setSyncResult({ dry_run: dryRun, results: [{ step: 'sync', ok: false, output: String(e) }], restarted: false });
    } finally {
      setSyncing(false);
    }
  }

  async function handlePurgeCreds() {
    if (!window.confirm('Remove ALL AWS credentials and config from the server? You will need to re-sync them before provisioning.')) return;
    setCredMsg('');
    try {
      const r = await purgeAwsCredentials();
      setCredMsg(`Purged: ${r.removed.length ? r.removed.join(', ') : 'nothing to remove'}`);
      const status = await getAwsCredStatus();
      setCredStatus(status);
    } catch (e: unknown) {
      setCredMsg(`Error: ${e}`);
    }
  }

  async function handleDeleteAwsProfile(name: string) {
    if (!window.confirm(`Remove the AWS profile "${name}"?`)) return;
    setCredMsg('');
    try {
      const r = await deleteAwsProfile(name);
      setCredMsg(`Removed profile "${r.profile}" from ${r.removed_from.join(' & ')}`);
      const status = await getAwsCredStatus();
      setCredStatus(status);
    } catch (e: unknown) {
      setCredMsg(`Error: ${e}`);
    }
  }

  async function handlePurgeKeys() {
    if (!window.confirm('Remove ALL SSH .pem keys from the server? You will need to re-upload before provisioning.')) return;
    setKeyMsg('');
    try {
      const r = await purgeSshKeys();
      setKeyMsg(`Removed ${r.removed.length} key(s)${r.removed.length ? ': ' + r.removed.join(', ') : ''}`);
      const status = await getSshKeyStatus();
      setKeyStatus(status);
    } catch (e: unknown) {
      setKeyMsg(`Error: ${e}`);
    }
  }

  async function handleDeleteKey(filename: string) {
    if (!window.confirm(`Remove SSH key "${filename}"?`)) return;
    setKeyMsg('');
    try {
      await deleteSshKey(filename);
      setKeyMsg(`Removed ${filename}`);
      const status = await getSshKeyStatus();
      setKeyStatus(status);
    } catch (e: unknown) {
      setKeyMsg(`Error: ${e}`);
    }
  }

  async function handleDeleteToken() {
    if (!window.confirm('Remove the saved GitHub token? Auto-updates will stop working until a new token is configured.')) return;
    setTokenMsg('');
    try {
      await deleteGitToken();
      setTokenMsg('Token removed');
      const status = await getGitTokenStatus();
      setTokenStatus(status);
    } catch (e: unknown) {
      setTokenMsg(`Error: ${e}`);
    }
  }

  async function handleRestart() {
    setRestarting(true);
    setRestartMsg('');
    try {
      await restartApp();
      setRestartMsg('Service restarted successfully');
    } catch (e: unknown) {
      setRestartMsg(`Error: ${e}`);
    } finally {
      setRestarting(false);
    }
  }

  async function handleExport() {
    setExporting(true);
    setExportMsg('');
    try {
      const include = Array.from(exportInclude) as ExportInclude[];
      const bundle = await exportData(include);
      const blob = new Blob([JSON.stringify(bundle, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `ops-console-export-${new Date().toISOString().slice(0, 10)}.json`;
      a.click();
      URL.revokeObjectURL(url);
      setExportMsg(`Exported: ${include.join(', ')}`);
    } catch (e: unknown) {
      setExportMsg(`Error: ${e}`);
    } finally {
      setExporting(false);
    }
  }

  async function handleImport() {
    if (!importFile) return;
    setImporting(true);
    setImportMsg('');
    try {
      const text = await importFile.text();
      const bundle: ExportBundle = JSON.parse(text);
      const result = await importData(bundle, importStrategy);
      const statParts = Object.entries(result.stats)
        .map(([k, v]) => `${v} ${k}`)
        .join(', ');
      setImportMsg(`Imported (${result.strategy}): ${statParts || 'nothing new'}`);
      setImportFile(null);
    } catch (e: unknown) {
      setImportMsg(`Error: ${e}`);
    } finally {
      setImporting(false);
    }
  }

  return (
    <div>
      <h2>Config</h2>
      <p style={{ color: '#8e9eab', marginBottom: 16, fontSize: 13 }}>
        Set up the AWS credentials and SSH keys needed to provision and manage instances.
      </p>

      {/* AWS Credentials Section */}
      <div style={sectionBox}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 8 }}>
          <span style={{ fontWeight: 600, fontSize: 14 }}>AWS Credentials</span>
          {credStatus && (
            <span style={{ fontSize: 12, color: credStatus.configured ? '#27ae60' : '#e67e22' }}>
              {credStatus.configured
                ? `${credStatus.profiles.length} profile(s) configured`
                : 'not configured'}
            </span>
          )}
          <button onClick={() => setShowCredForm(!showCredForm)} style={smallBtn} title="Push AWS credentials to the ops-console server">
            {showCredForm ? 'Cancel' : 'Sync Credentials'}
          </button>
          <button onClick={handleCopyOktaCommand} style={smallBtn} title="Copy the local okta-aws command used to refresh your browser-backed AWS session">
            Authenticate
          </button>
          <button
            onClick={handleVerifyAwsProfile}
            disabled={authBusy || !authProfile.trim()}
            style={smallBtn}
            title="Verify that the selected AWS profile already synced to the server can call STS"
          >
            {authBusy ? 'Verifying…' : 'Verify Profile'}
          </button>
          {credStatus?.configured && (
            <button onClick={handlePurgeCreds} style={dangerBtn} title="Remove all AWS credentials and config from the server">
              Purge All
            </button>
          )}
        </div>

        <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap', marginBottom: 8 }}>
          <input
            value={authProfile}
            onChange={(e) => setAuthProfile(e.target.value)}
            placeholder="Okta/AWS profile (e.g. khaas)"
            style={{ ...inputStyle, width: 220 }}
          />
          <span style={{ fontSize: 12, color: '#666' }}>
            Local refresh command: <code style={{ fontSize: 11 }}>{oktaCommand}</code>
          </span>
        </div>

        <div style={{ fontSize: 12, color: '#666', lineHeight: 1.5, maxWidth: 760 }}>
          Authenticate is a local helper only: it gives you the <code style={{ fontSize: 11 }}>okta-aws</code> command to run on your machine so the browser MFA flow can happen there. Verify Profile is server-side: it tests whether the synced AWS profile already on the ops-console server can call STS successfully.
        </div>

        {credStatus?.profiles && credStatus.profiles.length > 0 && !showCredForm && (
          <div style={{ fontSize: 12, color: '#666', display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            {credStatus.profiles.map((p) => (
              <span key={p.name} style={{ display: 'inline-flex', alignItems: 'center', gap: 4, padding: '3px 6px 3px 10px', border: '1px solid #e0e0e0', borderRadius: 12, background: '#fafafa' }}>
                <strong>{p.name}</strong>
                <span style={{ color: '#888' }}>
                  {p.has_session_token ? ' (session)' : ' (permanent)'}
                </span>
                <button
                  onClick={() => handleDeleteAwsProfile(p.name)}
                  style={chipDeleteBtn}
                  title={`Remove the ${p.name} AWS profile`}
                >
                  ✕
                </button>
              </span>
            ))}
          </div>
        )}

        {showCredForm && (
          <div style={{ marginTop: 8, maxWidth: 560 }}>
            <p style={{ fontSize: 12, color: '#666', marginBottom: 8 }}>
              Paste your AWS credentials below. To refresh them locally via Okta SSO:
            </p>
            <pre style={codeHint}>{oktaCommand}</pre>
            <p style={{ fontSize: 11, color: '#999', margin: '4px 0 4px' }}>
              Complete the browser login and MFA flow, then copy the credentials file:
            </p>
            <pre style={codeHint}>cat ~/.aws/credentials</pre>
            <p style={{ fontSize: 11, color: '#999', margin: '4px 0 8px' }}>
              Accepts INI format (from ~/.aws/credentials), env exports, or JSON (STS output). The pasted credentials are written to the ops-console server under ~/.aws/.
            </p>
            <div style={{ display: 'flex', gap: 8, marginBottom: 8 }}>
              <input
                placeholder="Region (us-east-1)"
                value={credRegion}
                onChange={(e) => setCredRegion(e.target.value)}
                style={{ ...inputStyle, width: 140 }}
              />
            </div>
            <textarea
              placeholder={`[khaas]\naws_access_key_id = ASIA...\naws_secret_access_key = ...\naws_session_token = ...`}
              value={credPaste}
              onChange={(e) => setCredPaste(e.target.value)}
              rows={10}
              style={{ ...inputStyle, width: '100%', resize: 'vertical' }}
            />
            <button
              onClick={handleCredSync}
              disabled={credSyncing || !credPaste.trim()}
              style={{ ...primaryBtn, marginTop: 8, width: 'fit-content' }}
              title="Upload these AWS credentials to the ops-console server"
            >
              {credSyncing ? 'Syncing…' : 'Push Credentials to Server'}
            </button>
          </div>
        )}

        {credMsg && (
          <div style={{ marginTop: 8, fontSize: 12, color: credMsg.startsWith('Error') ? '#c0392b' : '#27ae60' }}>
            {credMsg}
          </div>
        )}

        {authMsg && (
          <div style={{ marginTop: 8, fontSize: 12, color: authMsg.startsWith('Error') ? '#c0392b' : '#27ae60' }}>
            {authMsg}
          </div>
        )}
      </div>

      {/* SSH Key Section */}
      <div style={sectionBox}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 8 }}>
          <span style={{ fontWeight: 600, fontSize: 14 }}>SSH Key</span>
          {keyStatus && (
            <span style={{ fontSize: 12, color: keyStatus.keys.length > 0 ? '#27ae60' : '#e67e22' }}>
              {keyStatus.keys.length > 0
                ? `${keyStatus.keys.length} key(s) installed`
                : 'no keys'}
            </span>
          )}
          <button onClick={() => setShowKeyForm(!showKeyForm)} style={smallBtn} title="Upload an SSH private key (.pem) to the server">
            {showKeyForm ? 'Cancel' : 'Upload Key'}
          </button>
          {keyStatus && keyStatus.keys.length > 0 && (
            <button onClick={handlePurgeKeys} style={dangerBtn} title="Remove all SSH keys from the server">
              Purge All
            </button>
          )}
        </div>

        {keyStatus?.keys && keyStatus.keys.length > 0 && !showKeyForm && (
          <div style={{ fontSize: 12, color: '#666', display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            {keyStatus.keys.map((k) => (
              <span key={k.name} style={{ display: 'inline-flex', alignItems: 'center', gap: 4, padding: '3px 6px 3px 10px', border: '1px solid #e0e0e0', borderRadius: 12, background: '#fafafa' }}>
                <strong>{k.name}</strong> <span style={{ color: '#888' }}>({Math.round(k.size / 1024)}KB)</span>
                <button
                  onClick={() => handleDeleteKey(k.name)}
                  style={chipDeleteBtn}
                  title={`Remove the ${k.name} SSH key`}
                >
                  ✕
                </button>
              </span>
            ))}
          </div>
        )}

        {showKeyForm && (
          <div style={{ marginTop: 8, maxWidth: 560 }}>
            <p style={{ fontSize: 12, color: '#666', marginBottom: 8 }}>
              Paste your PEM private key below. Copy it locally with:
            </p>
            <pre style={codeHint}>cat ~/.ssh/pentaho+_se_keypair.pem</pre>
            <div style={{ display: 'flex', gap: 8, margin: '8px 0' }}>
              <input
                placeholder="Filename (e.g. pentaho+_se_keypair.pem)"
                value={keyFilename}
                onChange={(e) => setKeyFilename(e.target.value)}
                style={{ ...inputStyle, flex: 1 }}
              />
            </div>
            <textarea
              placeholder="-----BEGIN RSA PRIVATE KEY-----&#10;...&#10;-----END RSA PRIVATE KEY-----"
              value={keyPaste}
              onChange={(e) => setKeyPaste(e.target.value)}
              rows={8}
              style={{ ...inputStyle, width: '100%', resize: 'vertical' }}
            />
            <button
              onClick={handleKeyUpload}
              disabled={keyUploading || !keyPaste.trim() || !keyFilename.trim()}
              style={{ ...primaryBtn, marginTop: 8, width: 'fit-content' }}
              title="Upload this SSH key to the ops-console server"
            >
              {keyUploading ? 'Uploading…' : 'Upload Key to Server'}
            </button>
          </div>
        )}

        {keyMsg && (
          <div style={{ marginTop: 8, fontSize: 12, color: keyMsg.startsWith('Error') ? '#c0392b' : '#27ae60' }}>
            {keyMsg}
          </div>
        )}
      </div>

      {/* Git Sync Section */}
      <div style={sectionBox}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 8 }}>
          <span style={{ fontWeight: 600, fontSize: 14 }}>App Sync</span>
          {gitStatus && (
            <span style={{ fontSize: 12, color: '#666' }}>
              {gitStatus.branch} @ {gitStatus.commit}
              {gitStatus.dirty && <span style={{ color: '#e67e22', marginLeft: 6 }}>(dirty)</span>}
            </span>
          )}
        </div>

        {gitStatus && (
          <div style={{ fontSize: 12, color: '#888', marginBottom: 12 }}>
            Last commit: {gitStatus.commit_message}
          </div>
        )}

        <div style={{ marginBottom: 12, maxWidth: 760 }}>
          <div style={{ fontSize: 13, marginBottom: 6, color: 'var(--text-primary)' }}>Update Source</div>
          <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
            <input
              value={gitRepo}
              onChange={(e) => setGitRepo(e.target.value)}
              placeholder="owner/repo"
              style={{ ...inputStyle, width: 260, fontFamily: 'inherit' }}
            />
            <input
              value={gitBranch}
              onChange={(e) => setGitBranch(e.target.value)}
              placeholder="main"
              style={{ ...inputStyle, width: 140, fontFamily: 'inherit' }}
            />
            <button
              onClick={handleGitSourceSave}
              disabled={gitSourceSaving || !gitRepo.trim() || !gitBranch.trim()}
              style={smallBtn}
              title="Save the GitHub repository and branch used by Pull & Deploy"
            >
              {gitSourceSaving ? 'Saving…' : 'Save Source'}
            </button>
          </div>
          <div style={{ fontSize: 12, color: 'var(--text-muted)', marginTop: 6 }}>
            Pull &amp; Deploy fetches from {gitStatus?.source_url || `https://github.com/${gitRepo || 'owner/repo'}.git`} on branch {gitBranch || 'main'}.
          </div>
          {gitSourceMsg && (
            <div style={{ marginTop: 6, fontSize: 12, color: gitSourceMsg.startsWith('Error') ? '#c0392b' : '#27ae60' }}>
              {gitSourceMsg}
            </div>
          )}
        </div>

        {/* GitHub Token */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 12 }}>
          <span style={{ fontSize: 13 }}>GitHub Token</span>
          <span style={{ fontSize: 12, color: tokenStatus?.configured ? '#27ae60' : '#e67e22' }}>
            {tokenStatus?.configured ? 'configured' : 'not configured'}
          </span>
          <button onClick={() => setShowTokenForm(!showTokenForm)} style={smallBtn} title="Set a GitHub Personal Access Token for auto-updates">
            {showTokenForm ? 'Cancel' : tokenStatus?.configured ? 'Update Token' : 'Configure Token'}
          </button>
          {tokenStatus?.configured && (
            <button onClick={handleDeleteToken} style={dangerBtn} title="Remove the saved GitHub token">
              Remove Token
            </button>
          )}
        </div>

        {showTokenForm && (
          <div style={{ marginBottom: 12, maxWidth: 560 }}>
            <p style={{ fontSize: 12, color: '#666', marginBottom: 4 }}>
              Create a <strong>fine-grained</strong> Personal Access Token:
            </p>
            <ol style={{ fontSize: 12, color: '#666', margin: '0 0 8px 20px', padding: 0, lineHeight: 1.7 }}>
              <li>Go to <a href="https://github.com/settings/tokens?type=beta" target="_blank" rel="noreferrer">github.com/settings/tokens</a> → <strong>Generate new token</strong></li>
              <li>Resource owner: <strong>{gitRepo.split('/')[0] || 'github owner'}</strong></li>
              <li>Repository access → <strong>Only select repositories</strong> → <code style={{ fontSize: 11 }}>{gitRepo}</code></li>
              <li>Permissions → Repository permissions → <strong>Contents: Read-only</strong></li>
              <li>Generate token and paste below</li>
            </ol>
            <p style={{ fontSize: 11, color: '#999', marginBottom: 8 }}>
              If the org requires approval, use a <strong>classic token</strong> with <code style={{ fontSize: 10 }}>repo</code> scope instead, then SSO-authorize it for Pentaho.
            </p>
            <input
              type="password"
              placeholder="github_pat_... or ghp_..."
              value={tokenPaste}
              onChange={(e) => setTokenPaste(e.target.value)}
              style={{ ...inputStyle, width: '100%' }}
            />
            <button
              onClick={handleTokenSave}
              disabled={tokenSaving || !tokenPaste.trim()}
              style={{ ...primaryBtn, marginTop: 8, width: 'fit-content' }}
              title="Validate and save the GitHub token for auto-updates"
            >
              {tokenSaving ? 'Validating…' : 'Save Token'}
            </button>
          </div>
        )}

        {tokenMsg && (
          <div style={{ marginBottom: 8, fontSize: 12, color: tokenMsg.startsWith('Token saved') ? '#27ae60' : '#c0392b', maxWidth: 560, lineHeight: 1.5 }}>
            {tokenMsg}
          </div>
        )}

        <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
          <button
            onClick={() => handleSync(true)}
            disabled={syncing}
            style={smallBtn}
            title="Pull latest code from GitHub and rebuild without restarting the service"
          >
            {syncing ? 'Running…' : 'Dry Run (pull + build, no restart)'}
          </button>
          <button
            onClick={() => {
              if (!window.confirm('Pull latest code, rebuild, and restart the service? The app will go offline briefly.')) return;
              handleSync(false);
            }}
            disabled={syncing}
            style={primaryBtn}
            title="Pull latest code, rebuild, and restart the service (brief downtime)"
          >
            {syncing ? 'Syncing…' : 'Pull & Deploy'}
          </button>
          <button
            onClick={() => {
              if (!window.confirm('Restart the ops-console service? The app will go offline briefly.')) return;
              handleRestart();
            }}
            disabled={restarting}
            style={{ ...smallBtn, background: '#f39c12', color: '#fff' }}
            title="Restart the ops-console systemd service (brief downtime)"
          >
            {restarting ? 'Restarting…' : 'Restart Service'}
          </button>
        </div>

        {syncResult && (
          <div style={{ marginTop: 12 }}>
            {syncResult.dry_run && (
              <div style={{ fontSize: 12, color: '#0073e7', marginBottom: 6, fontWeight: 600 }}>
                DRY RUN — no restart performed
              </div>
            )}
            {syncResult.results.map((r, i) => (
              <div key={i} style={{ fontSize: 12, marginBottom: 4, display: 'flex', gap: 8 }}>
                <span style={{ color: r.ok ? '#27ae60' : '#c0392b', fontWeight: 600 }}>
                  {r.ok ? '✓' : '✗'} {r.step}
                </span>
                <span style={{ color: '#666' }}>{r.output.slice(0, 200)}</span>
              </div>
            ))}
          </div>
        )}

        {restartMsg && (
          <div style={{ marginTop: 8, fontSize: 12, color: restartMsg.startsWith('Error') ? '#c0392b' : '#27ae60' }}>
            {restartMsg}
          </div>
        )}
      </div>

      {/* Import / Export Section */}
      <div style={sectionBox}>
        <div style={{ fontWeight: 600, fontSize: 14, marginBottom: 12 }}>Data Export &amp; Import</div>
        <p style={{ fontSize: 12, color: '#666', marginBottom: 12 }}>
          Export configuration to a JSON file you can back up or copy to another server.
          Import a previously exported file to restore data.
        </p>

        {/* Export */}
        <div style={{ marginBottom: 16 }}>
          <div style={{ fontSize: 13, fontWeight: 500, marginBottom: 6 }}>Export</div>
          <div style={{ display: 'flex', gap: 16, flexWrap: 'wrap', marginBottom: 8 }}>
            {allExportItems.map((item) => (
              <label key={item} style={{ fontSize: 12, display: 'flex', alignItems: 'center', gap: 4, cursor: 'pointer' }}>
                <input
                  type="checkbox"
                  checked={exportInclude.has(item)}
                  onChange={(e) => {
                    const next = new Set(exportInclude);
                    if (e.target.checked) next.add(item);
                    else next.delete(item);
                    setExportInclude(next);
                  }}
                />
                {item}
              </label>
            ))}
          </div>
          <button
            onClick={handleExport}
            disabled={exporting || exportInclude.size === 0}
            style={smallBtn}
          >
            {exporting ? 'Exporting…' : 'Download JSON'}
          </button>
          {exportMsg && (
            <span style={{ marginLeft: 10, fontSize: 12, color: exportMsg.startsWith('Error') ? '#c0392b' : '#27ae60' }}>
              {exportMsg}
            </span>
          )}
        </div>

        {/* Import */}
        <div>
          <div style={{ fontSize: 13, fontWeight: 500, marginBottom: 6 }}>Import</div>
          <div style={{ display: 'flex', gap: 12, alignItems: 'center', flexWrap: 'wrap', marginBottom: 8 }}>
            <input
              type="file"
              accept=".json,application/json"
              style={{ fontSize: 12 }}
              onChange={(e) => {
                setImportFile(e.target.files?.[0] ?? null);
                setImportMsg('');
              }}
            />
            <select
              value={importStrategy}
              onChange={(e) => setImportStrategy(e.target.value as 'merge' | 'overwrite')}
              style={{ fontSize: 12, padding: '4px 8px', borderRadius: 4, border: '1px solid #ccc' }}
            >
              <option value="merge">Merge (skip existing)</option>
              <option value="overwrite">Overwrite (replace existing)</option>
            </select>
          </div>
          <button
            onClick={handleImport}
            disabled={importing || !importFile}
            style={importStrategy === 'overwrite' ? { ...dangerBtn, fontSize: 13, padding: '6px 14px' } : smallBtn}
          >
            {importing ? 'Importing…' : importStrategy === 'overwrite' ? 'Import & Overwrite' : 'Import'}
          </button>
          {importMsg && (
            <div style={{ marginTop: 6, fontSize: 12, color: importMsg.startsWith('Error') ? '#c0392b' : '#27ae60' }}>
              {importMsg}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

const sectionBox: React.CSSProperties = {
  background: 'var(--panel-bg)',
  border: '1px solid var(--panel-border)',
  borderRadius: 6,
  padding: 16,
  marginBottom: 16,
};

const smallBtn: React.CSSProperties = {
  background: 'var(--button-subtle-bg)',
  color: 'var(--button-subtle-text)',
  border: 'none',
  padding: '6px 14px',
  borderRadius: 4,
  cursor: 'pointer',
  fontSize: 13,
};

const dangerBtn: React.CSSProperties = {
  background: '#fff',
  color: '#c0392b',
  border: '1px solid #e2b7b3',
  padding: '5px 12px',
  borderRadius: 4,
  cursor: 'pointer',
  fontSize: 12,
};

const chipDeleteBtn: React.CSSProperties = {
  background: 'transparent',
  color: '#c0392b',
  border: 'none',
  padding: '0 4px',
  cursor: 'pointer',
  fontSize: 13,
  lineHeight: 1,
  fontWeight: 600,
};

const primaryBtn: React.CSSProperties = {
  background: '#0073e7',
  color: '#fff',
  border: 'none',
  padding: '6px 14px',
  borderRadius: 4,
  cursor: 'pointer',
  fontSize: 13,
};

const inputStyle: React.CSSProperties = {
  background: 'var(--field-bg)',
  color: 'var(--text-primary)',
  padding: '6px 10px',
  borderRadius: 4,
  border: '1px solid var(--field-border)',
  fontSize: 13,
  fontFamily: 'Menlo, Monaco, monospace',
};

const codeHint: React.CSSProperties = {
  background: 'var(--code-bg)',
  border: '1px solid var(--code-border)',
  color: 'var(--text-primary)',
  borderRadius: 4,
  padding: '6px 10px',
  fontSize: 12,
  fontFamily: 'Menlo, Monaco, monospace',
  userSelect: 'all',
  cursor: 'pointer',
};
