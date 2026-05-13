DROP MATERIALIZED VIEW IF EXISTS fact_lineage_connection CASCADE;
CREATE MATERIALIZED VIEW fact_lineage_connection AS
SELECT
    c.connection_nk                                             AS lineage_connection_nk,

    md5(
        lower(trim(COALESCE(NULLIF(TRIM(c.orig_namespace), ''), 'Unknown'))) || '|' ||
        lower(trim(COALESCE(NULLIF(TRIM(c.orig_name),      ''), 'Unknown')))
    )                                                           AS source_endpoint_key,
    md5(
        lower(trim(COALESCE(NULLIF(TRIM(c.dest_namespace), ''), 'Unknown'))) || '|' ||
        lower(trim(COALESCE(NULLIF(TRIM(c.dest_name),      ''), 'Unknown')))
    )                                                           AS dest_endpoint_key,

    md5(lower(trim(COALESCE(NULLIF(TRIM(c.orig_name), ''), 'Unknown'))))
                                                                AS source_entity_key,
    md5(lower(trim(COALESCE(NULLIF(TRIM(c.dest_name), ''), 'Unknown'))))
                                                                AS dest_entity_key,

    md5(lower(trim(COALESCE(NULLIF(TRIM(e.event_type), ''), 'UNKNOWN'))))
                                                                AS event_type_key,
    md5(
        lower(trim(COALESCE(NULLIF(TRIM(e.integration),    ''), 'Unknown'))) || '|' ||
        lower(trim(COALESCE(NULLIF(TRIM(e.job_type),       ''), 'Unknown'))) || '|' ||
        lower(trim(COALESCE(NULLIF(TRIM(e.job_name),       ''), 'Unknown Job'))) || '|' ||
        lower(trim(COALESCE(NULLIF(TRIM(e.processing_type),''), 'Unknown')))
    )                                                           AS lineage_job_key,

    COALESCE(TO_CHAR(e.event_date, 'YYYYMMDD')::INT, 19000101) AS event_date_key,

    c.run_id,
    COALESCE(NULLIF(TRIM(c.orig_namespace), ''), 'Unknown')     AS orig_namespace,
    COALESCE(NULLIF(TRIM(c.orig_name),      ''), 'Unknown')     AS orig_name,
    COALESCE(NULLIF(TRIM(c.orig_db),        ''), 'Unknown')     AS orig_db,
    COALESCE(NULLIF(TRIM(c.orig_schema),    ''), 'Unknown')     AS orig_schema,
    COALESCE(NULLIF(TRIM(c.orig_table),     ''), 'Unknown')     AS orig_table,
    COALESCE(NULLIF(TRIM(c.dest_namespace), ''), 'Unknown')     AS dest_namespace,
    COALESCE(NULLIF(TRIM(c.dest_name),      ''), 'Unknown')     AS dest_name,
    COALESCE(NULLIF(TRIM(c.dest_db),        ''), 'Unknown')     AS dest_db,
    COALESCE(NULLIF(TRIM(c.dest_schema),    ''), 'Unknown')     AS dest_schema,
    COALESCE(NULLIF(TRIM(c.dest_table),     ''), 'Unknown')     AS dest_table,

    1                                                           AS connection_count,
    COALESCE(e.record_count, 0)::BIGINT                         AS record_count

FROM stg_lineage_connection c
LEFT JOIN stg_lineage_event e ON c.event_nk = e.event_nk;

CREATE UNIQUE INDEX idx_flc_nk              ON fact_lineage_connection (lineage_connection_nk);
CREATE        INDEX idx_flc_source_endpoint ON fact_lineage_connection (source_endpoint_key);
CREATE        INDEX idx_flc_dest_endpoint   ON fact_lineage_connection (dest_endpoint_key);
CREATE        INDEX idx_flc_source_entity   ON fact_lineage_connection (source_entity_key);
CREATE        INDEX idx_flc_dest_entity     ON fact_lineage_connection (dest_entity_key);
CREATE        INDEX idx_flc_event_type      ON fact_lineage_connection (event_type_key);
CREATE        INDEX idx_flc_lineage_job     ON fact_lineage_connection (lineage_job_key);
CREATE        INDEX idx_flc_event_date      ON fact_lineage_connection (event_date_key);
