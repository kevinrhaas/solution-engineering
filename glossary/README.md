# Database Schema Glossary Generator

A little bitty web service that analyzes database schemas and generates baseline hierarchical business glossaries using AI.

**Supports multiple databases:** PostgreSQL, MySQL/MariaDB, SQLite, SQL Server, Oracle, and any SQLAlchemy-compatible database.

## Quick Start

1. **Install dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

2. **Configure environment:**
   ```bash
   cp .env.example .env
   # Edit .env with your database and API credentials
   ```

3. **Run locally:**
   ```bash
   python app.py
   ```

4. **Test the service:**
   ```bash
   curl http://localhost:5000/health
   ```

## Environment Configuration

Create a `.env` file with your settings:

```bash
# Required
DATABASE_URL=postgresql://user:password@host:port/database
API_BASE_URL=your-ai-api-endpoint.com
API_KEY=your-api-key

# Optional (with defaults)
DATABASE_SCHEMA=public
API_DEPLOYMENT_ID=model-router
API_VERSION=2025-01-01-preview
API_MAX_TOKENS=8192
API_TEMPERATURE=0.7
API_TIMEOUT=60.0
API_MAX_RETRIES=3
PORT=5000
```

### Database URL Examples

**PostgreSQL:**
```
DATABASE_URL=postgresql://user:password@host:port/database
DATABASE_SCHEMA=public
```

**MySQL/MariaDB:**
```
DATABASE_URL=mysql://user:password@host:port/database
```

**SQLite:**
```
DATABASE_URL=sqlite:///path/to/database.db
```

**SQL Server:**
```
DATABASE_URL=mssql+pyodbc://user:password@host:port/database?driver=ODBC+Driver+17+for+SQL+Server
DATABASE_SCHEMA=dbo
```

## API Endpoints

### `GET /`
Service information and available endpoints

### `GET /health`
Health check with database connectivity test

### `GET /config`
View current configuration (sensitive values masked)

### `GET /prompts`
List available route-based prompt templates

**Response:**
```json
{
  "prompt_templates": {
    "analyze": {
      "name": "Database Schema Analyzer",
      "description": "Analyzes database schemas and generates comprehensive business glossaries"
    },
    "generate": {
      "name": "Glossary Format Generator",
      "description": "Transforms glossary data into different output formats"
    }
  },
  "available_routes": ["analyze", "generate"],
  "usage": "Each route automatically uses its corresponding prompt template",
  "count": 2
}
```

### `POST /analyze`
Generate business glossary from database schema

**Basic request:**
```bash
curl -X POST http://localhost:5000/analyze \
  -H "Content-Type: application/json" \
  -d "{}"
```

**Request with API overrides:**
```bash
curl -X POST http://localhost:5000/analyze \
  -H "Content-Type: application/json" \
  -d '{
  "database": {
    "url": "postgresql://user:pass@host:port/dbname?sslmode=require",
    "schema": "my_schema"
  }
}'

**Response:**
```json
{
  "success": true,
  "data": {
    "Business Glossary": [
      {
        "Customer Management": [
          "Customer",
          "Customer Segment",
          {
            "Customer Lifecycle": [
              "Customer Acquisition",
              "Customer Retention"
            ]
          }
        ]
      }
    ]
  },
  "metadata": {
    "tables_analyzed": 7,
    "schema_name": "public",
    "processing_time": 5.2,
    "ai_model_used": "model-router"
  }
}
```




### `POST /generate`
Transform glossary data into PDC export format with GUIDs and hierarchical relationships

**Request (uses output from /analyze):**
```bash
curl -X POST http://localhost:5000/generate \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "Healthcare Laboratory Operations": [
        {
          "Patients": [
            "Patient Identification",
            "Patient Demographics"
          ]
        },
        {
          "Tests": [
            "Test Code", 
            "Test Name"
          ]
        }
      ]
    }
  }'
```

**Response (CSV Download):**
The endpoint returns a CSV file with PDC-compatible format:

```csv
_id,name,type,fqdn,parentId,rootId,resourceId,createdAt,updatedAt,createdBy,updatedBy,attributes
2a5178c3-95c2-421e-b063-5392c7234936,Healthcare Laboratory Operations,glossary,Healthcare Laboratory Operations,,2a5178c3-95c2-421e-b063-5392c7234936,,2025-08-04T14:43:58.000Z,2025-08-04T14:43:58.000Z,system,system,"{""info"":{""status"":""Draft""}}"
c7c0e5a0-3000-4758-a44e-dee69249818e,Patients,category,Healthcare Laboratory Operations/Patients,2a5178c3-95c2-421e-b063-5392c7234936,2a5178c3-95c2-421e-b063-5392c7234936,,2025-08-04T14:43:58.000Z,2025-08-04T14:43:58.000Z,system,system,"{""info"":{""status"":""Draft""}}"
f1e4d3c2-b1a9-4567-8901-234567890abc,Patient Identification,term,Healthcare Laboratory Operations/Patients/Patient Identification,c7c0e5a0-3000-4758-a44e-dee69249818e,2a5178c3-95c2-421e-b063-5392c7234936,,2025-08-04T14:43:58.000Z,2025-08-04T14:43:58.000Z,system,system,"{""info"":{""status"":""Draft""}}"
```

**Headers:**
- `Content-Type: text/csv`
- `Content-Disposition: attachment; filename="glossary_export.csv"`

**Format Features:**
- **GUID-based IDs**: Each item has a unique identifier
- **Hierarchical Types**: `glossary` (root) → `category` (container) → `term` (leaf)
- **FQDN Paths**: Forward-slash separated fully qualified domain names
- **Parent-Child Relationships**: `parentId` and `rootId` maintain hierarchy
- **PDC Compatible**: Direct import into Pentaho Data Catalog

## Deployment

### 🚀 EC2 Deployment (One Instance Per Environment)

This service uses a **one-instance-per-environment** architecture with dedicated EC2 instances:

**Architecture:**
- **Dedicated Instances**: Each environment (prod, test, dev, staging) gets its own EC2 instance
- **Network**: Private VPC with direct RDS database connectivity
- **Consistent Port**: All environments run on port 80 (no port conflicts)
- **Cost**: ~$15/month per environment (instance + storage)

**Quick Deploy Commands:**
```bash
# Deploy any environment (creates instance if needed)
cd deploy/
./full-deploy.sh prod        # Production environment
./full-deploy.sh test        # Test environment
./full-deploy.sh dev         # Development environment

# Individual deployment steps
./01-create-ec2-instance.sh [environment]  # Create dedicated instance
./02-transfer-and-build.sh [environment]   # Transfer code and build
./03-deploy-app.sh [environment]           # Deploy application

# Check status of all environments
./90-status.sh                              # Show all environment status
./90-status.sh prod                         # Show specific environment
```

**Current Deployments:**
- **Production**: `http://[prod-instance-ip]` (example: `http://10.80.230.59`)
- **Test**: `http://[test-instance-ip]` (example: `http://10.80.230.124`)
- **Health Checks**: `http://[instance-ip]/health`
- **SSH Access**: `ssh -i "~/.ssh/pentaho+_se_keypair.pem" ec2-user@[instance-ip]`

**Infrastructure Benefits:**
- **Direct RDS Access**: Same VPC as airlinesample database - no network routing issues
- **Stable IP**: Private IP remains constant unless instance is terminated
- **Simple Management**: SSH access, Docker containers, standard Linux tools
- **Cost Effective**: Simple architecture without load balancers or complex networking

### Alternative Deployments

Previous deployment configurations (ECS Fargate, App Runner, etc.) are available in `deploy/archive/` for reference.

## API Request Options

### Route-Based Prompt Templates

The system uses route-based prompt templates stored in `prompts.json`:
- **`/analyze`**: Uses "analyze" prompt - analyzes database schemas and generates hierarchical business glossaries
- **`/generate`**: Uses "generate" prompt - transforms glossary data into PDC export format with GUIDs and parent-child relationships

Each route automatically uses its corresponding prompt template. Use `GET /prompts` to see all available routes and their descriptions.

### Two-Stage Workflow

1. **Analyze Database** → `/analyze` generates hierarchical business glossary from schema
2. **Generate PDC Export** → `/generate` transforms glossary into PDC format with GUIDs, types (glossary/category/term), and proper parent-child relationships

### API Parameter Overrides

You can override any API parameter per request while keeping environment defaults:

```json
{
  "api": {
    "temperature": 0.3,
    "max_tokens": 4096
  }
}
```

For the `/generate` endpoint, provide the data to transform:

```json
{
  "data": { /* hierarchical glossary data from /analyze */ },
  "api": {
    "temperature": 0.3
  }
}
```

The request overrides are merged with environment defaults, so you only need to specify what you want to change.
