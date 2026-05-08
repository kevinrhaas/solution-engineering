# PDC Automation

Shell-script toolkit for automating Pentaho Data Catalog (PDC) API workflows — ingestion, profiling, aggregation, collection management, entity tagging, and optional jobs. Scripts are thin wrappers that delegate to a single dispatcher (`pdc-action-dispatch.sh`) which handles authentication, dry-run mode, and payload injection.

Scripts are also invokable directly from the Ops Console **Manage → PDC Automation** panel.

## Quick Start

```bash
# 1. Check connectivity and authentication
./00-preflight.sh my-pdc.env

# 2. Run a full ingest cycle
./20-ingest.sh my-pdc.env

# 3. Run all steps in sequence
./run-all.sh my-pdc.env
```

All scripts take the **env file path** as the first argument.

## Prerequisites

| Requirement | Details |
|---|---|
| `curl` | HTTP calls to PDC API |
| `jq` | JSON parsing and payload construction |
| **PDC env file** | Contains `PDC_API_BASE_URL`, `PDC_API_USERNAME`, `PDC_API_PASSWORD` (or legacy aliases) |

## Environment File

Each script sources a `.env` file that configures the target PDC instance. Minimum required variables:

| Variable | Aliases | Description |
|---|---|---|
| `PDC_API_BASE_URL` | `PDC_SERVER_URL`, `PDC_URL`, `PENTAHO_HOST` | PDC server base URL |
| `PDC_API_USERNAME` | `PDC_USERNAME` | API username |
| `PDC_API_PASSWORD` | `PDC_PASSWORD` | API password |

The dispatcher auto-prepends `https://` if the URL has no scheme and appends `/api/public/v1` for all API calls.

## Scripts

| Script | Action | What It Does |
|---|---|---|
| `00-preflight.sh` | `preflight` | Validate token and check `/notifications` endpoint |
| `10-manage-datasource.sh` | `datasource` | Create a data source (POST `/data-sources`) |
| `20-ingest.sh` | `ingest` | Trigger metadata ingestion job |
| `30-create-collection.sh` | `collection` | Create a data collection |
| `40-profile.sh` | `profile` | Run data profiling job |
| `50-aggregate.sh` | `aggregate` | Run data aggregation job |
| `60-get-results.sh` | `results` | Retrieve profiling results for a collection |
| `70-tag-entities.sh` | `tagging` | Apply tags to an entity (requires `--param entity-id=<uuid>`) |
| `80-optional-jobs.sh` | `optional` | Run optional jobs: discovery, identification, pii, trust-score |
| `run-all.sh` | `run-all` | Run preflight baseline (explicit step payloads for subsequent steps) |

## Options

All scripts pass extra arguments through to `pdc-action-dispatch.sh`:

```bash
# Override the full request payload
./20-ingest.sh my-pdc.env --payload-json '{"scope":"full"}'

# Pass named parameters
./70-tag-entities.sh my-pdc.env --param entity-id=abc-123 --param tags=pii,sensitive

# Dry run — prints all API calls without executing them
./20-ingest.sh my-pdc.env --dry-run
```

### Optional Job Types

`80-optional-jobs.sh` supports selecting the job type via `--param`:

```bash
./80-optional-jobs.sh my-pdc.env --param job-type=discovery
./80-optional-jobs.sh my-pdc.env --param job-type=identification
./80-optional-jobs.sh my-pdc.env --param job-type=pii
./80-optional-jobs.sh my-pdc.env --param job-type=trust-score
```

## Typical Workflow

A full end-to-end catalog automation run follows this sequence:

```
00-preflight    → confirm connectivity
10-manage-datasource → register data source
20-ingest       → ingest metadata from data source
30-create-collection → group ingested assets into a collection
40-profile      → run profiling on the collection
50-aggregate    → aggregate profiling results
60-get-results  → retrieve and inspect results
70-tag-entities → apply governance tags to discovered entities
80-optional-jobs → run discovery, PII detection, or trust scoring
```

Steps can be run individually with custom payloads or all at once via `run-all.sh`.

## Technical Reference

### Dispatcher: `pdc-action-dispatch.sh`

All numbered scripts are thin wrappers that exec the dispatcher with their action name:

```bash
exec bash "$SCRIPT_DIR/pdc-action-dispatch.sh" ingest "$@"
```

The dispatcher:
1. Validates `ACTION` and `ENV_FILE_PATH` arguments
2. Sources the env file
3. Resolves the PDC base URL (handles scheme and path normalization)
4. Authenticates via `/auth` (OAuth2 password grant, `pdc-client`) and retrieves a bearer token
5. Parses `--payload-json`, `--param key=value`, and `--dry-run` flags
6. Calls the appropriate `run_<action>()` function

### Project Structure

```
pdc-automation/
├── pdc-action-dispatch.sh  # Core dispatcher — authentication, API calls, routing
├── 00-preflight.sh         # Connectivity and auth check
├── 10-manage-datasource.sh # Data source management
├── 20-ingest.sh            # Metadata ingestion
├── 30-create-collection.sh # Collection creation
├── 40-profile.sh           # Data profiling
├── 50-aggregate.sh         # Data aggregation
├── 60-get-results.sh       # Results retrieval
├── 70-tag-entities.sh      # Entity tagging
├── 80-optional-jobs.sh     # Optional job runner
└── run-all.sh              # Full sequence runner
```
