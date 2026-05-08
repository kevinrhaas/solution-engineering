-- ============================================================================
-- FACT: fact_entity_snapshot
-- ============================================================================
-- Daily entity snapshots with storage metrics
-- Grain: entity + scanned_date
-- Includes term_key and filetype_key pointing to default members
-- ============================================================================

CREATE MATERIALIZED VIEW fact_entity_snapshot AS
SELECT DISTINCT ON (stg.entity_nk, stg.scanned_ts::date)
  md5(stg.entity_nk) AS entity_key,
  md5(stg.datasource_nk) AS datasource_key,
  -- Add term_key pointing to "No Term Available" default member
  'unknown'::text AS term_key,
  -- Add glossary_term_key pointing to "No Glossary Available" default member
  'unknown'::text AS glossary_term_key,
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

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_fes_entity ON fact_entity_snapshot(entity_key);
CREATE INDEX IF NOT EXISTS idx_fes_datasource ON fact_entity_snapshot(datasource_key);
CREATE INDEX IF NOT EXISTS idx_fes_term ON fact_entity_snapshot(term_key);
CREATE INDEX IF NOT EXISTS idx_fes_glossary ON fact_entity_snapshot(glossary_term_key);
CREATE INDEX IF NOT EXISTS idx_fes_filetype ON fact_entity_snapshot(filetype_key);
CREATE INDEX IF NOT EXISTS idx_fes_scanned_date ON fact_entity_snapshot(scanned_date_key);
CREATE INDEX IF NOT EXISTS idx_fes_created_date ON fact_entity_snapshot(created_date_key);
CREATE INDEX IF NOT EXISTS idx_fes_modified_date ON fact_entity_snapshot(modified_date_key);
CREATE INDEX IF NOT EXISTS idx_fes_accessed_date ON fact_entity_snapshot(accessed_date_key);
CREATE INDEX IF NOT EXISTS idx_fes_last_update_date ON fact_entity_snapshot(last_update_date_key);
CREATE INDEX IF NOT EXISTS idx_fes_last_update_stats_date ON fact_entity_snapshot(last_update_statistics_date_key);
CREATE INDEX IF NOT EXISTS idx_fes_composite_grain ON fact_entity_snapshot(entity_key, scanned_date_key);
