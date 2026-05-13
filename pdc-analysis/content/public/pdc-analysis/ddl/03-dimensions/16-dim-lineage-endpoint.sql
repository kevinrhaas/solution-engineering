DROP MATERIALIZED VIEW IF EXISTS dim_lineage_endpoint CASCADE;
CREATE MATERIALIZED VIEW dim_lineage_endpoint AS
WITH endpoints AS (
    SELECT
        COALESCE(NULLIF(TRIM(orig_namespace), ''), 'Unknown') AS endpoint_namespace,
        COALESCE(NULLIF(TRIM(orig_name),      ''), 'Unknown') AS endpoint_name,
        COALESCE(NULLIF(TRIM(orig_db),        ''), 'Unknown') AS endpoint_db,
        COALESCE(NULLIF(TRIM(orig_schema),    ''), 'Unknown') AS endpoint_schema,
        COALESCE(NULLIF(TRIM(orig_table),     ''), 'Unknown') AS endpoint_table
    FROM stg_lineage_connection
    UNION
    SELECT
        COALESCE(NULLIF(TRIM(dest_namespace), ''), 'Unknown'),
        COALESCE(NULLIF(TRIM(dest_name),      ''), 'Unknown'),
        COALESCE(NULLIF(TRIM(dest_db),        ''), 'Unknown'),
        COALESCE(NULLIF(TRIM(dest_schema),    ''), 'Unknown'),
        COALESCE(NULLIF(TRIM(dest_table),     ''), 'Unknown')
    FROM stg_lineage_connection
    UNION ALL
    SELECT 'Unknown', 'Unknown', 'Unknown', 'Unknown', 'Unknown'
)
SELECT
    md5(lower(trim(endpoint_namespace)) || '|' || lower(trim(endpoint_name))) AS endpoint_key,
    md5(lower(trim(endpoint_name)))     AS entity_key,  -- matches dim_entity.entity_key for cross-cube joins
    endpoint_namespace,
    endpoint_name,
    endpoint_db,
    endpoint_schema,
    endpoint_table
FROM endpoints;

CREATE UNIQUE INDEX idx_dlep_key       ON dim_lineage_endpoint (endpoint_key);
CREATE        INDEX idx_dlep_entity_key ON dim_lineage_endpoint (entity_key);
CREATE        INDEX idx_dlep_namespace  ON dim_lineage_endpoint (endpoint_namespace);
CREATE        INDEX idx_dlep_db         ON dim_lineage_endpoint (endpoint_db);
CREATE        INDEX idx_dlep_schema     ON dim_lineage_endpoint (endpoint_schema);
CREATE        INDEX idx_dlep_table      ON dim_lineage_endpoint (endpoint_table);
