# Lineage Integration: pdc-analysis Data Model Extension

This document describes the design for integrating PDC lineage data into the `pdc-analysis` star
schema — extending it with new staging tables, dimensions, facts, and Mondrian cubes that follow all
existing DDL conventions in `bidb_ext`.

The files in this `lineage/` folder are the ETL foundation (PDI jobs and transformations) that this
design builds upon. The target implementation lives in `solution-engineering/pdc-analysis`.

---

## Context

The `pdc-analysis` project provides a PostgreSQL star schema (`bidb_ext`) backed by 22 materialized
views, 9 OLAP cubes, and 135+ Analyzer reports. All existing data flows from PDC's operational tables
via a Foreign Data Wrapper (FDW) into `mv_stg_entity_term`, then into 13 conformed dimensions and 8
fact MVs.

**The lineage problem:** PDC lineage events are not stored in the operational DB tables exposed by the
FDW. They are available only via a paginated REST API (Keycloak OAuth2 → GET `/lineage/api/events`).
The existing `lineage/` project (this folder) already solves this ingestion problem, storing raw events
in `pdc.lineage` and `pdc.connection` physical tables. We must extend that pattern into `bidb_ext` with
new physical staging tables → dimension MVs → fact MVs → Mondrian cubes, following all existing DDL
conventions exactly.

**Goal:** Add 3 new dimensions, 2 new facts, 2 new Mondrian cubes, and a lineage ETL job to `bidb_ext`,
enabling analysts to answer: which jobs move data between which entities, how often, what volumes, and
across what integration types — all joinable to the existing entity/glossary/datasource dimensions.

---

## Source Data: PDC Lineage API

**Auth:** `POST https://{PDC_HOST}/keycloak/realms/pdc/protocol/openid-connect/token`
- Body: `client_id=pdc-client&grant_type=password&username={PDC_USERNAME}&password={PDC_PASSWORD}&scope=openid`
- Returns: `{ "access_token": "...", "token_type": "Bearer" }`

**Events:** `GET https://{PDC_HOST}/lineage/api/events?perPage=100&page={N}`
- Header: `Authorization: Bearer {access_token}`
- Returns:
```json
{
  "events": [
    {
      "id": "...", "eventTime": "...", "eventType": "WRITE|READ|DELETE",
      "runid": "...", "jobName": "...", "processingType": "...",
      "integration": "...", "jobType": "...",
      "inNamespace": "...", "inNames": "pipe|delimited|list",
      "outNamespace": "...", "outNames": "pipe|delimited|list",
      "count": 12345.0,
      "eventDate": "...", "eventYear": 2025.0, "eventMonth": 5.0, "eventDay": 28.0
    }
  ],
  "hasNextPage": true
}
```

**Connections (derived in ETL from `t_PDC_lineage.ktr` explode step):**
Each event's `inNames`/`outNames` are cross-joined to produce (orig, dest) pairs, mirroring
`pdc.connection`:
- `OrigNamespace, OrigName, OrigDB, OrigSchema, OrigTable`
- `DestNamespace, DestName, DestDB, DestSchema, DestTable`
- `eventid, runid`

---

## Architecture Overview

```
PDC Lineage API  ──────────────────────────────────────────────────────────────
    │  (ETL: j-lineage-main.kjb)
    ▼
[ stg_lineage_event ]      ← physical TABLE, loaded by ETL (truncate + insert)
[ stg_lineage_connection ] ← physical TABLE, loaded by ETL (truncate + insert)
    │
    ▼  (REFRESH MATERIALIZED VIEW — same refresh-all.sql pattern as pdc-analysis)
[ dim_lineage_event_type ] (14)  [ dim_lineage_job ] (15)  [ dim_lineage_endpoint ] (16)
    │                                  │                           │
    ▼                                  ▼                           ▼
[ fact_lineage_event ]  (09)  ──────────────────────────────────────────────
[ fact_lineage_connection ] (10) ─── role-playing: source + dest endpoints
    │
    ▼
Mondrian: Cube 79 "Lineage Events" + Cube 80 "Data Lineage Connections"
```

---

## Layer 1: Physical Staging Tables

**File to create in pdc-analysis:** `ddl/01-setup/04-lineage-tables-setup.sql`

These are physical TABLEs (not MVs) because they are populated by the ETL job.
They use `CREATE TABLE IF NOT EXISTS` — they are NOT dropped by `03-drop-all-objects.sql`.
They persist across `execute-all.sql` runs so that MV creation can reference them.

```sql
-- staging tables for lineage data (loaded by PDI ETL, not FDW)
-- must exist before lineage dimension/fact MVs are created

CREATE TABLE IF NOT EXISTS stg_lineage_event (
    event_nk            TEXT        NOT NULL,   -- API event id (natural key)
    event_time          TIMESTAMP,              -- full timestamp
    event_type          TEXT,                   -- WRITE | READ | DELETE | etc.
    run_id              TEXT,
    job_name            TEXT,
    processing_type     TEXT,
    integration         TEXT,
    job_type            TEXT,
    in_namespace        TEXT,
    in_names            TEXT,                   -- pipe-delimited list
    out_namespace       TEXT,
    out_names           TEXT,                   -- pipe-delimited list
    input_count         INTEGER,                -- derived: cardinality of in_names
    output_count        INTEGER,                -- derived: cardinality of out_names
    record_count        DOUBLE PRECISION,       -- API "count" field (rows moved)
    event_date          DATE,
    load_ts             TIMESTAMP DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_sle_event_nk ON stg_lineage_event (event_nk);
CREATE INDEX IF NOT EXISTS idx_sle_event_date  ON stg_lineage_event (event_date);
CREATE INDEX IF NOT EXISTS idx_sle_event_type  ON stg_lineage_event (event_type);
CREATE INDEX IF NOT EXISTS idx_sle_job_name    ON stg_lineage_event (job_name);

CREATE TABLE IF NOT EXISTS stg_lineage_connection (
    connection_nk       TEXT        NOT NULL,   -- MD5(event_nk|orig_name|dest_name)
    event_nk            TEXT        NOT NULL,   -- FK → stg_lineage_event.event_nk
    run_id              TEXT,
    orig_namespace      TEXT,
    orig_name           TEXT,                   -- source entity FQDN / name
    orig_db             TEXT,
    orig_schema         TEXT,
    orig_table          TEXT,
    dest_namespace      TEXT,
    dest_name           TEXT,                   -- destination entity FQDN / name
    dest_db             TEXT,
    dest_schema         TEXT,
    dest_table          TEXT,
    load_ts             TIMESTAMP DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_slc_connection_nk ON stg_lineage_connection (connection_nk);
CREATE INDEX IF NOT EXISTS idx_slc_event_nk    ON stg_lineage_connection (event_nk);
CREATE INDEX IF NOT EXISTS idx_slc_orig_name   ON stg_lineage_connection (orig_name);
CREATE INDEX IF NOT EXISTS idx_slc_dest_name   ON stg_lineage_connection (dest_name);
```

**Why separate from the MV DDL run:** The FDW-based MVs can always be rebuilt from source because the
source data is live. Lineage staging tables are populated by a scheduled ETL job; they must not be
dropped when `execute-all.sql` is re-run. This matches how `pipeline_log` works in the existing model.

---

## Layer 2: New Dimensions (3)

### dim_lineage_event_type
**File:** `ddl/03-dimensions/14-dim-lineage-event-type.sql`

Modeled after `dim_pipeline_status` — static canonical values + observed fallback.

```sql
DROP MATERIALIZED VIEW IF EXISTS dim_lineage_event_type CASCADE;
CREATE MATERIALIZED VIEW dim_lineage_event_type AS
WITH observed AS (
    SELECT DISTINCT COALESCE(NULLIF(TRIM(event_type),''), 'UNKNOWN') AS event_type_nk
    FROM stg_lineage_event
),
canonical AS (
    SELECT 'WRITE'   AS event_type_nk UNION ALL
    SELECT 'READ'             UNION ALL
    SELECT 'DELETE'           UNION ALL
    SELECT 'UNKNOWN'
),
combined AS (
    SELECT event_type_nk FROM canonical
    UNION
    SELECT event_type_nk FROM observed
)
SELECT
    md5(lower(trim(event_type_nk)))         AS event_type_key,
    event_type_nk                           AS event_type_nk,
    CASE event_type_nk
        WHEN 'WRITE'   THEN '01. Write'
        WHEN 'READ'    THEN '02. Read'
        WHEN 'DELETE'  THEN '03. Delete'
        WHEN 'UNKNOWN' THEN '99. Unknown'
        ELSE '98. Other'
    END                                     AS event_type_label,
    CASE event_type_nk
        WHEN 'WRITE'   THEN 1
        WHEN 'READ'    THEN 2
        WHEN 'DELETE'  THEN 3
        WHEN 'UNKNOWN' THEN 99
        ELSE 98
    END                                     AS event_type_sort,
    CASE WHEN event_type_nk = 'WRITE'  THEN true ELSE false END AS is_write_flag,
    CASE WHEN event_type_nk = 'READ'   THEN true ELSE false END AS is_read_flag,
    CASE WHEN event_type_nk = 'DELETE' THEN true ELSE false END AS is_delete_flag
FROM combined;

CREATE UNIQUE INDEX idx_dlet_key    ON dim_lineage_event_type (event_type_key);
CREATE        INDEX idx_dlet_sort   ON dim_lineage_event_type (event_type_sort);
```

---

### dim_lineage_job
**File:** `ddl/03-dimensions/15-dim-lineage-job.sql`

Captures the processing context of each lineage-generating job — integration type, job framework, and
job name as a 3-level hierarchy for Mondrian drill-through.

```sql
DROP MATERIALIZED VIEW IF EXISTS dim_lineage_job CASCADE;
CREATE MATERIALIZED VIEW dim_lineage_job AS
WITH jobs AS (
    SELECT DISTINCT
        COALESCE(NULLIF(TRIM(integration), ''), 'Unknown')     AS integration,
        COALESCE(NULLIF(TRIM(job_type),    ''), 'Unknown')     AS job_type,
        COALESCE(NULLIF(TRIM(job_name),    ''), 'Unknown Job') AS job_name,
        COALESCE(NULLIF(TRIM(processing_type),''),'Unknown')   AS processing_type
    FROM stg_lineage_event
    UNION ALL
    SELECT 'Unknown', 'Unknown', 'Unknown Job', 'Unknown'
)
SELECT
    md5(
        lower(trim(integration))     || '|' ||
        lower(trim(job_type))        || '|' ||
        lower(trim(job_name))        || '|' ||
        lower(trim(processing_type))
    )                                AS lineage_job_key,
    integration,
    job_type,
    job_name,
    processing_type
FROM jobs;

CREATE UNIQUE INDEX idx_dlj_key          ON dim_lineage_job (lineage_job_key);
CREATE        INDEX idx_dlj_integration  ON dim_lineage_job (integration);
CREATE        INDEX idx_dlj_job_type     ON dim_lineage_job (job_type);
CREATE        INDEX idx_dlj_job_name     ON dim_lineage_job (job_name);
```

---

### dim_lineage_endpoint
**File:** `ddl/03-dimensions/16-dim-lineage-endpoint.sql`

Represents individual data endpoints (source OR destination) referenced in lineage connections.
Includes an `entity_key` column (MD5 of `endpoint_name`) that **intentionally matches** the key
pattern of `dim_entity.entity_key`, enabling cross-cube lookups without a separate join table.

```sql
DROP MATERIALIZED VIEW IF EXISTS dim_lineage_endpoint CASCADE;
CREATE MATERIALIZED VIEW dim_lineage_endpoint AS
WITH endpoints AS (
    -- sources
    SELECT
        COALESCE(NULLIF(TRIM(orig_namespace),''), 'Unknown') AS endpoint_namespace,
        COALESCE(NULLIF(TRIM(orig_name),     ''), 'Unknown') AS endpoint_name,
        COALESCE(NULLIF(TRIM(orig_db),       ''), 'Unknown') AS endpoint_db,
        COALESCE(NULLIF(TRIM(orig_schema),   ''), 'Unknown') AS endpoint_schema,
        COALESCE(NULLIF(TRIM(orig_table),    ''), 'Unknown') AS endpoint_table
    FROM stg_lineage_connection
    UNION
    -- destinations
    SELECT
        COALESCE(NULLIF(TRIM(dest_namespace),''), 'Unknown'),
        COALESCE(NULLIF(TRIM(dest_name),     ''), 'Unknown'),
        COALESCE(NULLIF(TRIM(dest_db),       ''), 'Unknown'),
        COALESCE(NULLIF(TRIM(dest_schema),   ''), 'Unknown'),
        COALESCE(NULLIF(TRIM(dest_table),    ''), 'Unknown')
    FROM stg_lineage_connection
    UNION ALL
    SELECT 'Unknown', 'Unknown', 'Unknown', 'Unknown', 'Unknown'
)
SELECT
    md5(lower(trim(endpoint_namespace)) || '|' || lower(trim(endpoint_name))) AS endpoint_key,
    -- entity_key matches dim_entity.entity_key for cross-cube analysis
    md5(lower(trim(endpoint_name)))      AS entity_key,
    endpoint_namespace,
    endpoint_name,
    endpoint_db,
    endpoint_schema,
    endpoint_table
FROM endpoints;

CREATE UNIQUE INDEX idx_dlep_key        ON dim_lineage_endpoint (endpoint_key);
CREATE        INDEX idx_dlep_entity_key ON dim_lineage_endpoint (entity_key);
CREATE        INDEX idx_dlep_namespace  ON dim_lineage_endpoint (endpoint_namespace);
CREATE        INDEX idx_dlep_db         ON dim_lineage_endpoint (endpoint_db);
CREATE        INDEX idx_dlep_schema     ON dim_lineage_endpoint (endpoint_schema);
CREATE        INDEX idx_dlep_table      ON dim_lineage_endpoint (endpoint_table);
```

---

## Layer 3: New Facts (2)

### fact_lineage_event
**File:** `ddl/04-facts/09-fact-lineage-event.sql`

Grain: one row per lineage event (atomic API event). This is the "header" fact — event-level measures
without the source/destination explosion.

```sql
DROP MATERIALIZED VIEW IF EXISTS fact_lineage_event CASCADE;
CREATE MATERIALIZED VIEW fact_lineage_event AS
SELECT
    -- Natural key (degenerate)
    md5(lower(trim(e.event_nk)))            AS lineage_event_nk,

    -- Dimension Foreign Keys
    md5(lower(trim(COALESCE(NULLIF(TRIM(e.event_type),''), 'UNKNOWN'))))
                                            AS event_type_key,
    md5(
        lower(trim(COALESCE(NULLIF(TRIM(e.integration),   ''),'Unknown'))) || '|' ||
        lower(trim(COALESCE(NULLIF(TRIM(e.job_type),      ''),'Unknown'))) || '|' ||
        lower(trim(COALESCE(NULLIF(TRIM(e.job_name),      ''),'Unknown Job'))) || '|' ||
        lower(trim(COALESCE(NULLIF(TRIM(e.processing_type),''),'Unknown')))
    )                                       AS lineage_job_key,

    -- Date Foreign Key (role-playing via dim_date)
    COALESCE(TO_CHAR(e.event_date, 'YYYYMMDD')::INT, 19000101)
                                            AS event_date_key,

    -- Degenerate Dimensions (stored in fact, not joined)
    e.run_id,
    e.in_namespace,
    e.out_namespace,

    -- Measures
    1                                       AS event_count,
    COALESCE(e.input_count,  0)             AS input_count,
    COALESCE(e.output_count, 0)             AS output_count,
    COALESCE(e.record_count, 0)::BIGINT     AS record_count

FROM stg_lineage_event e;

CREATE UNIQUE INDEX idx_fle_nk             ON fact_lineage_event (lineage_event_nk);
CREATE        INDEX idx_fle_event_type     ON fact_lineage_event (event_type_key);
CREATE        INDEX idx_fle_lineage_job    ON fact_lineage_event (lineage_job_key);
CREATE        INDEX idx_fle_event_date     ON fact_lineage_event (event_date_key);
```

---

### fact_lineage_connection
**File:** `ddl/04-facts/10-fact-lineage-connection.sql`

Grain: one row per source→destination endpoint pair per event. This is the "line" fact — the actual
data flow graph edge. Role-playing `source_endpoint_key` and `dest_endpoint_key` both join to
`dim_lineage_endpoint`. The `source_entity_key` / `dest_entity_key` columns (MD5 of name) allow
optional joining to `dim_entity` for cross-cube lineage impact analysis.

```sql
DROP MATERIALIZED VIEW IF EXISTS fact_lineage_connection CASCADE;
CREATE MATERIALIZED VIEW fact_lineage_connection AS
SELECT
    -- Natural key
    c.connection_nk                         AS lineage_connection_nk,

    -- Role-playing endpoint FKs (both → dim_lineage_endpoint)
    md5(
        lower(trim(COALESCE(NULLIF(TRIM(c.orig_namespace),''),'Unknown'))) || '|' ||
        lower(trim(COALESCE(NULLIF(TRIM(c.orig_name),    ''),'Unknown')))
    )                                       AS source_endpoint_key,
    md5(
        lower(trim(COALESCE(NULLIF(TRIM(c.dest_namespace),''),'Unknown'))) || '|' ||
        lower(trim(COALESCE(NULLIF(TRIM(c.dest_name),    ''),'Unknown')))
    )                                       AS dest_endpoint_key,

    -- Entity linkage keys (match dim_entity.entity_key for cross-cube joins)
    md5(lower(trim(COALESCE(NULLIF(TRIM(c.orig_name),''),'Unknown'))))
                                            AS source_entity_key,
    md5(lower(trim(COALESCE(NULLIF(TRIM(c.dest_name),''),'Unknown'))))
                                            AS dest_entity_key,

    -- Dimension FKs (from event context)
    md5(lower(trim(COALESCE(NULLIF(TRIM(e.event_type),''),'UNKNOWN'))))
                                            AS event_type_key,
    md5(
        lower(trim(COALESCE(NULLIF(TRIM(e.integration),   ''),'Unknown'))) || '|' ||
        lower(trim(COALESCE(NULLIF(TRIM(e.job_type),      ''),'Unknown'))) || '|' ||
        lower(trim(COALESCE(NULLIF(TRIM(e.job_name),      ''),'Unknown Job'))) || '|' ||
        lower(trim(COALESCE(NULLIF(TRIM(e.processing_type),''),'Unknown')))
    )                                       AS lineage_job_key,

    -- Date FK
    COALESCE(TO_CHAR(e.event_date, 'YYYYMMDD')::INT, 19000101)
                                            AS event_date_key,

    -- Degenerate Dimensions
    c.run_id,
    COALESCE(NULLIF(TRIM(c.orig_namespace),''), 'Unknown') AS orig_namespace,
    COALESCE(NULLIF(TRIM(c.orig_name),    ''), 'Unknown') AS orig_name,
    COALESCE(NULLIF(TRIM(c.orig_db),      ''), 'Unknown') AS orig_db,
    COALESCE(NULLIF(TRIM(c.orig_schema),  ''), 'Unknown') AS orig_schema,
    COALESCE(NULLIF(TRIM(c.orig_table),   ''), 'Unknown') AS orig_table,
    COALESCE(NULLIF(TRIM(c.dest_namespace),''),'Unknown') AS dest_namespace,
    COALESCE(NULLIF(TRIM(c.dest_name),    ''), 'Unknown') AS dest_name,
    COALESCE(NULLIF(TRIM(c.dest_db),      ''), 'Unknown') AS dest_db,
    COALESCE(NULLIF(TRIM(c.dest_schema),  ''), 'Unknown') AS dest_schema,
    COALESCE(NULLIF(TRIM(c.dest_table),   ''), 'Unknown') AS dest_table,

    -- Measures
    1                                       AS connection_count,
    COALESCE(e.record_count, 0)::BIGINT     AS record_count

FROM stg_lineage_connection c
LEFT JOIN stg_lineage_event e ON c.event_nk = e.event_nk;

CREATE UNIQUE INDEX idx_flc_nk               ON fact_lineage_connection (lineage_connection_nk);
CREATE        INDEX idx_flc_source_endpoint  ON fact_lineage_connection (source_endpoint_key);
CREATE        INDEX idx_flc_dest_endpoint    ON fact_lineage_connection (dest_endpoint_key);
CREATE        INDEX idx_flc_source_entity    ON fact_lineage_connection (source_entity_key);
CREATE        INDEX idx_flc_dest_entity      ON fact_lineage_connection (dest_entity_key);
CREATE        INDEX idx_flc_event_type       ON fact_lineage_connection (event_type_key);
CREATE        INDEX idx_flc_lineage_job      ON fact_lineage_connection (lineage_job_key);
CREATE        INDEX idx_flc_event_date       ON fact_lineage_connection (event_date_key);
```

---

## Layer 4: Mondrian Schema Extensions (`analyzer/bidb_ext.xml`)

### New Shared Dimensions (add before closing `</Schema>` tag)

```xml
<Dimension name="Lineage Event Type">
  <Hierarchy hasAll="true" primaryKey="event_type_key" allMemberName="All Event Types">
    <Table name="dim_lineage_event_type"/>
    <Level name="Event Type" column="event_type_key" nameColumn="event_type_label"
           ordinalColumn="event_type_sort" uniqueMembers="true" type="String"
           description="The type of lineage event (Write, Read, Delete).">
      <Annotations><Annotation name="AnalyzerBusinessGroup">30. Lineage</Annotation></Annotations>
    </Level>
  </Hierarchy>
</Dimension>

<Dimension name="Lineage Job">
  <Hierarchy hasAll="true" primaryKey="lineage_job_key" allMemberName="All Jobs">
    <Table name="dim_lineage_job"/>
    <Level name="Integration" column="integration" uniqueMembers="false" type="String"
           description="The integration platform (PDI, Spark, etc.).">
      <Annotations><Annotation name="AnalyzerBusinessGroup">30. Lineage</Annotation></Annotations>
    </Level>
    <Level name="Job Type" column="job_type" uniqueMembers="false" type="String"
           description="The type of job (Transformation, Job, etc.).">
      <Annotations><Annotation name="AnalyzerBusinessGroup">30. Lineage</Annotation></Annotations>
    </Level>
    <Level name="Job Name" column="lineage_job_key" nameColumn="job_name"
           uniqueMembers="true" type="String" description="The name of the job or transformation.">
      <Annotations><Annotation name="AnalyzerBusinessGroup">30. Lineage</Annotation></Annotations>
    </Level>
  </Hierarchy>
</Dimension>

<Dimension name="Lineage Endpoint">
  <Hierarchy hasAll="true" primaryKey="endpoint_key" allMemberName="All Endpoints">
    <Table name="dim_lineage_endpoint"/>
    <Level name="Namespace" column="endpoint_namespace" uniqueMembers="false" type="String"
           description="The namespace of the data endpoint.">
      <Annotations><Annotation name="AnalyzerBusinessGroup">30. Lineage</Annotation></Annotations>
    </Level>
    <Level name="Database" column="endpoint_db" uniqueMembers="false" type="String"
           description="The database of the data endpoint.">
      <Annotations><Annotation name="AnalyzerBusinessGroup">30. Lineage</Annotation></Annotations>
    </Level>
    <Level name="Schema" column="endpoint_schema" uniqueMembers="false" type="String"
           description="The schema of the data endpoint.">
      <Annotations><Annotation name="AnalyzerBusinessGroup">30. Lineage</Annotation></Annotations>
    </Level>
    <Level name="Table" column="endpoint_table" uniqueMembers="false" type="String"
           description="The table of the data endpoint.">
      <Annotations><Annotation name="AnalyzerBusinessGroup">30. Lineage</Annotation></Annotations>
    </Level>
    <Level name="Endpoint" column="endpoint_key" nameColumn="endpoint_name"
           uniqueMembers="true" type="String" description="The full endpoint identifier.">
      <Annotations><Annotation name="AnalyzerBusinessGroup">30. Lineage</Annotation></Annotations>
    </Level>
  </Hierarchy>
</Dimension>
```

---

### New Cube 79: Lineage Events

```xml
<Cube name="79. Lineage Events" cache="true" enabled="true">
  <Table name="fact_lineage_event"/>
  <DimensionUsage name="Lineage Event Type" source="Lineage Event Type"
                  foreignKey="event_type_key"/>
  <DimensionUsage name="Lineage Job" source="Lineage Job"
                  foreignKey="lineage_job_key"/>
  <Dimension name="Event Date" foreignKey="event_date_key">
    <Hierarchy hasAll="true" primaryKey="date_key" allMemberName="All Dates">
      <Table name="dim_date"/>
      <Level name="Event Year" column="year" type="Numeric" levelType="TimeYears"
             uniqueMembers="false" description="Year of the lineage event.">
        <Annotations><Annotation name="AnalyzerBusinessGroup">30. Lineage</Annotation></Annotations>
      </Level>
      <Level name="Event Year-Month" column="year_month_number" nameColumn="year_month_name"
             ordinalColumn="year_month_number" type="String" levelType="TimeMonths"
             uniqueMembers="false" description="Year-Month of the lineage event.">
        <Annotations><Annotation name="AnalyzerBusinessGroup">30. Lineage</Annotation></Annotations>
      </Level>
      <Level name="Event Date" column="date_key" nameColumn="full_date" type="Numeric"
             levelType="TimeDays" uniqueMembers="true" description="Date of the lineage event.">
        <Annotations><Annotation name="AnalyzerBusinessGroup">30. Lineage</Annotation></Annotations>
      </Level>
    </Hierarchy>
  </Dimension>

  <Measure name="Event Count"   column="event_count"   aggregator="sum"
           formatString="#,##0" description="Number of lineage events."/>
  <Measure name="Input Count"   column="input_count"   aggregator="sum"
           formatString="#,##0" description="Total number of input entities across events."/>
  <Measure name="Output Count"  column="output_count"  aggregator="sum"
           formatString="#,##0" description="Total number of output entities across events."/>
  <Measure name="Record Count"  column="record_count"  aggregator="sum"
           formatString="#,##0" description="Total rows moved across all lineage events."/>

  <CalculatedMember name="Average Records per Event" dimension="Measures"
                    formula="IIF([Measures].[Event Count] = 0, 0,
                             [Measures].[Record Count] / [Measures].[Event Count])"
                    formatString="#,##0.0"
                    description="Average row count moved per lineage event.">
    <Annotations><Annotation name="AnalyzerBusinessGroup">30. Lineage</Annotation></Annotations>
  </CalculatedMember>
  <CalculatedMember name="Avg Inputs per Event" dimension="Measures"
                    formula="IIF([Measures].[Event Count] = 0, 0,
                             [Measures].[Input Count] / [Measures].[Event Count])"
                    formatString="#,##0.0">
    <Annotations><Annotation name="AnalyzerBusinessGroup">30. Lineage</Annotation></Annotations>
  </CalculatedMember>
  <CalculatedMember name="Avg Outputs per Event" dimension="Measures"
                    formula="IIF([Measures].[Event Count] = 0, 0,
                             [Measures].[Output Count] / [Measures].[Event Count])"
                    formatString="#,##0.0">
    <Annotations><Annotation name="AnalyzerBusinessGroup">30. Lineage</Annotation></Annotations>
  </CalculatedMember>
</Cube>
```

---

### New Cube 80: Data Lineage Connections

```xml
<Cube name="80. Data Lineage Connections" cache="true" enabled="true">
  <Table name="fact_lineage_connection"/>

  <!-- Source endpoint: role-playing dim_lineage_endpoint -->
  <Dimension name="Source Endpoint" foreignKey="source_endpoint_key">
    <Hierarchy hasAll="true" primaryKey="endpoint_key" allMemberName="All Sources">
      <Table name="dim_lineage_endpoint"/>
      <Level name="Source Namespace" column="endpoint_namespace" uniqueMembers="false" type="String">
        <Annotations><Annotation name="AnalyzerBusinessGroup">30. Lineage</Annotation></Annotations>
      </Level>
      <Level name="Source Database" column="endpoint_db" uniqueMembers="false" type="String">
        <Annotations><Annotation name="AnalyzerBusinessGroup">30. Lineage</Annotation></Annotations>
      </Level>
      <Level name="Source Schema" column="endpoint_schema" uniqueMembers="false" type="String">
        <Annotations><Annotation name="AnalyzerBusinessGroup">30. Lineage</Annotation></Annotations>
      </Level>
      <Level name="Source Table" column="endpoint_table" uniqueMembers="false" type="String">
        <Annotations><Annotation name="AnalyzerBusinessGroup">30. Lineage</Annotation></Annotations>
      </Level>
      <Level name="Source" column="endpoint_key" nameColumn="endpoint_name"
             uniqueMembers="true" type="String" description="Source data endpoint.">
        <Annotations><Annotation name="AnalyzerBusinessGroup">30. Lineage</Annotation></Annotations>
      </Level>
    </Hierarchy>
  </Dimension>

  <!-- Destination endpoint: role-playing dim_lineage_endpoint -->
  <Dimension name="Destination Endpoint" foreignKey="dest_endpoint_key">
    <Hierarchy hasAll="true" primaryKey="endpoint_key" allMemberName="All Destinations">
      <Table name="dim_lineage_endpoint"/>
      <Level name="Destination Namespace" column="endpoint_namespace" uniqueMembers="false" type="String">
        <Annotations><Annotation name="AnalyzerBusinessGroup">30. Lineage</Annotation></Annotations>
      </Level>
      <Level name="Destination Database" column="endpoint_db" uniqueMembers="false" type="String">
        <Annotations><Annotation name="AnalyzerBusinessGroup">30. Lineage</Annotation></Annotations>
      </Level>
      <Level name="Destination Schema" column="endpoint_schema" uniqueMembers="false" type="String">
        <Annotations><Annotation name="AnalyzerBusinessGroup">30. Lineage</Annotation></Annotations>
      </Level>
      <Level name="Destination Table" column="endpoint_table" uniqueMembers="false" type="String">
        <Annotations><Annotation name="AnalyzerBusinessGroup">30. Lineage</Annotation></Annotations>
      </Level>
      <Level name="Destination" column="endpoint_key" nameColumn="endpoint_name"
             uniqueMembers="true" type="String" description="Destination data endpoint.">
        <Annotations><Annotation name="AnalyzerBusinessGroup">30. Lineage</Annotation></Annotations>
      </Level>
    </Hierarchy>
  </Dimension>

  <DimensionUsage name="Lineage Event Type" source="Lineage Event Type"
                  foreignKey="event_type_key"/>
  <DimensionUsage name="Lineage Job" source="Lineage Job"
                  foreignKey="lineage_job_key"/>

  <Dimension name="Connection Date" foreignKey="event_date_key">
    <Hierarchy hasAll="true" primaryKey="date_key" allMemberName="All Dates">
      <Table name="dim_date"/>
      <Level name="Connection Year" column="year" type="Numeric" levelType="TimeYears"
             uniqueMembers="false"/>
      <Level name="Connection Year-Month" column="year_month_number" nameColumn="year_month_name"
             ordinalColumn="year_month_number" type="String" levelType="TimeMonths"
             uniqueMembers="false"/>
      <Level name="Connection Date" column="date_key" nameColumn="full_date" type="Numeric"
             levelType="TimeDays" uniqueMembers="true"/>
    </Hierarchy>
  </Dimension>

  <Measure name="Connection Count" column="connection_count" aggregator="sum"
           formatString="#,##0" description="Number of source-to-destination data connections."/>
  <Measure name="Record Count"     column="record_count"     aggregator="sum"
           formatString="#,##0" description="Total rows moved across these connections."/>

  <CalculatedMember name="Avg Records per Connection" dimension="Measures"
                    formula="IIF([Measures].[Connection Count] = 0, 0,
                             [Measures].[Record Count] / [Measures].[Connection Count])"
                    formatString="#,##0.0"
                    description="Average rows moved per lineage connection.">
    <Annotations><Annotation name="AnalyzerBusinessGroup">30. Lineage</Annotation></Annotations>
  </CalculatedMember>
</Cube>
```

---

## Layer 5: Files to Modify in pdc-analysis

### `ddl/00-execute-all.sql`

Add to **PHASE 1 (Setup)**, after the data multiplier function step:
```sql
\ir 01-setup/04-lineage-tables-setup.sql
```

Add to **PHASE 3 (Dimensions)**, after `13-dim-pipeline-status.sql`:
```sql
\ir 03-dimensions/14-dim-lineage-event-type.sql
\ir 03-dimensions/15-dim-lineage-job.sql
\ir 03-dimensions/16-dim-lineage-endpoint.sql
```

Add to **PHASE 4 (Facts)**, after `08-fact-temperature-daily.sql`:
```sql
\ir 04-facts/09-fact-lineage-event.sql
\ir 04-facts/10-fact-lineage-connection.sql
```

---

### `ddl/01-setup/03-drop-all-objects.sql`

Add drops for the new MVs (staging tables are **not** dropped — they survive DDL rebuilds):
```sql
-- Lineage facts (drop first)
DROP MATERIALIZED VIEW IF EXISTS fact_lineage_connection CASCADE;
DROP MATERIALIZED VIEW IF EXISTS fact_lineage_event CASCADE;
-- Lineage dimensions
DROP MATERIALIZED VIEW IF EXISTS dim_lineage_endpoint CASCADE;
DROP MATERIALIZED VIEW IF EXISTS dim_lineage_job CASCADE;
DROP MATERIALIZED VIEW IF EXISTS dim_lineage_event_type CASCADE;
-- Note: stg_lineage_event and stg_lineage_connection are NOT dropped here
```

---

### `ddl/05-refresh/01-refresh-all.sql`

Add at the end, after `fact_temperature_daily`:
```sql
-- Lineage (depends only on stg_ physical tables, not on FDW MVs)
REFRESH MATERIALIZED VIEW dim_lineage_event_type;
REFRESH MATERIALIZED VIEW dim_lineage_job;
REFRESH MATERIALIZED VIEW dim_lineage_endpoint;
REFRESH MATERIALIZED VIEW fact_lineage_event;
REFRESH MATERIALIZED VIEW fact_lineage_connection;
```

---

## Layer 6: ETL Job (Lineage Ingestion)

**Location in pdc-analysis:** `content/public/pdc-analysis/utility/lineage/`

**Strategy:** Truncate + insert (full reload) matching this project's existing approach.

### Copy from this `lineage/` folder (no modification needed):
- `t_PDC_authenticate.ktr`
- `t_PDC_get_token.ktr`
- `t_PDC_RESTcall.ktr`
- `t_PDC_get_lineage.ktr`
- `t_PAGENO%2B%2B.ktr`

### New transformation: `t-load-lineage-stg.ktr`

Replaces `t_PDC_lineage.ktr` — targets `bidb_ext` schema instead of `pdc` schema.

Steps:
1. **Get Variables** — reads `HTTP_RESPONSE` from page-iterator
2. **JSON Input** — parses `$.events[*]` array
3. **Select / Rename Fields** — maps API fields to stg column names:
   - `id` → `event_nk`
   - `eventTime` → `event_time` (Timestamp)
   - `eventType` → `event_type`
   - `runid` → `run_id`
   - `jobName` → `job_name`
   - `processingType` → `processing_type`
   - `integration` → `integration`
   - `jobType` → `job_type`
   - `inNamespace` → `in_namespace`
   - `inNames` → `in_names`
   - `outNamespace` → `out_namespace`
   - `outNames` → `out_names`
   - `count` → `record_count`
   - `eventDate` → `event_date` (Date)
4. **String operations** — split `in_names` / `out_names` on `|`, count → `input_count` / `output_count`
5. **Table output** → `stg_lineage_event` (bidb_ext connection)
6. **Cartesian split** — cross-join `inNames × outNames` to build source/dest pairs
7. **MD5 key** — `connection_nk` = MD5(`event_nk|orig_name|dest_name`)
8. **Table output** → `stg_lineage_connection`

### New job: `j-lineage-main.kjb`

| Step | Action |
|------|--------|
| 1 | START |
| 2 | Set Variables — load `PDC_HOST`, `PDC_USERNAME`, `PDC_PASSWORD`, `PDC_LINEAGE_PAGE_SIZE` from properties |
| 3 | Truncate `stg_lineage_event` |
| 4 | Truncate `stg_lineage_connection` |
| 5 | Get Auth Token — `t_PDC_authenticate.ktr` → `t_PDC_get_token.ktr` |
| 6 | Paginate Events — modified `page-iterator.kjb` targeting `t-load-lineage-stg.ktr` |
| 7 | Refresh Lineage MVs — SQL: REFRESH 3 dims + 2 facts |
| 8 | SUCCESS |

### Properties (`pdc_analysis.properties`) — add:
```properties
PDC_HOST=https://<your-pdc-host>
PDC_USERNAME=<your-username>
PDC_PASSWORD=<your-password>
PDC_LINEAGE_PAGE_SIZE=100
```

---

---

## Layer 7: Analytics Layer — Analyzer Reports & Dashboards

The analytics layer delivers 13 Analyzer reports organized into 3 executive dashboards that surface
lineage insights across cubes 79 and 80. All files follow the existing `pdc-analysis` naming conventions
(prefix `19-*` for reports, `D8x` for dashboards) and are deployed alongside the existing reports in
`content/public/pdc-analysis/`.

---

### Dashboard D81: Lineage Activity Overview

**Purpose:** Volume, trends, and composition of lineage events across jobs and integrations.

**Business questions answered:**
- What proportion of lineage events are writes vs. reads?
- Is lineage activity growing month-over-month?
- Which jobs generate the most lineage events and move the most data?
- Which integration platforms (PDI, Spark, etc.) dominate?
- Are data flows expanding — are jobs touching more sources and destinations over time?

| Report file | Chart type | Cube | Rows | Columns | Measures |
|-------------|-----------|------|------|---------|---------|
| `19-lineage-event-type-mix.xanalyzer` | Donut | 79 | Event Type | — | Event Count |
| `19-lineage-event-trend.xanalyzer` | Line | 79 | Event Year-Month | — | Event Count, Record Count |
| `19-lineage-top-jobs.xanalyzer` | BarHorizontal | 79 | Job Name (top 25, DESC) | — | Event Count, Record Count |
| `19-lineage-integration-heatgrid.xanalyzer` | HeatGrid | 79 | Integration → Job Type | — | Event Count, Record Count, Avg Records/Event |
| `19-lineage-io-trend.xanalyzer` | Line | 79 | Event Year-Month | — | Input Count, Output Count, Event Count |

---

### Dashboard D82: Data Flow Map

**Purpose:** Source-to-destination connection topology — which data assets flow where and how much data
moves across each link.

**Business questions answered:**
- Which source namespaces produce the most outbound data connections?
- Which destination namespaces consume the most data?
- What does the full source → destination flow matrix look like?
- Are the number of connections and volume of records moved growing over time?
- What operation types (write, read, delete) drive the connections?

| Report file | Chart type | Cube | Rows | Columns | Measures |
|-------------|-----------|------|------|---------|---------|
| `19-lineage-flow-heatgrid.xanalyzer` | HeatGrid (matrix) | 80 | Source Namespace | Destination Namespace | Connection Count |
| `19-lineage-top-sources.xanalyzer` | BarHorizontal | 80 | Source Namespace (DESC) | — | Connection Count, Record Count |
| `19-lineage-top-destinations.xanalyzer` | BarHorizontal | 80 | Destination Namespace (DESC) | — | Connection Count, Record Count |
| `19-lineage-connection-trend.xanalyzer` | Line | 80 | Connection Year-Month | — | Connection Count, Record Count |
| `19-lineage-connection-by-type.xanalyzer` | Donut | 80 | Event Type | — | Connection Count |

**Key design note:** `19-lineage-flow-heatgrid.xanalyzer` uses both row and column attributes — Source
Namespace on rows, Destination Namespace on columns, Connection Count as the heat value — producing a
true source→destination matrix that is the visual centerpiece of lineage impact analysis.

---

### Dashboard D83: Lineage Operations Summary

**Purpose:** Executive KPI summary across lineage activity and data movement, combining pivot-table
detail with trend and heat visualizations.

**Business questions answered:**
- What are the total event and record volumes broken down by integration and job type?
- How does the mix of write vs. read events change over time?
- Which individual jobs move the most data per run (highest avg records per event)?
- Are connection volumes and record volumes trending together or diverging?

| Report file | Chart type | Cube | Rows | Columns | Measures |
|-------------|-----------|------|------|---------|---------|
| `19-lineage-kpi-pivot.xanalyzer` | Pivot table | 79 | Integration → Job Type | — | Event Count, Record Count, Input Count, Output Count, Avg Records/Event |
| `19-lineage-type-trend.xanalyzer` | Line (multi-series) | 79 | Event Year-Month | Event Type | Event Count |
| `19-lineage-job-heatgrid.xanalyzer` | HeatGrid | 79 | Job Name (top 50, DESC) | — | Event Count, Record Count, Avg Records/Event |
| `19-lineage-connection-trend.xanalyzer` | Line | 80 | Connection Year-Month | — | Connection Count, Record Count |

**Key design note:** `19-lineage-type-trend.xanalyzer` places Event Type in `columnAttributes`,
producing one line series per event type (Write, Read, Delete) over time — immediately revealing if
delete operations are rising relative to writes, a potential data governance signal.

---

### Deploying the Analytics Layer

1. Run `push-content.sh` to upload the new `19-*` analyzer reports and `D8x` dashboards to the PDC server.
2. Run `push-cube.sh` to publish the updated `bidb_ext.xml` (which includes cubes 79 and 80).
3. In PDC Analyzer, navigate to **Public > pdc-analysis > dashboards** and open **D81**, **D82**, **D83**.
4. Confirm each panel renders without "No data" errors (requires the lineage stg tables to be populated first).

---

## Summary: New Files

| File | Type | Purpose |
|------|------|---------|
| `ddl/01-setup/04-lineage-tables-setup.sql` | SQL | `CREATE TABLE IF NOT EXISTS` for stg_ tables |
| `ddl/03-dimensions/14-dim-lineage-event-type.sql` | SQL | `dim_lineage_event_type` MV |
| `ddl/03-dimensions/15-dim-lineage-job.sql` | SQL | `dim_lineage_job` MV |
| `ddl/03-dimensions/16-dim-lineage-endpoint.sql` | SQL | `dim_lineage_endpoint` MV |
| `ddl/04-facts/09-fact-lineage-event.sql` | SQL | `fact_lineage_event` MV |
| `ddl/04-facts/10-fact-lineage-connection.sql` | SQL | `fact_lineage_connection` MV |
| `utility/lineage/t-load-lineage-stg.ktr` | PDI | JSON parse + stg table loader |
| `utility/lineage/j-lineage-main.kjb` | PDI | Lineage ETL orchestrator |
| `utility/lineage/t_PDC_authenticate.ktr` | PDI | Copied from this folder |
| `utility/lineage/t_PDC_get_token.ktr` | PDI | Copied from this folder |
| `utility/lineage/t_PDC_RESTcall.ktr` | PDI | Copied from this folder |
| `utility/lineage/t_PDC_get_lineage.ktr` | PDI | Copied from this folder |
| `utility/lineage/t_PAGENO%2B%2B.ktr` | PDI | Copied from this folder |
| `utility/lineage/page-iterator.kjb` | PDI | Modified — point to new transformation |
| `analyzer/19-lineage-event-type-mix.xanalyzer` | Analyzer | Donut: Event Count by Event Type |
| `analyzer/19-lineage-event-trend.xanalyzer` | Analyzer | Line: Event Count + Record Count over time |
| `analyzer/19-lineage-top-jobs.xanalyzer` | Analyzer | BarHorizontal: Top 25 jobs by Event/Record Count |
| `analyzer/19-lineage-integration-heatgrid.xanalyzer` | Analyzer | HeatGrid: Volume by Integration × Job Type |
| `analyzer/19-lineage-io-trend.xanalyzer` | Analyzer | Line: Input/Output Count trend over time |
| `analyzer/19-lineage-flow-heatgrid.xanalyzer` | Analyzer | HeatGrid matrix: Source × Destination flow map |
| `analyzer/19-lineage-top-sources.xanalyzer` | Analyzer | BarHorizontal: Top source namespaces |
| `analyzer/19-lineage-top-destinations.xanalyzer` | Analyzer | BarHorizontal: Top destination namespaces |
| `analyzer/19-lineage-connection-trend.xanalyzer` | Analyzer | Line: Connection + Record Count trend |
| `analyzer/19-lineage-connection-by-type.xanalyzer` | Analyzer | Donut: Connection mix by Event Type |
| `analyzer/19-lineage-kpi-pivot.xanalyzer` | Analyzer | Pivot: KPIs by Integration × Job Type |
| `analyzer/19-lineage-type-trend.xanalyzer` | Analyzer | Line multi-series: Events by Type over time |
| `analyzer/19-lineage-job-heatgrid.xanalyzer` | Analyzer | HeatGrid: Volume + Avg Records by Job Name |
| `dashboards/D81-lineage-activity.xdash` | Dashboard | 5-panel: Lineage Activity Overview |
| `dashboards/D82-data-flow-map.xdash` | Dashboard | 5-panel: Data Flow Map |
| `dashboards/D83-lineage-operations-summary.xdash` | Dashboard | 4-panel: Operations KPI Summary |

## Summary: Modified Files

| File | Change |
|------|--------|
| `ddl/00-execute-all.sql` | Add `\ir` for setup/04, dims 14–16, facts 09–10 |
| `ddl/01-setup/03-drop-all-objects.sql` | Add DROP for 5 new lineage MVs (not stg tables) |
| `ddl/05-refresh/01-refresh-all.sql` | Add REFRESH for 5 new lineage MVs |
| `analyzer/bidb_ext.xml` | Add 3 SharedDimensions + Cube 79 + Cube 80 |
| `pdc_analysis.properties` | Add PDC connection properties |

---

## Key Design Decisions

1. **Physical tables for stg layer** — ETL writes data the same way as this project does; MVs sit on
   top. Unlike FDW tables, stg_ tables are not dropped by `drop-all`, preserving loaded data across
   DDL rebuilds. Same pattern as `pipeline_log` in the existing model.

2. **`dim_lineage_endpoint` with `entity_key`** — The `entity_key` column (MD5 of `endpoint_name`)
   matches `dim_entity.entity_key`, enabling cross-cube lineage impact analysis without a bridge table.
   A future virtual cube combining cubes 80 + 71 can expose which catalogued entities appear as
   lineage sources or destinations.

3. **Role-playing endpoints** — `source_endpoint_key` and `dest_endpoint_key` both reference
   `dim_lineage_endpoint`, exactly as multiple date FKs in `fact_entity_snapshot` all reference
   `dim_date`. The Mondrian cube uses two separate inline `<Dimension>` blocks (not `<DimensionUsage>`)
   to give them distinct names in Analyzer.

4. **Business group "30. Lineage"** — All new Mondrian members use this group so they appear in their
   own section in Analyzer's field list, separate from the existing 01–27 groups.

5. **Truncate-and-reload ETL** — Matches the existing lineage project pattern. For future incremental
   loads, add `UNIQUE` constraints on `event_nk` / `connection_nk` and switch to
   `ON CONFLICT DO UPDATE` — the MD5 natural keys are already designed for this transition.

6. **No changes to existing cubes or facts** — All lineage data lives in new objects; existing
   dashboards and reports are unaffected.

---

## Verification Steps

```sql
-- 1. Confirm staging tables exist and are populated after ETL run
SELECT event_type, COUNT(*), SUM(record_count) FROM stg_lineage_event GROUP BY 1;
SELECT COUNT(*) FROM stg_lineage_connection;

-- 2. Confirm dimension row counts
SELECT COUNT(*) FROM dim_lineage_event_type;  -- expect ≥ 4 rows
SELECT COUNT(*) FROM dim_lineage_job;          -- expect ≥ 1 + Unknown
SELECT COUNT(*) FROM dim_lineage_endpoint;     -- expect all unique source ∪ dest + Unknown

-- 3. Confirm fact row counts
SELECT COUNT(*) FROM fact_lineage_event;
SELECT COUNT(*) FROM fact_lineage_connection;

-- 4. Referential integrity: orphan date keys
SELECT COUNT(*) FROM fact_lineage_event f
LEFT JOIN dim_date d ON f.event_date_key = d.date_key WHERE d.date_key IS NULL;

-- 5. Referential integrity: orphan endpoint keys
SELECT COUNT(*) FROM fact_lineage_connection f
LEFT JOIN dim_lineage_endpoint e ON f.source_endpoint_key = e.endpoint_key
WHERE e.endpoint_key IS NULL;
```

After SQL validation:
- Run `push-cube.sh` to republish `bidb_ext.xml` and flush the Mondrian cache
- Open Analyzer → cube **79. Lineage Events** → drag Event Date to rows, Event Count to measures
- Open Analyzer → cube **80. Data Lineage Connections** → drill Source Namespace → Source → Destination
