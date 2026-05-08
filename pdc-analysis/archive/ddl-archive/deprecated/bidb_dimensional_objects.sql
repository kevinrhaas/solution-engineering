-- Drop all materialized views in dependency order
-- (Facts first, then dimensions, then staging)

-- Fact tables
DROP MATERIALIZED VIEW IF EXISTS fact_entity_term CASCADE;
DROP MATERIALIZED VIEW IF EXISTS fact_entity_snapshot CASCADE;

-- Dimension tables
DROP MATERIALIZED VIEW IF EXISTS dim_term CASCADE;
DROP MATERIALIZED VIEW IF EXISTS dim_filetype CASCADE;
DROP MATERIALIZED VIEW IF EXISTS dim_entity CASCADE;
DROP MATERIALIZED VIEW IF EXISTS dim_date CASCADE;
DROP MATERIALIZED VIEW IF EXISTS dim_datasource CASCADE;

-- Staging table (last, since others depend on it)
DROP MATERIALIZED VIEW IF EXISTS mv_stg_entity_term CASCADE;


CREATE MATERIALIZED VIEW mv_stg_entity_term AS
 SELECT emv._id AS entity_nk,
    emv."FqdnDisplay" AS entity_fqdn,
    tv."TermName" AS term_name,
    emv."DataSourceId" AS datasource_nk,
    emv."DataSourceName" AS datasource_name,
    emv."DataSourceType" AS datasource_type,
    emv."Name" AS entity_name,
    emv."Type" AS entity_type,
    emv."ResourceType" AS resource_type,
    emv."Path" AS path,
    emv."ParentPath" AS parent_path,
    emv."PathType" AS path_type,           -- ADD THIS
    emv."FileExtension" AS file_extension,  -- ADD THIS
    emv."Url" AS url,                       -- ADD THIS
    emv."PhysicalLocation" AS physicallocation,  -- ADD THIS
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
    COALESCE(emv."Size", (0)::bigint) AS bytes
   FROM (entities_master_view emv
     LEFT JOIN terms_view tv ON ((emv."FqdnDisplay" = tv."FqdnDisplay")))
  ;



CREATE MATERIALIZED VIEW dim_term AS
SELECT
  md5(lower(trim(term_name))) AS term_key,
  term_name
FROM mv_stg_entity_term
WHERE term_name IS NOT NULL
GROUP BY 1,2;



CREATE MATERIALIZED VIEW dim_entity AS
 SELECT md5(entity_nk) AS entity_key,
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
    file_extension,    -- ADD THIS
    path_type,         -- ADD THIS
    url,               -- ADD THIS
    physicallocation,  -- ADD THIS
    datasource_nk
   FROM ( SELECT DISTINCT ON (mv_stg_entity_term.entity_nk) 
            mv_stg_entity_term.entity_nk,
            mv_stg_entity_term.entity_fqdn,
            mv_stg_entity_term.entity_name,
            mv_stg_entity_term.entity_type,
            mv_stg_entity_term.resource_type,
            mv_stg_entity_term.path,
            mv_stg_entity_term.parent_path,
            mv_stg_entity_term.owner_name,
            mv_stg_entity_term.group_name,
            mv_stg_entity_term.filetype,
            mv_stg_entity_term.file_extension,    -- ADD THIS
            mv_stg_entity_term.path_type,         -- ADD THIS
            mv_stg_entity_term.url,               -- ADD THIS
            mv_stg_entity_term.physicallocation,  -- ADD THIS
            mv_stg_entity_term.datasource_nk
           FROM mv_stg_entity_term
          WHERE (mv_stg_entity_term.entity_nk IS NOT NULL)
          ORDER BY mv_stg_entity_term.entity_nk) x
;


CREATE MATERIALIZED VIEW dim_datasource AS
SELECT
  md5(datasource_nk) AS datasource_key,
  datasource_nk,
  datasource_name,
  datasource_type
FROM bidb_ext_demo.mv_stg_entity_term
WHERE datasource_nk IS NOT NULL
GROUP BY 1,2,3,4;




CREATE MATERIALIZED VIEW dim_filetype AS
SELECT
  md5(lower(trim(filetype))) AS filetype_key,
  filetype
FROM bidb_ext_demo.mv_stg_entity_term
WHERE filetype IS NOT NULL
GROUP BY 1,2;



CREATE MATERIALIZED VIEW dim_date AS
WITH dates AS (
  SELECT DISTINCT (created_ts::date)  AS d FROM mv_stg_entity_term WHERE created_ts IS NOT NULL
  UNION
  SELECT DISTINCT (modified_ts::date) AS d FROM mv_stg_entity_term WHERE modified_ts IS NOT NULL
  UNION
  SELECT DISTINCT (accessed_ts::date) AS d FROM mv_stg_entity_term WHERE accessed_ts IS NOT NULL
  UNION
  SELECT DISTINCT (scanned_ts::date)  AS d FROM mv_stg_entity_term WHERE scanned_ts IS NOT NULL
)
SELECT
  to_char(d,'YYYYMMDD')::int AS date_key,
  d                          AS full_date,
  extract(year  from d)::int AS year,
  extract(month from d)::int AS month,
  extract(day   from d)::int AS day,
  extract(dow   from d)::int AS day_of_week
FROM dates;



CREATE MATERIALIZED VIEW fact_entity_term AS
SELECT
  md5(stg.entity_nk)                       AS entity_key,
  md5(lower(trim(stg.term_name)))          AS term_key,
  md5(stg.datasource_nk)                   AS datasource_key,
  -- role-playing date keys (nullable)
  to_char(stg.created_ts::date,  'YYYYMMDD')::int AS created_date_key,
  to_char(stg.modified_ts::date, 'YYYYMMDD')::int AS modified_date_key,
  to_char(stg.accessed_ts::date, 'YYYYMMDD')::int AS accessed_date_key,
  to_char(stg.scanned_ts::date,  'YYYYMMDD')::int AS scanned_date_key,
  1::int AS association_count
FROM mv_stg_entity_term stg
WHERE stg.entity_nk IS NOT NULL
  AND stg.term_name IS NOT NULL;




CREATE MATERIALIZED VIEW fact_entity_snapshot AS
SELECT DISTINCT ON (stg.entity_nk, stg.scanned_ts::date)
  md5(stg.entity_nk) AS entity_key,
  md5(stg.datasource_nk) AS datasource_key,
  to_char(stg.scanned_ts::date, 'YYYYMMDD')::int AS scanned_date_key,
  1::int AS entity_count,
  COALESCE(stg.bytes, 0) AS bytes,
  COALESCE(emv."ChildDirs",0)           AS child_dirs,
  COALESCE(emv."ChildFiles",0)          AS child_files,
  COALESCE(emv."ChildDirSize",0)        AS child_dir_bytes,
  COALESCE(emv."ChildFileSize",0)       AS child_file_bytes,
  COALESCE(emv."TotalChildDirs",0)      AS total_child_dirs,
  COALESCE(emv."TotalChildFiles",0)     AS total_child_files,
  COALESCE(emv."TotalChildDirSize",0)   AS total_child_dir_bytes,
  COALESCE(emv."TotalChildFileSize",0)  AS total_child_file_bytes,
  -- Age metrics at snapshot time (months/years)
  COALESCE(
    date_part('year', age(stg.scanned_ts, stg.created_ts))::int * 12
    + date_part('month', age(stg.scanned_ts, stg.created_ts))::int,
    0
  ) AS created_age_months,
  COALESCE(date_part('year', age(stg.scanned_ts, stg.created_ts))::int, 0)
    AS created_age_years,
  COALESCE(
    date_part('year', age(stg.scanned_ts, stg.modified_ts))::int * 12
    + date_part('month', age(stg.scanned_ts, stg.modified_ts))::int,
    0
  ) AS modified_age_months,
  COALESCE(date_part('year', age(stg.scanned_ts, stg.modified_ts))::int, 0)
    AS modified_age_years,
  COALESCE(
    date_part('year', age(stg.scanned_ts, stg.accessed_ts))::int * 12
    + date_part('month', age(stg.scanned_ts, stg.accessed_ts))::int,
    0
  ) AS accessed_age_months,
  COALESCE(date_part('year', age(stg.scanned_ts, stg.accessed_ts))::int, 0)
    AS accessed_age_years
FROM mv_stg_entity_term stg
JOIN entities_master_view emv
  ON emv._id::text = stg.entity_nk
WHERE stg.scanned_ts IS NOT NULL
  AND stg.entity_nk IS NOT NULL
  AND stg.datasource_nk IS NOT NULL
ORDER BY
  stg.entity_nk,
  stg.scanned_ts::date,
  stg.scanned_ts DESC;


  
CREATE UNIQUE INDEX IF NOT EXISTS ux_fact_entity_term
  ON fact_entity_term (entity_key, term_key);

CREATE INDEX IF NOT EXISTS ix_fact_entity_term_term
  ON fact_entity_term (term_key);  
  
CREATE UNIQUE INDEX IF NOT EXISTS ux_fact_entity_snapshot
ON fact_entity_snapshot (entity_key, scanned_date_key);

CREATE INDEX IF NOT EXISTS ix_fact_entity_snapshot_entity
  ON bidb_ext_demo.fact_entity_snapshot (entity_key);

CREATE INDEX IF NOT EXISTS ix_fact_entity_snapshot_scandate
  ON bidb_ext_demo.fact_entity_snapshot (scanned_date_key);

CREATE UNIQUE INDEX IF NOT EXISTS ux_fact_entity_snapshot
  ON fact_entity_snapshot (entity_key, scanned_date_key);



-- =====================================================
-- STAGING TABLE INDEXES
-- =====================================================
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

-- =====================================================
-- DIMENSION TABLE INDEXES (Primary Keys)
-- =====================================================
CREATE UNIQUE INDEX IF NOT EXISTS idx_dim_entity_key ON dim_entity(entity_key);
CREATE INDEX IF NOT EXISTS idx_dim_entity_nk ON dim_entity(entity_nk);

CREATE UNIQUE INDEX IF NOT EXISTS idx_dim_term_key ON dim_term(term_key);
CREATE UNIQUE INDEX IF NOT EXISTS idx_dim_datasource_key ON dim_datasource(datasource_key);
CREATE UNIQUE INDEX IF NOT EXISTS idx_dim_date_key ON dim_date(date_key);
CREATE INDEX IF NOT EXISTS idx_dim_date_full ON dim_date(full_date);

-- =====================================================
-- FACT TABLE INDEXES (Foreign Keys & Composites)
-- =====================================================

-- fact_entity_snapshot
CREATE INDEX IF NOT EXISTS idx_fact_snap_entity ON fact_entity_snapshot(entity_key);
CREATE INDEX IF NOT EXISTS idx_fact_snap_datasource ON fact_entity_snapshot(datasource_key);
CREATE INDEX IF NOT EXISTS idx_fact_snap_date ON fact_entity_snapshot(scanned_date_key);
CREATE INDEX IF NOT EXISTS idx_fact_snap_composite ON fact_entity_snapshot(entity_key, datasource_key, scanned_date_key);

-- fact_entity_term
CREATE INDEX IF NOT EXISTS idx_fact_term_entity ON fact_entity_term(entity_key);
CREATE INDEX IF NOT EXISTS idx_fact_term_term ON fact_entity_term(term_key);
CREATE INDEX IF NOT EXISTS idx_fact_term_datasource ON fact_entity_term(datasource_key);
CREATE INDEX IF NOT EXISTS idx_fact_term_created ON fact_entity_term(created_date_key);
CREATE INDEX IF NOT EXISTS idx_fact_term_modified ON fact_entity_term(modified_date_key);
CREATE INDEX IF NOT EXISTS idx_fact_term_scanned ON fact_entity_term(scanned_date_key);
CREATE INDEX IF NOT EXISTS idx_fact_term_composite ON fact_entity_term(entity_key, term_key, datasource_key);

-- =====================================================
-- ATTRIBUTE DIMENSION SUPPORT (dim_entity columns)
-- =====================================================
-- These support the attribute dimensions in your cube
CREATE INDEX IF NOT EXISTS idx_dim_entity_type ON dim_entity(entity_type);
CREATE INDEX IF NOT EXISTS idx_dim_entity_resource_type ON dim_entity(resource_type);
CREATE INDEX IF NOT EXISTS idx_dim_entity_filetype ON dim_entity(filetype);
CREATE INDEX IF NOT EXISTS idx_dim_entity_path ON dim_entity(path);
CREATE INDEX IF NOT EXISTS idx_dim_entity_parent_path ON dim_entity(parent_path);

-- # Connect to your database and run:
REFRESH MATERIALIZED VIEW mv_stg_entity_term;
REFRESH MATERIALIZED VIEW dim_entity;
REFRESH MATERIALIZED VIEW dim_term;
REFRESH MATERIALIZED VIEW dim_datasource;
REFRESH MATERIALIZED VIEW dim_date;
REFRESH MATERIALIZED VIEW dim_filetype;
REFRESH MATERIALIZED VIEW fact_entity_snapshot;
REFRESH MATERIALIZED VIEW fact_entity_term;
