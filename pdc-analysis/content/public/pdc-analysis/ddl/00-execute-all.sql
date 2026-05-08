-- ============================================================================
-- PDC BUSINESS INTELLIGENCE DATABASE - MASTER DDL EXECUTION SCRIPT
-- ============================================================================
-- This script executes all modular DDL scripts in the correct order
-- Schema: bidb_ext_demo
-- Prerequisites: 
--   - Foreign data wrapper configured (remote_bidb server)
--   - entities_master_view and terms_view available
--   - glossary_summary_view available
-- ============================================================================

\echo ''
\echo '============================================================================'
\echo 'PDC BIDB - DIMENSIONAL MODEL DEPLOYMENT'
\echo '============================================================================'
\echo ''

-- ============================================================================
-- PHASE 1: SETUP
-- ============================================================================
\echo '>>> PHASE 1: Setup - Load Variables'
\ir 01-setup/00-psql-variables.sql

\echo '>>> PHASE 1: Setup - Foreign Data Wrapper'
\ir 01-setup/01-fdw-setup.sql

\echo '>>> PHASE 1: Setup - Set search_path'
SET search_path TO :"BIDB_EXT_SCHEMA_NAME", public;

\echo '>>> PHASE 1: Setup - Data Multiplier Function'
\ir 01-setup/02-data-multiplier-function.sql

\echo '>>> PHASE 1: Setup - Drop All Objects'
\ir 01-setup/03-drop-all-objects.sql

-- ============================================================================
-- PHASE 2: STAGING
-- ============================================================================
\echo ''
\echo '>>> PHASE 2: Staging - Create mv_stg_entity_term'
\ir 02-staging/01-mv-stg-entity-term.sql

-- ============================================================================
-- PHASE 3: DIMENSIONS
-- ============================================================================
\echo ''
\echo '>>> PHASE 3: Dimensions - Creating dimension tables...'
\ir 03-dimensions/01-dim-date.sql
\ir 03-dimensions/02-dim-term.sql
\ir 03-dimensions/03-dim-glossary-term.sql
\ir 03-dimensions/04-dim-entity.sql
\ir 03-dimensions/05-dim-datasource.sql
\ir 03-dimensions/06-dim-filetype.sql
\ir 03-dimensions/07-dim-leaf-flag.sql

-- ============================================================================
-- PHASE 4: FACTS
-- ============================================================================
\echo ''
\echo '>>> PHASE 4: Facts - Creating fact tables...'
\ir 04-facts/01-fact-entity-snapshot.sql
\ir 04-facts/02-fact-entity-term.sql

-- ============================================================================
-- PHASE 5: REFRESH
-- ============================================================================
\echo ''
\echo '>>> PHASE 5: Refresh - Refreshing all materialized views...'
\ir 05-refresh/01-refresh-all.sql

-- ============================================================================
-- COMPLETION
-- ============================================================================
\echo ''
\echo '============================================================================'
\echo 'DEPLOYMENT COMPLETE'
\echo '============================================================================'
\echo ''
\echo 'Summary:'
\echo '  - Staging:    1 view'
\echo '  - Dimensions: 7 tables'
\echo '  - Facts:      2 tables'
\echo ''
\echo 'Next steps:'
\echo '  1. Verify row counts: SELECT COUNT(*) FROM fact_entity_snapshot;'
\echo '  2. Verify row counts: SELECT COUNT(*) FROM fact_entity_term;'
\echo '  3. Publish Mondrian schema to Pentaho Server'
\echo '  4. Clear Mondrian cache'
\echo ''
