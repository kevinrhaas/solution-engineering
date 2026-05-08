# Pentaho Ops Console

Web UI + API for provisioning, operating, and migrating Pentaho Server and PDC environments with job-based execution and live logs.

## Live Environment

- Ops Console: http://10.80.230.233:8000

## What You Can Do (Core Features)

### Instances (Fleet Visibility)

- Discover tracked and untracked EC2 instances in one view.
- See server type, deployment phase, IPs, instance metadata, and quick links.
- Run health checks and content previews for tracked instances.
- Jump directly from an instance card to its profile.

### Profiles (Configuration Source of Truth)

- Create, duplicate, edit, and delete deployment profiles.
- Manage `.env` profile content in the UI.
- View merged runtime state alongside configured profile values.

### Provision (Day-0 Deployment)

- Run preflight checks before deployment.
- Deploy new or existing instances.
- Run full pipelines for Pentaho Server and PDC.
- Execute step actions (auth, create/check EC2, deploy server, deploy plugins, teardown).

### Manage (Day-2 Operations)

- Restart, start, and stop Pentaho Server containers.
- Run PDC service restart workflow (OAuth → Frontend → Ingress).
- Tail Catalina logs and capture Docker logs.
- Run diagnostics and resource monitoring.
- Copy ready-to-use SSH command for a profile.
- Run PDC API automation actions (preflight, ingest, profile, aggregate, tagging, optional jobs) through the PDC Automation panel.

### Migrate (Pentaho + PDC)

- Run full Pentaho Server migration between source and target servers.
- Run Pentaho quick migration actions (content, datasources, home pull/push).
- Run full PDC host-to-host migration.
- Use dry-run before making changes.

### Jobs (Execution + Audit Trail)

- Every action runs as a job with status, exit code, and output.
- Watch live output through SSE streaming.
- Keep historical jobs and bulk-delete completed ones.
- Job history survives service restarts.

### Config (Credentials + App Control)

- Sync AWS credentials and SSH keys used by deploy/manage flows.
- Configure GitHub token for update automation.
- Trigger app sync (pull/build/install/restart) from the UI.
- Restart the service from the UI.
- Export and import application data bundles.

## How To Use The App (Recommended Flow)

1. Open Config and sync prerequisites.
2. Set AWS credentials, upload SSH key, and configure GitHub token.
3. Open Profiles and create or update the `.env` profile.
4. Open Provision and run preflight.
5. Deploy a new instance or target an existing one.
6. Open Instances to verify state, IPs, and health.
7. Open Manage for lifecycle actions, logs, diagnostics, and SSH.
8. Open Migrate for Pentaho Server or PDC migration workflows.
9. Open Jobs to monitor execution and review history.

## Migration Workflows

### Pentaho Server Migration

The Full Pentaho Server Migration workflow runs a server-to-server migration for content, datasources, and home directory files.

Inputs and options:

- Source and target server URLs (can be selected from discovered instances).
- Source and target credentials.
- Dry run mode.
- Skip flags: `skip-home`, `skip-content`, `skip-datasources`.

Available Pentaho migration actions:

- Full migration: move all supported assets in one run.
- Pull/Push Content.
- Pull/Push Datasources.
- Pull/Push Home files.
- Publish Mondrian schema via API endpoint.

### PDC Migration

The Full PDC Migration workflow drives `40-migrate-pdc.sh` from `pentaho-11-docker-deploy/`.

Inputs and options:

- Source and target instance selection (auto-fill IP and env file when tracked).
- Source and target IPs.
- Source and target env files (`.env`).
- Optional SSH user overrides.
- Dry run mode.
- Optional stop-source for maintenance windows.

What it does:

1. Packages `conf/` and all `pdc*` Docker volumes on source.
2. Transfers with resumable rsync.
3. Restores on target and backfills required host/UUID settings.
4. Regenerates TLS certs on target as needed.
5. Restarts PDC services and performs post-restore health checks.

## Application Screenshots

The following views are the current UI experience:

### Instances
<img width="1673" height="1135" alt="image" src="https://github.com/user-attachments/assets/708cb679-1be2-4330-9b3a-4f6b6c085c12" />

### Profiles
<img width="1618" height="1131" alt="image" src="https://github.com/user-attachments/assets/d3c651c5-7fb1-428a-9bee-891e3c63ddea" />

### Provision (New Instance)
<img width="1627" height="1126" alt="image" src="https://github.com/user-attachments/assets/798486d2-d5c9-4b14-9320-872fb1c8545a" />

### Provision (Existing Instance)
<img width="1625" height="1135" alt="image" src="https://github.com/user-attachments/assets/dbf20ea0-33ca-48b2-9c59-a367206e4ce4" />

### Manage
<img width="1633" height="1130" alt="image" src="https://github.com/user-attachments/assets/0d14b745-d66d-45b9-9a57-d4539aecffa8" />

### Migrate
<img width="1637" height="1189" alt="image" src="https://github.com/user-attachments/assets/302b3d3a-63a2-484d-bd5d-f8db37909882" />

### Jobs
<img width="1658" height="1178" alt="image" src="https://github.com/user-attachments/assets/2039a3e3-1b73-4233-88fb-2150f4ee35f9" />

## Technical Appendix

### Architecture and Component Overview

```
pentaho-ops-console/
├── api/                    # FastAPI backend
│   ├── main.py             # API app and route registration
│   ├── config.py           # Workspace/script/database configuration
│   ├── runner.py           # Job runner + async execution + SSE
│   ├── db/                 # SQLAlchemy models/engine/seed/crypto
│   └── routes/
│       ├── jobs.py
│       ├── profiles.py
│       ├── provision.py
│       ├── manage.py
│       ├── migrate.py
│       └── config.py
├── ui/                     # React + Vite + TypeScript frontend
│   └── src/
│       ├── api.ts          # Typed API client
│       ├── components/
│       └── pages/          # Instances, Profiles, Provision, Manage, Migrate, Jobs, Config
└── requirements.txt        # Python dependencies
```

### Script Integration Model

The console orchestrates existing shell scripts through jobs. Script logic remains in the script repositories.

| Script Directory | Purpose |
|---|---|
| `pentaho-11-docker-deploy/` | EC2, Pentaho, PDC, plugin, lifecycle, and PDC migration actions |
| `pdc-analysis/utility/` | Pentaho Server migration actions (content, datasources, home, server migration) |
| `pdc-automation/` | PDC API automation: ingest, profile, aggregate, collections, tagging, optional jobs |

The backend launches scripts through `subprocess.Popen`, captures line output, and streams output to the UI terminal via SSE.

### Persistence and Secrets

- Database-backed persistence for profiles, instances, jobs, secrets, and app settings.
- Default DB is SQLite under `pentaho-ops-console/data/`.
- Secrets are encrypted at rest when `OPS_ENCRYPTION_KEY` is configured.
- Import/export supports profiles, instances, jobs, secrets, and settings.

### API Surface

| Area | Endpoint | Description |
|---|---|---|
| Health | `GET /api/health` | Liveness + DB status |
| Profiles | `GET /api/profiles` | List all profiles |
| | `GET /api/profiles/{name}` | Get profile + merged runtime state |
| | `POST /api/profiles` | Create profile |
| | `POST /api/profiles/{name}/duplicate` | Duplicate profile |
| | `PUT /api/profiles/{name}` | Update profile |
| | `DELETE /api/profiles/{name}` | Delete profile |
| Instances | `GET /api/profiles/instances` | List tracked instances |
| | `GET /api/profiles/instances/ec2` | EC2 discovery |
| | `GET /api/profiles/instances/health` | Health check all instances |
| | `DELETE /api/profiles/instances/{state_file}` | Remove tracked state |
| | `POST /api/profiles/instances/content-preview/start` | Start content preview job |
| | `GET /api/profiles/instances/content-preview/{id}` | Get content preview result |
| Provision | `POST /api/provision/preflight` | Run preflight checks |
| | `POST /api/provision/full-deploy` | Full Pentaho deploy |
| | `POST /api/provision/full-deploy-pdc` | Full PDC deploy |
| | `POST /api/provision/auth` | Okta/AWS authentication |
| | `POST /api/provision/create-ec2` | Create EC2 instance |
| | `POST /api/provision/check-ec2` | Check EC2 readiness |
| | `POST /api/provision/deploy-pentaho` | Deploy Pentaho Server |
| | `POST /api/provision/deploy-pdc` | Deploy PDC |
| | `POST /api/provision/deploy-plugins` | Deploy all plugins |
| | `POST /api/provision/deploy-plugin` | Deploy a single plugin |
| | `POST /api/provision/teardown` | Tear down instance |
| Manage | `POST /api/manage/restart` | Restart Pentaho Server |
| | `POST /api/manage/up` | Start Pentaho container |
| | `POST /api/manage/down` | Stop Pentaho container |
| | `POST /api/manage/pdc-restart` | Restart PDC services |
| | `POST /api/manage/logs/catalina` | Tail Catalina log |
| | `POST /api/manage/logs/docker` | Capture Docker logs |
| | `POST /api/manage/monitor` | Resource monitoring |
| | `POST /api/manage/diagnose` | Instance diagnostics |
| | `GET /api/manage/ssh-command/{profile}` | Get SSH command for profile |
| Migrate (Pentaho) | `POST /api/migrate/full` | Full server-to-server migration |
| | `POST /api/migrate/content/pull` | Pull content from server |
| | `POST /api/migrate/content/push` | Push content to server |
| | `POST /api/migrate/datasources/pull` | Pull datasources |
| | `POST /api/migrate/datasources/push` | Push datasources |
| | `POST /api/migrate/home/pull` | Pull home files |
| | `POST /api/migrate/home/push` | Push home files |
| | `POST /api/migrate/cube/publish` | Publish Mondrian schema |
| Migrate (PDC) | `POST /api/migrate/pdc/full` | Full PDC host-to-host migration |
| Config | `POST /api/config/aws-credentials` | Sync AWS credentials |
| | `GET /api/config/aws-credentials/status` | AWS credential status |
| | `DELETE /api/config/aws-credentials` | Purge AWS credentials |
| | `DELETE /api/config/aws-credentials/{profile}` | Delete AWS profile |
| | `POST /api/config/ssh-key` | Upload SSH key |
| | `GET /api/config/ssh-key/status` | SSH key status |
| | `DELETE /api/config/ssh-key` | Purge SSH keys |
| | `DELETE /api/config/ssh-key/{filename}` | Delete SSH key |
| | `POST /api/config/github-token` | Save GitHub token |
| | `GET /api/config/github-token/status` | GitHub token status |
| | `DELETE /api/config/github-token` | Delete GitHub token |
| | `GET /api/config/git/status` | Git status |
| | `POST /api/config/sync` | Pull/build/deploy update |
| | `POST /api/config/restart` | Restart app service |
| | `POST /api/config/export` | Export app data bundle |
| | `POST /api/config/import` | Import app data bundle |
| Jobs | `GET /api/jobs` | List all jobs |
| | `GET /api/jobs/{id}` | Get job detail |
| | `GET /api/jobs/{id}/stream` | SSE stream of live output |
| | `POST /api/jobs/{id}/cancel` | Cancel running job |
| | `POST /api/jobs/bulk-delete` | Bulk delete completed jobs |

### Building and Running (Local)

Backend:

```bash
cd pentaho-ops-console
pip install -r requirements.txt
uvicorn api.main:app --reload --port 8000
```

Frontend:

```bash
cd pentaho-ops-console/ui
npm install
npm run dev
```

The UI dev server runs on `http://localhost:5173` and proxies `/api` to port `8000`.

### Deployment

Deploy to target host:

```bash
cd pentaho-ops-console
./deploy-ops-console.sh <env-file>
```

Typical post-deploy checks:

1. Confirm service health: `curl http://<server-ip>:8000/api/health`
2. Open UI: `http://<server-ip>:8000`
3. Run preflight from Provision.
4. Confirm Jobs shows live and historical output.
