-- ============================================================================
-- DROP ALL OBJECTS (Dependency Order)
-- ============================================================================
-- Drop all materialized views in dependency order
-- (Facts first, then dimensions, then staging)
-- ============================================================================

-- Fact tables
DROP MATERIALIZED VIEW IF EXISTS fact_entity_term CASCADE;
DROP MATERIALIZED VIEW IF EXISTS fact_entity_snapshot CASCADE;

-- Dimension tables
DROP MATERIALIZED VIEW IF EXISTS dim_term CASCADE;
DROP MATERIALIZED VIEW IF EXISTS dim_glossary_term CASCADE;
DROP MATERIALIZED VIEW IF EXISTS dim_leaf_flag CASCADE;
DROP MATERIALIZED VIEW IF EXISTS dim_filetype CASCADE;
DROP MATERIALIZED VIEW IF EXISTS dim_entity CASCADE;
DROP MATERIALIZED VIEW IF EXISTS dim_date CASCADE;
DROP MATERIALIZED VIEW IF EXISTS dim_datasource CASCADE;

-- Staging table (last, since others depend on it)
DROP MATERIALIZED VIEW IF EXISTS mv_stg_entity_term CASCADE;
