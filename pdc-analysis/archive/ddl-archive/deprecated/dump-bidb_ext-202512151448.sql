--
-- PostgreSQL database dump
--

-- Dumped from database version 13.20
-- Dumped by pg_dump version 16.6 (Homebrew)

-- Started on 2025-12-15 14:48:03 CST

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
-- TOC entry 443 (class 1259 OID 154821)
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
-- TOC entry 444 (class 1259 OID 154913)
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
-- TOC entry 446 (class 1259 OID 155018)
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
-- TOC entry 445 (class 1259 OID 155003)
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
-- TOC entry 441 (class 1259 OID 144470)
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
-- TOC entry 442 (class 1259 OID 154808)
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
-- TOC entry 448 (class 1259 OID 161289)
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
-- TOC entry 4563 (class 2606 OID 164310)
-- Name: pdso_entities pdso_entities2_pkey; Type: CONSTRAINT; Schema: bidb_ext; Owner: -
--

ALTER TABLE ONLY bidb_ext.pdso_entities
    ADD CONSTRAINT pdso_entities2_pkey PRIMARY KEY (_id);


--
-- TOC entry 4539 (class 1259 OID 155487)
-- Name: idx_agg_fileext_dst_pathtype; Type: INDEX; Schema: bidb_ext; Owner: -
--

CREATE INDEX idx_agg_fileext_dst_pathtype ON bidb_ext.agg_tp_rt_dsn_dst_pt_fe_ft_tn_mam_may USING btree (fileextension, datasourcetype, pathtype);


--
-- TOC entry 4540 (class 1259 OID 155257)
-- Name: idx_agg_modified_age_yrs; Type: INDEX; Schema: bidb_ext; Owner: -
--

CREATE INDEX idx_agg_modified_age_yrs ON bidb_ext.agg_tp_rt_dsn_dst_pt_fe_ft_tn_mam_may USING btree (modified_age_years);


--
-- TOC entry 4541 (class 1259 OID 155256)
-- Name: idx_agg_modified_age_yrs_mos; Type: INDEX; Schema: bidb_ext; Owner: -
--

CREATE INDEX idx_agg_modified_age_yrs_mos ON bidb_ext.agg_tp_rt_dsn_dst_pt_fe_ft_tn_mam_may USING btree (modified_age_years, modified_age_months);


--
-- TOC entry 4545 (class 1259 OID 169169)
-- Name: idx_agg_parentpath_pathtype_not_null; Type: INDEX; Schema: bidb_ext; Owner: -
--

CREATE INDEX idx_agg_parentpath_pathtype_not_null ON bidb_ext.agg_tp_rt_dsn_dst_pp_pt_fe_ft_tn_mam_may USING btree (parentpath, pathtype) WHERE (parentpath IS NOT NULL);


--
-- TOC entry 4542 (class 1259 OID 155260)
-- Name: idx_agg_resourcetype; Type: INDEX; Schema: bidb_ext; Owner: -
--

CREATE INDEX idx_agg_resourcetype ON bidb_ext.agg_tp_rt_dsn_dst_pt_fe_ft_tn_mam_may USING btree (resourcetype);


--
-- TOC entry 4543 (class 1259 OID 155259)
-- Name: idx_agg_resourcetype_size; Type: INDEX; Schema: bidb_ext; Owner: -
--

CREATE INDEX idx_agg_resourcetype_size ON bidb_ext.agg_tp_rt_dsn_dst_pt_fe_ft_tn_mam_may USING btree (resourcetype, size);


--
-- TOC entry 4544 (class 1259 OID 155272)
-- Name: idx_agg_rt_dsn_dst; Type: INDEX; Schema: bidb_ext; Owner: -
--

CREATE INDEX idx_agg_rt_dsn_dst ON bidb_ext.agg_tp_rt_dsn_dst_pt_fe_ft_tn_mam_may USING btree (resourcetype, datasourcename, datasourcetype);


--
-- TOC entry 4546 (class 1259 OID 164409)
-- Name: idx_pdso_ent2_datasourcename; Type: INDEX; Schema: bidb_ext; Owner: -
--

CREATE INDEX idx_pdso_ent2_datasourcename ON bidb_ext.pdso_entities USING btree (datasourcename);


--
-- TOC entry 4547 (class 1259 OID 164435)
-- Name: idx_pdso_ent2_datasourcetype; Type: INDEX; Schema: bidb_ext; Owner: -
--

CREATE INDEX idx_pdso_ent2_datasourcetype ON bidb_ext.pdso_entities USING btree (datasourcetype);


--
-- TOC entry 4548 (class 1259 OID 164463)
-- Name: idx_pdso_ent2_datasourcetype_not_null; Type: INDEX; Schema: bidb_ext; Owner: -
--

CREATE INDEX idx_pdso_ent2_datasourcetype_not_null ON bidb_ext.pdso_entities USING btree (datasourcetype) WHERE (datasourcetype IS NOT NULL);


--
-- TOC entry 4549 (class 1259 OID 164349)
-- Name: idx_pdso_ent2_ff_ds_year_term; Type: INDEX; Schema: bidb_ext; Owner: -
--

CREATE INDEX idx_pdso_ent2_ff_ds_year_term ON bidb_ext.pdso_entities USING btree (datasourcename, modifiedat_year, termname) WHERE ("Type" = ANY (ARRAY['FILE'::text, 'FOLDER'::text]));


--
-- TOC entry 4550 (class 1259 OID 164488)
-- Name: idx_pdso_ent2_fileextension; Type: INDEX; Schema: bidb_ext; Owner: -
--

CREATE INDEX idx_pdso_ent2_fileextension ON bidb_ext.pdso_entities USING btree (fileextension);


--
-- TOC entry 4551 (class 1259 OID 164513)
-- Name: idx_pdso_ent2_fileextension_not_null; Type: INDEX; Schema: bidb_ext; Owner: -
--

CREATE INDEX idx_pdso_ent2_fileextension_not_null ON bidb_ext.pdso_entities USING btree (fileextension) WHERE (fileextension IS NOT NULL);


--
-- TOC entry 4552 (class 1259 OID 168382)
-- Name: idx_pdso_ent2_modified_age_months; Type: INDEX; Schema: bidb_ext; Owner: -
--

CREATE INDEX idx_pdso_ent2_modified_age_months ON bidb_ext.pdso_entities USING btree (modified_age_months);


--
-- TOC entry 4553 (class 1259 OID 168524)
-- Name: idx_pdso_ent2_modified_age_years; Type: INDEX; Schema: bidb_ext; Owner: -
--

CREATE INDEX idx_pdso_ent2_modified_age_years ON bidb_ext.pdso_entities USING btree (modified_age_years);


--
-- TOC entry 4554 (class 1259 OID 168737)
-- Name: idx_pdso_ent2_parentpath; Type: INDEX; Schema: bidb_ext; Owner: -
--

CREATE INDEX idx_pdso_ent2_parentpath ON bidb_ext.pdso_entities USING btree (parentpath);


--
-- TOC entry 4555 (class 1259 OID 168801)
-- Name: idx_pdso_ent2_parentpath_not_null; Type: INDEX; Schema: bidb_ext; Owner: -
--

CREATE INDEX idx_pdso_ent2_parentpath_not_null ON bidb_ext.pdso_entities USING btree (parentpath) WHERE (parentpath IS NOT NULL);


--
-- TOC entry 4556 (class 1259 OID 168858)
-- Name: idx_pdso_ent2_path_datasourcename; Type: INDEX; Schema: bidb_ext; Owner: -
--

CREATE INDEX idx_pdso_ent2_path_datasourcename ON bidb_ext.pdso_entities USING btree ("Path", datasourcename);


--
-- TOC entry 4557 (class 1259 OID 168941)
-- Name: idx_pdso_ent2_path_datasourcename_not_null; Type: INDEX; Schema: bidb_ext; Owner: -
--

CREATE INDEX idx_pdso_ent2_path_datasourcename_not_null ON bidb_ext.pdso_entities USING btree ("Path", datasourcename) WHERE ("Path" IS NOT NULL);


--
-- TOC entry 4558 (class 1259 OID 164540)
-- Name: idx_pdso_ent2_pathtype; Type: INDEX; Schema: bidb_ext; Owner: -
--

CREATE INDEX idx_pdso_ent2_pathtype ON bidb_ext.pdso_entities USING btree (pathtype);


--
-- TOC entry 4559 (class 1259 OID 164561)
-- Name: idx_pdso_ent2_pathtype_not_null; Type: INDEX; Schema: bidb_ext; Owner: -
--

CREATE INDEX idx_pdso_ent2_pathtype_not_null ON bidb_ext.pdso_entities USING btree (pathtype) WHERE (pathtype IS NOT NULL);


--
-- TOC entry 4560 (class 1259 OID 164585)
-- Name: idx_pdso_ent2_resourcetype; Type: INDEX; Schema: bidb_ext; Owner: -
--

CREATE INDEX idx_pdso_ent2_resourcetype ON bidb_ext.pdso_entities USING btree (resourcetype);


--
-- TOC entry 4561 (class 1259 OID 164378)
-- Name: idx_pdso_ent2_termname; Type: INDEX; Schema: bidb_ext; Owner: -
--

CREATE INDEX idx_pdso_ent2_termname ON bidb_ext.pdso_entities USING btree (termname);


-- Completed on 2025-12-15 14:48:10 CST

--
-- PostgreSQL database dump complete
--

