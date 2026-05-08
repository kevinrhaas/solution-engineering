-- ============================================================================
-- PDC BUSINESS INTELLIGENCE DATABASE - DIMENSIONAL MODEL DDL
-- ============================================================================
-- This script creates the complete star schema for PDC analysis
-- Extracted from: j-main.kjb
-- Schema: bidb_ext_demo
-- Prerequisites: entities_master_view and terms_view must exist
-- ============================================================================

-- ============================================================================
-- DATA VOLUME MULTIPLIER (for demo/testing purposes)
-- ============================================================================
-- Set this to 1 for actual data, or higher values to inflate metrics for demos
-- Example: Set to 10 to show 10x the actual storage/counts
-- Change this one value and refresh materialized views to adjust data volume
DO $$
BEGIN
  -- Create or replace the multiplier function
  CREATE OR REPLACE FUNCTION get_data_multiplier() RETURNS numeric AS $func$
    SELECT 1::numeric;  -- Change this value: 1=actual, 10=10x, 100=100x, etc.
  $func$ LANGUAGE sql IMMUTABLE;
END $$;

-- ============================================================================
-- SECTION 1: DROP ALL OBJECTS (Dependency Order)
-- ============================================================================

-- Drop all materialized views in dependency order
-- (Facts first, then dimensions, then staging)

-- Fact tables
DROP MATERIALIZED VIEW IF EXISTS fact_entity_term CASCADE;
DROP MATERIALIZED VIEW IF EXISTS fact_entity_snapshot CASCADE;

-- Dimension tables
DROP MATERIALIZED VIEW IF EXISTS dim_term CASCADE;
DROP MATERIALIZED VIEW IF EXISTS dim_glossary_term CASCADE;
DROP MATERIALIZED VIEW IF EXISTS dim_filetype CASCADE;
DROP MATERIALIZED VIEW IF EXISTS dim_entity CASCADE;
DROP MATERIALIZED VIEW IF EXISTS dim_date CASCADE;
DROP MATERIALIZED VIEW IF EXISTS dim_datasource CASCADE;

-- Staging table (last, since others depend on it)
DROP MATERIALIZED VIEW IF EXISTS mv_stg_entity_term CASCADE;


-- ============================================================================
-- SECTION 2: CREATE STAGING LAYER
-- ============================================================================

CREATE MATERIALIZED VIEW mv_stg_entity_term AS
 SELECT emv._id AS entity_nk,
    emv."FqdnDisplay" AS entity_fqdn,
    tv."TermName" AS term_name,
    tv."GlossaryId" AS glossary_term_id,
    emv."DataSourceId" AS datasource_nk,
    emv."DataSourceName" AS datasource_name,
    emv."DataSourceType" AS datasource_type,
    emv."Name" AS entity_name,
    emv."Type" AS entity_type,
    emv."ResourceType" AS resource_type,
    emv."Path" AS path,
    emv."ParentPath" AS parent_path,
    emv."PathType" AS path_type,
    emv."FileExtension" AS file_extension,
    emv."Url" AS url,
    emv."PhysicalLocation" AS physicallocation,
    emv."Owner" AS owner_name,
    emv."Group" AS group_name,
    CASE
        WHEN (emv."FileType" ~~* 'parquet%'::text) THEN 'parquet'::text
        ELSE emv."FileType"
    END AS filetype,
    to_timestamp((emv."CreatedAt")::text, 'YYYY-MM-DD HH24:MI:SS'::text) AS created_ts,
    to_timestamp((emv."ModifiedAt")::text, 'YYYY-MM-DD HH24:MI:SS'::text) AS modified_ts,
    to_timestamp((emv."AccessedAt")::text, 'YYYY-MM-DD HH24:MI:SS'::text) AS accessed_ts,
    to_timestamp((emv."ScannedAt")::text, 'YYYY-MM-DD HH24:MI:SS'::text) AS scanned_ts,
    to_timestamp((emv."LastUpdate")::text, 'YYYY-MM-DD HH24:MI:SS'::text) AS last_update_ts,
    to_timestamp((emv."LastUpdateStatistics")::text, 'YYYY-MM-DD HH24:MI:SS'::text) AS last_update_statistics_ts,
    COALESCE(emv."Size", (0)::bigint) AS bytes
   FROM (entities_master_view emv
     LEFT JOIN terms_view tv ON ((emv."FqdnDisplay" = tv."FqdnDisplay")));


-- ============================================================================
-- SECTION 3: CREATE STAGING INDEXES
-- ============================================================================

-- Primary lookup columns
CREATE INDEX IF NOT EXISTS idx_stg_entity_nk ON mv_stg_entity_term(entity_nk);
CREATE INDEX IF NOT EXISTS idx_stg_datasource_nk ON mv_stg_entity_term(datasource_nk);
CREATE INDEX IF NOT EXISTS idx_stg_term_name ON mv_stg_entity_term(lower(trim(term_name)));

-- Date columns for time-based queries
CREATE INDEX IF NOT EXISTS idx_stg_created_ts ON mv_stg_entity_term(created_ts);
CREATE INDEX IF NOT EXISTS idx_stg_modified_ts ON mv_stg_entity_term(modified_ts);
CREATE INDEX IF NOT EXISTS idx_stg_scanned_ts ON mv_stg_entity_term(scanned_ts);

-- Composite for common filtering patterns
CREATE INDEX IF NOT EXISTS idx_stg_entity_datasource ON mv_stg_entity_term(entity_nk, datasource_nk);


-- ============================================================================
-- SECTION 4: CREATE DIMENSION TABLES
-- ============================================================================

-- ============================================================================
-- DIMENSION: DATE (with Unknown date 1900-01-01)
-- ============================================================================

CREATE MATERIALIZED VIEW dim_date AS
WITH date_range AS (
  -- Get min/max dates from all timestamp fields
  SELECT 
    LEAST(
      MIN(created_ts::date),
      MIN(modified_ts::date),
      MIN(accessed_ts::date),
      MIN(scanned_ts::date),
      MIN(last_update_ts::date),
      MIN(last_update_statistics_ts::date)
    ) AS min_date,
    GREATEST(
      MAX(created_ts::date),
      MAX(modified_ts::date),
      MAX(accessed_ts::date),
      MAX(scanned_ts::date),
      MAX(last_update_ts::date),
      MAX(last_update_statistics_ts::date),
      CURRENT_DATE
    ) AS max_date
  FROM mv_stg_entity_term
),
all_dates AS (
  -- Generate complete date range
  SELECT generate_series(
    (SELECT min_date FROM date_range),
    (SELECT max_date FROM date_range),
    '1 day'::interval
  )::date AS d
  
  UNION
  
  -- Add Unknown date
  SELECT '1900-01-01'::date
)
SELECT
  to_char(d, 'YYYYMMDD')::int AS date_key,
  d AS full_date,
  extract(year FROM d)::int AS year,
  extract(month FROM d)::int AS month,
  extract(day FROM d)::int AS day,
  extract(dow FROM d)::int AS day_of_week,
  CASE WHEN d = '1900-01-01'::date THEN true ELSE false END AS is_unknown
FROM all_dates;


-- ============================================================================
-- DIMENSION: TERM (with default "No Term Available")
-- ============================================================================

CREATE MATERIALIZED VIEW dim_term AS
SELECT
  md5(lower(trim(term_name))) AS term_key,
  term_name
FROM mv_stg_entity_term
WHERE term_name IS NOT NULL
GROUP BY 1, 2

UNION ALL

-- Default member for entities without terms
SELECT
  'unknown'::text AS term_key,
  'No Term Available'::text AS term_name;


-- ============================================================================
-- DIMENSION: GLOSSARY TERM (6-level hierarchy)
-- ============================================================================

CREATE MATERIALIZED VIEW dim_glossary_term AS
SELECT
  _id AS glossary_term_id,
  "Name" AS term_name,
  "Type" AS term_type,
  "Fqdn" AS term_fqdn,
  "Parent" AS parent_id,
  
  -- Parse FQDN into 6 levels (handles ragged hierarchies with NULLs)
  SPLIT_PART("Fqdn", '/', 1) AS level_1_glossary,
  NULLIF(SPLIT_PART("Fqdn", '/', 2), '') AS level_2,
  NULLIF(SPLIT_PART("Fqdn", '/', 3), '') AS level_3,
  NULLIF(SPLIT_PART("Fqdn", '/', 4), '') AS level_4,
  NULLIF(SPLIT_PART("Fqdn", '/', 5), '') AS level_5,
  NULLIF(SPLIT_PART("Fqdn", '/', 6), '') AS level_6,
  
  -- Calculate hierarchy depth
  ARRAY_LENGTH(STRING_TO_ARRAY("Fqdn", '/'), 1) AS hierarchy_depth,
  
  -- Flag for leaf terms
  CASE 
    WHEN "Type" = 'term' 
      AND NOT EXISTS (
        SELECT 1 FROM glossary_summary_view child 
        WHERE child."Parent" = glossary_summary_view._id
      )
    THEN true
    ELSE false
  END AS is_leaf_term,
  
  -- Get the leaf name (last segment of FQDN)
  SPLIT_PART("Fqdn", '/', ARRAY_LENGTH(STRING_TO_ARRAY("Fqdn", '/'), 1)) AS leaf_name
  
FROM glossary_summary_view;


-- ============================================================================
-- DIMENSION: ENTITY
-- ============================================================================

CREATE MATERIALIZED VIEW dim_entity AS
SELECT 
  md5(entity_nk) AS entity_key,
  entity_nk,
  entity_fqdn,
  entity_name,
  entity_type,
  resource_type,
  path,
  parent_path,
  owner_name,
  group_name,
  filetype,
  file_extension,
  path_type,
  url,
  physicallocation,
  datasource_nk
FROM (
  SELECT DISTINCT ON (entity_nk) 
    entity_nk,
    entity_fqdn,
    entity_name,
    entity_type,
    resource_type,
    path,
    parent_path,
    owner_name,
    group_name,
    filetype,
    file_extension,
    path_type,
    url,
    physicallocation,
    datasource_nk
  FROM mv_stg_entity_term
  WHERE entity_nk IS NOT NULL
  ORDER BY entity_nk
) x;


-- ============================================================================
-- DIMENSION: DATA SOURCE
-- ============================================================================

CREATE MATERIALIZED VIEW dim_datasource AS
SELECT
  md5(datasource_nk) AS datasource_key,
  datasource_nk,
  datasource_name,
  datasource_type
FROM mv_stg_entity_term
WHERE datasource_nk IS NOT NULL
GROUP BY 1, 2, 3, 4;


-- ============================================================================
-- DIMENSION: FILE TYPE (with default "No File Type Available")
-- ============================================================================

CREATE MATERIALIZED VIEW dim_filetype AS
SELECT
  md5(lower(trim(filetype))) AS filetype_key,
  filetype
FROM mv_stg_entity_term
WHERE filetype IS NOT NULL
GROUP BY 1, 2

UNION ALL

-- Default member for entities without file types
SELECT
  'unknown'::text AS filetype_key,
  'No File Type Available'::text AS filetype;


-- ============================================================================
-- SECTION 5: CREATE DIMENSION INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_dim_entity_key ON dim_entity(entity_key);
CREATE INDEX IF NOT EXISTS idx_dim_term_key ON dim_term(term_key);
CREATE INDEX IF NOT EXISTS idx_dim_glossary_term_id ON dim_glossary_term(glossary_term_id);
CREATE INDEX IF NOT EXISTS idx_dim_glossary_fqdn ON dim_glossary_term(term_fqdn);
CREATE INDEX IF NOT EXISTS idx_dim_glossary_level1 ON dim_glossary_term(level_1_glossary);
CREATE INDEX IF NOT EXISTS idx_dim_glossary_parent ON dim_glossary_term(parent_id);
CREATE INDEX IF NOT EXISTS idx_dim_glossary_leaf ON dim_glossary_term(is_leaf_term) WHERE is_leaf_term = true;
CREATE INDEX IF NOT EXISTS idx_dim_datasource_key ON dim_datasource(datasource_key);
CREATE INDEX IF NOT EXISTS idx_dim_filetype_key ON dim_filetype(filetype_key);
CREATE INDEX IF NOT EXISTS idx_dim_date_key ON dim_date(date_key);

-- Attribute dimension support (dim_entity columns)
CREATE INDEX IF NOT EXISTS idx_dim_entity_type ON dim_entity(entity_type);
CREATE INDEX IF NOT EXISTS idx_dim_entity_resource_type ON dim_entity(resource_type);
CREATE INDEX IF NOT EXISTS idx_dim_entity_filetype ON dim_entity(filetype);
CREATE INDEX IF NOT EXISTS idx_dim_entity_path ON dim_entity(path);
CREATE INDEX IF NOT EXISTS idx_dim_entity_parent_path ON dim_entity(parent_path);


-- ============================================================================
-- SECTION 6: CREATE FACT TABLES
-- ============================================================================

-- ============================================================================
-- FACT: ENTITY SNAPSHOT (daily entity snapshots with storage metrics)
-- NOW INCLUDES term_key and filetype_key pointing to default members
-- ============================================================================

CREATE MATERIALIZED VIEW fact_entity_snapshot AS
SELECT DISTINCT ON (stg.entity_nk, stg.scanned_ts::date)
  md5(stg.entity_nk) AS entity_key,
  md5(stg.datasource_nk) AS datasource_key,
  -- Add term_key pointing to "No Term Available" default member
  'unknown'::text AS term_key,
  -- Add filetype_key (use actual if exists, otherwise default to "No File Type Available")
  COALESCE(md5(lower(trim(stg.filetype))), 'unknown'::text) AS filetype_key,
  -- Date foreign keys with Unknown handling
  COALESCE(to_char(stg.scanned_ts::date, 'YYYYMMDD')::int, 19000101) AS scanned_date_key,
  COALESCE(to_char(stg.created_ts::date, 'YYYYMMDD')::int, 19000101) AS created_date_key,
  COALESCE(to_char(stg.modified_ts::date, 'YYYYMMDD')::int, 19000101) AS modified_date_key,
  COALESCE(to_char(stg.accessed_ts::date, 'YYYYMMDD')::int, 19000101) AS accessed_date_key,
  COALESCE(to_char(stg.last_update_ts::date, 'YYYYMMDD')::int, 19000101) AS last_update_date_key,
  COALESCE(to_char(stg.last_update_statistics_ts::date, 'YYYYMMDD')::int, 19000101) AS last_update_statistics_date_key,
  -- Measures
  1 AS entity_count,
  (COALESCE(stg.bytes, 0) * get_data_multiplier())::bigint AS bytes,
  (COALESCE(emv."ChildDirs", 0) * get_data_multiplier())::bigint AS child_dirs,
  (COALESCE(emv."ChildFiles", 0) * get_data_multiplier())::bigint AS child_files,
  (COALESCE(emv."ChildDirSize", 0) * get_data_multiplier())::bigint AS child_dir_bytes,
  (COALESCE(emv."ChildFileSize", 0) * get_data_multiplier())::bigint AS child_file_bytes,
  (COALESCE(emv."TotalChildDirs", 0) * get_data_multiplier())::bigint AS total_child_dirs,
  (COALESCE(emv."TotalChildFiles", 0) * get_data_multiplier())::bigint AS total_child_files,
  (COALESCE(emv."TotalChildDirSize", 0) * get_data_multiplier())::bigint AS total_child_dir_bytes,
  (COALESCE(emv."TotalChildFileSize", 0) * get_data_multiplier())::bigint AS total_child_file_bytes,
  -- Age metrics at snapshot time
  COALESCE(
    date_part('year', age(stg.scanned_ts, stg.created_ts))::int * 12
    + date_part('month', age(stg.scanned_ts, stg.created_ts))::int,
    0
  ) AS created_age_months,
  COALESCE(date_part('year', age(stg.scanned_ts, stg.created_ts))::int, 0) AS created_age_years,
  COALESCE(
    date_part('year', age(stg.scanned_ts, stg.modified_ts))::int * 12
    + date_part('month', age(stg.scanned_ts, stg.modified_ts))::int,
    0
  ) AS modified_age_months,
  COALESCE(date_part('year', age(stg.scanned_ts, stg.modified_ts))::int, 0) AS modified_age_years,
  COALESCE(
    date_part('year', age(stg.scanned_ts, stg.accessed_ts))::int * 12
    + date_part('month', age(stg.scanned_ts, stg.accessed_ts))::int,
    0
  ) AS accessed_age_months,
  COALESCE(date_part('year', age(stg.scanned_ts, stg.accessed_ts))::int, 0) AS accessed_age_years
FROM mv_stg_entity_term stg
LEFT JOIN entities_master_view emv ON stg.entity_nk = emv._id
WHERE stg.entity_nk IS NOT NULL
  AND stg.scanned_ts IS NOT NULL;


-- ============================================================================
-- FACT: ENTITY TERM (many-to-many associative fact)
-- NOW INCLUDES storage metrics from most recent entity snapshot for term analysis
-- ============================================================================

CREATE MATERIALIZED VIEW fact_entity_term AS
SELECT
  md5(stg.entity_nk) AS entity_key,
  md5(lower(trim(stg.term_name))) AS term_key,
  stg.glossary_term_id AS glossary_term_id,
  md5(stg.datasource_nk) AS datasource_key,
  COALESCE(to_char(stg.created_ts::date, 'YYYYMMDD')::int, 19000101) AS created_date_key,
  COALESCE(to_char(stg.modified_ts::date, 'YYYYMMDD')::int, 19000101) AS modified_date_key,
  COALESCE(to_char(stg.accessed_ts::date, 'YYYYMMDD')::int, 19000101) AS accessed_date_key,
  COALESCE(to_char(stg.scanned_ts::date, 'YYYYMMDD')::int, 19000101) AS scanned_date_key,
  1 AS association_count,
  -- Storage metrics from most recent snapshot (enables "GB by Term" analysis)
  -- NOTE: These values are duplicated for each term assignment to the same entity
  (COALESCE(snap.bytes, 0) * get_data_multiplier())::bigint AS bytes,
  (COALESCE(snap.child_dirs, 0) * get_data_multiplier())::bigint AS child_dirs,
  (COALESCE(snap.child_files, 0) * get_data_multiplier())::bigint AS child_files,
  (COALESCE(snap.child_dir_bytes, 0) * get_data_multiplier())::bigint AS child_dir_bytes,
  (COALESCE(snap.child_file_bytes, 0) * get_data_multiplier())::bigint AS child_file_bytes,
  (COALESCE(snap.total_child_dirs, 0) * get_data_multiplier())::bigint AS total_child_dirs,
  (COALESCE(snap.total_child_files, 0) * get_data_multiplier())::bigint AS total_child_files,
  (COALESCE(snap.total_child_dir_bytes, 0) * get_data_multiplier())::bigint AS total_child_dir_bytes,
  (COALESCE(snap.total_child_file_bytes, 0) * get_data_multiplier())::bigint AS total_child_file_bytes
FROM mv_stg_entity_term stg
LEFT JOIN LATERAL (
  SELECT 
    bytes, child_dirs, child_files, child_dir_bytes, child_file_bytes,
    total_child_dirs, total_child_files, total_child_dir_bytes, total_child_file_bytes
  FROM fact_entity_snapshot fes
  WHERE fes.entity_key = md5(stg.entity_nk)
  ORDER BY fes.scanned_date_key DESC
  LIMIT 1
) snap ON true
WHERE stg.entity_nk IS NOT NULL
  AND stg.term_name IS NOT NULL;


-- ============================================================================
-- SECTION 7: CREATE FACT TABLE INDEXES
-- ============================================================================

-- fact_entity_snapshot - All foreign keys plus composite for grain
CREATE INDEX IF NOT EXISTS idx_fes_entity ON fact_entity_snapshot(entity_key);
CREATE INDEX IF NOT EXISTS idx_fes_datasource ON fact_entity_snapshot(datasource_key);
CREATE INDEX IF NOT EXISTS idx_fes_term ON fact_entity_snapshot(term_key);
CREATE INDEX IF NOT EXISTS idx_fes_filetype ON fact_entity_snapshot(filetype_key);
CREATE INDEX IF NOT EXISTS idx_fes_scanned_date ON fact_entity_snapshot(scanned_date_key);
CREATE INDEX IF NOT EXISTS idx_fes_created_date ON fact_entity_snapshot(created_date_key);
CREATE INDEX IF NOT EXISTS idx_fes_modified_date ON fact_entity_snapshot(modified_date_key);
CREATE INDEX IF NOT EXISTS idx_fes_accessed_date ON fact_entity_snapshot(accessed_date_key);
CREATE INDEX IF NOT EXISTS idx_fes_last_update_date ON fact_entity_snapshot(last_update_date_key);
CREATE INDEX IF NOT EXISTS idx_fes_last_update_stats_date ON fact_entity_snapshot(last_update_statistics_date_key);
CREATE INDEX IF NOT EXISTS idx_fes_composite_grain ON fact_entity_snapshot(entity_key, scanned_date_key);

-- fact_entity_term - All foreign keys plus composite for grain
CREATE INDEX IF NOT EXISTS idx_fet_entity ON fact_entity_term(entity_key);
CREATE INDEX IF NOT EXISTS idx_fet_term ON fact_entity_term(term_key);
CREATE INDEX IF NOT EXISTS idx_fet_glossary ON fact_entity_term(glossary_term_id);
CREATE INDEX IF NOT EXISTS idx_fet_datasource ON fact_entity_term(datasource_key);
CREATE INDEX IF NOT EXISTS idx_fet_created_date ON fact_entity_term(created_date_key);
CREATE INDEX IF NOT EXISTS idx_fet_modified_date ON fact_entity_term(modified_date_key);
CREATE INDEX IF NOT EXISTS idx_fet_accessed_date ON fact_entity_term(accessed_date_key);
CREATE INDEX IF NOT EXISTS idx_fet_scanned_date ON fact_entity_term(scanned_date_key);
CREATE INDEX IF NOT EXISTS idx_fet_composite_grain ON fact_entity_term(entity_key, term_key);


-- ============================================================================
-- SECTION 8: REFRESH ALL MATERIALIZED VIEWS
-- ============================================================================
-- Run this to update data after source views change

REFRESH MATERIALIZED VIEW mv_stg_entity_term;
REFRESH MATERIALIZED VIEW dim_entity;
REFRESH MATERIALIZED VIEW dim_term;
REFRESH MATERIALIZED VIEW dim_glossary_term;
REFRESH MATERIALIZED VIEW dim_datasource;
REFRESH MATERIALIZED VIEW dim_date;
REFRESH MATERIALIZED VIEW dim_filetype;
REFRESH MATERIALIZED VIEW fact_entity_snapshot;
REFRESH MATERIALIZED VIEW fact_entity_term;


-- ============================================================================
-- END OF SCRIPT
-- ============================================================================
