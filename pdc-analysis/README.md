# Pentaho Data Catalog Analytics

**Manage your data estate with key performance dashboards.**

Pentaho Data Catalog (PDC) supports assessment and optimization of your data estate across multiple dimensions. This project turns PDC metadata into a star‑schema warehouse, a Mondrian cube, and a curated set of Analyzer reports and dashboards so business users — not just engineers — can answer the questions that matter.

![Pentaho Data Catalog Analytics](https://github.com/user-attachments/assets/0626fdd8-3a3f-4786-8652-6e77987091f7)

## Analytics Categories

The platform is organized around eleven analytical perspectives. Each dashboard or report below maps to one or more of these categories.

| Category | What it answers | Coverage |
|---|---|---|
| **Storage Capacity** | Where is my data, how much, and where is it growing? | ✅ D10 Storage Footprint, D11 Storage Overview, D12 Structured / D13 Unstructured, D14 Top Heavies, `10-storage-by-data-source` |
| **Data Sensitivity** | Where is my regulated/sensitive data and is it protected? | ✅ D20 Data Sensitivity, D21 Sensitivity Analysis, `00-sensitivity-*` |
| **Policy Adherence** | Is the catalog actually being governed? Coverage by source? | ✅ D30 Policy Coverage, D31 Governance Health, `12-policy-*`, `10-governance-coverage`, `11-governance-mix-*` |
| **Data Source Usage** | Which sources contribute the most data and the most risk? | ✅ Cross‑cut on every dashboard, D40 Extension Trends, `00-resource-type-data-source-*` |
| **Data Quality** | How complete is the metadata? What's missing? | ✅ D31 Governance Health, `10-metadata-completeness`, `11-missing-attributes-by-source` |
| **PDC Administration** | Tag assessment, refresh status, repository health | ✅ D60 Pipeline Operations, `16-pipeline-*`, job consoles + variable manager (see *How to Configure*) |
| **PDC Application Usage** | How is PDC being used by people? | ✅ D70 Application Reach, `14-app-*` |
| **Data Temperature** *(Obsolescence)* | Which data is hot, warm, cold, frozen — and stale? | ✅ D80 Data Temperature, D83 Temperature Trends, `10-lifecycle-by-accessed-age`, `00-temperature-*`, `18-temperature-*` |
| **Redundant Data** | Where is duplicate / near‑duplicate content? | ✅ D90 Redundant Data Savings, `15-duplicate-*` (cube `75. Duplicate Savings`) |
| **Lineage Analysis** | What flows where? Term‑to‑entity reach? | ✅ Entity↔Term cube (`72. Entity Term`) + 6‑level glossary hierarchy |
| **Workflow / Collaboration** | Who owns what, who's accountable, who's the risk? | ✅ D95 Ownership Accountability, `10-owner-accountability`, `11-owner-risk-scatter` |
| **Cost Optimization / Planning** | What can be tiered or deleted? Sustainability impact? | ✅ D98 Cost Optimization, D10 Storage & Sustainability, `12-policy-cost-*`, `15-duplicate-savings-*`, `11-co2e-by-data-source`, `10-lifecycle-by-accessed-age` |

---

# Part 1 — How to Use

> **Audience:** business analysts, data stewards, executives. **Prerequisite:** the platform has been deployed (see *Part 2*).

## 1.1 Where to find everything

Open Pentaho User Console: **`http://<server>/pentaho/Home`** → **Browse Files** → **`/public/pdc-analysis/`**.

```
/public/pdc-analysis/
├── dashboards/      ← start here (executive views)
├── analyzer/        ← drill‑down reports (used as panels by dashboards)
└── utility/         ← admin tools (job console, variable manager)
```

## 1.2 Executive Dashboards

Double‑click any `.xdash` file to open it. Each dashboard is a single page of related panels.

The dashboard catalog is organized by the eleven analytics categories from the framework above. The tens digit of every dashboard ID maps to a category:

| Tens | Category |
|---|---|
| **D0x** | Executive roll‑up & cross‑cut |
| **D1x** | Storage Capacity |
| **D2x** | Data Sensitivity |
| **D3x** | Policy Adherence + Data Quality |
| **D4x** | Data Source Usage |
| **D6x** | PDC Administration |
| **D7x** | PDC Application Usage |
| **D8x** | Data Temperature (Obsolescence) |
| **D9x** | Redundant Data, Workflow / Collaboration, Cost Optimization, Cross‑cut |

### Executive Roll‑up

#### D00 — Executive Value Command Center
Single board with KPIs + storage by source + lifecycle + governance % + completeness % + top 10 owners. **Open this first.**

![D00 Executive Value Command Center](docs/screenshots/D00-Executive-Value-Command-Center.png)

#### D01 — Data Health Heatmap
Spot governance and quality gaps across the estate at a glance.

![D01 Data Health Heatmap](docs/screenshots/D01-Data-Health-Heatmap.png)

#### D99 — PDC Operations Overview
Cross‑cut snapshot: pipeline status, policy mix, app mix, redundancy, temperature.

![D99 PDC Operations Overview](docs/screenshots/D99-PDC-Operations-Overview.png)

### Storage Capacity (D1x)

#### D10 — Storage Footprint & Sustainability
Combine TB by source + lifecycle (accessed‑age) + CO₂e to make a tiering / archival case.

![D10 Storage Footprint and Sustainability](docs/screenshots/D10-Storage-Footprint-and-Sustainability.png)

#### D11 — Storage Overview
One‑glance picture of total storage and where it concentrates (sunburst).

![D11 Storage Overview](docs/screenshots/D11-Storage-Overview.png)

#### D12 — Structured Data Footprint
Profile relational/structured assets — counts, scatter, top‑10.

![D12 Structured Data Footprint](docs/screenshots/D12-Structured-Data-Footprint.png)

#### D13 — Unstructured Data Footprint
Profile files/objects — size patterns, top‑10 largest.

![D13 Unstructured Data Footprint](docs/screenshots/D13-Unstructured-Data-Footprint.png)

#### D14 — Top Heavies & Hotspots
Identify the largest paths and objects to target for remediation first.

![D14 Top Heavies and Hotspots](docs/screenshots/D14-Top-Heavies-and-Hotspots.png)

### Data Sensitivity (D2x)

#### D20 — Data Sensitivity
Locate regulated data across sources.

![D20 Data Sensitivity](docs/screenshots/D20-Data-Sensitivity.png)

#### D21 — Sensitivity Analysis
Drill into high‑risk sensitivity concentrations.

![D21 Sensitivity Analysis](docs/screenshots/D21-Sensitivity-Analysis.png)

### Policy Adherence & Data Quality (D3x)

#### D30 — Policy Coverage
Policy coverage breadth, top policies, coverage by source/owner, governed cost. Each chart shows a single metric.

![D30 Policy Coverage](docs/screenshots/D30-Policy-Coverage.png)

#### D31 — Governance Health
Coverage %, governed vs ungoverned counts, donut of governance status, missing attributes.

![D31 Governance Health](docs/screenshots/D31-Governance-Health.png)

### Data Source Usage (D4x)

#### D40 — Extension Trends
File extension distribution and trend by category, source, and time.

![D40 Extension Trends](docs/screenshots/D40-Extension-Trends.png)

### PDC Administration (D6x)

#### D60 — Pipeline Operations
ETL pipeline run health: success rates, runtimes, status mix and trend.

![D60 Pipeline Operations](docs/screenshots/D60-Pipeline-Operations.png)

### PDC Application Usage (D7x)

#### D70 — Application Reach
Application access reach by app, source, owner; type mix.

![D70 Application Reach](docs/screenshots/D70-Application-Reach.png)

### Data Temperature — Obsolescence (D8x)

#### D80 — Data Temperature
Hot / warm / cold / frozen distribution by glossary level and file type.

![D80 Data Temperature](docs/screenshots/D80-Data-Temperature.png)

#### D83 — Temperature Trends
Temperature mix and trend over time, by source.

![D83 Temperature Trends](docs/screenshots/D83-Temperature-Trends.png)

### Redundant Data (D9x)

#### D90 — Redundant Data Savings
Storage redundancy savings — bytes, cost, category, resource‑type breakdowns.

![D90 Redundant Data Savings](docs/screenshots/D90-Redundant-Data-Savings.png)

### Workflow / Collaboration (D9x)

#### D95 — Ownership Accountability
Find top owners by storage, plot owner‑risk (completeness × storage × ungoverned count).

![D95 Ownership Accountability](docs/screenshots/D95-Ownership-Accountability.png)

### Cost Optimization / Planning (D9x)

#### D98 — Cost Optimization
Cost rollups across policy, app, savings, temperature — single‑metric charts.

![D98 Cost Optimization](docs/screenshots/D98-Cost-Optimization.png)

## 1.3 Reading the panels — design rules

The dashboard panels follow a few deliberate rules. Knowing them helps you trust what you see.

1. **One metric per chart, one grain per axis.** Bars and donuts only ever show measures of the same kind (TB next to TB, % next to %, counts next to counts). Mixing grains in a single bar would be visually deceiving.
2. **Tables are for mixed metrics.** The KPI table (`10-exec-kpis`) is a native pivot — that's the only place TB, %, and counts coexist, and the table format makes the units obvious.
3. **Scatter / bubble for cross‑grain relationships.** When you see a bubble chart (e.g. **Owner Risk**), each axis intentionally encodes a *different* unit — that's what scatter is for.
4. **Stacked bars only stack same‑grain things.** "Governance Mix" stacks governed + ungoverned counts. "Missing Attributes" stacks three count metrics at the same grain.
5. **Naming convention.** Every panel title states the metric and the grain — e.g. *"Storage TB by Data Source"* — so you never have to guess.
6. **Asset Mix is unfiltered.** The Asset Mix donut on D10 reflects the full estate (no date filter) so the structured/unstructured split represents *total* composition, not a single scan window.

## 1.4 Drill, slice, and pivot

Every panel is a live Analyzer report — right‑click any cell to drill, change the chart, swap dimensions, or export to Excel/CSV. Standard slicers available across the catalog:

- **Time** — Scanned, Created, Modified, Accessed, Last Update, Last Update Statistics (6 role‑playing date dimensions). Filter by year/month or by *age in months/years* (e.g. "Accessed > 24 months").
- **Source** — Data Source Type (AWS, AZURE, MSSQL, POSTGRES, SNOWFLAKE, …) and Data Source Name.
- **Entity** — Type, Path, FQDN, Owner, Group.
- **Glossary** — 6‑level business glossary; sensitivity / temperature classifications.
- **Resource Type** — Database, Schema, Table, Column, File, etc.

## 1.5 Daily / weekly workflow

| Cadence | Open this | Look for |
|---|---|---|
| **Daily steward** | D31 Governance Health, D95 Ownership Accountability | New ungoverned entities, missing‑owner spikes |
| **Weekly architect** | D10 Storage & Sustainability, D14 Top Heavies, D90 Redundant Data | Growth deltas, archival candidates, savings opportunities |
| **Weekly ops** | D60 Pipeline Operations | Failed runs, runtime drift |
| **Monthly exec** | D00 Executive Value Command Center, D99 PDC Operations Overview | Trend in coverage %, completeness %, total TB & CO₂e, cross‑cut health |

---

# Part 2 — How to Configure

> **Audience:** Pentaho administrators and BI engineers deploying or upgrading the platform.

## 2.1 Prerequisites

- **PostgreSQL 17.7+** with the `bidb_ext_demo` schema (PDC's metadata target).
- **Pentaho Server 11.x** running, reachable at `http://<server>:80/pentaho`.
- **Pentaho Data Catalog** populated, with `entities_master_view` and `terms_view` available (FDW or direct).
- A workstation with `bash`, `curl`, `psql` to run the deploy scripts in `utility/`.

## 2.2 One‑time setup

### Step 1 — Build the warehouse

Two options, both produce the same 10 materialized views.

**A. Pentaho‑driven (preferred, repeatable):**

Run the orchestrator job `j-main-script.kjb` from the User Console. It calls `j-set-system-var` (loads connection strings + credentials from `utility/properties/pdc_analysis.properties`) and then `t-execute-repo-file.ktr` (iterates the SQL files in `ddl/`, performs `${VAR}` substitution, splits multi‑statement SQL on semicolons with dollar‑quote awareness, and executes against PostgreSQL).

Or trigger via REST:
```bash
curl -u admin:password "http://<server>/pentaho/kettle/runJob/?job=/public/pdc-analysis/utility/main/j-main-script"
```

**B. Direct psql (standalone):**
```bash
psql -h <host> -U postgres -d bidb_ext_demo -f content/public/pdc-analysis/ddl/00-execute-all.sql
```

### Step 2 — Publish the Mondrian cube

```bash
cd utility
./push-cube.sh ../analyzer/bidb_ext.xml PDC-BIDB-EXT 10.80.230.193:80 admin password
```

This uploads the schema, binds it to the `PDC-BIDB-EXT` JDBC datasource, enables XMLA, and refreshes the Mondrian cache. Cubes appear in Analyzer immediately.

### Step 3 — Publish dashboards, reports, and utility content

```bash
./utility/push-content.sh --smart-title \
  ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80 admin password
```

Smart sync — diffs local against the server, only uploads new/changed files, backs up server versions to `archive/content-backup/<timestamp>/` before overwriting. Add `--dry-run` first to preview.

## 2.3 Day‑two operations

### Refresh the warehouse on a schedule

Use `j-refresh-only.kjb` (skips DDL rebuild, just refreshes the materialized views) on a cron / Pentaho scheduler.

### Edit runtime variables without touching files

Open `http://<server>/pentaho/api/repos/:public:pdc-analysis:utility:sample-variable-manager.html/generatedContent` to get/set Kettle variables (DB hosts, credentials, schema names) through a browser UI.

### Run jobs from a browser

Open `http://<server>/pentaho/api/repos/:public:pdc-analysis:utility:sample-job-console.html/generatedContent` to launch any job with real‑time status polling.

### Push content from local edits

```bash
# Preview
./utility/push-content.sh --dry-run --smart-title ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80
# Push
./utility/push-content.sh --smart-title ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80 admin password
```

### Pull server content into git

```bash
./utility/pull-content.sh ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80 admin password
```

### Bidirectional sync (resolve by timestamp, prefer‑local, or prefer‑server)

```bash
./utility/sync-content.sh --smart-title ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80 admin password
./utility/sync-content.sh --prefer-local  ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80 admin password
./utility/sync-content.sh --prefer-server ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80 admin password
```

### Migrate to a new server

```bash
./utility/migrate-server.sh 10.80.230.123:80 10.80.230.225:80 admin password
```

Migrates `/public` content, `/home` user files, and datasource definitions (Analysis, DSW, Metadata, JDBC). Does **not** migrate server settings, LDAP/SSO, schedules, user accounts, JNDI, or installed plugins — those are platform‑level concerns.

## 2.4 Adding a new report or dashboard

1. Build it in Analyzer (use a single metric per chart unless you genuinely need cross‑grain comparison — then use scatter/bubble).
2. Save under `/public/pdc-analysis/analyzer/` or `/public/pdc-analysis/dashboards/`.
3. Pull into git: `./utility/pull-content.sh ./content/public/pdc-analysis /public/pdc-analysis <server>`.
4. Commit and push.

## 2.5 Adding a new SQL DDL step

1. Drop a new `.sql` file under `ddl/0X-*/` and reference it in `00-execute-all.sql` (psql `\ir`).
2. Add it to the data grid inside `t-execute-repo-file.ktr` so the harness picks it up.
3. Re‑run `j-main-script`.

---

# Part 3 — Technical Reference

> **Audience:** engineers extending the schema, the harness, or the deploy tooling.

## 3.1 Project layout

```
pdc-analysis/
├── analyzer/
│   ├── bidb_ext.xml                    # Production Mondrian schema (3-cube architecture)
│   ├── deprecated/                     # Archived schema versions
│   └── archive/                        # Legacy cube definitions
├── content/
│   └── public/pdc-analysis/
│       ├── analyzer/                   # 30+ pre-built Analyzer reports (.xanalyzer + .locale)
│       ├── dashboards/                 # 14 dashboards (.xdash + .locale)
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
│           ├── properties/pdc_analysis.properties  # Runtime config (connection strings, creds)
│           └── main/
│               ├── j-main-script.kjb            # Main orchestration job
│               ├── j-set-system-var.kjb         # Loads variables from properties file
│               ├── j-refresh-only.kjb           # Refresh-only job (skip DDL rebuild)
│               ├── t-execute-repo-file.ktr      # Dynamic SQL executor
│               └── t-set-variables-from-properties.ktr
├── archive/content-backup/             # Timestamped backups from sync scripts (gitignored)
├── utility/
│   ├── migrate-server.sh, download.sh, upload.sh
│   ├── sync-content.sh, push-content.sh, pull-content.sh
│   ├── push-cube.sh
│   ├── push-datasources.sh, pull-datasources.sh
│   └── pull-home-files.sh, push-home-files.sh
└── README.md
```

## 3.2 Architecture

### Three‑Cube Design
- **`01. Data Asset Analysis`** (Virtual Cube) — unified entity + term analysis with full time context.
- **`71. Entity Snapshot`** — entity‑grain fact table with storage metrics, child hierarchies, 6 role‑playing date dimensions.
- **`72. Entity Term`** — many‑to‑many associative fact linking entities to glossary terms.

### Dimensional Model (PostgreSQL 17.7, 10 materialized views)

**Fact tables**
- `fact_entity_snapshot` — daily entity snapshots (storage + hierarchy)
- `fact_entity_term` — entity‑to‑term associations with time context

**Dimensions**
- `dim_date` — complete date range with Unknown handling (1900‑01‑01)
- `dim_entity` — Name, Type, Path, FQDN, Owner, Group
- `dim_term` — business glossary terms
- `dim_glossary_term` — 6‑level business glossary hierarchy
- `dim_datasource` — source system classification
- `dim_filetype` — file type taxonomy
- `dim_leaf_flag` — leaf‑term filter

**Time‑based analysis**
- 6 role‑playing date dimensions: Scanned, Created, Modified, Accessed, Last Update, Last Update Statistics
- Age calculations (months/years) for staleness detection
- Unknown date (1900‑01‑01) ensures drill‑through always returns rows

### Business‑First Categorization
```
01-06: Business dimensions (Data Source, Entity attributes, Terms)
05:    Time Attributes (date hierarchies)
05:    Time Attributes — Year/Month Age (separate category for age metrics)
11-15: Measures (Object Volume, Storage Size, Children, Total Children, Environmental Impact)
70-79: Core/technical cubes
```

## 3.3 Pentaho Processing Harness

```
j-main-script.kjb
  ├── j-set-system-var.kjb           # Loads variables from pdc_analysis.properties
  │   └── t-set-variables-from-properties.ktr
  └── t-execute-repo-file.ktr        # Fetches SQL files from repo, splits, executes
```

`t-execute-repo-file.ktr` iterates a configurable data grid of SQL file paths, fetches each file via the BA Server `generic-files` API, performs `${VAR}` substitution, splits multi‑statement SQL on semicolons (dollar‑quote aware), and executes each statement against PostgreSQL. Adding/removing SQL is a data‑grid edit — no code changes.

**Outputs:**
- 10 materialized views (1 staging, 2 facts, 7 dimensions)
- Date dimension covering MIN→MAX of all date fields + current
- Unknown date row (1900‑01‑01, key=19000101) for missing timestamps
- All fact date FKs use `COALESCE(to_char(ts::date, 'YYYYMMDD')::int, 19000101)`
- Default "No Glossary Available" member for missing glossary assignments
- Term fact links to `glossary_term_key` for hierarchy rollups
- Indexes on every date FK

## 3.4 Utility Scripts (reference)

### `migrate-server.sh` — full server‑to‑server migration
```bash
./migrate-server.sh [flags] <source-server> <target-server> [user] [pass]
```
Flags: `--dry-run`, `--skip-content`, `--skip-home`, `--skip-ds`, `--no-git`, `--content-path <path>`, `--smart-title`. Runs in three phases: pull from source → snapshot to git → push to target. /home content uses file‑by‑file `/inline` API to bypass legacy 403 restrictions; `.ktr`/`.kjb` zip wrappers are auto‑extracted before re‑upload.

### `push-cube.sh` — Mondrian schema publishing
```bash
./push-cube.sh <xml-file> <datasource> <server[:port]> [user] [pass]
```
Validates connectivity, uploads via Data Source Analysis REST API, enables XMLA, refreshes Mondrian cache. Exit 0 on success.

### `upload.sh` — repository file/folder upload
```bash
./upload.sh [--dry-run] [--smart-title] [--title "Name"] <source> <repo-path> <server[:port]> [user] [pass]
```
Single file or recursive directory. `--smart-title` auto‑titles from filenames (`j-main-script.kjb` → "J Main Script"). Sets both locale properties and metadata. Binary upload mode (`--data-binary`, not multipart) prevents boundary errors.

### `download.sh` — counterpart to upload.sh
```bash
./download.sh [--dry-run] <repo-path> <local-path> <server[:port]> [user] [pass]
```
Auto‑detects file vs folder; folders arrive as zip and are auto‑extracted.

### `push-content.sh` — smart sync UP
```bash
./push-content.sh [--dry-run] [--smart-title] <local-dir> <repo-path> <server[:port]> [user] [pass]
```
Pulls server state, diffs against local, uploads only new/changed files, backs up server versions to `archive/content-backup/<timestamp>/`. Ignores `.locale` timestamp comments to avoid false positives.

### `pull-content.sh` — smart sync DOWN
```bash
./pull-content.sh [--dry-run] <local-dir> <repo-path> <server[:port]> [user] [pass]
```
Downloads server content, skips identical files, backs up locally‑changed files before overwrite.

### `sync-content.sh` — bidirectional sync
```bash
./sync-content.sh [--dry-run] [--smart-title] [--prefer-local|--prefer-server] \
    <local-dir> <repo-path> <server[:port]> [user] [pass]
```
Single command instead of separate push+pull. Conflicts resolved by mtime (newer wins) unless `--prefer-local`/`--prefer-server` overrides. Losing versions archived. Compatible with macOS bash 3.2 and Linux.

### `pull-datasources.sh` / `push-datasources.sh`
Export and import Analysis, DSW, Metadata, and JDBC definitions. Organized directory layout (`analysis/`, `dsw/`, `metadata/`, `jdbc/`). `--uncompress` extracts ZIP exports.

### `pull-home-files.sh` / `push-home-files.sh`
File‑by‑file `/home` directory transfer to bypass the 403 restriction on `/home` zip exports in older Pentaho versions. Falls back from `/inline` to `/download` on failure. Auto‑extracts `.ktr`/`.kjb` export bundles before re‑upload (avoids HTTP 500 on Pentaho 11).

## 3.5 Database Schema Reference

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

**Date Foreign Keys**
```sql
-- Entity Snapshot: 6 date dimensions
scanned_date_key, created_date_key, modified_date_key,
accessed_date_key, last_update_date_key, last_update_statistics_date_key

-- Entity Term: 4 date dimensions
created_date_key, modified_date_key, accessed_date_key, scanned_date_key
```
All use `COALESCE(to_char(ts::date, 'YYYYMMDD')::int, 19000101)`.

## 3.6 Design notes

**Date dimension** — complete range (MIN→MAX of all date fields + current) with Unknown=1900‑01‑01; 6 role‑playing usages off a single physical table; **no** `TimeDimension` type (so Analyzer categorizes properly via annotations); drill‑through never INNER‑JOIN‑fails on NULL.

**Environmental impact** — CO₂e at `(Size Bytes / 1099511627776) * 0.35` (industry standard 0.35 metric tons / TB‑year). Aggregates correctly across any dimension combo.

**Glossary level ordering** — `dim_glossary_term.level_2_sort` enforces business order (Frozen=1, Cold=2, Warm=3, Hot=4, else 999) instead of alphabetical.

**Single‑grain chart rule** — every `10-*` and `11-*` Analyzer report carries one metric (or same‑grain group). Mixed metrics live in pivot tables (`10-exec-kpis`) or in scatter/bubble (`11-owner-risk-scatter`) where each axis encodes a different unit on purpose.

## 3.7 Troubleshooting

**Drill‑through returns 0 rows**
- Check date keys: `SELECT COUNT(accessed_date_key) FROM fact_entity_term;`
- If NULLs exist, rebuild views with the COALESCE→19000101 pattern
- Verify the 1900‑01‑01 row exists in `dim_date`

**Dates not grouping in Analyzer**
- Remove `type="TimeDimension"` from the Date dimension
- Add `<Annotation name="AnalyzerBusinessGroup">05. Time Attributes</Annotation>` to **all** levels (Year, Month, Date) **and** to the `DimensionUsage` elements

**Schema not appearing**
- Verify the datasource exists and is active
- `curl http://<server>:<port>/pentaho/api/system/refresh/mondrianSchemaCache`
- Check `catalina.out` for Mondrian errors

**File upload "unmarshall boundary" errors**
- Use `upload.sh` (binary `--data-binary`, not multipart form‑data)

**Titles missing in BA Server console**
- `upload.sh --smart-title` sets both locale properties and metadata
- `.kjb`/`.ktr` display names come from `/localeProperties`, not `/metadata`
- Verify: `curl -u admin:password http://<server>/pentaho/api/repo/files/<pathId>/localeProperties`

**Analyzer reports won't load after upload**
- Confirm `.locale` files were uploaded alongside `.xanalyzer` / `.xdash`
- Use `upload.sh` for recursive directory uploads

## 3.8 Content Inventory

**Analyzer reports** (`content/public/pdc-analysis/analyzer/`)
- `00-*` — temperature, sensitivity, resource type, paths, scatter, sunburst, top‑10 (overall, structured, unstructured, by data source, by file type)
- `10-*` — single‑grain executive measures: storage TB by source, governance coverage %, lifecycle TB by accessed age, metadata completeness %, top‑10 owners, exec KPI pivot table
- `11-*` — governance & risk views: governance mix bar + donut, missing attributes by source, CO₂e by source, owner‑risk bubble scatter

**Dashboards** (`content/public/pdc-analysis/dashboards/`)
- `D00-*` — foundational views: storage overview, sensitivity, sensitivity analysis, structured / unstructured footprint, top heavies & hotspots, data temperature, data health heatmap
- `D01-*` / `D02-*` — temperature variations
- `D10` — Executive Value Command Center
- `D11` — Governance Health
- `D12` — Storage Footprint & Sustainability
- `D13` — Ownership Accountability

Every report and dashboard has a matching `.locale` file controlling display names and descriptions in the Pentaho UI. These files are uploaded with `_PERM_HIDDEN=true` (handled automatically by `push-content.sh`) so they don't clutter the user-facing file browser. If you see them in **Browse Files**, toggle off **View → Show Hidden Files**.

## Version History

**May 2026 — Strategic upgrade: 6 new cubes, 28 reports, 8 dashboards**
- 13 new materialized views in `bidb_ext_dev`: dim_policy, dim_application, dim_extension, dim_temperature, dim_currency, dim_pipeline_status, fact_entity_policy, fact_entity_application, fact_duplicate, fact_pipeline_run, fact_extension_daily, fact_temperature_daily (plus extended `dim_entity` with cost fallback)
- Mondrian cube schema extended: 7 new shared dimensions (Policy, Application, Extension, Temperature, Currency, Pipeline Status, Run Date) and 6 new cubes (`73. Entity Policy`, `74. Entity Application`, `75. Duplicate Savings`, `76. Pipeline Run`, `77. Extension Trend`, `78. Temperature Trend`)
- 28 new analyzer reports (`12-*` cost/policy, `13-*` policy detail, `14-*` application reach, `15-*` redundancy, `16-*` pipeline ops, `17-*` extension trends, `18-*` temperature trends)
- 8 new dashboards: D14 Policy Coverage, D15 Application Reach, D16 Duplicate Savings, D17 Pipeline Operations, D18 Extension Trends, D19 Temperature Trends, D20 Cost Optimization, D21 PDC Operations Overview
- Closes Roadmap items: ✅ Redundant Data, ✅ PDC Application Usage
- Cost-fallback pattern in `dim_entity`: `COALESCE(NULLIF(price,0)*fx, avg_by_source_type, global_avg, 0)` so cost rolls up even when source price is 0/null
- All builds & tests target `bidb_ext_dev`; production cutover is a single `currentSchema` flip on the `PDC-BIDB-EXT` Mondrian datasource

**May 2026 — Single‑grain dashboards & analytics‑category alignment**
- README restructured: How to Use → How to Configure → Technical Reference; mapped content to the 11 PDC analytics categories
- `10-*` reports refactored to single‑metric charts (one grain per axis)
- New `11-*` reports: governance mix (bar + donut), missing attributes, CO₂e by source, owner‑risk bubble scatter
- New dashboards D11 (Governance Health), D12 (Storage & Sustainability), D13 (Ownership Accountability)
- D10 Executive Value Command Center — panel titles updated to call out metric and grain

**March 2026 — Content sync & smart titles**
- `push-content.sh` / `pull-content.sh` smart sync with delta upload + server backup
- `sync-content.sh` bidirectional sync with timestamp / prefer‑local / prefer‑server resolution
- `upload.sh` gains `--smart-title` and `--dry-run`
- Renamed for consistency: `push-file.sh` → `upload.sh`, `publish-analyzer-cube.sh` → `push-cube.sh`
- New `download.sh`, `push-datasources.sh`
- Pentaho Processing Harness: data‑driven SQL executor with dollar‑quote‑aware splitting
- Web management consoles (job, variable manager)

**February 2026 — Content organization & deployment utilities**
- Reorganized analyzer reports into `/public/pdc-analysis/analyzer/`
- Added 6 executive dashboards under `/public/pdc-analysis/dashboards/`
- Binary‑upload fix for multipart boundary issue

**January 2026 — Star schema foundation**
- Complete dimensional model redesign, 3‑cube architecture
- 6 role‑playing date dimensions with Unknown handling
- Environmental impact metrics (CO₂e)
- Business‑first categorization
- Eliminated aggregate tables (query straight from indexed facts)
