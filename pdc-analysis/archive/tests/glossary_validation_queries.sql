-- ============================================================================
-- GLOSSARY DIMENSION - VALIDATION QUERIES
-- ============================================================================

-- 1. Check hierarchy depth distribution
SELECT 
  hierarchy_depth,
  COUNT(*) AS term_count,
  COUNT(CASE WHEN is_leaf_term THEN 1 END) AS leaf_term_count
FROM dim_glossary_term
GROUP BY hierarchy_depth
ORDER BY hierarchy_depth;

-- 2. View sample 6-level hierarchy
SELECT 
  term_fqdn,
  level_1_glossary,
  level_2,
  level_3,
  level_4,
  level_5,
  level_6,
  hierarchy_depth,
  is_leaf_term
FROM dim_glossary_term
WHERE hierarchy_depth = 6
LIMIT 20;

-- 3. Check ragged hierarchies (gaps in levels)
SELECT 
  term_fqdn,
  level_1_glossary,
  level_2,
  level_3,
  level_4,
  level_5,
  level_6
FROM dim_glossary_term
WHERE 
  (level_2 IS NULL AND level_3 IS NOT NULL) OR  -- Gap at level 2
  (level_3 IS NULL AND level_4 IS NOT NULL) OR  -- Gap at level 3
  (level_4 IS NULL AND level_5 IS NOT NULL) OR  -- Gap at level 4
  (level_5 IS NULL AND level_6 IS NOT NULL)     -- Gap at level 5
LIMIT 20;

-- 4. View all leaf terms (deepest terms for reporting)
SELECT 
  term_fqdn,
  leaf_name,
  hierarchy_depth,
  term_type
FROM dim_glossary_term
WHERE is_leaf_term = true
ORDER BY term_fqdn
LIMIT 50;

-- 5. Count terms by type at each level
SELECT 
  CASE 
    WHEN level_6 IS NOT NULL THEN 6
    WHEN level_5 IS NOT NULL THEN 5
    WHEN level_4 IS NOT NULL THEN 4
    WHEN level_3 IS NOT NULL THEN 3
    WHEN level_2 IS NOT NULL THEN 2
    ELSE 1
  END AS deepest_level,
  term_type,
  COUNT(*) AS term_count
FROM dim_glossary_term
GROUP BY deepest_level, term_type
ORDER BY deepest_level, term_type;

-- 6. Check for Mondrian drilldown paths
-- (Shows how many distinct values at each level)
SELECT 
  COUNT(DISTINCT level_1_glossary) AS level_1_count,
  COUNT(DISTINCT level_2) AS level_2_count,
  COUNT(DISTINCT level_3) AS level_3_count,
  COUNT(DISTINCT level_4) AS level_4_count,
  COUNT(DISTINCT level_5) AS level_5_count,
  COUNT(DISTINCT level_6) AS level_6_count
FROM dim_glossary_term;

-- 7. Sample drilldown: Pick one glossary and show its structure
WITH sample_glossary AS (
  SELECT level_1_glossary
  FROM dim_glossary_term
  GROUP BY level_1_glossary
  ORDER BY COUNT(*) DESC
  LIMIT 1
)
SELECT 
  term_fqdn,
  level_1_glossary,
  level_2,
  level_3,
  level_4,
  level_5,
  level_6,
  term_type,
  is_leaf_term
FROM dim_glossary_term
WHERE level_1_glossary = (SELECT level_1_glossary FROM sample_glossary)
ORDER BY term_fqdn
LIMIT 30;

-- 8. Check fact table join
SELECT 
  g.term_fqdn,
  g.term_type,
  g.is_leaf_term,
  COUNT(DISTINCT f.entity_key) AS distinct_entities,
  SUM(f.assignment_count) AS total_assignments
FROM fact_entity_glossary_term f
JOIN dim_glossary_term g ON f.glossary_term_key = g.glossary_term_key
GROUP BY g.term_fqdn, g.term_type, g.is_leaf_term
ORDER BY total_assignments DESC
LIMIT 20;

-- 9. Leaf terms with entity counts
SELECT 
  g.leaf_name,
  g.term_fqdn,
  COUNT(DISTINCT f.entity_key) AS entity_count
FROM dim_glossary_term g
LEFT JOIN fact_entity_glossary_term f ON g.glossary_term_key = f.glossary_term_key
WHERE g.is_leaf_term = true
GROUP BY g.leaf_name, g.term_fqdn
ORDER BY entity_count DESC NULLS LAST
LIMIT 30;

-- 10. Check for orphaned records
-- Terms without parent
SELECT 
  term_name,
  term_fqdn,
  parent_id
FROM dim_glossary_term
WHERE parent_id IS NOT NULL 
  AND NOT EXISTS (
    SELECT 1 FROM glossary_summary_view 
    WHERE _id = dim_glossary_term.parent_id
  )
LIMIT 10;
