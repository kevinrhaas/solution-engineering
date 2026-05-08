--
-- PostgreSQL database dump
--

-- Dumped from database version 15.10
-- Dumped by pg_dump version 16.6 (Homebrew)

-- Started on 2026-01-23 11:21:20 CST

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 5 (class 2615 OID 49437)
-- Name: bidb; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA bidb;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 214 (class 1259 OID 16444)
-- Name: SequelizeMeta; Type: TABLE; Schema: bidb; Owner: -
--

CREATE TABLE bidb."SequelizeMeta" (
    name character varying(255) NOT NULL
);


--
-- TOC entry 231 (class 1259 OID 16589)
-- Name: applications_policies_view; Type: TABLE; Schema: bidb; Owner: -
--

CREATE TABLE bidb.applications_policies_view (
    _id bigint NOT NULL,
    "ApplicationId" text,
    "PolicyId" text
);


--
-- TOC entry 230 (class 1259 OID 16588)
-- Name: applications_policies_view__id_seq; Type: SEQUENCE; Schema: bidb; Owner: -
--

CREATE SEQUENCE bidb.applications_policies_view__id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 3524 (class 0 OID 0)
-- Dependencies: 230
-- Name: applications_policies_view__id_seq; Type: SEQUENCE OWNED BY; Schema: bidb; Owner: -
--

ALTER SEQUENCE bidb.applications_policies_view__id_seq OWNED BY bidb.applications_policies_view._id;


--
-- TOC entry 226 (class 1259 OID 16565)
-- Name: applications_summary_view; Type: TABLE; Schema: bidb; Owner: -
--

CREATE TABLE bidb.applications_summary_view (
    _id text NOT NULL,
    "Name" text,
    "Type" text,
    "Parent" text,
    "Fqdn" text,
    "UsersWithAccess" jsonb
);


--
-- TOC entry 233 (class 1259 OID 16598)
-- Name: applications_terms_view; Type: TABLE; Schema: bidb; Owner: -
--

CREATE TABLE bidb.applications_terms_view (
    _id bigint NOT NULL,
    "ApplicationId" text,
    "TermId" text
);


--
-- TOC entry 232 (class 1259 OID 16597)
-- Name: applications_terms_view__id_seq; Type: SEQUENCE; Schema: bidb; Owner: -
--

CREATE SEQUENCE bidb.applications_terms_view__id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 3527 (class 0 OID 0)
-- Dependencies: 232
-- Name: applications_terms_view__id_seq; Type: SEQUENCE OWNED BY; Schema: bidb; Owner: -
--

ALTER SEQUENCE bidb.applications_terms_view__id_seq OWNED BY bidb.applications_terms_view._id;


--
-- TOC entry 221 (class 1259 OID 16532)
-- Name: checksum_aggregated_view; Type: TABLE; Schema: bidb; Owner: -
--

CREATE TABLE bidb.checksum_aggregated_view (
    _id text NOT NULL,
    "duplicateFilesCount" integer,
    "duplicateFilesSize" bigint
);


--
-- TOC entry 240 (class 1259 OID 16645)
-- Name: currency_exchange_rates; Type: TABLE; Schema: bidb; Owner: -
--

CREATE TABLE bidb.currency_exchange_rates (
    currency_symbol text NOT NULL,
    "ConversionRateToUSD" double precision
);


--
-- TOC entry 234 (class 1259 OID 16606)
-- Name: custom_properties_view; Type: TABLE; Schema: bidb; Owner: -
--

CREATE TABLE bidb.custom_properties_view (
    "EntityId" character varying(255) NOT NULL,
    "PropertyId" character varying(255) NOT NULL,
    "Value" text,
    "PropertyName" character varying(255),
    "FqdnDisplay" text
);


--
-- TOC entry 239 (class 1259 OID 16638)
-- Name: datasource_category_mapping; Type: TABLE; Schema: bidb; Owner: -
--

CREATE TABLE bidb.datasource_category_mapping (
    "DataSourceType" text NOT NULL,
    category text
);


--
-- TOC entry 237 (class 1259 OID 16628)
-- Name: delete_memo; Type: TABLE; Schema: bidb; Owner: -
--

CREATE TABLE bidb.delete_memo (
    view_name text NOT NULL,
    id text NOT NULL,
    related_id text,
    job_id text NOT NULL
);


--
-- TOC entry 217 (class 1259 OID 16485)
-- Name: duplicate_files_view; Type: TABLE; Schema: bidb; Owner: -
--

CREATE TABLE bidb.duplicate_files_view (
    _id bigint NOT NULL,
    "EntityId" text,
    "GroupId" text,
    "FileCount" integer,
    "Size" bigint,
    "CreatedAt" timestamp with time zone,
    "ModifiedAt" timestamp with time zone
);


--
-- TOC entry 216 (class 1259 OID 16484)
-- Name: duplicate_files_view__id_seq; Type: SEQUENCE; Schema: bidb; Owner: -
--

CREATE SEQUENCE bidb.duplicate_files_view__id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 3534 (class 0 OID 0)
-- Dependencies: 216
-- Name: duplicate_files_view__id_seq; Type: SEQUENCE OWNED BY; Schema: bidb; Owner: -
--

ALTER SEQUENCE bidb.duplicate_files_view__id_seq OWNED BY bidb.duplicate_files_view._id;


--
-- TOC entry 224 (class 1259 OID 16553)
-- Name: entities_aggregated_view; Type: TABLE; Schema: bidb; Owner: -
--

CREATE TABLE bidb.entities_aggregated_view (
    "Attribute" character varying(255),
    "Type" character varying(255),
    "Value" jsonb
);


--
-- TOC entry 219 (class 1259 OID 16521)
-- Name: entities_applications_view; Type: TABLE; Schema: bidb; Owner: -
--

CREATE TABLE bidb.entities_applications_view (
    "EntityId" text,
    "ApplicationId" text,
    "FqdnDisplay" text
);


--
-- TOC entry 241 (class 1259 OID 16652)
-- Name: entities_custom_categorization; Type: TABLE; Schema: bidb; Owner: -
--

CREATE TABLE bidb.entities_custom_categorization (
    _id character varying(24) NOT NULL,
    "EntityCategory" text,
    "GlossaryName" text,
    "GlossaryType" text
);


--
-- TOC entry 222 (class 1259 OID 16539)
-- Name: entities_extension_count_view; Type: TABLE; Schema: bidb; Owner: -
--

CREATE TABLE bidb.entities_extension_count_view (
    _id text NOT NULL,
    "Date" timestamp with time zone,
    "DataSourceFqdnId" text,
    "Extension" text,
    "FileCount" integer
);


--
-- TOC entry 215 (class 1259 OID 16477)
-- Name: entities_master_view; Type: TABLE; Schema: bidb; Owner: -
--

CREATE TABLE bidb.entities_master_view (
    _id text NOT NULL,
    "Name" text,
    "Type" text,
    "Parent" text,
    "ResourceType" text,
    "DataSourceId" text,
    "DataSourceName" text,
    "DataSourceType" text,
    "DataSourceCostPerTbCurrency" text,
    "DataSourceCostPerTbPrice" integer,
    "DataSourceAffinityId" text,
    "DataProfileStatus" text,
    "DataProfiled" text,
    "LastUpdate" timestamp with time zone,
    "ProductName" text,
    "ProductVersion" text,
    "DriverName" text,
    "Url" text,
    "ParentName" text,
    "TotalTables" integer,
    "TotalColumns" integer,
    "SchemaName" text,
    "DatabaseName" text,
    "LastUpdateStatistics" timestamp with time zone,
    "RowCount" bigint,
    "NullCount" bigint,
    "Cardinality" bigint,
    "Hll" bigint,
    "BlankCount" bigint,
    "Min" double precision,
    "Max" double precision,
    "AvgValue" double precision,
    "MinWidth" integer,
    "MaxWidth" integer,
    "AvgWidth" double precision,
    "ColumnsCount" integer,
    "CheckClause" text,
    "TableName" text,
    "DataType" text,
    "TypeName" text,
    "ColumnSize" integer,
    "BufferLength" integer,
    "DecimalDigits" integer,
    "NumPrecRadix" integer,
    "IsNullable" boolean,
    "OrdinalPosition" integer,
    "IsPrimaryKey" boolean,
    "IsForeignKey" boolean,
    "Path" text,
    "ParentPath" text,
    "PathType" text,
    "FileExtension" text,
    "Size" bigint,
    "Flags" integer,
    "Owner" text,
    "Group" text,
    "SymLinkTarget" text,
    "FileType" text,
    "CreatedAt" timestamp with time zone,
    "ModifiedAt" timestamp with time zone,
    "AccessedAt" timestamp with time zone,
    "ScannedAt" timestamp with time zone,
    "IsSymlink" boolean,
    "LinkType" text,
    "PhysicalLocation" text,
    "Title" text,
    "Author" text,
    "Subject" text,
    "Application" text,
    "Producer" text,
    "Version" text,
    "DocumentSize" bigint,
    "PageSize" bigint,
    "PageCount" bigint,
    "Company" text,
    "Paragraphs" text,
    "Lines" bigint,
    "Words" bigint,
    "Characters" bigint,
    "CharactersWithSpaces" bigint,
    "Language" text,
    "Checksum" text,
    "PropertiesChecksum" text,
    "ChildDirs" bigint,
    "ChildFiles" bigint,
    "ChildDirSize" bigint,
    "ChildFileSize" bigint,
    "TotalChildDirs" bigint,
    "TotalChildFiles" bigint,
    "TotalChildDirSize" bigint,
    "TotalChildFileSize" bigint,
    "LocationName" text,
    "LocationStreetAddress" text,
    "LocationStreetAddress2" text,
    "LocationLocalityCity" text,
    "LocationStateProvince" text,
    "LocationPostalCode" text,
    "LocationCountry" text,
    "CostPerTbFrequency" text,
    "TotalCapacity" jsonb,
    "FqdnDisplay" text,
    "OwnerFirstName" text,
    "OwnerLastName" text,
    "OwnerEmail" text,
    "OwnerUserName" text,
    "OwnerIsDeleted" boolean,
    "UserAccessDetails" jsonb,
    "Sensitivity" text,
    "Selectivity" double precision,
    "Uniqueness" double precision,
    "Density" double precision,
    "LexicalMin" text,
    "LexicalMax" text
);


--
-- TOC entry 220 (class 1259 OID 16527)
-- Name: entities_policies_view; Type: TABLE; Schema: bidb; Owner: -
--

CREATE TABLE bidb.entities_policies_view (
    "EntityId" text,
    "PolicyId" text,
    "FqdnDisplay" text
);


--
-- TOC entry 238 (class 1259 OID 16633)
-- Name: entities_summary_view; Type: VIEW; Schema: bidb; Owner: -
--

CREATE VIEW bidb.entities_summary_view AS
 SELECT m._id,
    m."Name",
    m."Type",
    m."Parent",
    m."FqdnDisplay"
   FROM bidb.entities_master_view m;


--
-- TOC entry 223 (class 1259 OID 16546)
-- Name: entities_temperature_count_view; Type: TABLE; Schema: bidb; Owner: -
--

CREATE TABLE bidb.entities_temperature_count_view (
    _id text NOT NULL,
    "Date" timestamp with time zone,
    "DataSourceFqdnId" text,
    "Temperature" text,
    "FileCount" integer
);


--
-- TOC entry 225 (class 1259 OID 16558)
-- Name: glossary_summary_view; Type: TABLE; Schema: bidb; Owner: -
--

CREATE TABLE bidb.glossary_summary_view (
    _id text NOT NULL,
    "Name" text,
    "Type" text,
    "Parent" text,
    "Fqdn" text
);


--
-- TOC entry 218 (class 1259 OID 16505)
-- Name: terms_view; Type: TABLE; Schema: bidb; Owner: -
--

CREATE TABLE bidb.terms_view (
    "EntityId" text NOT NULL,
    "TermName" text,
    "GlossaryId" text,
    "TermId" text NOT NULL,
    "FqdnDisplay" text
);


--
-- TOC entry 245 (class 1259 OID 16680)
-- Name: mv_duplicate_by_term_summary_view; Type: MATERIALIZED VIEW; Schema: bidb; Owner: -
--

CREATE MATERIALIZED VIEW bidb.mv_duplicate_by_term_summary_view AS
 WITH temperature_roots AS (
         SELECT g._id
           FROM (bidb.entities_custom_categorization ecc
             JOIN bidb.glossary_summary_view g ON (((lower(ecc."GlossaryName") = lower(g."Name")) AND (lower(ecc."GlossaryType") = lower(g."Type")))))
          WHERE (ecc."EntityCategory" = 'Temperature'::text)
        ), relevant_terms AS (
         SELECT DISTINCT t._id AS term_id,
            lower(t."Name") AS term_label
           FROM (bidb.glossary_summary_view t
             LEFT JOIN bidb.glossary_summary_view parent ON ((t."Parent" = parent._id)))
          WHERE ((t."Type" = 'term'::text) AND ((t."Parent" IN ( SELECT temperature_roots._id
                   FROM temperature_roots)) OR (parent."Parent" IN ( SELECT temperature_roots._id
                   FROM temperature_roots))))
        ), earliest_files AS (
         SELECT duplicate_files_view."GroupId",
            min(
                CASE
                    WHEN (duplicate_files_view."CreatedAt" IS NULL) THEN duplicate_files_view."ModifiedAt"
                    ELSE duplicate_files_view."CreatedAt"
                END) AS min_created_date
           FROM bidb.duplicate_files_view
          GROUP BY duplicate_files_view."GroupId"
        ), duplicates_only AS (
         SELECT DISTINCT dfv."EntityId"
           FROM (bidb.duplicate_files_view dfv
             JOIN earliest_files ef ON ((dfv."GroupId" = ef."GroupId")))
          WHERE (
                CASE
                    WHEN (dfv."CreatedAt" IS NULL) THEN dfv."ModifiedAt"
                    ELSE dfv."CreatedAt"
                END <> ef.min_created_date)
        ), filtered_terms AS (
         SELECT DISTINCT tv."EntityId",
            rt.term_label
           FROM (bidb.terms_view tv
             JOIN relevant_terms rt ON ((tv."TermId" = rt.term_id)))
        ), joined_data AS (
         SELECT ft.term_label,
                CASE
                    WHEN (emv."Type" = 'TABLE'::text) THEN (0)::double precision
                    WHEN (emv."Type" = 'FILE'::text) THEN ((emv."Size")::double precision / (1099511627776.0)::double precision)
                    ELSE NULL::double precision
                END AS size_tb,
                CASE
                    WHEN (emv."Type" = 'TABLE'::text) THEN (0)::double precision
                    WHEN (emv."Type" = 'FILE'::text) THEN (((emv."Size")::double precision / (1099511627776.0)::double precision) * COALESCE(((emv."DataSourceCostPerTbPrice")::double precision * cer."ConversionRateToUSD"), (0)::double precision))
                    ELSE NULL::double precision
                END AS cost_usd
           FROM (((duplicates_only d
             JOIN filtered_terms ft ON ((d."EntityId" = ft."EntityId")))
             JOIN bidb.entities_master_view emv ON ((d."EntityId" = emv._id)))
             LEFT JOIN bidb.currency_exchange_rates cer ON ((emv."DataSourceCostPerTbCurrency" = cer.currency_symbol)))
        )
 SELECT joined_data.term_label,
    count(*) AS entity_count,
    sum(joined_data.size_tb) AS total_duplicate_tb,
    sum(joined_data.cost_usd) AS total_duplicate_cost_usd
   FROM joined_data
  GROUP BY joined_data.term_label
  WITH NO DATA;


--
-- TOC entry 246 (class 1259 OID 16687)
-- Name: mv_duplicate_entities_summary_view; Type: MATERIALIZED VIEW; Schema: bidb; Owner: -
--

CREATE MATERIALIZED VIEW bidb.mv_duplicate_entities_summary_view AS
 WITH earliest_files AS (
         SELECT dfv."GroupId",
            min(
                CASE
                    WHEN (dfv."CreatedAt" IS NULL) THEN dfv."ModifiedAt"
                    ELSE dfv."CreatedAt"
                END) AS min_created_date
           FROM bidb.duplicate_files_view dfv
          GROUP BY dfv."GroupId"
        ), duplicates_only AS (
         SELECT dfv._id,
            dfv."EntityId",
            dfv."GroupId",
            dfv."FileCount",
            dfv."Size",
            dfv."CreatedAt",
            dfv."ModifiedAt"
           FROM (bidb.duplicate_files_view dfv
             JOIN earliest_files ef ON ((dfv."GroupId" = ef."GroupId")))
          WHERE (
                CASE
                    WHEN (dfv."CreatedAt" IS NULL) THEN dfv."ModifiedAt"
                    ELSE dfv."CreatedAt"
                END <> ef.min_created_date)
        ), deduplicated_costs AS (
         SELECT dfv."EntityId",
                CASE
                    WHEN (emv."Type" = 'TABLE'::text) THEN (0)::double precision
                    WHEN (emv."Type" = 'FILE'::text) THEN ((emv."Size")::double precision / (1099511627776.0)::double precision)
                    ELSE NULL::double precision
                END AS size_tb,
                CASE
                    WHEN (emv."Type" = 'TABLE'::text) THEN (0)::double precision
                    WHEN (emv."Type" = 'FILE'::text) THEN (((emv."Size")::double precision / (1099511627776.0)::double precision) * COALESCE(((emv."DataSourceCostPerTbPrice")::double precision * cer."ConversionRateToUSD"), (0)::double precision))
                    ELSE NULL::double precision
                END AS cost_usd
           FROM ((duplicates_only dfv
             JOIN bidb.entities_master_view emv ON ((dfv."EntityId" = emv._id)))
             LEFT JOIN bidb.currency_exchange_rates cer ON ((emv."DataSourceCostPerTbCurrency" = cer.currency_symbol)))
        )
 SELECT count(*) AS total_duplicate_files,
    sum(deduplicated_costs.size_tb) AS total_duplicate_tb,
    sum(deduplicated_costs.cost_usd) AS total_duplicate_cost_usd
   FROM deduplicated_costs
  WITH NO DATA;


--
-- TOC entry 247 (class 1259 OID 16692)
-- Name: mv_duplicate_entity_detail_view; Type: MATERIALIZED VIEW; Schema: bidb; Owner: -
--

CREATE MATERIALIZED VIEW bidb.mv_duplicate_entity_detail_view AS
 WITH earliest_files AS (
         SELECT dfv_1."GroupId",
            min(
                CASE
                    WHEN (dfv_1."CreatedAt" IS NULL) THEN dfv_1."ModifiedAt"
                    ELSE dfv_1."CreatedAt"
                END) AS min_created_date
           FROM bidb.duplicate_files_view dfv_1
          GROUP BY dfv_1."GroupId"
        ), duplicates_only AS (
         SELECT dfv_1."GroupId",
            dfv_1."EntityId"
           FROM (bidb.duplicate_files_view dfv_1
             JOIN earliest_files ef ON (((dfv_1."GroupId" = ef."GroupId") AND (
                CASE
                    WHEN (dfv_1."CreatedAt" IS NULL) THEN dfv_1."ModifiedAt"
                    ELSE dfv_1."CreatedAt"
                END <> ef.min_created_date))))
        )
 SELECT dfv."GroupId",
    emv."Path" AS duplicate_path,
    emv._id AS entity_id,
        CASE
            WHEN (emv."Type" = 'TABLE'::text) THEN (0)::double precision
            WHEN (emv."Type" = 'FILE'::text) THEN ((emv."Size")::double precision / (1099511627776.0)::double precision)
            ELSE NULL::double precision
        END AS size_tb,
        CASE
            WHEN (emv."Type" = 'TABLE'::text) THEN (0)::double precision
            WHEN (emv."Type" = 'FILE'::text) THEN (((emv."Size")::double precision / (1099511627776.0)::double precision) * COALESCE(((emv."DataSourceCostPerTbPrice")::double precision * cer."ConversionRateToUSD"), (0)::double precision))
            ELSE NULL::double precision
        END AS cost_usd,
    emv."DataSourceName",
    emv."FileType"
   FROM ((duplicates_only dfv
     JOIN bidb.entities_master_view emv ON ((dfv."EntityId" = emv._id)))
     LEFT JOIN bidb.currency_exchange_rates cer ON ((emv."DataSourceCostPerTbCurrency" = cer.currency_symbol)))
  WITH NO DATA;


--
-- TOC entry 244 (class 1259 OID 16673)
-- Name: mv_duplicate_savings_by_original_view; Type: MATERIALIZED VIEW; Schema: bidb; Owner: -
--

CREATE MATERIALIZED VIEW bidb.mv_duplicate_savings_by_original_view AS
 WITH min_time_per_group AS (
         SELECT dfv."GroupId",
            min(
                CASE
                    WHEN (dfv."CreatedAt" IS NULL) THEN dfv."ModifiedAt"
                    ELSE dfv."CreatedAt"
                END) AS min_created_at
           FROM bidb.duplicate_files_view dfv
          GROUP BY dfv."GroupId"
        ), original_files AS (
         SELECT DISTINCT ON (dfv."GroupId") dfv."GroupId",
            dfv."EntityId",
            dfv."FileCount",
            dfv."Size"
           FROM (bidb.duplicate_files_view dfv
             JOIN min_time_per_group mt ON (((dfv."GroupId" = mt."GroupId") AND (
                CASE
                    WHEN (dfv."CreatedAt" IS NULL) THEN dfv."ModifiedAt"
                    ELSE dfv."CreatedAt"
                END = mt.min_created_at))))
          ORDER BY dfv."GroupId", dfv."EntityId"
        )
 SELECT of."GroupId",
    emv."Path" AS original_path,
    (of."FileCount" - 1) AS duplicate_file_count,
        CASE
            WHEN (emv."Type" = 'TABLE'::text) THEN (0)::double precision
            WHEN (emv."Type" = 'FILE'::text) THEN (((of."Size")::double precision / (1099511627776.0)::double precision) * ((of."FileCount" - 1))::double precision)
            ELSE NULL::double precision
        END AS savings_size_tb,
        CASE
            WHEN (emv."Type" = 'TABLE'::text) THEN (0)::double precision
            WHEN (emv."Type" = 'FILE'::text) THEN ((((emv."Size")::double precision / (1099511627776.0)::double precision) * COALESCE(((emv."DataSourceCostPerTbPrice")::double precision * cer."ConversionRateToUSD"), (0)::double precision)) * ((of."FileCount" - 1))::double precision)
            ELSE NULL::double precision
        END AS savings_cost_usd,
    emv."DataSourceType",
    emv."Type",
    dcm.category AS "Category"
   FROM (((original_files of
     JOIN bidb.entities_master_view emv ON ((of."EntityId" = emv._id)))
     LEFT JOIN bidb.currency_exchange_rates cer ON ((emv."DataSourceCostPerTbCurrency" = cer.currency_symbol)))
     LEFT JOIN bidb.datasource_category_mapping dcm ON ((emv."DataSourceType" = dcm."DataSourceType")))
  WITH NO DATA;


--
-- TOC entry 243 (class 1259 OID 16666)
-- Name: mv_entity_category_summary_view; Type: MATERIALIZED VIEW; Schema: bidb; Owner: -
--

CREATE MATERIALIZED VIEW bidb.mv_entity_category_summary_view AS
 WITH category_roots AS (
         SELECT g._id,
            ecc."EntityCategory"
           FROM (bidb.entities_custom_categorization ecc
             JOIN bidb.glossary_summary_view g ON (((lower(ecc."GlossaryName") = lower(g."Name")) AND (lower(ecc."GlossaryType") = lower(g."Type")))))
        ), relevant_terms AS (
         SELECT DISTINCT t._id AS term_id,
            lower(t."Name") AS term_label,
            COALESCE(gr."EntityCategory", pr."EntityCategory") AS entity_category
           FROM (((bidb.glossary_summary_view t
             LEFT JOIN bidb.glossary_summary_view p ON ((t."Parent" = p._id)))
             LEFT JOIN category_roots gr ON ((t."Parent" = gr._id)))
             LEFT JOIN category_roots pr ON ((p."Parent" = pr._id)))
          WHERE (t."Type" = 'term'::text)
        ), term_entities AS (
         SELECT tv."EntityId",
            rt.term_label,
            rt.entity_category
           FROM (bidb.terms_view tv
             JOIN relevant_terms rt ON ((tv."TermId" = rt.term_id)))
        ), entity_costs AS (
         SELECT emv._id AS entity_id,
            emv."Path",
            emv."DataSourceName",
            emv."DataSourceType",
            dcm.category AS "Category",
            emv."Type",
                CASE
                    WHEN (emv."Type" = 'TABLE'::text) THEN (0)::double precision
                    WHEN (emv."Type" = 'FILE'::text) THEN ((emv."Size")::double precision / (1099511627776.0)::double precision)
                    ELSE NULL::double precision
                END AS size_tb,
                CASE
                    WHEN (emv."Type" = 'TABLE'::text) THEN (0)::double precision
                    WHEN (emv."Type" = 'FILE'::text) THEN (((emv."Size")::double precision / (1099511627776.0)::double precision) * COALESCE(((emv."DataSourceCostPerTbPrice")::double precision * cer."ConversionRateToUSD"), (0)::double precision))
                    ELSE NULL::double precision
                END AS cost_usd
           FROM ((bidb.entities_master_view emv
             LEFT JOIN bidb.currency_exchange_rates cer ON ((emv."DataSourceCostPerTbCurrency" = cer.currency_symbol)))
             LEFT JOIN bidb.datasource_category_mapping dcm ON ((emv."DataSourceType" = dcm."DataSourceType")))
        )
 SELECT te.entity_category AS "EntityCategory",
    te.term_label AS "TermLabel",
    ec."DataSourceName",
    ec."DataSourceType",
    ec."Category",
    ec."Type",
    count(DISTINCT ec.entity_id) AS entity_count,
    sum(ec.size_tb) AS total_size_tb,
    sum(ec.cost_usd) AS total_cost_usd
   FROM (term_entities te
     JOIN entity_costs ec ON ((te."EntityId" = ec.entity_id)))
  GROUP BY te.entity_category, te.term_label, ec."DataSourceName", ec."DataSourceType", ec."Category", ec."Type"
  WITH NO DATA;


--
-- TOC entry 242 (class 1259 OID 16659)
-- Name: mv_master; Type: MATERIALIZED VIEW; Schema: bidb; Owner: -
--

CREATE MATERIALIZED VIEW bidb.mv_master AS
 WITH categorized_data AS (
         SELECT emv._id,
            emv."Name",
            emv."Type",
            emv."DataSourceName",
            emv."DataSourceType",
            emv."DataSourceCostPerTbCurrency",
            emv."DataSourceCostPerTbPrice",
            emv."Size",
            cer."ConversionRateToUSD",
            emv."Path",
            emv."FileType",
            dcm.category AS "Category",
            ((emv."DataSourceCostPerTbPrice")::double precision * cer."ConversionRateToUSD") AS "Converted Amount",
                CASE
                    WHEN (emv."Type" = 'TABLE'::text) THEN (0)::double precision
                    WHEN (emv."Type" = 'FILE'::text) THEN ((emv."Size")::double precision / (1099511627776.0)::double precision)
                    ELSE NULL::double precision
                END AS "Size in TB",
            emv."Sensitivity"
           FROM ((bidb.entities_master_view emv
             LEFT JOIN bidb.datasource_category_mapping dcm ON ((emv."DataSourceType" = dcm."DataSourceType")))
             LEFT JOIN bidb.currency_exchange_rates cer ON ((emv."DataSourceCostPerTbCurrency" = cer.currency_symbol)))
        )
 SELECT categorized_data."Category",
    categorized_data."DataSourceName",
    categorized_data."DataSourceType",
    categorized_data."DataSourceCostPerTbCurrency",
    categorized_data."DataSourceCostPerTbPrice",
    categorized_data."FileType",
    categorized_data."Type",
    categorized_data."ConversionRateToUSD",
    categorized_data."Sensitivity",
    count(categorized_data._id) AS "Total IDs",
    (sum(COALESCE(categorized_data."Size", (0)::bigint)))::double precision AS "Total Size (Bytes)",
    sum(COALESCE(categorized_data."Size in TB", (0)::double precision)) AS "Total Size (TB)",
    sum((COALESCE(categorized_data."Size in TB", (0)::double precision) * COALESCE(((categorized_data."DataSourceCostPerTbPrice")::double precision * categorized_data."ConversionRateToUSD"), (0)::double precision))) AS "Total Cost"
   FROM categorized_data
  GROUP BY categorized_data."Category", categorized_data."DataSourceName", categorized_data."ConversionRateToUSD", categorized_data."DataSourceType", categorized_data."DataSourceCostPerTbCurrency", categorized_data."DataSourceCostPerTbPrice", categorized_data."FileType", categorized_data."Type", categorized_data."Sensitivity"
  WITH NO DATA;


--
-- TOC entry 227 (class 1259 OID 16572)
-- Name: policies_summary_view; Type: TABLE; Schema: bidb; Owner: -
--

CREATE TABLE bidb.policies_summary_view (
    _id text NOT NULL,
    "Name" text,
    "Type" text,
    "Parent" text,
    "Fqdn" text
);


--
-- TOC entry 248 (class 1259 OID 16699)
-- Name: mv_policies_summary; Type: MATERIALIZED VIEW; Schema: bidb; Owner: -
--

CREATE MATERIALIZED VIEW bidb.mv_policies_summary AS
 SELECT l1."Name" AS "Level1_Name",
    l2."Name" AS "Level2_Name",
    l3."Name" AS "Level3_Name",
    count(m._id) AS "MasterView_ID_Count"
   FROM ((((bidb.policies_summary_view l1
     JOIN bidb.policies_summary_view l2 ON ((l1._id = l2."Parent")))
     JOIN bidb.policies_summary_view l3 ON ((l2._id = l3."Parent")))
     JOIN bidb.entities_policies_view epv ON ((l3._id = epv."PolicyId")))
     JOIN bidb.entities_master_view m ON ((epv."EntityId" = m._id)))
  WHERE ((l1."Parent" IS NULL) AND (l2."Parent" IS NOT NULL) AND (l2."Type" = 'policy'::text) AND (l3."Type" = 'standard'::text))
  GROUP BY l1."Name", l2."Name", l3."Name"
UNION
 SELECT l1."Name" AS "Level1_Name",
    NULL::text AS "Level2_Name",
    l2."Name" AS "Level3_Name",
    count(m._id) AS "MasterView_ID_Count"
   FROM (((bidb.policies_summary_view l1
     JOIN bidb.policies_summary_view l2 ON ((l1._id = l2."Parent")))
     JOIN bidb.entities_policies_view epv ON ((l2._id = epv."PolicyId")))
     JOIN bidb.entities_master_view m ON ((epv."EntityId" = m._id)))
  WHERE ((l1."Parent" IS NULL) AND (l2."Type" = 'standard'::text))
  GROUP BY l1."Name", l2."Name"
  WITH NO DATA;


--
-- TOC entry 235 (class 1259 OID 16613)
-- Name: pipeline_control; Type: TABLE; Schema: bidb; Owner: -
--

CREATE TABLE bidb.pipeline_control (
    view_name text NOT NULL,
    last_successful_started_at timestamp with time zone NOT NULL,
    last_job_id text NOT NULL
);


--
-- TOC entry 236 (class 1259 OID 16620)
-- Name: pipeline_log; Type: TABLE; Schema: bidb; Owner: -
--

CREATE TABLE bidb.pipeline_log (
    job_id text NOT NULL,
    view_name text NOT NULL,
    started_at timestamp with time zone NOT NULL,
    completed_at timestamp with time zone,
    status text
);


--
-- TOC entry 229 (class 1259 OID 16580)
-- Name: terms_policies_view; Type: TABLE; Schema: bidb; Owner: -
--

CREATE TABLE bidb.terms_policies_view (
    _id bigint NOT NULL,
    "TermId" text,
    "PolicyId" text
);


--
-- TOC entry 228 (class 1259 OID 16579)
-- Name: terms_policies_view__id_seq; Type: SEQUENCE; Schema: bidb; Owner: -
--

CREATE SEQUENCE bidb.terms_policies_view__id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 3556 (class 0 OID 0)
-- Dependencies: 228
-- Name: terms_policies_view__id_seq; Type: SEQUENCE OWNED BY; Schema: bidb; Owner: -
--

ALTER SEQUENCE bidb.terms_policies_view__id_seq OWNED BY bidb.terms_policies_view._id;


--
-- TOC entry 3325 (class 2604 OID 16592)
-- Name: applications_policies_view _id; Type: DEFAULT; Schema: bidb; Owner: -
--

ALTER TABLE ONLY bidb.applications_policies_view ALTER COLUMN _id SET DEFAULT nextval('bidb.applications_policies_view__id_seq'::regclass);


--
-- TOC entry 3326 (class 2604 OID 16601)
-- Name: applications_terms_view _id; Type: DEFAULT; Schema: bidb; Owner: -
--

ALTER TABLE ONLY bidb.applications_terms_view ALTER COLUMN _id SET DEFAULT nextval('bidb.applications_terms_view__id_seq'::regclass);


--
-- TOC entry 3323 (class 2604 OID 16488)
-- Name: duplicate_files_view _id; Type: DEFAULT; Schema: bidb; Owner: -
--

ALTER TABLE ONLY bidb.duplicate_files_view ALTER COLUMN _id SET DEFAULT nextval('bidb.duplicate_files_view__id_seq'::regclass);


--
-- TOC entry 3324 (class 2604 OID 16583)
-- Name: terms_policies_view _id; Type: DEFAULT; Schema: bidb; Owner: -
--

ALTER TABLE ONLY bidb.terms_policies_view ALTER COLUMN _id SET DEFAULT nextval('bidb.terms_policies_view__id_seq'::regclass);


--
-- TOC entry 3328 (class 2606 OID 16452)
-- Name: SequelizeMeta SequelizeMeta_pkey; Type: CONSTRAINT; Schema: bidb; Owner: -
--

ALTER TABLE ONLY bidb."SequelizeMeta"
    ADD CONSTRAINT "SequelizeMeta_pkey" PRIMARY KEY (name);


--
-- TOC entry 3350 (class 2606 OID 16596)
-- Name: applications_policies_view applications_policies_view_pkey; Type: CONSTRAINT; Schema: bidb; Owner: -
--

ALTER TABLE ONLY bidb.applications_policies_view
    ADD CONSTRAINT applications_policies_view_pkey PRIMARY KEY (_id);


--
-- TOC entry 3344 (class 2606 OID 16571)
-- Name: applications_summary_view applications_summary_view_pkey; Type: CONSTRAINT; Schema: bidb; Owner: -
--

ALTER TABLE ONLY bidb.applications_summary_view
    ADD CONSTRAINT applications_summary_view_pkey PRIMARY KEY (_id);


--
-- TOC entry 3352 (class 2606 OID 16605)
-- Name: applications_terms_view applications_terms_view_pkey; Type: CONSTRAINT; Schema: bidb; Owner: -
--

ALTER TABLE ONLY bidb.applications_terms_view
    ADD CONSTRAINT applications_terms_view_pkey PRIMARY KEY (_id);


--
-- TOC entry 3336 (class 2606 OID 16538)
-- Name: checksum_aggregated_view checksum_aggregated_view_pkey; Type: CONSTRAINT; Schema: bidb; Owner: -
--

ALTER TABLE ONLY bidb.checksum_aggregated_view
    ADD CONSTRAINT checksum_aggregated_view_pkey PRIMARY KEY (_id);


--
-- TOC entry 3363 (class 2606 OID 16651)
-- Name: currency_exchange_rates currency_exchange_rates_pkey; Type: CONSTRAINT; Schema: bidb; Owner: -
--

ALTER TABLE ONLY bidb.currency_exchange_rates
    ADD CONSTRAINT currency_exchange_rates_pkey PRIMARY KEY (currency_symbol);


--
-- TOC entry 3354 (class 2606 OID 41338)
-- Name: custom_properties_view custom_properties_view_pkey; Type: CONSTRAINT; Schema: bidb; Owner: -
--

ALTER TABLE ONLY bidb.custom_properties_view
    ADD CONSTRAINT custom_properties_view_pkey PRIMARY KEY ("EntityId", "PropertyId");


--
-- TOC entry 3361 (class 2606 OID 16644)
-- Name: datasource_category_mapping datasource_category_mapping_pkey; Type: CONSTRAINT; Schema: bidb; Owner: -
--

ALTER TABLE ONLY bidb.datasource_category_mapping
    ADD CONSTRAINT datasource_category_mapping_pkey PRIMARY KEY ("DataSourceType");


--
-- TOC entry 3332 (class 2606 OID 16499)
-- Name: duplicate_files_view duplicate_files_view_pkey; Type: CONSTRAINT; Schema: bidb; Owner: -
--

ALTER TABLE ONLY bidb.duplicate_files_view
    ADD CONSTRAINT duplicate_files_view_pkey PRIMARY KEY (_id);


--
-- TOC entry 3365 (class 2606 OID 16658)
-- Name: entities_custom_categorization entities_custom_categorization_pkey; Type: CONSTRAINT; Schema: bidb; Owner: -
--

ALTER TABLE ONLY bidb.entities_custom_categorization
    ADD CONSTRAINT entities_custom_categorization_pkey PRIMARY KEY (_id);


--
-- TOC entry 3338 (class 2606 OID 16545)
-- Name: entities_extension_count_view entities_extension_count_view_pkey; Type: CONSTRAINT; Schema: bidb; Owner: -
--

ALTER TABLE ONLY bidb.entities_extension_count_view
    ADD CONSTRAINT entities_extension_count_view_pkey PRIMARY KEY (_id);


--
-- TOC entry 3330 (class 2606 OID 16483)
-- Name: entities_master_view entities_master_view_pkey; Type: CONSTRAINT; Schema: bidb; Owner: -
--

ALTER TABLE ONLY bidb.entities_master_view
    ADD CONSTRAINT entities_master_view_pkey PRIMARY KEY (_id);


--
-- TOC entry 3340 (class 2606 OID 16552)
-- Name: entities_temperature_count_view entities_temperature_count_view_pkey; Type: CONSTRAINT; Schema: bidb; Owner: -
--

ALTER TABLE ONLY bidb.entities_temperature_count_view
    ADD CONSTRAINT entities_temperature_count_view_pkey PRIMARY KEY (_id);


--
-- TOC entry 3342 (class 2606 OID 16564)
-- Name: glossary_summary_view glossary_summary_view_pkey; Type: CONSTRAINT; Schema: bidb; Owner: -
--

ALTER TABLE ONLY bidb.glossary_summary_view
    ADD CONSTRAINT glossary_summary_view_pkey PRIMARY KEY (_id);


--
-- TOC entry 3356 (class 2606 OID 16619)
-- Name: pipeline_control pipeline_control_pkey; Type: CONSTRAINT; Schema: bidb; Owner: -
--

ALTER TABLE ONLY bidb.pipeline_control
    ADD CONSTRAINT pipeline_control_pkey PRIMARY KEY (view_name);


--
-- TOC entry 3359 (class 2606 OID 16626)
-- Name: pipeline_log pipeline_log_pkey; Type: CONSTRAINT; Schema: bidb; Owner: -
--

ALTER TABLE ONLY bidb.pipeline_log
    ADD CONSTRAINT pipeline_log_pkey PRIMARY KEY (job_id);


--
-- TOC entry 3346 (class 2606 OID 16578)
-- Name: policies_summary_view policies_summary_view_pkey; Type: CONSTRAINT; Schema: bidb; Owner: -
--

ALTER TABLE ONLY bidb.policies_summary_view
    ADD CONSTRAINT policies_summary_view_pkey PRIMARY KEY (_id);


--
-- TOC entry 3348 (class 2606 OID 16587)
-- Name: terms_policies_view terms_policies_view_pkey; Type: CONSTRAINT; Schema: bidb; Owner: -
--

ALTER TABLE ONLY bidb.terms_policies_view
    ADD CONSTRAINT terms_policies_view_pkey PRIMARY KEY (_id);


--
-- TOC entry 3334 (class 2606 OID 16511)
-- Name: terms_view terms_view_pkey; Type: CONSTRAINT; Schema: bidb; Owner: -
--

ALTER TABLE ONLY bidb.terms_view
    ADD CONSTRAINT terms_view_pkey PRIMARY KEY ("EntityId", "TermId");


--
-- TOC entry 3357 (class 1259 OID 16627)
-- Name: idx_pipeline_log_viewname_startdate; Type: INDEX; Schema: bidb; Owner: -
--

CREATE INDEX idx_pipeline_log_viewname_startdate ON bidb.pipeline_log USING btree (view_name, started_at);


--
-- TOC entry 3521 (class 0 OID 0)
-- Dependencies: 5
-- Name: SCHEMA bidb; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA bidb TO bidb_ro;


--
-- TOC entry 3522 (class 0 OID 0)
-- Dependencies: 214
-- Name: TABLE "SequelizeMeta"; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb."SequelizeMeta" TO bidb_ro;


--
-- TOC entry 3523 (class 0 OID 0)
-- Dependencies: 231
-- Name: TABLE applications_policies_view; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb.applications_policies_view TO bidb_ro;


--
-- TOC entry 3525 (class 0 OID 0)
-- Dependencies: 226
-- Name: TABLE applications_summary_view; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb.applications_summary_view TO bidb_ro;


--
-- TOC entry 3526 (class 0 OID 0)
-- Dependencies: 233
-- Name: TABLE applications_terms_view; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb.applications_terms_view TO bidb_ro;


--
-- TOC entry 3528 (class 0 OID 0)
-- Dependencies: 221
-- Name: TABLE checksum_aggregated_view; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb.checksum_aggregated_view TO bidb_ro;


--
-- TOC entry 3529 (class 0 OID 0)
-- Dependencies: 240
-- Name: TABLE currency_exchange_rates; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb.currency_exchange_rates TO bidb_ro;


--
-- TOC entry 3530 (class 0 OID 0)
-- Dependencies: 234
-- Name: TABLE custom_properties_view; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb.custom_properties_view TO bidb_ro;


--
-- TOC entry 3531 (class 0 OID 0)
-- Dependencies: 239
-- Name: TABLE datasource_category_mapping; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb.datasource_category_mapping TO bidb_ro;


--
-- TOC entry 3532 (class 0 OID 0)
-- Dependencies: 237
-- Name: TABLE delete_memo; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb.delete_memo TO bidb_ro;


--
-- TOC entry 3533 (class 0 OID 0)
-- Dependencies: 217
-- Name: TABLE duplicate_files_view; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb.duplicate_files_view TO bidb_ro;


--
-- TOC entry 3535 (class 0 OID 0)
-- Dependencies: 224
-- Name: TABLE entities_aggregated_view; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb.entities_aggregated_view TO bidb_ro;


--
-- TOC entry 3536 (class 0 OID 0)
-- Dependencies: 219
-- Name: TABLE entities_applications_view; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb.entities_applications_view TO bidb_ro;


--
-- TOC entry 3537 (class 0 OID 0)
-- Dependencies: 241
-- Name: TABLE entities_custom_categorization; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb.entities_custom_categorization TO bidb_ro;


--
-- TOC entry 3538 (class 0 OID 0)
-- Dependencies: 222
-- Name: TABLE entities_extension_count_view; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb.entities_extension_count_view TO bidb_ro;


--
-- TOC entry 3539 (class 0 OID 0)
-- Dependencies: 215
-- Name: TABLE entities_master_view; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb.entities_master_view TO bidb_ro;


--
-- TOC entry 3540 (class 0 OID 0)
-- Dependencies: 220
-- Name: TABLE entities_policies_view; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb.entities_policies_view TO bidb_ro;


--
-- TOC entry 3541 (class 0 OID 0)
-- Dependencies: 238
-- Name: TABLE entities_summary_view; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb.entities_summary_view TO bidb_ro;


--
-- TOC entry 3542 (class 0 OID 0)
-- Dependencies: 223
-- Name: TABLE entities_temperature_count_view; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb.entities_temperature_count_view TO bidb_ro;


--
-- TOC entry 3543 (class 0 OID 0)
-- Dependencies: 225
-- Name: TABLE glossary_summary_view; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb.glossary_summary_view TO bidb_ro;


--
-- TOC entry 3544 (class 0 OID 0)
-- Dependencies: 218
-- Name: TABLE terms_view; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb.terms_view TO bidb_ro;


--
-- TOC entry 3545 (class 0 OID 0)
-- Dependencies: 245
-- Name: TABLE mv_duplicate_by_term_summary_view; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb.mv_duplicate_by_term_summary_view TO bidb_ro;


--
-- TOC entry 3546 (class 0 OID 0)
-- Dependencies: 246
-- Name: TABLE mv_duplicate_entities_summary_view; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb.mv_duplicate_entities_summary_view TO bidb_ro;


--
-- TOC entry 3547 (class 0 OID 0)
-- Dependencies: 247
-- Name: TABLE mv_duplicate_entity_detail_view; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb.mv_duplicate_entity_detail_view TO bidb_ro;


--
-- TOC entry 3548 (class 0 OID 0)
-- Dependencies: 244
-- Name: TABLE mv_duplicate_savings_by_original_view; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb.mv_duplicate_savings_by_original_view TO bidb_ro;


--
-- TOC entry 3549 (class 0 OID 0)
-- Dependencies: 243
-- Name: TABLE mv_entity_category_summary_view; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb.mv_entity_category_summary_view TO bidb_ro;


--
-- TOC entry 3550 (class 0 OID 0)
-- Dependencies: 242
-- Name: TABLE mv_master; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb.mv_master TO bidb_ro;


--
-- TOC entry 3551 (class 0 OID 0)
-- Dependencies: 227
-- Name: TABLE policies_summary_view; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb.policies_summary_view TO bidb_ro;


--
-- TOC entry 3552 (class 0 OID 0)
-- Dependencies: 248
-- Name: TABLE mv_policies_summary; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb.mv_policies_summary TO bidb_ro;


--
-- TOC entry 3553 (class 0 OID 0)
-- Dependencies: 235
-- Name: TABLE pipeline_control; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb.pipeline_control TO bidb_ro;


--
-- TOC entry 3554 (class 0 OID 0)
-- Dependencies: 236
-- Name: TABLE pipeline_log; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb.pipeline_log TO bidb_ro;


--
-- TOC entry 3555 (class 0 OID 0)
-- Dependencies: 229
-- Name: TABLE terms_policies_view; Type: ACL; Schema: bidb; Owner: -
--

GRANT SELECT ON TABLE bidb.terms_policies_view TO bidb_ro;


--
-- TOC entry 2158 (class 826 OID 49441)
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: bidb; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA bidb GRANT SELECT ON TABLES TO bidb_ro;


-- Completed on 2026-01-23 11:21:29 CST

--
-- PostgreSQL database dump complete
--

