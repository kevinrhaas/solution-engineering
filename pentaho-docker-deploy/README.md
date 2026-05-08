# Pentaho Docker Deployment

Automated deployment of Pentaho Business Analytics & Data Integration Server using Docker containers on AWS EC2.

## Table of Contents
- [Overview](#overview)
- [Prerequisites](#prerequisites)  
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Access Pentaho](#access-pentaho)
- [Troubleshooting](#troubleshooting)

## Overview

Deploy Pentaho Server in Docker containers on AWS EC2 with a simple 4-step automation process.

### Key Features
- ✅ **One-click deployment** - fully automated with no prompts
- ✅ **Direct HTTP access** on port 80 (no tunneling needed)
- ✅ **Flexible environments** - supports any environment name (dev/test/prod/etc.)
- ✅ **Intelligent resource optimization** - automatic CPU/memory limits
- ✅ **Clean configuration** - separate input config from runtime state

### What You Get
- Pentaho Business Analytics & Data Integration Server 10.2.0.0
- PostgreSQL 15 database backend
- Dockerized deployment for portability
- Direct HTTP access at `http://<ec2-ip>:80/pentaho`

## Prerequisites

- **AWS CLI** with configured credentials
- **Okta-AWS CLI** (for HV AD users)  
- **SSH client** and **Bash shell**

### Required Files
Place Pentaho installation files in `pentaho-downloads/`. For example:
```
pentaho-downloads/
├── dock-maker-10.2.0.0-222-public.zip
├── pentaho-server-ee-10.2.0.0-222.zip
└── paz-plugin-ee-10.2.0.0-222.zip
```

Download from the [Pentaho Customer Support Portal](https://support.pentaho.com/).

### AWS Authentication Setup (HV AD Users)

**IMPORTANT**: If you're using Hitachi Vantara Active Directory authentication, you must complete these steps before deployment:

1. **Install Okta-AWS CLI** following the [official HV documentation](https://hv-eng.atlassian.net/wiki/spaces/DEVO/pages/1408761858/How+to+get+AWS+access+keys+for+HV+AD+users+via+OKTA+integration)

2. **Authenticate before each deployment session**:
   ```bash
   okta-aws [your-profile-name]
   aws sts get-caller-identity  # Verify
   ```

2. **Configure environment:**
   ```bash
   cp pentaho-deployment-sample.env pentaho-deployment-test.env
   # Edit pentaho-deployment-test.env with your AWS settings
   ```

3. **Have Pentaho license ready:**
   You'll install your `.pentaho_license` file through the web interface after deployment.

## Quick Start

⚠️  **BEFORE YOU START**: Complete all authentication and configuration steps in [Prerequisites](#prerequisites)

1. **Authenticate with AWS (HV AD users):**
   ```bash
   # Replace 'yourprofile' with your actual Okta profile
   okta-aws ${yourprofile} sts get-caller-identity
   aws sts get-caller-identity  # Verify authentication
   ```

2. **Clone and configure:**
   ```bash
   git clone <repository-url>
   cd pentaho-docker-deploy
   
   # Create your environment file from the sample
   cp pentaho-deployment-sample.env pentaho-deployment-test.env
   # Edit pentaho-deployment-test.env with your settings
   
   # Or use any environment name you prefer:
   # cp pentaho-deployment-sample.env pentaho-deployment-monkey.env
   ```

3. **Add Pentaho files:**
   Place the required Pentaho install zip files (dock maker, server, amy plugins) in the `pentaho-downloads/` directory.

4. **Prepare your Pentaho license file:**
   Have your `.pentaho_license` file or pentaho server URL ready for manual installation through the web interface.

5. **Run full deployment (fully automated, no prompts):**
   ```bash
   ./full-deployment.sh test
   ```
   
   The full deployment script runs all steps automatically:
   - ✅ Creates EC2 instance
   - ✅ Downloads and installs Pentaho files  
   - ✅ Builds containers (full mode, ~15-20 minutes)
   - ✅ Deploys and starts containers
   - ✅ Provides access instructions

4. **Access Pentaho:**
   
   **Direct Access (Primary method):**
   ```bash
   http://<ec2-private-ip>:80/pentaho
   ```
   
   **SSH Tunnel (Alternative method):**
   ```bash
   ssh -L 80:localhost:80 -i ~/.ssh/your-key.pem ubuntu@<ec2-ip>
   ```
   Then open: http://localhost:80/pentaho

## Configuration

### Environment Files

Each environment requires a configuration file: `pentaho-deployment-{env}.env`

**Example: pentaho-deployment-test.env**
```bash
# AWS Configuration
ENVIRONMENT=yourEnvNameHere ### e.g. test, dev
AWS_PROFILE=yourAWSPofileNameHere ### your okta-aws profile name to use for authenticating

# Key Configuration
KEY_PATH=/Users/khaas/.ssh/pentaho+_se_keypair.pem
KEY_NAME=pentaho+_se_keypair

# AWS Infrastructure Configuration
AWS_REGION=us-west-2
INSTANCE_TYPE=t3.large
AMI_ID=ami-0d70546e43a941d70  # Ubuntu 22.04 LTS AMI (us-west-2)
EBS_VOLUME_SIZE=75
VOLUME_TYPE=gp3
SSH_USER=ubuntu  # ec2-user for Amazon Linux AMI, ubuntu for Ubuntu AMI
PROJECT_NAME=pentaho-docker # name of the server

# VPC and Security Configuration  
VPC_ID=vpc-095f761a169c10b8e
SUBNET_ID=subnet-059321ee33ee549e7
SECURITY_GROUP_ID=sg-020200447994fa148

# Container Resource Limits (automatically applied during deployment)
CONTAINER_CPU_LIMIT=1.5      # CPU cores per container (adjust based on instance type)
CONTAINER_MEMORY_LIMIT=3GB   # Memory per container (adjust based on instance capacity)
```

### Runtime State

The deployment creates runtime state files (`*-runtime.state`) that contain:
- Instance ID and IP addresses
- SSH connection details
- Deployment timestamps

**⚠️ Important:** These files contain sensitive information and are automatically excluded from Git.

## Deployment Scripts

### Script Usage Options

**Automated Full Deployment (Recommended):**
```bash
./full-deployment.sh [environment]
# Runs all scripts automatically with optimal settings
# No user prompts - fully unattended deployment
```

**Manual Step-by-Step:**
```bash  
./01-create-pentaho-ec2.sh [environment]
./02-download-pentaho-files.sh [environment]
./03-build-pentaho-containers.sh [environment] [build-mode]  # Interactive prompts by default
./04-deploy-pentaho.sh [environment]
```

**Build Mode Options for Step 3:**
- `full` - Complete build with progress monitoring (~15-20 minutes)
- `background` - Start build, return immediately 
- `status` - Check current build progress
- `interactive` - Prompt user (default for manual execution)

---

### 1. Create EC2 Instance (`01-create-pentaho-ec2.sh`)

**Purpose:** Provisions AWS EC2 infrastructure for Pentaho deployment.

**What it does by default:**
- Uses optimized security group with open ports.
- Launches EC2 instance with specified configuration
- Attaches and mounts 75GB EBS volume for data storage
- Configures Docker to use EBS volume
- Updates system packages and installs dependencies
- Creates runtime state file with connection details

**Usage:**
```bash
./01-create-pentaho-ec2.sh [environment]
# Example: ./01-create-pentaho-ec2.sh test
```

**Key Features:**
- Includes security group with optimal settings
- EBS volume mounting at `/mnt/pentaho-data`
- Docker daemon configuration to use EBS volume
- User data script for automated setup
- Instance readiness verification

### 2. Download Pentaho Files (`02-download-pentaho-files.sh`)

**Purpose:** Transfers and sets up Pentaho installation files on EC2.

**What it does:**
- Installs Docker and docker-compose on EC2
- Creates directory structure for Pentaho files
- Uploads Pentaho installation files from local `pentaho-downloads/` directory. For example:
  - `dock-maker-10.2.0.0-222-public.zip` (DockMaker Tool)
  - `pentaho-server-ee-10.2.0.0-222.zip` (Pentaho Server)
  - `paz-plugin-ee-10.2.0.0-222.zip` (Analyzer Plugin)
- Extracts and prepares DockMaker for container building
- Verifies file integrity and setup

**Usage:**
```bash
./02-download-pentaho-files.sh [environment]
# Example: ./02-download-pentaho-files.sh test
```

**Requirements:**
- Pentaho files must be present in local `pentaho-downloads/` directory
- EC2 instance must be running and accessible
- Step 1 must be completed successfully

### 3. Build Pentaho Containers (`03-build-pentaho-containers.sh`)

**Purpose:** Creates Docker containers using Pentaho's official DockMaker tool.

**What it does:**
- Runs Docker system cleanup to ensure adequate disk space
- Configures DockMaker with PostgreSQL backend
- Executes DockMaker to build Pentaho Docker images:
  - Pentaho Server container (~3GB)
  - PostgreSQL 15 database container
- Generates docker-compose.yml with proper configuration
- Creates supporting files (Dockerfile, .env, entrypoint scripts)
- Adjusts resource limits for EC2 instance type

**Usage:**
```bash
./03-build-pentaho-containers.sh [environment] [build-mode]  
# Example: ./03-build-pentaho-containers.sh test
# Example: ./03-build-pentaho-containers.sh test full  
# Example: ./03-build-pentaho-containers.sh test background
```

**Build Modes:**
- `full` (default for full-deployment.sh) - Complete build with monitoring (15-20 minutes)
- `background` - Start build and return immediately for async execution  
- `status` - Check current build progress without starting new build
- `interactive` (default for manual runs) - Prompt user to choose build mode

**Note:** The `full-deployment.sh` script automatically uses `full` mode to ensure complete non-interactive deployment.

**Build Process:**
- Extracts Pentaho server and analyzer plugin
- Configures database connection settings
- Builds multi-stage Docker images
- Generates deployment artifacts in `generatedFiles/` directory

**Output Artifacts:**
```
generatedFiles/
├── docker-compose.yml    # Container orchestration
├── Dockerfile           # Pentaho server image
├── .env                # Environment variables
├── db_init_postgres/   # Database initialization
└── entrypoint/         # Container startup scripts
```

### 4. Deploy Pentaho Containers (`04-deploy-pentaho.sh`)

**Purpose:** Deploys and starts the Pentaho container stack.

**What it does:**
- Stops any existing containers gracefully
- Adjusts resource limits for target EC2 instance:
  - CPU limits: Ensures compatibility with instance vCPU count
  - Memory limits: Optimized for available RAM
- Starts container stack using docker-compose
- Waits for services to be fully operational  
- Tests internal connectivity (localhost:80)
- Configures external port binding for remote access
- Provides connection information and access instructions

**Usage:**
```bash
./04-deploy-pentaho.sh [environment]
# Example: ./04-deploy-pentaho.sh test  
```

**Resource Optimization:**
- **Automatic CPU limit validation:** Ensures CPU limits don't exceed instance capacity
- **Configurable limits via environment variables:**
  - `CONTAINER_CPU_LIMIT`: Maximum CPU cores per container (default: 1.5 for t3.large)
  - `CONTAINER_MEMORY_LIMIT`: Maximum memory per container (default: 3GB for t3.large)
- **Instance type compatibility:**
  - **t3.large (2 CPU, 8GB RAM):** 1.5 CPU, 3GB memory per container
  - **t3.xlarge (4 CPU, 16GB RAM):** 3 CPU, 6GB memory per container
  - **Auto-detection:** Script detects available resources and adjusts limits accordingly
- **Safe fallback:** If configured limits exceed capacity, script automatically reduces to safe values

**Health Checks:**
- Container startup verification
- Internal HTTP connectivity test
- External access validation
- Service log inspection

## Access Pentaho

**Primary:** `http://<ec2-private-ip>:80/pentaho`
- Login: admin/password

**Alternative (if needed):** SSH tunnel
```bash
ssh -L 80:localhost:80 -i ~/.ssh/your-key.pem ubuntu@<ec2-private-ip>
# Then: http://localhost:80/pentaho
```

## Post-Deployment

### Install License
1. Access `http://<server-ip>:80/pentaho`
2. Login with admin/password  
3. Go to Administration → Licenses
4. Upload your `.pentaho_license` file

3. **Navigate to License Management:**
   - Go to **Administration** → **Licenses**
   - Click **Add License**
   - Upload your `.pentaho_license` file or add your license server URL
   - Verify the license is accepted and shows valid dates

4. **Restart Pentaho services** (if required):
   ```bash
   ssh -i ~/.ssh/your-key.pem ubuntu@<ec2-ip>
   cd ~/pentaho/dockmaker/dock-maker-10.2.0.0-222/generatedFiles
   docker-compose restart pentahoServer
   ```

**Important:** Without a valid license, Pentaho will not run successfully.

## Troubleshooting

### Common Issues

#### 1. "No space left on device"
```
Error: write /var/lib/docker/...: no space left on device
```

**Solution:** Docker is not using EBS volume. Run Step 1 again or manually configure:
```bash
sudo service docker stop  
sudo mkdir -p /mnt/pentaho-data/docker
echo '{"data-root": "/mnt/pentaho-data/docker"}' | sudo tee /etc/docker/daemon.json
sudo service docker start
```

#### 2. Cannot Connect to EC2
```
Connection timeout or permission denied
```

**Solution:** Check security group and SSH key permissions:
```bash
# Verify security group allows SSH from your IP
aws ec2 describe-security-groups --group-names "pentaho-sg-test"

# Check SSH key permissions
chmod 400 ~/.ssh/your-key.pem
```

#### 3. AWS Authentication Issues (HV AD Users)
```
Unable to locate credentials or InvalidUserID.NotFound
```

**Solution:** Re-authenticate with Okta-AWS:
```bash
# Re-authenticate with your Okta profile
okta-aws ${yourprofile} sts get-caller-identity

# Verify authentication
aws sts get-caller-identity
```

**Note:** Okta-AWS tokens expire periodically. Re-run authentication if you get credential errors.

#### 5. License Installation
```
License file not found or invalid license in Pentaho interface
```

**Solution:** 
- Access Pentaho Administration Console: `http://your-server:80/pentaho`
- Navigate to Administration → Licenses
- Upload your `.pentaho_license` file through the web interface or add the license server url
- Verify the license is valid and not expired
- **Note:** License installation is done manually through the web interface, not during automated deployment

#### 6. Pentaho Not Responding
```
Containers start but Pentaho web interface not accessible
```

**Debugging:**
```bash
# Check container status
docker-compose ps

# View logs  
docker-compose logs pentahoServer

# Test internal connectivity
curl -I http://localhost:80/pentaho/Login

# Check port binding
netstat -tulpn | grep 80
```

### Log Files

The full deployment script creates detailed logs:
```
logs/
└── full-deployment-test-20250823-143022.log
```

Individual scripts log to stdout/stderr and can be redirected:
```bash
./01-create-pentaho-ec2.sh test 2>&1 | tee deployment.log
```

## Architecture

### Infrastructure Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         AWS VPC                             │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                    Public Subnet                        ││
│  │                                                         ││
│  │  ┌─────────────────────────────────────────────────────┐││
│  │  │               EC2 Instance                          │││
│  │  │            (t3.large/xlarge)                        │││
│  │  │                                                     │││
│  │  │  ┌─────────────────────────────────────────────────┐│││
│  │  │  │              Docker Engine                      ││││
│  │  │  │                                                 ││││
│  │  │  │  ┌─────────────────┐  ┌─────────────────────┐   ││││
│  │  │  │  │     Pentaho     │  │    PostgreSQL       │   ││││
│  │  │  │  │     Server      │  │    Database         │   ││││
│  │  │  │  │   Container     │  │    Container        │   ││││
│  │  │  │  │                 │  │                     │   ││││
│  │  │  │  │   Port 8080     │  │   Port 5432         │   ││││
│  │  │  │  └─────────────────┘  └─────────────────────┘   ││││
│  │  │  └─────────────────────────────────────────────────┘│││
│  │  │                                                     │││
│  │  │  Root FS (8GB)           EBS Volume (50GB)          │││
│  │  │  /                       /mnt/pentaho-data          │││
│  │  │  - OS & Apps             - Docker Images/Volumes    │││
│  │  │  - System Files          - Pentaho Data             │││
│  │  └─────────────────────────────────────────────────────┘││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘

         Security Group Rules:
         ┌────────────────────────────────┐
         │ SSH (22)    - Your IP Only     │
         │ HTTP (80)   - Your IP/Network  │  
         └────────────────────────────────┘
```

### Container Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          Docker Network                             │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │                    Pentaho Server Container                     ││
│  │                                                                 ││
│  │  ┌─────────────────────────────────────────────────────────────┐││
│  │  │                   Apache Tomcat                             │││
│  │  │                                                             │││
│  │  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐  │││
│  │  │  │ Pentaho Server  │  │   Analyzer      │  │  Reporting  │  │││
│  │  │  │   Web App       │  │   Plugin        │  │   Engine    │  │││
│  │  │  └─────────────────┘  └─────────────────┘  └─────────────┘  │││
│  │  └─────────────────────────────────────────────────────────────┘││
│  │                                                                 ││
│  │  Port 80 → EC2 Port 80                                       ││
│  │  CPU: 1.5 cores, Memory: 4GB                                    ││
│  └─────────────────────────────────────────────────────────────────┘│
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │                   PostgreSQL Container                          ││
│  │                                                                 ││
│  │  ┌─────────────────────────────────────────────────────────────┐││
│  │  │                PostgreSQL 15 Server                         │││
│  │  │                                                             │││
│  │  │  ┌─────────────────────────────────────────────────────────┐│││
│  │  │  │                   Databases:                            ││││
│  │  │  │   - hibernate (Pentaho Repository)                      ││││
│  │  │  │   - quartz (Scheduling)                                 ││││
│  │  │  │   - jackrabbit (Content Repository)                     ││││
│  │  │  └─────────────────────────────────────────────────────────┘│││
│  │  └─────────────────────────────────────────────────────────────┘││
│  │                                                                 ││
│  │  Port 5432 (Internal Only)                                      ││
│  │  Persistent Volume: /var/lib/postgresql/data                    ││
│  └─────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────┘

         External Access:
         ┌─────────────────────────────────────┐
         │  Direct: <ec2-ip>:80 (Primary)      │
         │  SSH Tunnel: localhost:80           │  
         │  Login: admin/password              │
         └─────────────────────────────────────┘
```

## Contributing

### Repository Structure

```
pentaho-docker-deploy/
├── 01-create-pentaho-ec2.sh          # EC2 provisioning
├── 02-download-pentaho-files.sh      # File transfer and setup  
├── 03-build-pentaho-containers.sh    # Container building
├── 04-deploy-pentaho.sh              # Container deployment
├── full-deployment.sh                # Automated full deployment
├── pentaho-deployment-sample.env     # Sample configuration
├── pentaho-downloads/                # Pentaho installation files
├── logs/                             # Deployment logs
└── experimental/                     # Experimental features (not production ready)
    ├── monitor-pentaho.sh            # Real-time monitoring dashboard
    ├── remote-monitor.sh             # Remote monitoring execution
    ├── install-monitor.sh            # Monitoring setup utility
    └── README.md                     # Experimental features documentation
```

**Note:** The `experimental/` directory contains proof-of-concept features that are not yet ready for production use. These are excluded from the main deployment workflow.

### Development Setup

1. **Fork and clone the repository**
2. **Create a development environment file:**
   ```bash
   cp pentaho-deployment-test.env pentaho-deployment-dev.env
   ```
3. **Add Pentaho files to `pentaho-downloads/`**
4. **Test changes in dev environment**

### Testing

Before submitting changes:

1. **Test full deployment flow:**
   ```bash
   ./full-deployment.sh dev
   ```

2. **Test individual scripts:**
   ```bash
   ./01-create-pentaho-ec2.sh dev
   ./02-download-pentaho-files.sh dev  
   ./03-build-pentaho-containers.sh dev full  # Use 'full' mode for non-interactive testing
   ./04-deploy-pentaho.sh dev
   ```

3. **Test teardown and cleanup:**
   ```bash
   ./teardown-instance.sh dev
   ```

---

## Support

For issues and questions:
- Check the [Troubleshooting](#troubleshooting) section
- Review deployment logs in the `logs/` directory  
- Open an issue in the GitHub repository

---

