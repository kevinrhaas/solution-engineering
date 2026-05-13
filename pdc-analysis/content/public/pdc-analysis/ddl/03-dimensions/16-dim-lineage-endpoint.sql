DROP MATERIALIZED VIEW IF EXISTS dim_lineage_endpoint CASCADE;
CREATE MATERIALIZED VIEW dim_lineage_endpoint AS
WITH endpoints AS (
    -- Sources: lowercase namespace/name so GROUP BY matches the md5() key
    SELECT
        COALESCE(NULLIF(TRIM(LOWER(orig_namespace)), ''), 'Unknown') AS endpoint_namespace,
        COALESCE(NULLIF(TRIM(LOWER(orig_name)),      ''), 'Unknown') AS endpoint_name,
        COALESCE(NULLIF(TRIM(orig_db),               ''), 'Unknown') AS endpoint_db,
        COALESCE(NULLIF(TRIM(orig_schema),           ''), 'Unknown') AS endpoint_schema,
        COALESCE(NULLIF(TRIM(orig_table),            ''), 'Unknown') AS endpoint_table
    FROM stg_lineage_connection
    UNION
    -- Destinations
    SELECT
        COALESCE(NULLIF(TRIM(LOWER(dest_namespace)), ''), 'Unknown'),
        COALESCE(NULLIF(TRIM(LOWER(dest_name)),      ''), 'Unknown'),
        COALESCE(NULLIF(TRIM(dest_db),               ''), 'Unknown'),
        COALESCE(NULLIF(TRIM(dest_schema),           ''), 'Unknown'),
        COALESCE(NULLIF(TRIM(dest_table),            ''), 'Unknown')
    FROM stg_lineage_connection
    UNION ALL
    SELECT 'Unknown', 'Unknown', 'Unknown', 'Unknown', 'Unknown'
)
-- GROUP BY the already-lowered (namespace, name) so the unique key is guaranteed.
-- COALESCE(MAX(NULLIF(...,'Unknown')), 'Unknown') picks any real value over the sentinel.
SELECT
    md5(endpoint_namespace || '|' || endpoint_name) AS endpoint_key,
    md5(endpoint_name)                              AS entity_key,  -- matches dim_entity.entity_key
    endpoint_namespace,
    endpoint_name,
    COALESCE(MAX(NULLIF(endpoint_db,     'Unknown')), 'Unknown') AS endpoint_db,
    COALESCE(MAX(NULLIF(endpoint_schema, 'Unknown')), 'Unknown') AS endpoint_schema,
    COALESCE(MAX(NULLIF(endpoint_table,  'Unknown')), 'Unknown') AS endpoint_table
FROM endpoints
GROUP BY endpoint_namespace, endpoint_name;

CREATE UNIQUE INDEX idx_dlep_key        ON dim_lineage_endpoint (endpoint_key);
CREATE        INDEX idx_dlep_entity_key ON dim_lineage_endpoint (entity_key);
CREATE        INDEX idx_dlep_namespace  ON dim_lineage_endpoint (endpoint_namespace);
CREATE        INDEX idx_dlep_db         ON dim_lineage_endpoint (endpoint_db);
CREATE        INDEX idx_dlep_schema     ON dim_lineage_endpoint (endpoint_schema);
CREATE        INDEX idx_dlep_table      ON dim_lineage_endpoint (endpoint_table);
