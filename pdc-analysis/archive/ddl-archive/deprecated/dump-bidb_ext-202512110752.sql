--
-- PostgreSQL database dump
--

-- Dumped from database version 13.20
-- Dumped by pg_dump version 16.6 (Homebrew)

-- Started on 2025-12-11 13:52:03 GMT

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
-- TOC entry 29 (class 2615 OID 144469)
-- Name: bidb_ext; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA bidb_ext;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 445 (class 1259 OID 154821)
-- Name: agg_nm_tp_pr_rt_dsn_dst_tn_mam_may; Type: TABLE; Schema: bidb_ext; Owner: -
--

CREATE TABLE bidb_ext.agg_nm_tp_pr_rt_dsn_dst_tn_mam_may (
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
    fact_count bigint
);


--
-- TOC entry 446 (class 1259 OID 154913)
-- Name: agg_nm_tp_rt_dsn_dst_pt_fe_ft_tn_mam_may; Type: TABLE; Schema: bidb_ext; Owner: -
--

CREATE TABLE bidb_ext.agg_nm_tp_rt_dsn_dst_pt_fe_ft_tn_mam_may (
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
    fact_count bigint
);


--
-- TOC entry 448 (class 1259 OID 155018)
-- Name: agg_tp_rt_dsn_dst_pp_pt_fe_ft_tn_mam_may; Type: TABLE; Schema: bidb_ext; Owner: -
--

CREATE TABLE bidb_ext.agg_tp_rt_dsn_dst_pp_pt_fe_ft_tn_mam_may (
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
    fact_count bigint
);


--
-- TOC entry 447 (class 1259 OID 155003)
-- Name: agg_tp_rt_dsn_dst_pt_fe_ft_tn_mam_may; Type: TABLE; Schema: bidb_ext; Owner: -
--

CREATE TABLE bidb_ext.agg_tp_rt_dsn_dst_pt_fe_ft_tn_mam_may (
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
    fact_count bigint
);


--
-- TOC entry 442 (class 1259 OID 144470)
-- Name: entities_master_view; Type: TABLE; Schema: bidb_ext; Owner: -
--

CREATE TABLE bidb_ext.entities_master_view (
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
-- TOC entry 444 (class 1259 OID 154808)
-- Name: mv_master_table; Type: TABLE; Schema: bidb_ext; Owner: -
--

CREATE TABLE bidb_ext.mv_master_table (
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
-- TOC entry 443 (class 1259 OID 144539)
-- Name: pdso_entities; Type: TABLE; Schema: bidb_ext; Owner: -
--

CREATE TABLE bidb_ext.pdso_entities (
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
    childdirs text,
    childfiles text,
    childdirsize text,
    childfilesize text,
    totalchilddirs text,
    totalchildfiles text,
    totalchilddirsize text,
    totalchildfilesize text,
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
-- TOC entry 4543 (class 2606 OID 154820)
-- Name: pdso_entities pdso_entities_pkey; Type: CONSTRAINT; Schema: bidb_ext; Owner: -
--

ALTER TABLE ONLY bidb_ext.pdso_entities
    ADD CONSTRAINT pdso_entities_pkey PRIMARY KEY (_id);


--
-- TOC entry 4540 (class 1259 OID 154817)
-- Name: idx_pdso_ent_ff_ds_year_term; Type: INDEX; Schema: bidb_ext; Owner: -
--

CREATE INDEX idx_pdso_ent_ff_ds_year_term ON bidb_ext.pdso_entities USING btree (datasourcename, modifiedat_year, termname) WHERE ("Type" = ANY (ARRAY['FILE'::text, 'FOLDER'::text]));


--
-- TOC entry 4541 (class 1259 OID 154818)
-- Name: idx_pdso_ent_termname; Type: INDEX; Schema: bidb_ext; Owner: -
--

CREATE INDEX idx_pdso_ent_termname ON bidb_ext.pdso_entities USING btree (termname);


-- Completed on 2025-12-11 13:52:16 GMT

--
-- PostgreSQL database dump complete
--

