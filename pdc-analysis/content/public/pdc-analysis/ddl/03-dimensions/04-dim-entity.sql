-- ============================================================================
-- DIMENSION: dim_entity
-- ============================================================================
-- Entity master dimension with all attributes
-- Used for Analyzer attribute dimensions (Name, Type, Path, etc.)
-- ============================================================================

CREATE MATERIALIZED VIEW dim_entity AS
SELECT 
  md5(entity_nk) AS entity_key,
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
  file_extension,
  path_type,
  unstructured_level_1,
  unstructured_level_2,
  unstructured_level_3,
  unstructured_level_4,
  unstructured_level_5,
  unstructured_level_6,
  unstructured_leaf,
  structured_schema,
  structured_table,
  structured_column,
  structured_fqdn,
  url,
  physicallocation,
  datasource_nk
FROM (
  SELECT DISTINCT ON (entity_nk) 
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
    file_extension,
    path_type,
    unstructured_level_1,
    unstructured_level_2,
    unstructured_level_3,
    unstructured_level_4,
    unstructured_level_5,
    unstructured_level_6,
    unstructured_leaf,
    structured_schema,
    structured_table,
    structured_column,
    structured_fqdn,
    url,
    physicallocation,
    datasource_nk
  FROM mv_stg_entity_term
  WHERE entity_nk IS NOT NULL
  ORDER BY entity_nk
) x;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_dim_entity_key ON dim_entity(entity_key);
CREATE INDEX IF NOT EXISTS idx_dim_entity_type ON dim_entity(entity_type);
CREATE INDEX IF NOT EXISTS idx_dim_entity_resource_type ON dim_entity(resource_type);
CREATE INDEX IF NOT EXISTS idx_dim_entity_filetype ON dim_entity(filetype);
CREATE INDEX IF NOT EXISTS idx_dim_entity_path ON dim_entity(path);
CREATE INDEX IF NOT EXISTS idx_dim_entity_parent_path ON dim_entity(parent_path);
CREATE INDEX IF NOT EXISTS idx_dim_entity_unstructured_level_1 ON dim_entity(unstructured_level_1);
CREATE INDEX IF NOT EXISTS idx_dim_entity_unstructured_leaf ON dim_entity(unstructured_leaf);
CREATE INDEX IF NOT EXISTS idx_dim_entity_structured_schema ON dim_entity(structured_schema);
CREATE INDEX IF NOT EXISTS idx_dim_entity_structured_table ON dim_entity(structured_table);
CREATE INDEX IF NOT EXISTS idx_dim_entity_structured_fqdn ON dim_entity(structured_fqdn);
