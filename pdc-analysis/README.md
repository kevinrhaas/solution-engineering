# Pentaho Data Catalog Analysis
## BIDB Extensions

**Enterprise data governance analytics powered by dimensional modeling and multi-perspective time-based analysis.**

This foundational analytics platform transforms Pentaho Data Catalog metadata into actionable insights through a rigorously designed star schema, enabling comprehensive analysis of data assets across storage, lineage, governance, and environmental impact dimensions.

<img width="1130" height="828" alt="dowen" src="https://github.com/user-attachments/assets/0626fdd8-3a3f-4786-8652-6e77987091f7" />

## Project Structure

```
pdc-analysis/
├── analyzer/
│   ├── bidb_ext.xml                    # Production Mondrian schema (3-cube architecture)
│   ├── deprecated/                     # Archived schema versions
│   └── archive/                        # Legacy cube definitions
├── content/
│   └── public/pdc-analysis/
│       ├── analyzer/                   # 18 pre-built Analyzer reports (.xanalyzer + .locale)
│       ├── dashboards/                 # 6 executive dashboards (.xdash + .locale)
│       ├── ddl/                        # SQL scripts (deployed to Pentaho repository)
│       │   ├── 00-execute-all.sql      # Master DDL script (psql \ir orchestration)
│       │   ├── 01-setup/               # FDW, utilities, cleanup
│       │   ├── 02-staging/             # Staging materialized views
│       │   ├── 03-dimensions/          # 7 dimension tables
│       │   ├── 04-facts/               # 2 fact tables
│       │   ├── 05-refresh/             # Materialized view refresh
│       │   └── README.md               # Detailed DDL documentation
│       └── utility/
│           ├── sample-job-console.html          # Web UI for running jobs
│           ├── sample-variable-manager.html     # Web UI for managing runtime variables
│           ├── properties/
│           │   └── pdc_analysis.properties      # Runtime configuration (connection strings, credentials)
│           └── main/
│               ├── j-main-script.kjb            # Main orchestration job
│               ├── j-set-system-var.kjb         # Loads variables from properties file
│               ├── j-refresh-only.kjb           # Refresh-only job (skip DDL rebuild)
│               ├── t-execute-repo-file.ktr      # Dynamic SQL executor (fetches/splits/runs SQL from repo)
│               ├── t-set-variables-from-properties.ktr  # Properties file reader via BA Server API
│               ├── j-sample-variable-manager-set.kjb    # Variable set job wrapper
│               ├── j-sample-variable-manager-confirm.kjb # Variable get job wrapper
│               ├── t-sample-variable-manager-set.ktr    # Variable set transformation
│               └── t-sample-variable-manager-confirm.ktr # Variable get transformation
├── archive/
│   └── content-backup/                 # Timestamped backups from sync scripts (gitignored)
├── utility/
│   ├── migrate-server.sh               # Full server-to-server migration (content + /home + datasources)
│   ├── download.sh                     # Download single file or folder from repository
│   ├── upload.sh                       # Upload single file or folder to repository
│   ├── sync-content.sh                 # Bidirectional sync with timestamp-based conflict resolution
│   ├── push-content.sh                 # Smart sync UP to server (compare, backup server, push deltas)
│   ├── pull-content.sh                 # Smart sync DOWN from server (compare, backup local, pull deltas)
│   ├── push-cube.sh                    # Mondrian cube publishing via Analyzer API
│   ├── push-datasources.sh             # Import datasource definitions to server
│   ├── pull-datasources.sh             # Export datasource definitions from server
│   ├── pull-home-files.sh              # Download /home directory content file-by-file (bypasses legacy API restrictions)
│   └── push-home-files.sh              # Upload /home directory content to server (handles .ktr/.kjb zip extraction)
└── README.md
```

## Architecture

### Three-Cube Design
- **`01. Data Asset Analysis`** (Virtual Cube): Unified view combining entity-level and term-level analysis with comprehensive time-based context
- **`71. Entity Snapshot`**: Entity-grain fact table capturing storage metrics, child hierarchies, and 6 role-playing date dimensions
- **`72. Entity Term`**: Many-to-many associative fact linking entities to business glossary terms

### Dimensional Model
Built on a production-grade **PostgreSQL 17.7** star schema with **10 materialized views** providing sub-second query performance:

**Fact Tables:**
- `fact_entity_snapshot` - Daily entity snapshots with storage and hierarchy metrics
- `fact_entity_term` - Entity-to-term associations with time-based context

**Dimensions:**
- `dim_date` - Complete date range with Unknown handling (1900-01-01)
- `dim_entity` - Entity attributes (Name, Type, Path, FQDN, Owner, etc.)
- `dim_term` - Business glossary terms
- `dim_glossary_term` - 6-level business glossary hierarchy
- `dim_datasource` - Source system classification
- `dim_filetype` - File type taxonomy
- `dim_leaf_flag` - Leaf-term filter (true/false)

**Time-Based Analysis:**
- 6 role-playing date dimensions: Scanned, Created, Modified, Accessed, Last Update, Last Update Statistics
- Age calculations (months/years) for access patterns and data staleness detection
- Unknown date handling (1900-01-01) ensures drill-through always returns results

### Content Organization
**Pre-Built Analytics:**
- **18 Analyzer Reports** (`content/public/pdc-analysis/analyzer/`) - Detailed analysis reports covering temperature, sensitivity, resource types, and data sources
- **6 Executive Dashboards** (`content/public/pdc-analysis/dashboards/`) - High-level KPI views combining multiple analyzer widgets
- **Localization Files** (`.locale`) - Custom display names and descriptions for all reports and dashboards

**Dashboard Portfolio:**
- `D00-Data-Temperature.xdash` - Temperature-based analysis by business glossary levels with file type breakouts
- `D00-Exec-Summary-Storage-Overview.xdash` - Storage distribution with sunburst view for concentration risk
- `D00-Sensitivity-Analysis.xdash` - Sensitivity classification with scatter analysis for high-risk data
- `D00-Structured-Data-Footprint.xdash` - Structured object volume, scatter, and top-10 largest assets
- `D00-Top-Heavies-and-Hotspots.xdash` - Largest paths and objects for rapid remediation targeting
- `D00-Unstructured-Data-Footprint.xdash` - Unstructured size patterns and top-10 largest objects

### Business-First Organization
All dimensions and measures organized into numbered categories for intuitive navigation:
- **01-06**: Business dimensions (Data Source, Entity attributes, Terms)
- **05**: Time Attributes (date hierarchies, categorized separately from age metrics)
- **11-15**: Metrics (Object Volume, Storage Size, Child Containers, Total Children, Environmental Impact)

## Key Capabilities

**Storage Intelligence:**
- Multi-scale storage metrics (Bytes, GB, TB) with environmental CO2e impact
- Child/Total child hierarchy analysis for container objects
- Average object size calculations at any aggregation level

**Time-Based Governance:**
- Track when data was created, last modified, last accessed (filesystem timestamps)
- Track when metadata was updated, statistics refreshed (governance timestamps)
- Age-based analysis for data lifecycle and retention policy enforcement

**Lineage & Classification:**
- Entity-to-term associations for semantic layer integration
- Business glossary hierarchy (6 levels) for taxonomy rollups
- Cross-datasource analysis across AWS, AZURE, MSSQL, POSTGRES, SNOWFLAKE
- Resource type classification (Database, Schema, Table, Column, etc.)

**Performance:**
- Date dimension with full date range eliminates NULL join failures
- Indexed foreign keys on all date dimensions
- Materialized views for instant aggregation

## Quick Start

### Prerequisites
- PostgreSQL 17.7+ with `bidb_ext_demo` schema
- Pentaho Server 11.x running
- Pentaho Data Catalog with populated `entities_master_view` and `terms_view`

### Database Setup
```bash
# Option 1: Execute full DDL via psql (standalone)
psql -h <host> -U postgres -d bidb_ext_demo -f ddl/00-execute-all.sql
```

### Pentaho Processing Harness

The preferred execution path uses Pentaho jobs and transformations deployed to the BA Server repository. All processing artifacts live in `content/public/pdc-analysis/utility/`.

**Architecture:**
```
j-main-script.kjb
  ├── j-set-system-var.kjb           # Loads variables from pdc_analysis.properties
  │   └── t-set-variables-from-properties.ktr
  └── t-execute-repo-file.ktr        # Fetches SQL files from repo, splits, executes
```

**How it works:**
1. `j-main-script` calls `j-set-system-var` to load 15 runtime variables (DB hosts, credentials, schema names) from the properties file via the BA Server `generic-files` API
2. `t-execute-repo-file` iterates through a configurable data grid of SQL file paths, fetches each file's content from the repository via the `generic-files` API, performs Kettle variable substitution (`${VAR}` → resolved values), splits multi-statement SQL on semicolons (dollar-quote aware), and executes each statement against the target database
3. SQL files are added/removed by editing the data grid — no code changes required

**Execution:**
- **Web UI**: Open `sample-job-console.html` in Pentaho and click Run (path pre-configured to `j-main-script.kjb`)
- **REST API**: `curl -u admin:password "http://<server>/pentaho/kettle/runJob/?job=/public/pdc-analysis/utility/main/j-main-script"`

**Key Features:**
- Creates 10 materialized views (1 staging, 2 facts, 7 dimensions)
- Generates complete date range from MIN/MAX of all date fields + current date
- Unknown date (1900-01-01, key=19000101) for missing timestamps
- NULL date handling: All fact table date foreign keys use `COALESCE(to_char(ts::date, 'YYYYMMDD')::int, 19000101)`
- Default "No Glossary Available" member for missing glossary assignments
- Term fact includes glossary linkage via `glossary_term_key` for hierarchy rollups
- Indexes on all date foreign keys for optimal join performance
- Eliminates INNER JOIN failures that cause drill-through to return 0 rows

### Management Consoles

Two web-based management UIs are deployed to the Pentaho repository at `/public/pdc-analysis/utility/`:

**Sample Job Console** (`sample-job-console.html`)
- Run any Pentaho job from a browser with real-time status polling
- Pre-configured with `j-main-script.kjb` path
- Shows running/success/error status with detail messages
- Access: `http://<server>/pentaho/api/repos/:public:pdc-analysis:utility:sample-job-console.html/generatedContent`

**Sample Variable Manager** (`sample-variable-manager.html`)
- Get and set Kettle runtime variables through a browser UI
- Uses a get-then-set workflow: retrieve current value, modify, then apply
- Useful for changing connection parameters or toggling settings without editing files
- Access: `http://<server>/pentaho/api/repos/:public:pdc-analysis:utility:sample-variable-manager.html/generatedContent`

### Cube Deployment

```bash
cd utility
./push-cube.sh ../analyzer/bidb_ext.xml PDC-BIDB-EXT 10.80.230.193:80 admin password
```

**What happens:**
1. Uploads Mondrian schema to Pentaho Server
2. Binds to datasource (PDC-BIDB-EXT)
3. Refreshes Mondrian cache
4. Cubes immediately available in Analyzer

Access Analyzer at: `http://<server>:80/pentaho/plugin/jpivot/Pivot`

### Content Deployment

```bash
# Push all content to repository with auto-generated display titles (brute-force, uploads everything)
./utility/upload.sh --smart-title ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80 admin password

# Preview what would be uploaded without making changes
./utility/upload.sh --dry-run --smart-title ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80
```

### Content Sync (Push to Server)

```bash
# Preview what local changes would be pushed
./utility/push-content.sh --dry-run --smart-title ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80

# Push only new/changed local files — server versions backed up before overwrite
./utility/push-content.sh --smart-title ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80 admin password
```

**Sync-up behavior:**
- **New files** (local only): uploaded to server
- **Identical files**: skipped
- **Changed files**: server copy backed up to `archive/content-backup/<timestamp>/`, local version pushed to server

### Content Sync (Pull from Server)

```bash
# Preview changes without modifying local files
./utility/pull-content.sh --dry-run ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80 admin password

# Sync server content to local — backs up changed files, skips identical ones
./utility/pull-content.sh ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80 admin password
```

**Sync behavior:**
- **New files** (server only): downloaded to local directory
- **Identical files**: skipped
- **Changed files**: local copy backed up to `archive/content-backup/<timestamp>/` preserving directory structure, server version replaces the original

> **Note:** All sync scripts ignore timestamp comment lines in `.locale` files so that Pentaho's auto-generated export timestamps don't trigger false changes.

### Bidirectional Content Sync

```bash
# Preview bidirectional sync — shows reasoning for every conflict resolution decision
./utility/sync-content.sh --dry-run --smart-title ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80

# Sync both directions — newer file wins conflicts
./utility/sync-content.sh --smart-title ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80 admin password

# Force local files to win all conflicts
./utility/sync-content.sh --prefer-local --smart-title ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80 admin password

# Force server files to win all conflicts
./utility/sync-content.sh --prefer-server --smart-title ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80 admin password
```

**Bidirectional sync behavior:**
- **Local-only files**: pushed to server
- **Server-only files**: pulled to local
- **Identical files**: skipped
- **Conflicts** (different content on both sides):
  - Default: newer file wins based on modification timestamps
  - `--prefer-local`: local version always wins
  - `--prefer-server`: server version always wins
  - Losing version archived to `archive/content-backup/<timestamp>/`
- Dry run output shows conflict reasoning (e.g., "local newer: 2026-03-19 14:30 vs 2026-03-18 09:15")

## Technical Highlights

### Date Dimension Design
- **Complete date range**: MIN to MAX of all date fields + current date
- **Unknown date handling**: 1900-01-01 (date_key = 19000101) for NULL dates
- **Role-playing dates**: Single `dim_date` table reused 6+ times via foreign keys
- **No TimeDimension type**: Allows proper Analyzer categorization with annotations
- **Result**: Drill-through always works, no INNER JOIN failures on NULLs

### Schema Evolution Pattern
Uses numbered categories for forward-compatible organization:
```
01-06: Business dimensions
05: Time Attributes (date hierarchies)
05: Time Attributes (Year/Month Age) - separate category for age metrics
11-15: Measures by business function
70-79: Core/technical cubes
```

New dimensions/measures slot into appropriate number ranges without disrupting existing reports.

### Environmental Impact Calculation
CO2e estimates based on 0.35 metric tons per TB-year (industry standard):
- Calculated at TB scale: `(Size Bytes / 1099511627776) * 0.35`
- Also available in kg/year for smaller datasets
- Aggregates correctly across all dimension combinations

### Glossary Level Ordering
`dim_glossary_term` includes a `level_2_sort` key (Frozen=1, Cold=2, Warm=3, Hot=4, else 999) to enforce business‑friendly ordering in Analyzer.

## Utility Scripts

### migrate-server.sh
**One-command server-to-server migration — content, /home directories, and datasources**

```bash
./migrate-server.sh [flags] <source-server> <target-server> [user] [pass]
```

**Flags:**
- `--dry-run` — preview what would happen without making changes
- `--skip-content` — skip /public repository content
- `--skip-home` — skip /home directory content
- `--skip-ds` — skip datasources
- `--no-git` — skip git snapshot step
- `--content-path <path>` — repository path to migrate (default: `/public`)
- `--smart-title` — auto-generate display titles on push

**What it migrates:**
- Repository content (reports, dashboards, .xanalyzer, .xdash, .prpti, etc.)
- Home directory content (/home/* user files — transformations, jobs, analyses)
- Datasources: JDBC connections, Analysis/Mondrian schemas, DSW, Metadata

**What it does NOT migrate:**
- Server settings, LDAP/SSO config, email config
- Scheduled jobs/triggers
- User accounts & roles
- JNDI datasources (tomcat-level)
- Installed plugins & drivers

**Workflow:**
1. **Phase 1 — Pull**: downloads content, /home files, and datasources from source server
2. **Phase 2 — Snapshot**: commits pulled content to git (optional)
3. **Phase 3 — Push**: uploads everything to target server

**Examples:**
```bash
# Dry run — see what would be migrated
./migrate-server.sh --dry-run 10.80.230.123:80 10.80.230.225:80

# Full migration
./migrate-server.sh 10.80.230.123:80 10.80.230.225:80 admin password

# Content and /home only (skip datasources)
./migrate-server.sh --skip-ds 10.80.230.123:80 10.80.230.225:80

# Datasources only
./migrate-server.sh --skip-content --skip-home 10.80.230.123:80 10.80.230.225:80
```

> **Note:** /home content uses a file-by-file download via the `/inline` API endpoint to bypass the 403 restriction on legacy Pentaho servers. `.ktr` and `.kjb` files are automatically extracted from their export zip wrappers before uploading to the target server.

### push-cube.sh
**One-command Mondrian schema publishing with automatic cache refresh**

```bash
./push-cube.sh <xml-file> <datasource> <server[:port]> [user] [pass]
```

**Features:**
- Validates connectivity before upload
- Uses Data Source Analysis REST API
- Enables XMLA access automatically  
- Refreshes Mondrian cache (tries 2 endpoints)
- Exit code 0 = success, 1 = failure

**Example:**
```bash
./push-cube.sh ../analyzer/bidb_ext.xml PDC-BIDB-EXT 10.80.230.193:80 admin password
```

### upload.sh  
**Repository file/folder upload with smart titles and dry-run support**

```bash
./upload.sh [--dry-run] [--smart-title] [--title "Name"] <source> <repo-path> <server[:port]> [user] [pass]
```

**Features:**
- Single file or recursive directory upload
- `--smart-title` auto-generates display titles from filenames (e.g., `j-main-script.kjb` → "J Main Script")
- `--dry-run` previews actions without uploading
- Sets both locale properties and metadata for correct BA Server console display
- Binary upload mode (application/octet-stream) prevents encoding issues
- Automatically creates missing repository directories

**Examples:**
```bash
# Upload a folder with auto-generated titles
./upload.sh --smart-title ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80

# Upload a single file with an explicit title
./upload.sh --title "Main Script" j-main-script.kjb /public/pdc-analysis/utility/main 10.80.230.193:80

# Dry run
./upload.sh --dry-run --smart-title ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80
```

### pull-content.sh
**Smart sync DOWN from Pentaho Server — downloads, compares, and merges content**

```bash
./pull-content.sh [--dry-run] <local-dir> <repo-path> <server[:port]> [user] [pass]
```

**Features:**
- Downloads repository content and compares against local files
- Skips identical files (no unnecessary overwrites)
- Backs up locally changed files to `archive/content-backup/<timestamp>/` preserving directory structure
- `--dry-run` shows what would change without modifying anything
- Progress indicators during download and extraction
- Ignores timestamp comment lines in `.locale` files

**Examples:**
```bash
# Preview sync
./pull-content.sh --dry-run ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80

# Sync from server
./pull-content.sh ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80 admin password
```

### push-content.sh
**Smart sync UP to Pentaho Server — compares local against server, pushes only deltas**

```bash
./push-content.sh [--dry-run] [--smart-title] <local-dir> <repo-path> <server[:port]> [user] [pass]
```

**Features:**
- Pulls server content first, then compares against local files
- Only uploads files that are new or changed locally
- Backs up server versions to `archive/content-backup/<timestamp>/` before overwriting
- `--smart-title` auto-generates display titles from filenames
- `--dry-run` previews what would be pushed
- Ignores timestamp comment lines in `.locale` files

**Examples:**
```bash
# Preview what would be pushed
./push-content.sh --dry-run --smart-title ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80

# Push changes to server
./push-content.sh --smart-title ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80 admin password
```

### sync-content.sh
**Bidirectional content sync with timestamp-based conflict resolution**

```bash
./sync-content.sh [--dry-run] [--smart-title] [--prefer-local|--prefer-server] <local-dir> <repo-path> <server[:port]> [user] [pass]
```

**Features:**
- Single command replaces separate push-content.sh / pull-content.sh runs
- Downloads server content, compares against local files, syncs in both directions
- Local-only files pushed to server, server-only files pulled locally
- Conflicts resolved by file modification timestamp (newer wins) by default
- `--prefer-local` or `--prefer-server` overrides force a direction for all conflicts
- Losing versions archived to `archive/content-backup/<timestamp>/`
- `--dry-run` shows detailed reasoning for every sync decision and conflict resolution
- `--smart-title` auto-generates display titles for pushed files
- Ignores timestamp comment lines in `.locale` files
- Compatible with macOS (bash 3.2) and Linux

**Examples:**
```bash
# Dry run to see what would happen
./sync-content.sh --dry-run --smart-title ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80

# Full bidirectional sync
./sync-content.sh --smart-title ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80 admin password

# Force local wins on conflicts
./sync-content.sh --prefer-local --smart-title ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80 admin password
```

### pull-datasources.sh
**Datasource definitions export (Analysis, DSW, Metadata, JDBC)**

```bash
./pull-datasources.sh [--uncompress] <output-dir> <server[:port]> [user] [pass]
```

**Features:**
- Exports all datasource types separately
- Creates organized directory structure (analysis/, dsw/, metadata/, jdbc/)
- `--uncompress` automatically extracts ZIP exports
- Includes connection parameters and schema definitions

**Example:**
```bash
./pull-datasources.sh --uncompress ./datasource-exports 10.80.230.193:80 admin password
```

### push-datasources.sh
**Import datasource definitions back to server — counterpart to pull-datasources.sh**

```bash
./push-datasources.sh [--dry-run] <input-dir> <server[:port]> [user] [pass]
```

**Features:**
- Reads the same directory layout created by pull-datasources.sh
- Imports Analysis catalogs, DSW domains, Metadata domains, and JDBC connections
- `--dry-run` previews what would be imported
- Summary report with counts of uploaded/failed/skipped

**Example:**
```bash
./push-datasources.sh ./datasource-exports 10.80.230.193:80 admin password
```

### download.sh
**Download a single file or folder from repository — counterpart to upload.sh**

```bash
./download.sh [--dry-run] <repo-path> <local-path> <server[:port]> [user] [pass]
```

**Features:**
- Downloads a single file or entire folder from repository
- Auto-detects file vs folder (folder downloads arrive as zip, auto-extracted)
- `--dry-run` previews what would be downloaded

**Examples:**
```bash
# Download a single file
./download.sh /public/pdc-analysis/utility/main/j-main-script.kjb ./j-main-script.kjb 10.80.230.193:80

# Download a folder
./download.sh /public/pdc-analysis ./content/public/pdc-analysis 10.80.230.193:80
```

### pull-home-files.sh
**Download /home directory content file-by-file from Pentaho Server**

```bash
./pull-home-files.sh [--dry-run] <local-dir> <repo-path> <server[:port]> [user] [pass]
```

**Features:**
- Recursively lists all files under the given repo path using the REST API
- Downloads each file individually via the `/api/repo/files/{pathId}/inline` endpoint
- Bypasses the 403 restriction on `/home` directory exports in older Pentaho versions
- Falls back to `/download` endpoint if `/inline` fails
- `--dry-run` lists all files without downloading
- Summary report with total/downloaded/failed counts

**Examples:**
```bash
# Preview all /home files
./pull-home-files.sh --dry-run ./home-backup /home 10.80.230.123:80

# Download all /home content
./pull-home-files.sh ./home-backup /home 10.80.230.123:80 admin password

# Download only one user's home directory
./pull-home-files.sh ./admin-files /home/admin 10.80.230.123:80 admin password
```

### push-home-files.sh
**Upload /home directory content to Pentaho Server**

```bash
./push-home-files.sh [--dry-run] <local-dir> <server[:port]> [user] [pass]
```

**Features:**
- Iterates over all files in the local directory and uploads them to `/home/*` paths on the server
- Automatically creates missing directories on the target server
- Handles `.ktr`/`.kjb` files that were downloaded as Pentaho export bundles (zip-wrapped) — extracts the raw XML content before uploading to avoid HTTP 500 errors on Pentaho 11
- `--dry-run` previews what would be uploaded
- Summary report with total/uploaded/failed counts

**Examples:**
```bash
# Preview what would be pushed
./push-home-files.sh --dry-run ./home-backup 10.80.230.225:80

# Push all /home content to server
./push-home-files.sh ./home-backup 10.80.230.225:80 admin password
```

> **Note:** `pull-home-files.sh` downloads `.ktr`/`.kjb` files as zip-wrapped export bundles (containing the file plus an `exportManifest.xml`). `push-home-files.sh` automatically detects and extracts the raw XML before uploading. These scripts are called automatically by `migrate-server.sh` but can also be used standalone.

## Troubleshooting

**Drill-through returns 0 rows:**
- Check date keys populated: `SELECT COUNT(accessed_date_key) FROM fact_entity_term;`
- If NULLs exist, rebuild views with COALESCE to 19000101
- Verify 1900-01-01 exists in dim_date

**Dates not grouping in Analyzer:**
- Remove `type="TimeDimension"` from Date dimension
- Add annotations to ALL levels (Year, Month, Date) AND DimensionUsage elements
- Pattern: `<Annotation name="AnalyzerBusinessGroup">05. Time Attributes</Annotation>`

**Schema not appearing:**
- Verify datasource exists and is active
- Check connection: `curl http://<server>:<port>/pentaho/api/system/refresh/mondrianSchemaCache`
- Review catalina.out for Mondrian errors

**File upload errors (unmarshall boundary errors):**
- Use `upload.sh` which uses binary upload mode (`--data-binary`, not multipart form-data)

**Titles not showing in BA Server console:**
- `upload.sh --smart-title` sets both locale properties and metadata
- KJB/KTR display names come from the `/localeProperties` API, not `/metadata`
- Verify with: `curl -u admin:password http://<server>/pentaho/api/repo/files/<pathId>/localeProperties`

**Analyzer reports not loading after upload:**
- Verify `.locale` files uploaded alongside `.xanalyzer` and `.xdash` files
- Use `upload.sh` to upload entire directory structure recursively

## Database Schema Reference

**Materialized Views:**
```
mv_stg_entity_term          - Staging (entities + terms)
dim_date                    - Date dimension with Unknown
dim_entity                  - Entity attributes (name, type, path, FQDN, owner)
dim_term                    - Business glossary terms  
dim_glossary_term           - 6-level business glossary hierarchy
dim_datasource              - Source systems
dim_filetype                - File type taxonomy
dim_leaf_flag               - Leaf-term filter (true/false)
fact_entity_term            - Entity-term associations
fact_entity_snapshot        - Entity daily snapshots
```

**Date Foreign Keys:**
```sql
-- Entity Snapshot: 6 date dimensions
scanned_date_key, created_date_key, modified_date_key, 
accessed_date_key, last_update_date_key, last_update_statistics_date_key

-- Entity Term: 4 date dimensions  
created_date_key, modified_date_key, accessed_date_key, scanned_date_key
```

All use `COALESCE(to_char(ts::date, 'YYYYMMDD')::int, 19000101)` pattern.

## Content Files

**Analyzer Reports (18):** Located in `content/public/pdc-analysis/analyzer/`
- Temperature analysis (overall, file type, data source)
- Sensitivity analysis (overall, scatter, data source type)
- Resource type analysis (overall, structured, unstructured, data source, sunburst)
- Top paths and detailed breakdowns

**Executive Dashboards (6):** Located in `content/public/pdc-analysis/dashboards/`
- D00-Data-Temperature - Temperature-based analysis by glossary levels
- D00-Exec-Summary-Storage-Overview - Storage distribution with concentration risk
- D00-Sensitivity-Analysis - Sensitivity classification and high-risk identification
- D00-Structured-Data-Footprint - Structured object analysis and top-10 assets
- D00-Top-Heavies-and-Hotspots - Largest paths and objects for remediation
- D00-Unstructured-Data-Footprint - Unstructured size patterns and top-10 objects

**Localization:** Each report/dashboard has a corresponding `.locale` file controlling display names and descriptions in the Pentaho UI.

## Version History

**March 2026 - Content Sync & Smart Titles**
- `push-content.sh` smart sync UP: pulls server state, compares, pushes only new/changed files, backs up server versions
- `pull-content.sh` smart sync DOWN: compares server vs local, backs up changed files, skips identical
- Both sync scripts ignore `.locale` timestamp comments to prevent false positives
- `upload.sh` gains `--smart-title` (auto-generates display titles from filenames) and `--dry-run`
- Title setting uses locale properties API for correct BA Server console display
- Renamed scripts for consistency: `push-file.sh` → `upload.sh`, `publish-analyzer-cube.sh` → `push-cube.sh`
- New `download.sh`: download single file or folder from repository (counterpart to upload.sh)
- New `push-datasources.sh`: import datasource definitions (counterpart to pull-datasources.sh)
- Normalized `pull-datasources.sh` parameter order to match other scripts
- Pentaho Processing Harness: data-driven SQL executor (`t-execute-repo-file.ktr`) with dollar-quote-aware splitting
- Web management consoles: sample-job-console.html, sample-variable-manager.html

**February 2026 - Content Organization & Deployment Utilities**
- Reorganized analyzer reports into `/public/pdc-analysis/analyzer/` subfolder
- Added 6 executive dashboards in `/public/pdc-analysis/dashboards/`
- Enhanced utility scripts (pull-content, pull-datasources, upload with binary upload)
- Fixed multipart boundary issue in file uploads

**January 2026 - Star Schema Foundation**
- Complete dimensional model redesign
- 3-cube architecture (Virtual + 2 physical cubes)
- 6 role-playing date dimensions with Unknown handling
- Environmental impact metrics (CO2e)
- Business-first categorization system
- Eliminated aggregate tables (query from indexed facts)
