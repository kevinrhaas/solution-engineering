DROP MATERIALIZED VIEW IF EXISTS dim_lineage_event_type CASCADE;
CREATE MATERIALIZED VIEW dim_lineage_event_type AS
WITH observed AS (
    SELECT DISTINCT COALESCE(NULLIF(TRIM(event_type), ''), 'UNKNOWN') AS event_type_nk
    FROM stg_lineage_event
),
canonical AS (
    SELECT 'WRITE'   AS event_type_nk UNION ALL
    SELECT 'READ'              UNION ALL
    SELECT 'DELETE'            UNION ALL
    SELECT 'UNKNOWN'
),
combined AS (
    SELECT event_type_nk FROM canonical
    UNION
    SELECT event_type_nk FROM observed
)
SELECT
    md5(lower(trim(event_type_nk)))     AS event_type_key,
    event_type_nk                       AS event_type_nk,
    CASE event_type_nk
        WHEN 'WRITE'   THEN '01. Write'
        WHEN 'READ'    THEN '02. Read'
        WHEN 'DELETE'  THEN '03. Delete'
        WHEN 'UNKNOWN' THEN '99. Unknown'
        ELSE '98. Other'
    END                                 AS event_type_label,
    CASE event_type_nk
        WHEN 'WRITE'   THEN 1
        WHEN 'READ'    THEN 2
        WHEN 'DELETE'  THEN 3
        WHEN 'UNKNOWN' THEN 99
        ELSE 98
    END                                 AS event_type_sort,
    CASE WHEN event_type_nk = 'WRITE'  THEN true ELSE false END AS is_write_flag,
    CASE WHEN event_type_nk = 'READ'   THEN true ELSE false END AS is_read_flag,
    CASE WHEN event_type_nk = 'DELETE' THEN true ELSE false END AS is_delete_flag
FROM combined;

CREATE UNIQUE INDEX idx_dlet_key  ON dim_lineage_event_type (event_type_key);
CREATE        INDEX idx_dlet_sort ON dim_lineage_event_type (event_type_sort);
