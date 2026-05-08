-- ============================================================================
-- REFRESH ALL MATERIALIZED VIEWS
-- ============================================================================
-- Run this to update data after source views change
-- Execution order: staging → dimensions → facts
-- ============================================================================

-- Refresh staging
REFRESH MATERIALIZED VIEW mv_stg_entity_term;

-- Refresh dimensions
REFRESH MATERIALIZED VIEW dim_entity;
REFRESH MATERIALIZED VIEW dim_term;
REFRESH MATERIALIZED VIEW dim_glossary_term;
REFRESH MATERIALIZED VIEW dim_leaf_flag;
REFRESH MATERIALIZED VIEW dim_datasource;
REFRESH MATERIALIZED VIEW dim_date;
REFRESH MATERIALIZED VIEW dim_filetype;

-- Refresh facts
REFRESH MATERIALIZED VIEW fact_entity_snapshot;
REFRESH MATERIALIZED VIEW fact_entity_term;
