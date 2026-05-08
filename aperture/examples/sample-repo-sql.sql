select * from gen_ai.raw_lead_generation rlg left join gen_ai.adj_lead_generation alg  on rlg.lead_generation_id =alg.lead_generation_id 
order by alg.is_human_in_role_confidence_score  desc



select pl.*, rlg.* from gen_ai.raw_lead_generation rlg left join gen_ai.prompt_library pl on rlg.prompt_id = pl.prompt_id  where rlg.execution_time = (select max(erlg.execution_time) from gen_ai.raw_lead_generation erlg)


select rat.emea_region, rat.billing_state_province , rat.account_owner, count(distinct rat.opportunity_id)  from gen_ai.raw_account_territories rat  group by 1,2, 3

WITH owner_counts AS (
    SELECT
        rat.emea_region,
        rat.billing_state_province,
        rat.account_owner,
        COUNT(DISTINCT rat.opportunity_id) AS opp_count
    FROM gen_ai.raw_account_territories rat
    GROUP BY
        rat.emea_region,
        rat.billing_state_province,
        rat.account_owner
),
ranked AS (
    SELECT
        emea_region,
        billing_state_province,
        account_owner,
        opp_count,
        ROW_NUMBER() OVER (
            PARTITION BY emea_region, billing_state_province
            ORDER BY opp_count DESC, account_owner
        ) AS rn
    FROM owner_counts
)
SELECT
    emea_region,
    account_owner,
    billing_state_province,
    opp_count
FROM ranked
WHERE rn = 1 order by emea_region,account_owner,billing_state_province;



with a as (select rlg.prompt_id, rlg.contact_confidence_score::integer  + rlg.contact_phone_confidence_score::integer + rlg.org_confidence_score::integer totals  from gen_ai.raw_lead_generation rlg)
select prompt_id, avg(totals) tot, count(*) from a where totals is not null group by 1 order by tot desc

with a as (select ao.account_owner_id, ao.account_owner_region_list, ao.account_owner_subregion_list, case when count(distinct rlg.lead_generation_id) = 1 then 0 else count(distinct rlg.lead_generation_id) end cnt , case when count(distinct rlg.lead_generation_id) > 0 then 'X' end process
from  gen_ai.log_lead_gen_req_resp llgrr right join gen_ai.account_owner ao on llgrr.account_owner_id = ao.account_owner_id  left join gen_ai.raw_lead_generation rlg on ao.account_owner_id  = rlg.account_owner_id 
group by 1,2,3
having  ao.account_owner_id >=9)
select 0 , '','',sum(cnt), '' from a 
union all select * from a





SELECT
  account_owner_name
, account_owner_region_list
, account_owner_subregion_list
, account_owner_industry_list
, account_owner_id
, (select max(run_id) from gen_ai.run_log) run_id
FROM gen_ai.account_owner
where active
and account_owner_id not in(
select account_owner_id from gen_ai.raw_lead_generation where run_id = (select max(run_id) from gen_ai.run_log)
)
order by account_owner_id


select rlg.run_id, ao.account_owner_id, ao.account_owner_region_list, ao.account_owner_subregion_list, sum(case when llgrr.run_id)
--, case when count(distinct rlg.lead_generation_id) = 1 then 0 else count(distinct rlg.lead_generation_id) end cnt , case when count(distinct rlg.lead_generation_id) > 0 then 'X' end process

select ao.run_id, ao.account_owner_id, ao.account_owner_region_list, ao.account_owner_subregion_list, sum(case when rlg.run_id is null then 0 else 1 end)
from (select ao1.*, (select max(run_id) from gen_ai.run_log) run_id from gen_ai.account_owner ao1 where active) ao 
left join gen_ai.log_lead_gen_req_resp llgrr on llgrr.account_owner_id = ao.account_owner_id and llgrr.run_id = ao.run_id 
left join gen_ai.raw_lead_generation rlg on ao.account_owner_id  = rlg.account_owner_id  and rlg.run_id = ao.run_id
where ao.run_id = (select max(run_id) from gen_ai.run_log) and ((llgrr.prompt_id = 7) or rlg.run_id is null )
group by 1,2,3, 4

select * from
(select ao1.*, (select max(run_id) from gen_ai.run_log) run_id from gen_ai.account_owner ao1) ao



with a as (select rlg.run_id, ao.account_owner_id, ao.account_owner_region_list, ao.account_owner_subregion_list, case when count(distinct rlg.lead_generation_id) = 1 then 0 else count(distinct rlg.lead_generation_id) end cnt , case when count(distinct rlg.lead_generation_id) > 0 then 'X' end process
from  gen_ai.log_lead_gen_req_resp llgrr right join gen_ai.account_owner ao on llgrr.account_owner_id = ao.account_owner_id  left join gen_ai.raw_lead_generation rlg on ao.account_owner_id  = rlg.account_owner_id 
group by 1,2,3, 4
--having  rlg.run_id = (select max(run_id) from gen_ai.run_log)
 )
select 0 , 0,'','',sum(cnt), '' from a 
union all select * from a

select a.*, b.cnt, b.pt from
(select run_id, prompt_id, max(process_time), min(process_time), count(*) from gen_ai.log_lead_gen_req_resp group by 1, 2 order by 1 desc) a
left join
(select run_id, prompt_id, count(*) cnt, max(process_time) pt from gen_ai.raw_lead_generation rlg where rlg.contact_name is not null group by 1, 2) b
on a.run_id = b.run_id and a.prompt_id = b.prompt_id
where a.run_id is not null
order by run_id desc, prompt_id desc


select run_id, prompt_id, process_time, * from gen_ai.log_lead_gen_req_resp 
where run_id = (select max(run_id) from gen_ai.log_lead_gen_req_resp)
order by log_lead_gen_req_resp_id desc limit 10

select count(*) from gen_ai.raw_lead_generation rlg where rlg.contact_name is not null

select count(*) from (select distinct rlg.contact_name, rlg.org_name from gen_ai.raw_lead_generation rlg where rlg.contact_name is not null) a

with a as (
select ao.run_id, ao.account_owner_id, ao.account_owner_region_list, ao.account_owner_subregion_list, sum(case when rlg.run_id is null then 0 else 1 end) cnt, sum(case when rlg.contact_name is null then 0 else 1 end) cnt2
from (select ao1.*, (select max(run_id) from gen_ai.run_log) run_id from gen_ai.account_owner ao1 where active) ao 
left join gen_ai.log_lead_gen_req_resp llgrr on llgrr.account_owner_id = ao.account_owner_id and llgrr.run_id = ao.run_id 
left join gen_ai.raw_lead_generation rlg on ao.account_owner_id  = rlg.account_owner_id  and rlg.run_id = ao.run_id
where ao.run_id = (select max(run_id) from gen_ai.run_log) and ((llgrr.prompt_id in (select prompt_id from gen_ai.log_lead_gen_req_resp order by llgrr.log_lead_gen_req_resp_id desc limit 1)) or rlg.run_id is null )
group by 1,2,3, 4
)
select 0 , 0,'','',sum(cnt),sum(cnt2) from a 
union all select * from a
order by 2





-- Set this coalesce to whatever threshold you want:
-- 1  => only records with 0 adjudications
-- 2  => records with 0 or 1 adjudications
select count(*) from
(
WITH adj_counts AS (
  SELECT
      lead_generation_id,
      prompt_id,
      COUNT(*) AS adj_count
  FROM gen_ai.adj_lead_generation
  GROUP BY
      lead_generation_id,
      prompt_id
)
SELECT
    r.*
FROM gen_ai.raw_lead_generation r
LEFT JOIN adj_counts a
  ON  a.lead_generation_id = r.lead_generation_id
  AND a.prompt_id         = r.prompt_id
WHERE
    COALESCE(a.adj_count, 0) < 1
    AND r.contact_name IS NOT null) a
    
    
    
select count(*) from (    
SELECT
    r.*
FROM gen_ai.raw_lead_generation r
WHERE
    r.contact_name IS NOT NULL
    AND r.org_name IS NOT NULL
    AND r.org_site_location IS NOT NULL
    AND NOT EXISTS (
        SELECT 1
        FROM gen_ai.adj_lead_generation a
        WHERE a.prompt_id         = r.prompt_id
 		AND a.contact_email_address = r.contact_email_address 
 		AND a.contact_phone = r.contact_phone
 		AND a.contact_role = r.contact_role
		AND a.contact_name      = r.contact_name
          AND a.org_name          = r.org_name
          AND a.org_site_location = r.org_site_location
    )
 ) b  

 
 
select count(*) from (
WITH adj_counts AS (
    SELECT
        a.org_name,
        a.org_site_location,
        a.contact_name,
        a.contact_role,
        a.contact_email_address,
        a.contact_phone,
        COUNT(*) AS run_count
    FROM gen_ai.adj_lead_generation a
    GROUP BY
        a.org_name,
        a.org_site_location,
        a.contact_name,
        a.contact_role,
        a.contact_email_address,
        a.contact_phone
)
SELECT
    r.org_name,
    r.org_site_location,
    r.contact_name,
    r.contact_role,
    r.contact_email_address,
    r.contact_phone,
    array_agg(DISTINCT r.lead_generation_id ORDER BY r.lead_generation_id) AS lead_generation_ids,
    array_agg(DISTINCT r.prompt_id         ORDER BY r.prompt_id)         AS prompt_ids,
    COALESCE(a.run_count, 0) AS run_count
FROM gen_ai.raw_lead_generation r
LEFT JOIN adj_counts a
    ON  a.org_name              = r.org_name
    AND a.org_site_location     = r.org_site_location
    AND a.contact_name          = r.contact_name
    AND a.contact_role          = r.contact_role
    AND a.contact_email_address = r.contact_email_address
    AND a.contact_phone         = r.contact_phone
WHERE
    r.contact_name      IS NOT NULL
    AND r.org_name      IS NOT NULL
    AND r.org_site_location IS NOT NULL
    AND COALESCE(a.run_count, 0) < 1
GROUP BY
    r.org_name,
    r.org_site_location,
    r.contact_name,
    r.contact_role,
    r.contact_email_address,
    r.contact_phone,
    a.run_count 
 ) z  
   
 
 
 CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;
 CREATE EXTENSION IF NOT EXISTS unaccent;
 
 
delete from gen_ai.adj_lead_generation alg where alg.is_human is null 


select * from  gen_ai.adj_lead_generation alg order by alg.process_time desc






SELECT
  fuzzy_key,
  COUNT(*) AS row_count,
  array_agg(lead_generation_id) AS raw_ids  -- or whatever your PK is
FROM (
  SELECT
    r.*,
    (
      dmetaphone(unaccent(lower(coalesce(r.org_name, ''))))          || '|' ||
      dmetaphone(unaccent(lower(coalesce(r.org_site_location, '')))) || '|' ||
      dmetaphone(unaccent(lower(coalesce(r.contact_name, ''))))      || '|' ||
      dmetaphone(unaccent(lower(coalesce(r.contact_role, ''))))
    ) AS fuzzy_key
  FROM gen_ai.raw_lead_generation r
) s
GROUP BY fuzzy_key
ORDER BY row_count DESC;







-- 1) Add the column to the raw table
ALTER TABLE gen_ai.raw_lead_generation
ADD COLUMN fuzzy_match_contact_key text;


CREATE OR REPLACE FUNCTION gen_ai.set_fuzzy_match_contact_key()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.fuzzy_match_contact_key :=
    dmetaphone(unaccent(lower(coalesce(NEW.org_name, ''))))          || '|' ||
    dmetaphone(unaccent(lower(coalesce(NEW.org_site_location, '')))) || '|' ||
    dmetaphone(unaccent(lower(coalesce(NEW.contact_name, ''))))      || '|' ||
    dmetaphone(unaccent(lower(coalesce(NEW.contact_role, ''))))      ;
  RETURN NEW;
END;
$$;



DROP TRIGGER IF EXISTS trg_raw_lead_generation_fuzzy_contact_key
ON gen_ai.raw_lead_generation;

CREATE TRIGGER trg_raw_lead_generation_fuzzy_contact_key
BEFORE INSERT OR UPDATE OF
  org_name,
  org_site_location,
  contact_name,
  contact_role
ON gen_ai.raw_lead_generation
FOR EACH ROW
EXECUTE FUNCTION gen_ai.set_fuzzy_match_contact_key();


UPDATE gen_ai.raw_lead_generation
SET org_name = org_name;  -- just to fire the trigger






select count(*), sum(case when contact_name is not null then 1 else 0 end ), count(distinct fuzzy_match_key), count(distinct fuzzy_match_contact_key),
count(distinct  org_name ||
  org_site_location ||
  contact_name ||
  contact_role ||
  contact_email_address  ||
  contact_phone)
from gen_ai.raw_lead_generation



select fuzzy_match_contact_key, * from gen_ai.raw_lead_generation 
where fuzzy_match_contact_key <> '|||'
order by 1 asc



-- 1) Add the column to the raw table
ALTER TABLE gen_ai.raw_lead_generation
ADD COLUMN fuzzy_match_org_site_contact_key text;


CREATE OR REPLACE FUNCTION gen_ai.set_fuzzy_match_org_site_contact_key()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.fuzzy_match_org_site_contact_key :=
    dmetaphone(unaccent(lower(coalesce(NEW.org_name, ''))))          || '|' ||
    dmetaphone(unaccent(lower(coalesce(NEW.org_site_location, '')))) || '|' ||
    dmetaphone(unaccent(lower(coalesce(NEW.contact_name, ''))))      ;
  RETURN NEW;
END;
$$;



DROP TRIGGER IF EXISTS trg_raw_lead_generation_org_site_contact_key
ON gen_ai.raw_lead_generation;

CREATE TRIGGER trg_raw_lead_generation_fuzzy_org_site_contact_key
BEFORE INSERT OR UPDATE OF
  org_name,
  org_site_location,
  contact_name
ON gen_ai.raw_lead_generation
FOR EACH ROW
EXECUTE FUNCTION gen_ai.set_fuzzy_match_org_site_contact_key();


UPDATE gen_ai.raw_lead_generation
SET org_name = org_name;  -- just to fire the trigger


select fuzzy_match_org_site_contact_key, * from gen_ai.raw_lead_generation 
where fuzzy_match_org_site_contact_key <> '||'
order by 1 asc


select count(*), sum(case when contact_name is not null then 1 else 0 end ), count(distinct fuzzy_match_key), count(distinct fuzzy_match_contact_key),count(distinct fuzzy_match_org_site_contact_key),
count(distinct  org_name ||
  org_site_location ||
  contact_name ||
  contact_role ||
  contact_email_address  ||
  contact_phone)
from gen_ai.raw_lead_generation