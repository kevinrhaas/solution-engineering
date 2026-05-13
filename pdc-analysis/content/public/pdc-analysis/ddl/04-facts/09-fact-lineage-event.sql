DROP MATERIALIZED VIEW IF EXISTS fact_lineage_event CASCADE;
CREATE MATERIALIZED VIEW fact_lineage_event AS
SELECT
    md5(lower(trim(e.event_nk)))                                AS lineage_event_nk,

    md5(lower(trim(COALESCE(NULLIF(TRIM(e.event_type), ''), 'UNKNOWN'))))
                                                                AS event_type_key,
    md5(
        lower(trim(COALESCE(NULLIF(TRIM(e.integration),    ''), 'Unknown'))) || '|' ||
        lower(trim(COALESCE(NULLIF(TRIM(e.job_type),       ''), 'Unknown'))) || '|' ||
        lower(trim(COALESCE(NULLIF(TRIM(e.job_name),       ''), 'Unknown Job'))) || '|' ||
        lower(trim(COALESCE(NULLIF(TRIM(e.processing_type),''), 'Unknown')))
    )                                                           AS lineage_job_key,

    COALESCE(TO_CHAR(e.event_date, 'YYYYMMDD')::INT, 19000101) AS event_date_key,

    e.run_id,
    e.in_namespace,
    e.out_namespace,

    1                                                           AS event_count,
    COALESCE(e.input_count,  0)                                 AS input_count,
    COALESCE(e.output_count, 0)                                 AS output_count,
    COALESCE(e.record_count, 0)::BIGINT                         AS record_count

FROM stg_lineage_event e;

CREATE UNIQUE INDEX idx_fle_nk          ON fact_lineage_event (lineage_event_nk);
CREATE        INDEX idx_fle_event_type  ON fact_lineage_event (event_type_key);
CREATE        INDEX idx_fle_lineage_job ON fact_lineage_event (lineage_job_key);
CREATE        INDEX idx_fle_event_date  ON fact_lineage_event (event_date_key);
