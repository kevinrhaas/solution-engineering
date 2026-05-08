--
-- PostgreSQL database dump
--

\restrict 6wWWd6wSfhFqDgxWzUXXrjSlY29pKZDAQrQjWvKb9Q9jeJfwMkZZiQ1HfNwsRF1

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.7 (Homebrew)

-- Started on 2026-01-30 11:05:34 CST

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 16 (class 2615 OID 16423)
-- Name: bidb_ext_demo; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA bidb_ext_demo;


--
-- TOC entry 2 (class 3079 OID 16442)
-- Name: postgres_fdw; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgres_fdw WITH SCHEMA bidb_ext_demo;


--
-- TOC entry 5298 (class 0 OID 0)
-- Dependencies: 2
-- Name: EXTENSION postgres_fdw; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgres_fdw IS 'foreign-data wrapper for remote PostgreSQL servers';


--
-- TOC entry 489 (class 1259 OID 176433)
-- Name: SequelizeMeta; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo."SequelizeMeta" (
    name character varying(255) NOT NULL
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'SequelizeMeta'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo."SequelizeMeta" ALTER COLUMN name OPTIONS (
    column_name 'name'
);


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 482 (class 1259 OID 175811)
-- Name: agg_nm_tp_pr_rt_dsn_dst_tn_mam_may; Type: TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE TABLE bidb_ext_demo.agg_nm_tp_pr_rt_dsn_dst_tn_mam_may (
    "Name" text,
    "Type" text,
    parent text,
    resourcetype text,
    datasourcename text,
    datasourcetype text,
    termname text,
    modified_age_months double precision,
    modified_age_years double precision,
    filecount double precision,
    size bigint,
    fact_count bigint,
    childdirs double precision,
    childdirsize double precision,
    childfiles double precision,
    childfilesize double precision,
    totalchilddirs double precision,
    totalchilddirsize double precision,
    totalchildfiles double precision,
    totalchildfilesize double precision
);


--
-- TOC entry 483 (class 1259 OID 175817)
-- Name: agg_nm_tp_rt_dsn_dst_pt_fe_ft_tn_mam_may; Type: TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE TABLE bidb_ext_demo.agg_nm_tp_rt_dsn_dst_pt_fe_ft_tn_mam_may (
    "Name" text,
    "Type" text,
    resourcetype text,
    datasourcename text,
    datasourcetype text,
    pathtype text,
    fileextension text,
    filetype text,
    termname text,
    modified_age_months double precision,
    modified_age_years double precision,
    filecount double precision,
    size bigint,
    fact_count bigint,
    childdirs double precision,
    childdirsize double precision,
    childfiles double precision,
    childfilesize double precision,
    totalchilddirs double precision,
    totalchilddirsize double precision,
    totalchildfiles double precision,
    totalchildfilesize double precision
);


--
-- TOC entry 484 (class 1259 OID 175823)
-- Name: agg_tp_rt_dsn_dst_pp_pt_fe_ft_tn_mam_may; Type: TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE TABLE bidb_ext_demo.agg_tp_rt_dsn_dst_pp_pt_fe_ft_tn_mam_may (
    "Type" text,
    parentpath text,
    resourcetype text,
    datasourcename text,
    datasourcetype text,
    pathtype text,
    fileextension text,
    filetype text,
    termname text,
    modified_age_months double precision,
    modified_age_years double precision,
    filecount double precision,
    size bigint,
    fact_count bigint,
    childdirs double precision,
    childdirsize double precision,
    childfiles double precision,
    childfilesize double precision,
    totalchilddirs double precision,
    totalchilddirsize double precision,
    totalchildfiles double precision,
    totalchildfilesize double precision
);


--
-- TOC entry 485 (class 1259 OID 175829)
-- Name: agg_tp_rt_dsn_dst_pt_fe_ft_tn_mam_may; Type: TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE TABLE bidb_ext_demo.agg_tp_rt_dsn_dst_pt_fe_ft_tn_mam_may (
    "Type" text,
    resourcetype text,
    datasourcename text,
    datasourcetype text,
    pathtype text,
    fileextension text,
    filetype text,
    termname text,
    modified_age_months double precision,
    modified_age_years double precision,
    filecount double precision,
    size bigint,
    fact_count bigint,
    childdirs double precision,
    childdirsize double precision,
    childfiles double precision,
    childfilesize double precision,
    totalchilddirs double precision,
    totalchilddirsize double precision,
    totalchildfiles double precision,
    totalchildfilesize double precision
);


--
-- TOC entry 490 (class 1259 OID 176436)
-- Name: applications_policies_view; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo.applications_policies_view (
    _id bigint NOT NULL,
    "ApplicationId" text,
    "PolicyId" text
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'applications_policies_view'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.applications_policies_view ALTER COLUMN _id OPTIONS (
    column_name '_id'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.applications_policies_view ALTER COLUMN "ApplicationId" OPTIONS (
    column_name 'ApplicationId'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.applications_policies_view ALTER COLUMN "PolicyId" OPTIONS (
    column_name 'PolicyId'
);


--
-- TOC entry 491 (class 1259 OID 176439)
-- Name: applications_summary_view; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo.applications_summary_view (
    _id text NOT NULL,
    "Name" text,
    "Type" text,
    "Parent" text,
    "Fqdn" text,
    "UsersWithAccess" jsonb
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'applications_summary_view'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.applications_summary_view ALTER COLUMN _id OPTIONS (
    column_name '_id'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.applications_summary_view ALTER COLUMN "Name" OPTIONS (
    column_name 'Name'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.applications_summary_view ALTER COLUMN "Type" OPTIONS (
    column_name 'Type'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.applications_summary_view ALTER COLUMN "Parent" OPTIONS (
    column_name 'Parent'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.applications_summary_view ALTER COLUMN "Fqdn" OPTIONS (
    column_name 'Fqdn'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.applications_summary_view ALTER COLUMN "UsersWithAccess" OPTIONS (
    column_name 'UsersWithAccess'
);


--
-- TOC entry 492 (class 1259 OID 176442)
-- Name: applications_terms_view; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo.applications_terms_view (
    _id bigint NOT NULL,
    "ApplicationId" text,
    "TermId" text
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'applications_terms_view'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.applications_terms_view ALTER COLUMN _id OPTIONS (
    column_name '_id'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.applications_terms_view ALTER COLUMN "ApplicationId" OPTIONS (
    column_name 'ApplicationId'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.applications_terms_view ALTER COLUMN "TermId" OPTIONS (
    column_name 'TermId'
);


--
-- TOC entry 493 (class 1259 OID 176445)
-- Name: checksum_aggregated_view; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo.checksum_aggregated_view (
    _id text NOT NULL,
    "duplicateFilesCount" integer,
    "duplicateFilesSize" bigint
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'checksum_aggregated_view'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.checksum_aggregated_view ALTER COLUMN _id OPTIONS (
    column_name '_id'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.checksum_aggregated_view ALTER COLUMN "duplicateFilesCount" OPTIONS (
    column_name 'duplicateFilesCount'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.checksum_aggregated_view ALTER COLUMN "duplicateFilesSize" OPTIONS (
    column_name 'duplicateFilesSize'
);


--
-- TOC entry 494 (class 1259 OID 176448)
-- Name: currency_exchange_rates; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo.currency_exchange_rates (
    currency_symbol text NOT NULL,
    "ConversionRateToUSD" double precision
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'currency_exchange_rates'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.currency_exchange_rates ALTER COLUMN currency_symbol OPTIONS (
    column_name 'currency_symbol'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.currency_exchange_rates ALTER COLUMN "ConversionRateToUSD" OPTIONS (
    column_name 'ConversionRateToUSD'
);


--
-- TOC entry 495 (class 1259 OID 176451)
-- Name: custom_properties_view; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo.custom_properties_view (
    "EntityId" character varying(255) NOT NULL,
    "PropertyId" character varying(255) NOT NULL,
    "Value" text,
    "PropertyName" character varying(255),
    "FqdnDisplay" text
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'custom_properties_view'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.custom_properties_view ALTER COLUMN "EntityId" OPTIONS (
    column_name 'EntityId'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.custom_properties_view ALTER COLUMN "PropertyId" OPTIONS (
    column_name 'PropertyId'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.custom_properties_view ALTER COLUMN "Value" OPTIONS (
    column_name 'Value'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.custom_properties_view ALTER COLUMN "PropertyName" OPTIONS (
    column_name 'PropertyName'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.custom_properties_view ALTER COLUMN "FqdnDisplay" OPTIONS (
    column_name 'FqdnDisplay'
);


--
-- TOC entry 496 (class 1259 OID 176454)
-- Name: datasource_category_mapping; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo.datasource_category_mapping (
    "DataSourceType" text NOT NULL,
    category text
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'datasource_category_mapping'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.datasource_category_mapping ALTER COLUMN "DataSourceType" OPTIONS (
    column_name 'DataSourceType'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.datasource_category_mapping ALTER COLUMN category OPTIONS (
    column_name 'category'
);


--
-- TOC entry 497 (class 1259 OID 176457)
-- Name: delete_memo; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo.delete_memo (
    view_name text NOT NULL,
    id text NOT NULL,
    related_id text,
    job_id text NOT NULL
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'delete_memo'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.delete_memo ALTER COLUMN view_name OPTIONS (
    column_name 'view_name'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.delete_memo ALTER COLUMN id OPTIONS (
    column_name 'id'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.delete_memo ALTER COLUMN related_id OPTIONS (
    column_name 'related_id'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.delete_memo ALTER COLUMN job_id OPTIONS (
    column_name 'job_id'
);


--
-- TOC entry 503 (class 1259 OID 176475)
-- Name: entities_master_view; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo.entities_master_view (
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
    "LastUpdate" timestamp without time zone,
    "ProductName" text,
    "ProductVersion" text,
    "DriverName" text,
    "Url" text,
    "ParentName" text,
    "TotalTables" integer,
    "TotalColumns" integer,
    "SchemaName" text,
    "DatabaseName" text,
    "LastUpdateStatistics" timestamp without time zone,
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
    "CreatedAt" timestamp without time zone,
    "ModifiedAt" timestamp without time zone,
    "AccessedAt" timestamp without time zone,
    "ScannedAt" timestamp without time zone,
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
    "Sensitivity" text
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'entities_master_view'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN _id OPTIONS (
    column_name '_id'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "Name" OPTIONS (
    column_name 'Name'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "Type" OPTIONS (
    column_name 'Type'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "Parent" OPTIONS (
    column_name 'Parent'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "ResourceType" OPTIONS (
    column_name 'ResourceType'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "DataSourceId" OPTIONS (
    column_name 'DataSourceId'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "DataSourceName" OPTIONS (
    column_name 'DataSourceName'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "DataSourceType" OPTIONS (
    column_name 'DataSourceType'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "DataSourceCostPerTbCurrency" OPTIONS (
    column_name 'DataSourceCostPerTbCurrency'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "DataSourceCostPerTbPrice" OPTIONS (
    column_name 'DataSourceCostPerTbPrice'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "DataSourceAffinityId" OPTIONS (
    column_name 'DataSourceAffinityId'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "DataProfileStatus" OPTIONS (
    column_name 'DataProfileStatus'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "DataProfiled" OPTIONS (
    column_name 'DataProfiled'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "LastUpdate" OPTIONS (
    column_name 'LastUpdate'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "ProductName" OPTIONS (
    column_name 'ProductName'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "ProductVersion" OPTIONS (
    column_name 'ProductVersion'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "DriverName" OPTIONS (
    column_name 'DriverName'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "Url" OPTIONS (
    column_name 'Url'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "ParentName" OPTIONS (
    column_name 'ParentName'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "TotalTables" OPTIONS (
    column_name 'TotalTables'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "TotalColumns" OPTIONS (
    column_name 'TotalColumns'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "SchemaName" OPTIONS (
    column_name 'SchemaName'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "DatabaseName" OPTIONS (
    column_name 'DatabaseName'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "LastUpdateStatistics" OPTIONS (
    column_name 'LastUpdateStatistics'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "RowCount" OPTIONS (
    column_name 'RowCount'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "NullCount" OPTIONS (
    column_name 'NullCount'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "Cardinality" OPTIONS (
    column_name 'Cardinality'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "Hll" OPTIONS (
    column_name 'Hll'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "BlankCount" OPTIONS (
    column_name 'BlankCount'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "Min" OPTIONS (
    column_name 'Min'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "Max" OPTIONS (
    column_name 'Max'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "AvgValue" OPTIONS (
    column_name 'AvgValue'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "MinWidth" OPTIONS (
    column_name 'MinWidth'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "MaxWidth" OPTIONS (
    column_name 'MaxWidth'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "AvgWidth" OPTIONS (
    column_name 'AvgWidth'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "ColumnsCount" OPTIONS (
    column_name 'ColumnsCount'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "CheckClause" OPTIONS (
    column_name 'CheckClause'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "TableName" OPTIONS (
    column_name 'TableName'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "DataType" OPTIONS (
    column_name 'DataType'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "TypeName" OPTIONS (
    column_name 'TypeName'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "ColumnSize" OPTIONS (
    column_name 'ColumnSize'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "BufferLength" OPTIONS (
    column_name 'BufferLength'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "DecimalDigits" OPTIONS (
    column_name 'DecimalDigits'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "NumPrecRadix" OPTIONS (
    column_name 'NumPrecRadix'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "IsNullable" OPTIONS (
    column_name 'IsNullable'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "OrdinalPosition" OPTIONS (
    column_name 'OrdinalPosition'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "IsPrimaryKey" OPTIONS (
    column_name 'IsPrimaryKey'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "IsForeignKey" OPTIONS (
    column_name 'IsForeignKey'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "Path" OPTIONS (
    column_name 'Path'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "ParentPath" OPTIONS (
    column_name 'ParentPath'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "PathType" OPTIONS (
    column_name 'PathType'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "FileExtension" OPTIONS (
    column_name 'FileExtension'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "Size" OPTIONS (
    column_name 'Size'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "Flags" OPTIONS (
    column_name 'Flags'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "Owner" OPTIONS (
    column_name 'Owner'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "Group" OPTIONS (
    column_name 'Group'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "SymLinkTarget" OPTIONS (
    column_name 'SymLinkTarget'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "FileType" OPTIONS (
    column_name 'FileType'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "CreatedAt" OPTIONS (
    column_name 'CreatedAt'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "ModifiedAt" OPTIONS (
    column_name 'ModifiedAt'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "AccessedAt" OPTIONS (
    column_name 'AccessedAt'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "ScannedAt" OPTIONS (
    column_name 'ScannedAt'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "IsSymlink" OPTIONS (
    column_name 'IsSymlink'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "LinkType" OPTIONS (
    column_name 'LinkType'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "PhysicalLocation" OPTIONS (
    column_name 'PhysicalLocation'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "Title" OPTIONS (
    column_name 'Title'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "Author" OPTIONS (
    column_name 'Author'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "Subject" OPTIONS (
    column_name 'Subject'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "Application" OPTIONS (
    column_name 'Application'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "Producer" OPTIONS (
    column_name 'Producer'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "Version" OPTIONS (
    column_name 'Version'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "DocumentSize" OPTIONS (
    column_name 'DocumentSize'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "PageSize" OPTIONS (
    column_name 'PageSize'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "PageCount" OPTIONS (
    column_name 'PageCount'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "Company" OPTIONS (
    column_name 'Company'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "Paragraphs" OPTIONS (
    column_name 'Paragraphs'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "Lines" OPTIONS (
    column_name 'Lines'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "Words" OPTIONS (
    column_name 'Words'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "Characters" OPTIONS (
    column_name 'Characters'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "CharactersWithSpaces" OPTIONS (
    column_name 'CharactersWithSpaces'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "Language" OPTIONS (
    column_name 'Language'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "Checksum" OPTIONS (
    column_name 'Checksum'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "PropertiesChecksum" OPTIONS (
    column_name 'PropertiesChecksum'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "ChildDirs" OPTIONS (
    column_name 'ChildDirs'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "ChildFiles" OPTIONS (
    column_name 'ChildFiles'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "ChildDirSize" OPTIONS (
    column_name 'ChildDirSize'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "ChildFileSize" OPTIONS (
    column_name 'ChildFileSize'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "TotalChildDirs" OPTIONS (
    column_name 'TotalChildDirs'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "TotalChildFiles" OPTIONS (
    column_name 'TotalChildFiles'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "TotalChildDirSize" OPTIONS (
    column_name 'TotalChildDirSize'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "TotalChildFileSize" OPTIONS (
    column_name 'TotalChildFileSize'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "LocationName" OPTIONS (
    column_name 'LocationName'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "LocationStreetAddress" OPTIONS (
    column_name 'LocationStreetAddress'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "LocationStreetAddress2" OPTIONS (
    column_name 'LocationStreetAddress2'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "LocationLocalityCity" OPTIONS (
    column_name 'LocationLocalityCity'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "LocationStateProvince" OPTIONS (
    column_name 'LocationStateProvince'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "LocationPostalCode" OPTIONS (
    column_name 'LocationPostalCode'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "LocationCountry" OPTIONS (
    column_name 'LocationCountry'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "CostPerTbFrequency" OPTIONS (
    column_name 'CostPerTbFrequency'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "TotalCapacity" OPTIONS (
    column_name 'TotalCapacity'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "FqdnDisplay" OPTIONS (
    column_name 'FqdnDisplay'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "OwnerFirstName" OPTIONS (
    column_name 'OwnerFirstName'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "OwnerLastName" OPTIONS (
    column_name 'OwnerLastName'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "OwnerEmail" OPTIONS (
    column_name 'OwnerEmail'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "OwnerUserName" OPTIONS (
    column_name 'OwnerUserName'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "OwnerIsDeleted" OPTIONS (
    column_name 'OwnerIsDeleted'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "UserAccessDetails" OPTIONS (
    column_name 'UserAccessDetails'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_master_view ALTER COLUMN "Sensitivity" OPTIONS (
    column_name 'Sensitivity'
);


--
-- TOC entry 519 (class 1259 OID 176523)
-- Name: terms_view; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo.terms_view (
    "EntityId" text NOT NULL,
    "TermName" text,
    "GlossaryId" text,
    "TermId" text NOT NULL,
    "FqdnDisplay" text
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'terms_view'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.terms_view ALTER COLUMN "EntityId" OPTIONS (
    column_name 'EntityId'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.terms_view ALTER COLUMN "TermName" OPTIONS (
    column_name 'TermName'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.terms_view ALTER COLUMN "GlossaryId" OPTIONS (
    column_name 'GlossaryId'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.terms_view ALTER COLUMN "TermId" OPTIONS (
    column_name 'TermId'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.terms_view ALTER COLUMN "FqdnDisplay" OPTIONS (
    column_name 'FqdnDisplay'
);


--
-- TOC entry 520 (class 1259 OID 176563)
-- Name: mv_stg_entity_term; Type: MATERIALIZED VIEW; Schema: bidb_ext_demo; Owner: -
--

CREATE MATERIALIZED VIEW bidb_ext_demo.mv_stg_entity_term AS
 SELECT emv._id AS entity_nk,
    emv."FqdnDisplay" AS entity_fqdn,
    tv."TermName" AS term_name,
    emv."DataSourceId" AS datasource_nk,
    emv."DataSourceName" AS datasource_name,
    emv."DataSourceType" AS datasource_type,
    emv."Name" AS entity_name,
    emv."Type" AS entity_type,
    emv."ResourceType" AS resource_type,
    emv."Path" AS path,
    emv."ParentPath" AS parent_path,
    emv."Owner" AS owner_name,
    emv."Group" AS group_name,
        CASE
            WHEN (emv."FileType" ~~* 'parquet%'::text) THEN 'parquet'::text
            ELSE emv."FileType"
        END AS filetype,
    to_timestamp((emv."CreatedAt")::text, 'YYYY-MM-DD HH24:MI:SS'::text) AS created_ts,
    to_timestamp((emv."ModifiedAt")::text, 'YYYY-MM-DD HH24:MI:SS'::text) AS modified_ts,
    to_timestamp((emv."AccessedAt")::text, 'YYYY-MM-DD HH24:MI:SS'::text) AS accessed_ts,
    to_timestamp((emv."ScannedAt")::text, 'YYYY-MM-DD HH24:MI:SS'::text) AS scanned_ts,
    COALESCE(emv."Size", (0)::bigint) AS bytes
   FROM (bidb_ext_demo.entities_master_view emv
     LEFT JOIN bidb_ext_demo.terms_view tv ON ((emv."FqdnDisplay" = tv."FqdnDisplay")))
  WITH NO DATA;


--
-- TOC entry 523 (class 1259 OID 176611)
-- Name: dim_datasource; Type: MATERIALIZED VIEW; Schema: bidb_ext_demo; Owner: -
--

CREATE MATERIALIZED VIEW bidb_ext_demo.dim_datasource AS
 SELECT md5(datasource_nk) AS datasource_key,
    datasource_nk,
    datasource_name,
    datasource_type
   FROM bidb_ext_demo.mv_stg_entity_term
  WHERE (datasource_nk IS NOT NULL)
  GROUP BY (md5(datasource_nk)), datasource_nk, datasource_name, datasource_type
  WITH NO DATA;


--
-- TOC entry 525 (class 1259 OID 176633)
-- Name: dim_date; Type: MATERIALIZED VIEW; Schema: bidb_ext_demo; Owner: -
--

CREATE MATERIALIZED VIEW bidb_ext_demo.dim_date AS
 WITH dates AS (
         SELECT DISTINCT (mv_stg_entity_term.created_ts)::date AS d
           FROM bidb_ext_demo.mv_stg_entity_term
          WHERE (mv_stg_entity_term.created_ts IS NOT NULL)
        UNION
         SELECT DISTINCT (mv_stg_entity_term.modified_ts)::date AS d
           FROM bidb_ext_demo.mv_stg_entity_term
          WHERE (mv_stg_entity_term.modified_ts IS NOT NULL)
        UNION
         SELECT DISTINCT (mv_stg_entity_term.accessed_ts)::date AS d
           FROM bidb_ext_demo.mv_stg_entity_term
          WHERE (mv_stg_entity_term.accessed_ts IS NOT NULL)
        UNION
         SELECT DISTINCT (mv_stg_entity_term.scanned_ts)::date AS d
           FROM bidb_ext_demo.mv_stg_entity_term
          WHERE (mv_stg_entity_term.scanned_ts IS NOT NULL)
        )
 SELECT (to_char((d)::timestamp with time zone, 'YYYYMMDD'::text))::integer AS date_key,
    d AS full_date,
    (EXTRACT(year FROM d))::integer AS year,
    (EXTRACT(month FROM d))::integer AS month,
    (EXTRACT(day FROM d))::integer AS day,
    (EXTRACT(dow FROM d))::integer AS day_of_week
   FROM dates
  WITH NO DATA;


--
-- TOC entry 522 (class 1259 OID 176594)
-- Name: dim_entity; Type: MATERIALIZED VIEW; Schema: bidb_ext_demo; Owner: -
--

CREATE MATERIALIZED VIEW bidb_ext_demo.dim_entity AS
 SELECT md5(entity_nk) AS entity_key,
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
    datasource_nk
   FROM ( SELECT DISTINCT ON (mv_stg_entity_term.entity_nk) mv_stg_entity_term.entity_nk,
            mv_stg_entity_term.entity_fqdn,
            mv_stg_entity_term.entity_name,
            mv_stg_entity_term.entity_type,
            mv_stg_entity_term.resource_type,
            mv_stg_entity_term.path,
            mv_stg_entity_term.parent_path,
            mv_stg_entity_term.owner_name,
            mv_stg_entity_term.group_name,
            mv_stg_entity_term.filetype,
            mv_stg_entity_term.datasource_nk
           FROM bidb_ext_demo.mv_stg_entity_term
          WHERE (mv_stg_entity_term.entity_nk IS NOT NULL)
          ORDER BY mv_stg_entity_term.entity_nk) x
  WITH NO DATA;


--
-- TOC entry 524 (class 1259 OID 176622)
-- Name: dim_filetype; Type: MATERIALIZED VIEW; Schema: bidb_ext_demo; Owner: -
--

CREATE MATERIALIZED VIEW bidb_ext_demo.dim_filetype AS
 SELECT md5(lower(TRIM(BOTH FROM filetype))) AS filetype_key,
    filetype
   FROM bidb_ext_demo.mv_stg_entity_term
  WHERE (filetype IS NOT NULL)
  GROUP BY (md5(lower(TRIM(BOTH FROM filetype)))), filetype
  WITH NO DATA;


--
-- TOC entry 521 (class 1259 OID 176581)
-- Name: dim_term; Type: MATERIALIZED VIEW; Schema: bidb_ext_demo; Owner: -
--

CREATE MATERIALIZED VIEW bidb_ext_demo.dim_term AS
 SELECT md5(lower(TRIM(BOTH FROM term_name))) AS term_key,
    term_name
   FROM bidb_ext_demo.mv_stg_entity_term
  WHERE (term_name IS NOT NULL)
  GROUP BY (md5(lower(TRIM(BOTH FROM term_name)))), term_name
  WITH NO DATA;


--
-- TOC entry 498 (class 1259 OID 176460)
-- Name: duplicate_files_view; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo.duplicate_files_view (
    _id bigint NOT NULL,
    "EntityId" text,
    "GroupId" text,
    "FileCount" integer,
    "Size" bigint,
    "CreatedAt" timestamp without time zone,
    "ModifiedAt" timestamp without time zone
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'duplicate_files_view'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.duplicate_files_view ALTER COLUMN _id OPTIONS (
    column_name '_id'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.duplicate_files_view ALTER COLUMN "EntityId" OPTIONS (
    column_name 'EntityId'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.duplicate_files_view ALTER COLUMN "GroupId" OPTIONS (
    column_name 'GroupId'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.duplicate_files_view ALTER COLUMN "FileCount" OPTIONS (
    column_name 'FileCount'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.duplicate_files_view ALTER COLUMN "Size" OPTIONS (
    column_name 'Size'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.duplicate_files_view ALTER COLUMN "CreatedAt" OPTIONS (
    column_name 'CreatedAt'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.duplicate_files_view ALTER COLUMN "ModifiedAt" OPTIONS (
    column_name 'ModifiedAt'
);


--
-- TOC entry 499 (class 1259 OID 176463)
-- Name: entities_aggregated_view; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo.entities_aggregated_view (
    "Attribute" character varying,
    "Type" character varying,
    "Value" jsonb
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'entities_aggregated_view'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_aggregated_view ALTER COLUMN "Attribute" OPTIONS (
    column_name 'Attribute'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_aggregated_view ALTER COLUMN "Type" OPTIONS (
    column_name 'Type'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_aggregated_view ALTER COLUMN "Value" OPTIONS (
    column_name 'Value'
);


--
-- TOC entry 500 (class 1259 OID 176466)
-- Name: entities_applications_view; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo.entities_applications_view (
    "EntityId" text,
    "ApplicationId" text,
    "FqdnDisplay" text
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'entities_applications_view'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_applications_view ALTER COLUMN "EntityId" OPTIONS (
    column_name 'EntityId'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_applications_view ALTER COLUMN "ApplicationId" OPTIONS (
    column_name 'ApplicationId'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_applications_view ALTER COLUMN "FqdnDisplay" OPTIONS (
    column_name 'FqdnDisplay'
);


--
-- TOC entry 501 (class 1259 OID 176469)
-- Name: entities_custom_categorization; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo.entities_custom_categorization (
    _id character varying(24) NOT NULL,
    "EntityCategory" text,
    "GlossaryName" text,
    "GlossaryType" text
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'entities_custom_categorization'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_custom_categorization ALTER COLUMN _id OPTIONS (
    column_name '_id'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_custom_categorization ALTER COLUMN "EntityCategory" OPTIONS (
    column_name 'EntityCategory'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_custom_categorization ALTER COLUMN "GlossaryName" OPTIONS (
    column_name 'GlossaryName'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_custom_categorization ALTER COLUMN "GlossaryType" OPTIONS (
    column_name 'GlossaryType'
);


--
-- TOC entry 502 (class 1259 OID 176472)
-- Name: entities_extension_count_view; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo.entities_extension_count_view (
    _id text NOT NULL,
    "Date" timestamp without time zone,
    "DataSourceFqdnId" text,
    "Extension" text,
    "FileCount" integer
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'entities_extension_count_view'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_extension_count_view ALTER COLUMN _id OPTIONS (
    column_name '_id'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_extension_count_view ALTER COLUMN "Date" OPTIONS (
    column_name 'Date'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_extension_count_view ALTER COLUMN "DataSourceFqdnId" OPTIONS (
    column_name 'DataSourceFqdnId'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_extension_count_view ALTER COLUMN "Extension" OPTIONS (
    column_name 'Extension'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_extension_count_view ALTER COLUMN "FileCount" OPTIONS (
    column_name 'FileCount'
);


--
-- TOC entry 504 (class 1259 OID 176478)
-- Name: entities_policies_view; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo.entities_policies_view (
    "EntityId" text,
    "PolicyId" text,
    "FqdnDisplay" text
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'entities_policies_view'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_policies_view ALTER COLUMN "EntityId" OPTIONS (
    column_name 'EntityId'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_policies_view ALTER COLUMN "PolicyId" OPTIONS (
    column_name 'PolicyId'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_policies_view ALTER COLUMN "FqdnDisplay" OPTIONS (
    column_name 'FqdnDisplay'
);


--
-- TOC entry 505 (class 1259 OID 176481)
-- Name: entities_summary_view; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo.entities_summary_view (
    _id text,
    "Name" text,
    "Type" text,
    "Parent" text,
    "FqdnDisplay" text
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'entities_summary_view'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_summary_view ALTER COLUMN _id OPTIONS (
    column_name '_id'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_summary_view ALTER COLUMN "Name" OPTIONS (
    column_name 'Name'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_summary_view ALTER COLUMN "Type" OPTIONS (
    column_name 'Type'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_summary_view ALTER COLUMN "Parent" OPTIONS (
    column_name 'Parent'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_summary_view ALTER COLUMN "FqdnDisplay" OPTIONS (
    column_name 'FqdnDisplay'
);


--
-- TOC entry 506 (class 1259 OID 176484)
-- Name: entities_temperature_count_view; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo.entities_temperature_count_view (
    _id text NOT NULL,
    "Date" timestamp without time zone,
    "DataSourceFqdnId" text,
    "Temperature" text,
    "FileCount" integer
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'entities_temperature_count_view'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_temperature_count_view ALTER COLUMN _id OPTIONS (
    column_name '_id'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_temperature_count_view ALTER COLUMN "Date" OPTIONS (
    column_name 'Date'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_temperature_count_view ALTER COLUMN "DataSourceFqdnId" OPTIONS (
    column_name 'DataSourceFqdnId'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_temperature_count_view ALTER COLUMN "Temperature" OPTIONS (
    column_name 'Temperature'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.entities_temperature_count_view ALTER COLUMN "FileCount" OPTIONS (
    column_name 'FileCount'
);


--
-- TOC entry 486 (class 1259 OID 175835)
-- Name: ext_entities_master_view; Type: TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE TABLE bidb_ext_demo.ext_entities_master_view (
    _id text,
    accessedat timestamp without time zone,
    checksum text,
    columnscount integer,
    createdat timestamp without time zone,
    datasourceid text,
    datasourcename text,
    datasourcetype text,
    filetype text,
    flags integer,
    modifiedat timestamp without time zone,
    "Name" text,
    parent text,
    parentpath text,
    "Path" text,
    pathtype text,
    resourcetype text,
    scannedat timestamp without time zone,
    "Size" bigint,
    "Type" text
);


--
-- TOC entry 527 (class 1259 OID 176690)
-- Name: fact_entity_snapshot; Type: MATERIALIZED VIEW; Schema: bidb_ext_demo; Owner: -
--

CREATE MATERIALIZED VIEW bidb_ext_demo.fact_entity_snapshot AS
 SELECT DISTINCT ON (stg.entity_nk, ((stg.scanned_ts)::date)) md5(stg.entity_nk) AS entity_key,
    md5(stg.datasource_nk) AS datasource_key,
    (to_char(((stg.scanned_ts)::date)::timestamp with time zone, 'YYYYMMDD'::text))::integer AS scanned_date_key,
    1 AS entity_count,
    COALESCE(stg.bytes, (0)::bigint) AS bytes,
    COALESCE(emv."ChildDirs", (0)::bigint) AS child_dirs,
    COALESCE(emv."ChildFiles", (0)::bigint) AS child_files,
    COALESCE(emv."ChildDirSize", (0)::bigint) AS child_dir_bytes,
    COALESCE(emv."ChildFileSize", (0)::bigint) AS child_file_bytes,
    COALESCE(emv."TotalChildDirs", (0)::bigint) AS total_child_dirs,
    COALESCE(emv."TotalChildFiles", (0)::bigint) AS total_child_files,
    COALESCE(emv."TotalChildDirSize", (0)::bigint) AS total_child_dir_bytes,
    COALESCE(emv."TotalChildFileSize", (0)::bigint) AS total_child_file_bytes,
    COALESCE((((date_part('year'::text, age(stg.scanned_ts, stg.created_ts)))::integer * 12) + (date_part('month'::text, age(stg.scanned_ts, stg.created_ts)))::integer), 0) AS created_age_months,
    COALESCE((date_part('year'::text, age(stg.scanned_ts, stg.created_ts)))::integer, 0) AS created_age_years,
    COALESCE((((date_part('year'::text, age(stg.scanned_ts, stg.modified_ts)))::integer * 12) + (date_part('month'::text, age(stg.scanned_ts, stg.modified_ts)))::integer), 0) AS modified_age_months,
    COALESCE((date_part('year'::text, age(stg.scanned_ts, stg.modified_ts)))::integer, 0) AS modified_age_years,
    COALESCE((((date_part('year'::text, age(stg.scanned_ts, stg.accessed_ts)))::integer * 12) + (date_part('month'::text, age(stg.scanned_ts, stg.accessed_ts)))::integer), 0) AS accessed_age_months,
    COALESCE((date_part('year'::text, age(stg.scanned_ts, stg.accessed_ts)))::integer, 0) AS accessed_age_years
   FROM (bidb_ext_demo.mv_stg_entity_term stg
     JOIN bidb_ext_demo.entities_master_view emv ON ((emv._id = stg.entity_nk)))
  WHERE ((stg.scanned_ts IS NOT NULL) AND (stg.entity_nk IS NOT NULL) AND (stg.datasource_nk IS NOT NULL))
  ORDER BY stg.entity_nk, ((stg.scanned_ts)::date), stg.scanned_ts DESC
  WITH NO DATA;


--
-- TOC entry 526 (class 1259 OID 176641)
-- Name: fact_entity_term; Type: MATERIALIZED VIEW; Schema: bidb_ext_demo; Owner: -
--

CREATE MATERIALIZED VIEW bidb_ext_demo.fact_entity_term AS
 SELECT md5(entity_nk) AS entity_key,
    md5(lower(TRIM(BOTH FROM term_name))) AS term_key,
    md5(datasource_nk) AS datasource_key,
    (to_char(((created_ts)::date)::timestamp with time zone, 'YYYYMMDD'::text))::integer AS created_date_key,
    (to_char(((modified_ts)::date)::timestamp with time zone, 'YYYYMMDD'::text))::integer AS modified_date_key,
    (to_char(((accessed_ts)::date)::timestamp with time zone, 'YYYYMMDD'::text))::integer AS accessed_date_key,
    (to_char(((scanned_ts)::date)::timestamp with time zone, 'YYYYMMDD'::text))::integer AS scanned_date_key,
    1 AS association_count
   FROM bidb_ext_demo.mv_stg_entity_term stg
  WHERE ((entity_nk IS NOT NULL) AND (term_name IS NOT NULL))
  WITH NO DATA;


--
-- TOC entry 507 (class 1259 OID 176487)
-- Name: glossary_summary_view; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo.glossary_summary_view (
    _id text NOT NULL,
    "Name" text,
    "Type" text,
    "Parent" text,
    "Fqdn" text
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'glossary_summary_view'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.glossary_summary_view ALTER COLUMN _id OPTIONS (
    column_name '_id'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.glossary_summary_view ALTER COLUMN "Name" OPTIONS (
    column_name 'Name'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.glossary_summary_view ALTER COLUMN "Type" OPTIONS (
    column_name 'Type'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.glossary_summary_view ALTER COLUMN "Parent" OPTIONS (
    column_name 'Parent'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.glossary_summary_view ALTER COLUMN "Fqdn" OPTIONS (
    column_name 'Fqdn'
);


--
-- TOC entry 508 (class 1259 OID 176490)
-- Name: mv_duplicate_by_term_summary_view; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo.mv_duplicate_by_term_summary_view (
    term_label text,
    entity_count bigint,
    total_duplicate_tb double precision,
    total_duplicate_cost_usd double precision
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'mv_duplicate_by_term_summary_view'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_duplicate_by_term_summary_view ALTER COLUMN term_label OPTIONS (
    column_name 'term_label'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_duplicate_by_term_summary_view ALTER COLUMN entity_count OPTIONS (
    column_name 'entity_count'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_duplicate_by_term_summary_view ALTER COLUMN total_duplicate_tb OPTIONS (
    column_name 'total_duplicate_tb'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_duplicate_by_term_summary_view ALTER COLUMN total_duplicate_cost_usd OPTIONS (
    column_name 'total_duplicate_cost_usd'
);


--
-- TOC entry 509 (class 1259 OID 176493)
-- Name: mv_duplicate_entities_summary_view; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo.mv_duplicate_entities_summary_view (
    total_duplicate_files bigint,
    total_duplicate_tb double precision,
    total_duplicate_cost_usd double precision
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'mv_duplicate_entities_summary_view'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_duplicate_entities_summary_view ALTER COLUMN total_duplicate_files OPTIONS (
    column_name 'total_duplicate_files'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_duplicate_entities_summary_view ALTER COLUMN total_duplicate_tb OPTIONS (
    column_name 'total_duplicate_tb'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_duplicate_entities_summary_view ALTER COLUMN total_duplicate_cost_usd OPTIONS (
    column_name 'total_duplicate_cost_usd'
);


--
-- TOC entry 510 (class 1259 OID 176496)
-- Name: mv_duplicate_entity_detail_view; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo.mv_duplicate_entity_detail_view (
    "GroupId" text,
    duplicate_path text,
    entity_id text,
    size_tb double precision,
    cost_usd double precision,
    "DataSourceName" text,
    "FileType" text
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'mv_duplicate_entity_detail_view'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_duplicate_entity_detail_view ALTER COLUMN "GroupId" OPTIONS (
    column_name 'GroupId'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_duplicate_entity_detail_view ALTER COLUMN duplicate_path OPTIONS (
    column_name 'duplicate_path'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_duplicate_entity_detail_view ALTER COLUMN entity_id OPTIONS (
    column_name 'entity_id'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_duplicate_entity_detail_view ALTER COLUMN size_tb OPTIONS (
    column_name 'size_tb'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_duplicate_entity_detail_view ALTER COLUMN cost_usd OPTIONS (
    column_name 'cost_usd'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_duplicate_entity_detail_view ALTER COLUMN "DataSourceName" OPTIONS (
    column_name 'DataSourceName'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_duplicate_entity_detail_view ALTER COLUMN "FileType" OPTIONS (
    column_name 'FileType'
);


--
-- TOC entry 511 (class 1259 OID 176499)
-- Name: mv_duplicate_savings_by_original_view; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo.mv_duplicate_savings_by_original_view (
    "GroupId" text,
    original_path text,
    duplicate_file_count integer,
    savings_size_tb double precision,
    savings_cost_usd double precision,
    "DataSourceType" text,
    "Type" text,
    "Category" text
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'mv_duplicate_savings_by_original_view'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_duplicate_savings_by_original_view ALTER COLUMN "GroupId" OPTIONS (
    column_name 'GroupId'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_duplicate_savings_by_original_view ALTER COLUMN original_path OPTIONS (
    column_name 'original_path'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_duplicate_savings_by_original_view ALTER COLUMN duplicate_file_count OPTIONS (
    column_name 'duplicate_file_count'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_duplicate_savings_by_original_view ALTER COLUMN savings_size_tb OPTIONS (
    column_name 'savings_size_tb'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_duplicate_savings_by_original_view ALTER COLUMN savings_cost_usd OPTIONS (
    column_name 'savings_cost_usd'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_duplicate_savings_by_original_view ALTER COLUMN "DataSourceType" OPTIONS (
    column_name 'DataSourceType'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_duplicate_savings_by_original_view ALTER COLUMN "Type" OPTIONS (
    column_name 'Type'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_duplicate_savings_by_original_view ALTER COLUMN "Category" OPTIONS (
    column_name 'Category'
);


--
-- TOC entry 512 (class 1259 OID 176502)
-- Name: mv_entity_category_summary_view; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo.mv_entity_category_summary_view (
    "EntityCategory" text,
    "TermLabel" text,
    "DataSourceName" text,
    "DataSourceType" text,
    "Category" text,
    "Type" text,
    entity_count bigint,
    total_size_tb double precision,
    total_cost_usd double precision
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'mv_entity_category_summary_view'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_entity_category_summary_view ALTER COLUMN "EntityCategory" OPTIONS (
    column_name 'EntityCategory'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_entity_category_summary_view ALTER COLUMN "TermLabel" OPTIONS (
    column_name 'TermLabel'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_entity_category_summary_view ALTER COLUMN "DataSourceName" OPTIONS (
    column_name 'DataSourceName'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_entity_category_summary_view ALTER COLUMN "DataSourceType" OPTIONS (
    column_name 'DataSourceType'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_entity_category_summary_view ALTER COLUMN "Category" OPTIONS (
    column_name 'Category'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_entity_category_summary_view ALTER COLUMN "Type" OPTIONS (
    column_name 'Type'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_entity_category_summary_view ALTER COLUMN entity_count OPTIONS (
    column_name 'entity_count'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_entity_category_summary_view ALTER COLUMN total_size_tb OPTIONS (
    column_name 'total_size_tb'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_entity_category_summary_view ALTER COLUMN total_cost_usd OPTIONS (
    column_name 'total_cost_usd'
);


--
-- TOC entry 513 (class 1259 OID 176505)
-- Name: mv_master; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo.mv_master (
    "Category" text,
    "DataSourceName" text,
    "DataSourceType" text,
    "DataSourceCostPerTbCurrency" text,
    "DataSourceCostPerTbPrice" integer,
    "FileType" text,
    "Type" text,
    "ConversionRateToUSD" double precision,
    "Sensitivity" text,
    "Total IDs" bigint,
    "Total Size (Bytes)" double precision,
    "Total Size (TB)" double precision,
    "Total Cost" double precision
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'mv_master'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_master ALTER COLUMN "Category" OPTIONS (
    column_name 'Category'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_master ALTER COLUMN "DataSourceName" OPTIONS (
    column_name 'DataSourceName'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_master ALTER COLUMN "DataSourceType" OPTIONS (
    column_name 'DataSourceType'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_master ALTER COLUMN "DataSourceCostPerTbCurrency" OPTIONS (
    column_name 'DataSourceCostPerTbCurrency'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_master ALTER COLUMN "DataSourceCostPerTbPrice" OPTIONS (
    column_name 'DataSourceCostPerTbPrice'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_master ALTER COLUMN "FileType" OPTIONS (
    column_name 'FileType'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_master ALTER COLUMN "Type" OPTIONS (
    column_name 'Type'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_master ALTER COLUMN "ConversionRateToUSD" OPTIONS (
    column_name 'ConversionRateToUSD'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_master ALTER COLUMN "Sensitivity" OPTIONS (
    column_name 'Sensitivity'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_master ALTER COLUMN "Total IDs" OPTIONS (
    column_name 'Total IDs'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_master ALTER COLUMN "Total Size (Bytes)" OPTIONS (
    column_name 'Total Size (Bytes)'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_master ALTER COLUMN "Total Size (TB)" OPTIONS (
    column_name 'Total Size (TB)'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_master ALTER COLUMN "Total Cost" OPTIONS (
    column_name 'Total Cost'
);


--
-- TOC entry 487 (class 1259 OID 175841)
-- Name: mv_master_table; Type: TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE TABLE bidb_ext_demo.mv_master_table (
    category text,
    datasourcename text,
    datasourcetype text,
    datasourcecostpertbcurrency text,
    datasourcecostpertbprice integer,
    filetype text,
    "Type" text,
    conversionratetousd double precision,
    sensitivity text,
    totalids bigint,
    totalsizebytes double precision,
    totalsizetb double precision,
    totalcost double precision
);


--
-- TOC entry 514 (class 1259 OID 176508)
-- Name: mv_policies_summary; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo.mv_policies_summary (
    "Level1_Name" text,
    "Level2_Name" text,
    "Level3_Name" text,
    "MasterView_ID_Count" bigint
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'mv_policies_summary'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_policies_summary ALTER COLUMN "Level1_Name" OPTIONS (
    column_name 'Level1_Name'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_policies_summary ALTER COLUMN "Level2_Name" OPTIONS (
    column_name 'Level2_Name'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_policies_summary ALTER COLUMN "Level3_Name" OPTIONS (
    column_name 'Level3_Name'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.mv_policies_summary ALTER COLUMN "MasterView_ID_Count" OPTIONS (
    column_name 'MasterView_ID_Count'
);


--
-- TOC entry 488 (class 1259 OID 175847)
-- Name: pdso_entities; Type: TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE TABLE bidb_ext_demo.pdso_entities (
    _id text NOT NULL,
    "Name" text,
    "Type" text,
    parent text,
    resourcetype text,
    datasourceid text,
    datasourcename text,
    datasourcetype text,
    lastupdate text,
    url text,
    parentname text,
    lastupdatestatistics text,
    "Path" text,
    parentpath text,
    pathtype text,
    fileextension text,
    "Size" integer,
    flags text,
    "Owner" text,
    "Group" text,
    symlinktarget text,
    filetype text,
    createdat timestamp without time zone,
    modifiedat timestamp without time zone,
    accessedat timestamp without time zone,
    scannedat timestamp without time zone,
    issymlink text,
    linktype text,
    physicallocation text,
    childdirs bigint,
    childfiles bigint,
    childdirsize bigint,
    childfilesize bigint,
    totalchilddirs bigint,
    totalchildfiles bigint,
    totalchilddirsize bigint,
    totalchildfilesize bigint,
    fqdndisplay text,
    termname text,
    modified_age_months double precision,
    modified_age_years double precision,
    accessed_age_months double precision,
    accessed_age_years double precision,
    created_age_months double precision,
    created_age_years double precision,
    modifiedat_year double precision,
    modifiedat_month double precision,
    modifiedat_dom double precision,
    createdat_year double precision,
    createdat_month double precision,
    createdat_dom double precision,
    accessedat_year double precision,
    accessedat_month double precision,
    accessedat_dom double precision,
    filecount double precision
);


--
-- TOC entry 515 (class 1259 OID 176511)
-- Name: pipeline_control; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo.pipeline_control (
    view_name text NOT NULL,
    last_successful_started_at timestamp without time zone NOT NULL,
    last_job_id text NOT NULL
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'pipeline_control'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.pipeline_control ALTER COLUMN view_name OPTIONS (
    column_name 'view_name'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.pipeline_control ALTER COLUMN last_successful_started_at OPTIONS (
    column_name 'last_successful_started_at'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.pipeline_control ALTER COLUMN last_job_id OPTIONS (
    column_name 'last_job_id'
);


--
-- TOC entry 516 (class 1259 OID 176514)
-- Name: pipeline_log; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo.pipeline_log (
    job_id text NOT NULL,
    view_name text NOT NULL,
    started_at timestamp without time zone NOT NULL,
    completed_at timestamp without time zone,
    status text
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'pipeline_log'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.pipeline_log ALTER COLUMN job_id OPTIONS (
    column_name 'job_id'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.pipeline_log ALTER COLUMN view_name OPTIONS (
    column_name 'view_name'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.pipeline_log ALTER COLUMN started_at OPTIONS (
    column_name 'started_at'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.pipeline_log ALTER COLUMN completed_at OPTIONS (
    column_name 'completed_at'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.pipeline_log ALTER COLUMN status OPTIONS (
    column_name 'status'
);


--
-- TOC entry 517 (class 1259 OID 176517)
-- Name: policies_summary_view; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo.policies_summary_view (
    _id text NOT NULL,
    "Name" text,
    "Type" text,
    "Parent" text,
    "Fqdn" text
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'policies_summary_view'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.policies_summary_view ALTER COLUMN _id OPTIONS (
    column_name '_id'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.policies_summary_view ALTER COLUMN "Name" OPTIONS (
    column_name 'Name'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.policies_summary_view ALTER COLUMN "Type" OPTIONS (
    column_name 'Type'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.policies_summary_view ALTER COLUMN "Parent" OPTIONS (
    column_name 'Parent'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.policies_summary_view ALTER COLUMN "Fqdn" OPTIONS (
    column_name 'Fqdn'
);


--
-- TOC entry 518 (class 1259 OID 176520)
-- Name: terms_policies_view; Type: FOREIGN TABLE; Schema: bidb_ext_demo; Owner: -
--

CREATE FOREIGN TABLE bidb_ext_demo.terms_policies_view (
    _id bigint NOT NULL,
    "TermId" text,
    "PolicyId" text
)
SERVER remote_bidb
OPTIONS (
    schema_name 'public',
    table_name 'terms_policies_view'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.terms_policies_view ALTER COLUMN _id OPTIONS (
    column_name '_id'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.terms_policies_view ALTER COLUMN "TermId" OPTIONS (
    column_name 'TermId'
);
ALTER FOREIGN TABLE ONLY bidb_ext_demo.terms_policies_view ALTER COLUMN "PolicyId" OPTIONS (
    column_name 'PolicyId'
);


--
-- TOC entry 5111 (class 1259 OID 175855)
-- Name: idx_agg_fileext_dst_pathtype; Type: INDEX; Schema: bidb_ext_demo; Owner: -
--

CREATE INDEX idx_agg_fileext_dst_pathtype ON bidb_ext_demo.agg_tp_rt_dsn_dst_pt_fe_ft_tn_mam_may USING btree (fileextension, datasourcetype, pathtype);


--
-- TOC entry 5112 (class 1259 OID 175856)
-- Name: idx_agg_modified_age_yrs; Type: INDEX; Schema: bidb_ext_demo; Owner: -
--

CREATE INDEX idx_agg_modified_age_yrs ON bidb_ext_demo.agg_tp_rt_dsn_dst_pt_fe_ft_tn_mam_may USING btree (modified_age_years);


--
-- TOC entry 5113 (class 1259 OID 175857)
-- Name: idx_agg_modified_age_yrs_mos; Type: INDEX; Schema: bidb_ext_demo; Owner: -
--

CREATE INDEX idx_agg_modified_age_yrs_mos ON bidb_ext_demo.agg_tp_rt_dsn_dst_pt_fe_ft_tn_mam_may USING btree (modified_age_years, modified_age_months);


--
-- TOC entry 5110 (class 1259 OID 175858)
-- Name: idx_agg_parentpath_pathtype_not_null; Type: INDEX; Schema: bidb_ext_demo; Owner: -
--

CREATE INDEX idx_agg_parentpath_pathtype_not_null ON bidb_ext_demo.agg_tp_rt_dsn_dst_pp_pt_fe_ft_tn_mam_may USING btree (parentpath, pathtype) WHERE (parentpath IS NOT NULL);


--
-- TOC entry 5114 (class 1259 OID 175859)
-- Name: idx_agg_resourcetype; Type: INDEX; Schema: bidb_ext_demo; Owner: -
--

CREATE INDEX idx_agg_resourcetype ON bidb_ext_demo.agg_tp_rt_dsn_dst_pt_fe_ft_tn_mam_may USING btree (resourcetype);


--
-- TOC entry 5115 (class 1259 OID 175860)
-- Name: idx_agg_resourcetype_size; Type: INDEX; Schema: bidb_ext_demo; Owner: -
--

CREATE INDEX idx_agg_resourcetype_size ON bidb_ext_demo.agg_tp_rt_dsn_dst_pt_fe_ft_tn_mam_may USING btree (resourcetype, size);


--
-- TOC entry 5116 (class 1259 OID 175861)
-- Name: idx_agg_rt_dsn_dst; Type: INDEX; Schema: bidb_ext_demo; Owner: -
--

CREATE INDEX idx_agg_rt_dsn_dst ON bidb_ext_demo.agg_tp_rt_dsn_dst_pt_fe_ft_tn_mam_may USING btree (resourcetype, datasourcename, datasourcetype);


--
-- TOC entry 5117 (class 1259 OID 175862)
-- Name: idx_pdso_ent2_datasourcename; Type: INDEX; Schema: bidb_ext_demo; Owner: -
--

CREATE INDEX idx_pdso_ent2_datasourcename ON bidb_ext_demo.pdso_entities USING btree (datasourcename);


--
-- TOC entry 5118 (class 1259 OID 175863)
-- Name: idx_pdso_ent2_datasourcetype; Type: INDEX; Schema: bidb_ext_demo; Owner: -
--

CREATE INDEX idx_pdso_ent2_datasourcetype ON bidb_ext_demo.pdso_entities USING btree (datasourcetype);


--
-- TOC entry 5119 (class 1259 OID 175864)
-- Name: idx_pdso_ent2_datasourcetype_not_null; Type: INDEX; Schema: bidb_ext_demo; Owner: -
--

CREATE INDEX idx_pdso_ent2_datasourcetype_not_null ON bidb_ext_demo.pdso_entities USING btree (datasourcetype) WHERE (datasourcetype IS NOT NULL);


--
-- TOC entry 5120 (class 1259 OID 175865)
-- Name: idx_pdso_ent2_ff_ds_year_term; Type: INDEX; Schema: bidb_ext_demo; Owner: -
--

CREATE INDEX idx_pdso_ent2_ff_ds_year_term ON bidb_ext_demo.pdso_entities USING btree (datasourcename, modifiedat_year, termname) WHERE ("Type" = ANY (ARRAY['FILE'::text, 'FOLDER'::text]));


--
-- TOC entry 5121 (class 1259 OID 175866)
-- Name: idx_pdso_ent2_fileextension; Type: INDEX; Schema: bidb_ext_demo; Owner: -
--

CREATE INDEX idx_pdso_ent2_fileextension ON bidb_ext_demo.pdso_entities USING btree (fileextension);


--
-- TOC entry 5122 (class 1259 OID 175867)
-- Name: idx_pdso_ent2_fileextension_not_null; Type: INDEX; Schema: bidb_ext_demo; Owner: -
--

CREATE INDEX idx_pdso_ent2_fileextension_not_null ON bidb_ext_demo.pdso_entities USING btree (fileextension) WHERE (fileextension IS NOT NULL);


--
-- TOC entry 5123 (class 1259 OID 175868)
-- Name: idx_pdso_ent2_modified_age_months; Type: INDEX; Schema: bidb_ext_demo; Owner: -
--

CREATE INDEX idx_pdso_ent2_modified_age_months ON bidb_ext_demo.pdso_entities USING btree (modified_age_months);


--
-- TOC entry 5124 (class 1259 OID 175869)
-- Name: idx_pdso_ent2_modified_age_years; Type: INDEX; Schema: bidb_ext_demo; Owner: -
--

CREATE INDEX idx_pdso_ent2_modified_age_years ON bidb_ext_demo.pdso_entities USING btree (modified_age_years);


--
-- TOC entry 5125 (class 1259 OID 175870)
-- Name: idx_pdso_ent2_parentpath; Type: INDEX; Schema: bidb_ext_demo; Owner: -
--

CREATE INDEX idx_pdso_ent2_parentpath ON bidb_ext_demo.pdso_entities USING btree (parentpath);


--
-- TOC entry 5126 (class 1259 OID 175871)
-- Name: idx_pdso_ent2_parentpath_not_null; Type: INDEX; Schema: bidb_ext_demo; Owner: -
--

CREATE INDEX idx_pdso_ent2_parentpath_not_null ON bidb_ext_demo.pdso_entities USING btree (parentpath) WHERE (parentpath IS NOT NULL);


--
-- TOC entry 5127 (class 1259 OID 175872)
-- Name: idx_pdso_ent2_path_datasourcename; Type: INDEX; Schema: bidb_ext_demo; Owner: -
--

CREATE INDEX idx_pdso_ent2_path_datasourcename ON bidb_ext_demo.pdso_entities USING btree ("Path", datasourcename);


--
-- TOC entry 5128 (class 1259 OID 175873)
-- Name: idx_pdso_ent2_path_datasourcename_not_null; Type: INDEX; Schema: bidb_ext_demo; Owner: -
--

CREATE INDEX idx_pdso_ent2_path_datasourcename_not_null ON bidb_ext_demo.pdso_entities USING btree ("Path", datasourcename) WHERE ("Path" IS NOT NULL);


--
-- TOC entry 5129 (class 1259 OID 175874)
-- Name: idx_pdso_ent2_pathtype; Type: INDEX; Schema: bidb_ext_demo; Owner: -
--

CREATE INDEX idx_pdso_ent2_pathtype ON bidb_ext_demo.pdso_entities USING btree (pathtype);


--
-- TOC entry 5130 (class 1259 OID 175875)
-- Name: idx_pdso_ent2_pathtype_not_null; Type: INDEX; Schema: bidb_ext_demo; Owner: -
--

CREATE INDEX idx_pdso_ent2_pathtype_not_null ON bidb_ext_demo.pdso_entities USING btree (pathtype) WHERE (pathtype IS NOT NULL);


--
-- TOC entry 5131 (class 1259 OID 175876)
-- Name: idx_pdso_ent2_resourcetype; Type: INDEX; Schema: bidb_ext_demo; Owner: -
--

CREATE INDEX idx_pdso_ent2_resourcetype ON bidb_ext_demo.pdso_entities USING btree (resourcetype);


--
-- TOC entry 5132 (class 1259 OID 175877)
-- Name: idx_pdso_ent2_resourcetype_not_null; Type: INDEX; Schema: bidb_ext_demo; Owner: -
--

CREATE INDEX idx_pdso_ent2_resourcetype_not_null ON bidb_ext_demo.pdso_entities USING btree (resourcetype) WHERE (resourcetype IS NOT NULL);


--
-- TOC entry 5133 (class 1259 OID 175878)
-- Name: idx_pdso_ent2_termname; Type: INDEX; Schema: bidb_ext_demo; Owner: -
--

CREATE INDEX idx_pdso_ent2_termname ON bidb_ext_demo.pdso_entities USING btree (termname);


--
-- TOC entry 5134 (class 1259 OID 175879)
-- Name: idx_pdso_ent2_termname_not_null; Type: INDEX; Schema: bidb_ext_demo; Owner: -
--

CREATE INDEX idx_pdso_ent2_termname_not_null ON bidb_ext_demo.pdso_entities USING btree (termname) WHERE (termname IS NOT NULL);


--
-- TOC entry 5135 (class 1259 OID 176656)
-- Name: ix_fact_entity_term_term; Type: INDEX; Schema: bidb_ext_demo; Owner: -
--

CREATE INDEX ix_fact_entity_term_term ON bidb_ext_demo.fact_entity_term USING btree (term_key);


--
-- TOC entry 5137 (class 1259 OID 176703)
-- Name: ux_fact_entity_snapshot; Type: INDEX; Schema: bidb_ext_demo; Owner: -
--

CREATE UNIQUE INDEX ux_fact_entity_snapshot ON bidb_ext_demo.fact_entity_snapshot USING btree (entity_key, scanned_date_key);


--
-- TOC entry 5136 (class 1259 OID 176655)
-- Name: ux_fact_entity_term; Type: INDEX; Schema: bidb_ext_demo; Owner: -
--

CREATE UNIQUE INDEX ux_fact_entity_term ON bidb_ext_demo.fact_entity_term USING btree (entity_key, term_key);


-- Completed on 2026-01-30 11:05:47 CST

--
-- PostgreSQL database dump complete
--

\unrestrict 6wWWd6wSfhFqDgxWzUXXrjSlY29pKZDAQrQjWvKb9Q9jeJfwMkZZiQ1HfNwsRF1

