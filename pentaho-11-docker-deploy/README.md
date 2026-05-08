# Pentaho 11 Docker Deployment on AWS EC2

Automated deployment of Pentaho 11 Server and PDC (Pentaho Data Catalog) on AWS EC2 using Docker containers. Supports PostgreSQL, MySQL, SQL Server, or Oracle backends. All scripts are driven by env files and can be run standalone or through the [Ops Console](../pentaho-ops-console/README.md).

## Quick Start — Pentaho Server

```bash
# 1. Create your env file
cp pentaho-deployment-sample.env my-environment.env
# Edit my-environment.env — update values marked ⚠️ REQUIRED

# 2. Run preflight check (validates tools, auth, AWS resources, plugins)
./00-preflight-check.sh my-environment.env

# 3. Deploy everything in one shot
./00-full-deploy.sh my-environment.env

# 4. Access Pentaho (allow ~10 min for first-time startup)
http://<instance-ip>/pentaho    # admin / password
```

## Quick Start — PDC (Pentaho Data Catalog)

```bash
# 1. Create your PDC env file
cp pdc-10.2.11.env my-pdc.env
# Edit my-pdc.env — update IPs, credentials, and license URL

# 2. Run full PDC deployment (includes EC2 + PDC stack)
./00-full-deploy-pdc.sh my-pdc.env

# 3. Restart PDC services (OAuth → Frontend → Ingress)
./39-restart-pdc-services.sh my-pdc.env
```

All scripts take the **env file name** as the first parameter (tab-completion supported).

---

## Prerequisites

| Requirement | Details |
|---|---|
| **AWS CLI + Okta** | `okta-aws` configured ([setup guide](https://hv-eng.atlassian.net/wiki/spaces/DEVO/pages/1408761858)) |
| **SSH Key Pair** | `.pem` file locally + key pair registered in AWS |
| **JFrog Token** | From https://one.hitachivantara.com → Set Me Up |
| **License URL** | Flexera license server URL from your Pentaho account manager |
| **Network** | VPN access to your AWS VPC for private IP instances |

Run `./00-preflight-check.sh <env-file>` to validate all prerequisites automatically.

---

## Pentaho Server Deployment

### Step-by-Step (Manual)

```bash
./01-auth-okta-aws.sh my-environment.env        # Authenticate via Okta → AWS
./02-create-ec2.sh my-environment.env            # Create EC2 instance
./03-check-ec2.sh my-environment.env             # Wait for instance ready
./10-deploy-pentaho.sh my-environment.env        # Download + deploy Pentaho
./20-deploy-all-plugins.sh my-environment.env    # Install all plugins
```

### Container Lifecycle

```bash
./90-restart-pentaho-container.sh my-environment.env   # Restart container
./91-up-pentaho-container.sh my-environment.env        # Start container
./92-down-pentaho-container.sh my-environment.env      # Stop container
```

### Monitoring & Debugging

```bash
./97-monitor-resources.sh my-environment.env      # Real-time CPU/memory usage
./98-diagnose-container.sh my-environment.env      # Full container diagnostics
./93-tail-catalina-log.sh my-environment.env       # Stream Tomcat logs
./94-get-docker-logs.sh my-environment.env         # Capture Docker logs
./95-ssh-into-container.sh my-environment.env      # Shell into container
./96-ssh-into-instance.sh my-environment.env       # SSH to EC2 instance
```

### Teardown

```bash
./99-teardown.sh my-environment.env
```

⚠️ **This permanently terminates the EC2 instance and deletes all data.**

---

## PDC Deployment

### Full PDC Deploy

```bash
./00-full-deploy-pdc.sh my-pdc.env               # EC2 creation + full PDC stack
./30-deploy-pdc.sh my-pdc.env                    # Deploy PDC stack only (existing EC2)
```

### PDC Service Management

```bash
./39-restart-pdc-services.sh my-pdc.env          # Restart PDC services (auth → fe → ingress)
```

### PDC Migration (Host-to-Host)

Copies a populated PDC instance (`conf/` + all `pdc*` Docker volumes) from source to target.

```bash
# Standard migration (briefly stops source for consistency)
./40-migrate-pdc.sh pdc-10.2.11.env --source-ip 10.80.230.246 --target-ip 10.80.230.163

# Live copy (source stays running — higher consistency risk)
./40-migrate-pdc.sh pdc-10.2.11.env --source-ip 10.80.230.246 --target-ip 10.80.230.163 --live-copy

# Dry run — validates SSH and shows planned actions only
./40-migrate-pdc.sh pdc-10.2.11.env --source-ip 10.80.230.246 --target-ip 10.80.230.163 --dry-run
```

Target is always stopped, restored, and restarted by the script.

---

## Plugins

Plugins are defined in the env file and downloaded directly on the EC2 instance during deployment.

### Plugin Types

**Typical** — standard extraction to `pentaho-solutions/system/`:
```bash
PLUGINS_TYPICAL="
https://.../pdd-plugin-ee-${PENTAHO_VERSION}.zip
https://.../paz-plugin-ee-${PENTAHO_VERSION}.zip
https://.../pas-scheduler-${PENTAHO_VERSION}.zip
https://.../pir-plugin-ee-${PENTAHO_VERSION}.zip
"
```

**Special** — custom extraction logic (`name|URL` format):
```bash
PLUGINS_SPECIAL="
webttle-plugins-ee-client|https://.../webttle-plugins-ee-client-${PENTAHO_VERSION}.zip
"
```

**Local file** — for plugins not in Artifactory (place zip in `downloads/plugins/<version>/`):
```bash
PLUGINS_SPECIAL="
semantic-model-editor|file://semantic-model-editor-${PENTAHO_VERSION}.zip
"
```

### Plugin Commands

```bash
# Install all configured plugins
./20-deploy-all-plugins.sh my-environment.env

# Install single plugin by URL
./21-deploy-plugin.sh my-environment.env https://.../pdd-plugin-ee-11.0.0.1-259.zip

# Install single plugin by name (special plugins)
./21-deploy-plugin.sh my-environment.env webttle-plugins-ee-client

# Install without restart
./21-deploy-plugin.sh --no-restart my-environment.env pdd-plugin-ee

# Install from local zip
./22-install-plugin-from-local.sh my-environment.env semantic-model-editor-11.0.0.1-259.zip
```

**Adding new plugins:**
- **Typical**: Add the URL to `PLUGINS_TYPICAL` in the env file — no code changes needed.
- **Special**: Add `name|URL` to `PLUGINS_SPECIAL` and add a handler in `21-deploy-plugin.sh`.

---

## Configuration

### Environment File Setup

```bash
cp pentaho-deployment-sample.env my-environment.env
```

Update all values marked `⚠️ REQUIRED`.

### Key Variables

| Variable | Example | Description |
|---|---|---|
| `AWS_PROFILE` | `khaas` | Okta-AWS profile name |
| `KEY_NAME` | `my-keypair` | AWS key pair name |
| `KEY_PATH` | `~/.ssh/my-keypair.pem` | Path to SSH private key |
| `VPC_ID` | `vpc-0abc123` | Your VPC |
| `SUBNET_ID` | `subnet-0abc123` | Your subnet |
| `SECURITY_GROUP_ID` | `sg-0abc123` | SG allowing SSH (22) + HTTP (80) |
| `PENTAHO_VERSION` | `11.0.0.1-259` | Pentaho version to deploy |
| `JFROG_TOKEN` | `cmVmd...` | JFrog access token |
| `JFROG_BASE_URL` | `https://one.hitachivantara.com/...` | dev or rc repo URL |
| `LICENSE_URL` | `https://pentaho-uat...` | Flexera license server URL (Pentaho Server) |
| `LICENSING_SERVER_URL` | `https://pentaho.compliance.flexnetoperations.com/...` | Flexera URL (PDC) |
| `PDI_LICENSE_URL` | `https://pentaho.compliance.flexnetoperations.com/...` | PDI/Carte license URL (PDC workers) |
| `ENVIRONMENT` | `sample-11-0-0-1-259` | Environment identifier |

### Instance Size Profiles

Env files include two pre-configured profiles — toggle by commenting/uncommenting:

| Setting | t3.large (dev) | r7i.xlarge (prod) |
|---|---|---|
| **Instance** | 2 vCPU, 8GB RAM | 4 vCPU, 32GB RAM |
| **Pentaho Container** | 1.8 CPU, 5.5GB | 3.5 CPU, 24GB |
| **Database Container** | 0.2 CPU, 1.5GB | 0.5 CPU, 4GB |
| **JVM Heap** | 1–3 GB | 4–16 GB |

JVM max heap should be 60–75% of Pentaho container memory.

---

## Project Structure

```
pentaho-11-docker-deploy/
├── 00-preflight-check.sh           # Pre-deploy validation (tools, auth, resources, plugins)
├── 00-full-deploy.sh               # Full automated Pentaho Server deployment
├── 00-full-deploy-pdc.sh           # Full automated PDC deployment
├── 01-auth-okta-aws.sh             # AWS authentication via Okta
├── 02-create-ec2.sh                # EC2 instance creation
├── 03-check-ec2.sh                 # EC2 readiness check
├── 04-start-ec2.sh                 # Start stopped EC2 instance
├── 05-stop-ec2.sh                  # Stop running EC2 instance
├── 10-deploy-pentaho.sh            # Pentaho download + deploy (runs on EC2)
├── 20-deploy-all-plugins.sh        # Install all configured plugins
├── 21-deploy-plugin.sh             # Install single plugin (URL or name)
├── 22-install-plugin-from-local.sh # Install plugin from local zip
├── 30-deploy-pdc.sh                # Deploy PDC stack to EC2
├── 39-restart-pdc-services.sh      # Restart PDC services (auth → fe → ingress)
├── 40-migrate-pdc.sh               # PDC host-to-host migration
├── 90-restart-pentaho-container.sh # Restart Pentaho container
├── 91-up-pentaho-container.sh      # Start Pentaho container
├── 92-down-pentaho-container.sh    # Stop Pentaho container
├── 93-tail-catalina-log.sh         # Tail Tomcat/Catalina logs
├── 94-get-docker-logs.sh           # Capture Docker container logs
├── 95-ssh-into-container.sh        # Shell into Pentaho container
├── 96-ssh-into-instance.sh         # SSH to EC2 instance
├── 97-monitor-resources.sh         # Real-time CPU/memory monitoring
├── 98-diagnose-container.sh        # Full container diagnostics
├── 99-teardown.sh                  # Terminate EC2 + cleanup
├── softwareOverride/               # Custom drivers/configs (optional)
│   ├── 1_drivers/                  # Database drivers
│   ├── 2_repository/               # Repository configs
│   └── 4_others/                   # Other customizations
├── *.env                           # Environment configuration files
└── *-runtime.state                 # Runtime state (auto-generated)
```

---

## Architecture

- **EC2**: Ubuntu 22.04 with Docker, 200GB EBS volume
- **Pentaho Server**: Container image from JFrog Artifactory, configured via docker-compose
- **PDC**: Multi-container stack (services, PDI tray/workers) on the same EC2 host
- **Database**: PostgreSQL (default), MySQL, SQL Server, or Oracle container
- **Downloads**: All artifacts (images, on-prem dist, plugins) download directly on EC2
- **Networking**: Port 80 (HTTP), Port 22 (SSH). Outbound HTTPS for JFrog + Flexera license servers
- **Container user**: `pentaho` (uid 5000)

