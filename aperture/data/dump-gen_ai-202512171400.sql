--
-- PostgreSQL database dump
--

-- Dumped from database version 13.20
-- Dumped by pg_dump version 16.6 (Homebrew)

-- Started on 2025-12-17 14:00:18 CST

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

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 383 (class 1259 OID 22556)
-- Name: account_owner; Type: TABLE; Schema: gen_ai; Owner: -
--

CREATE TABLE gen_ai.account_owner (
    account_owner_name character varying,
    account_owner_region_list character varying,
    account_owner_subregion_list character varying,
    account_owner_industry_list character varying,
    account_owner_id integer NOT NULL,
    active boolean DEFAULT true,
    geo_region text,
    geo_subregion text
);


--
-- TOC entry 384 (class 1259 OID 22562)
-- Name: account_owner_account_owner_id_seq; Type: SEQUENCE; Schema: gen_ai; Owner: -
--

ALTER TABLE gen_ai.account_owner ALTER COLUMN account_owner_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME gen_ai.account_owner_account_owner_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 403 (class 1259 OID 23420)
-- Name: adj_lead_generation; Type: TABLE; Schema: gen_ai; Owner: -
--

CREATE TABLE gen_ai.adj_lead_generation (
    prompt_id_array text,
    lead_generation_id_array text,
    is_human text,
    is_human_confidence_score text,
    is_human_in_role text,
    is_human_in_role_confidence_score text,
    verifiable_url_source text,
    process_time timestamp without time zone,
    execution_time timestamp without time zone,
    rationale text,
    org_name text,
    org_site_location text,
    contact_name text,
    contact_role text,
    contact_email_address text,
    contact_phone text,
    prompt_id integer,
    run_id integer,
    request text,
    response text,
    url text,
    fuzzy_match_org_site_contact_key text,
    canonical_lead_generation_id integer,
    run_count bigint
);


--
-- TOC entry 448 (class 1259 OID 175292)
-- Name: adj_lead_score; Type: TABLE; Schema: gen_ai; Owner: -
--

CREATE TABLE gen_ai.adj_lead_score (
    fuzzy_match_org_site_contact_key text,
    is_human_cnt bigint,
    is_human_in_role_cnt bigint,
    num_of_adjudications bigint,
    max_is_human_confidence_score text,
    max_is_human_in_role_confidence_score text,
    canonical_lead_generation_id_mode integer,
    canonical_lead_generation_id_mode_cnt bigint,
    canonical_lead_generation_id_first integer,
    l_human_cnt double precision,
    l_role_cnt double precision,
    l_adj_cnt double precision,
    min_l_human_cnt double precision,
    max_l_human_cnt double precision,
    min_l_role_cnt double precision,
    max_l_role_cnt double precision,
    min_l_adj_cnt double precision,
    max_l_adj_cnt double precision,
    target_score double precision
);


--
-- TOC entry 424 (class 1259 OID 31935)
-- Name: err_lead_adjudication; Type: TABLE; Schema: gen_ai; Owner: -
--

CREATE TABLE gen_ai.err_lead_adjudication (
    run_id integer,
    prompt_id integer,
    request text,
    lead_generation_id_array text,
    prompt_id_array text,
    response text,
    error_code text,
    error_message text,
    process_time timestamp with time zone DEFAULT now() NOT NULL
);


--
-- TOC entry 425 (class 1259 OID 31942)
-- Name: err_lead_adjudication_api; Type: TABLE; Schema: gen_ai; Owner: -
--

CREATE TABLE gen_ai.err_lead_adjudication_api (
    run_id integer,
    prompt_id integer,
    request text,
    lead_generation_id_array text,
    prompt_id_array text,
    err_code text,
    err_message text,
    err_field text
);


--
-- TOC entry 426 (class 1259 OID 34231)
-- Name: err_lead_adjudication_unparsed; Type: TABLE; Schema: gen_ai; Owner: -
--

CREATE TABLE gen_ai.err_lead_adjudication_unparsed (
    run_id integer,
    prompt_id integer,
    request text,
    lead_generation_id_array text,
    prompt_id_array text,
    response text,
    org_name text,
    org_site_location text,
    contact_name text,
    contact_role text,
    contact_email_address text,
    contact_phone text,
    process_time timestamp with time zone DEFAULT now() NOT NULL
);


--
-- TOC entry 381 (class 1259 OID 22280)
-- Name: log_exception; Type: TABLE; Schema: gen_ai; Owner: -
--

CREATE TABLE gen_ai.log_exception (
    customer_id integer,
    organization character varying(100),
    request text,
    response text
);


--
-- TOC entry 419 (class 1259 OID 24002)
-- Name: log_lead_gen_req_resp; Type: TABLE; Schema: gen_ai; Owner: -
--

CREATE TABLE gen_ai.log_lead_gen_req_resp (
    log_lead_gen_req_resp_id integer NOT NULL,
    request text,
    response text,
    url character varying(84),
    account_owner_name text,
    account_owner_region_list text,
    account_owner_subregion_list text,
    account_owner_industry_list text,
    account_owner_id integer,
    prompt_id integer,
    prompt_name text,
    run_id bigint,
    process_time timestamp with time zone DEFAULT now()
);


--
-- TOC entry 418 (class 1259 OID 24000)
-- Name: log_lead_gen_req_resp_log_lead_gen_req_resp_id_seq; Type: SEQUENCE; Schema: gen_ai; Owner: -
--

ALTER TABLE gen_ai.log_lead_gen_req_resp ALTER COLUMN log_lead_gen_req_resp_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME gen_ai.log_lead_gen_req_resp_log_lead_gen_req_resp_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 377 (class 1259 OID 22189)
-- Name: prompt_library; Type: TABLE; Schema: gen_ai; Owner: -
--

CREATE TABLE gen_ai.prompt_library (
    prompt_type character varying,
    prompt character varying,
    prompt_id integer NOT NULL,
    prompt_name character varying,
    active boolean DEFAULT true NOT NULL
);


--
-- TOC entry 378 (class 1259 OID 22195)
-- Name: prompt_library_prompt_id_seq; Type: SEQUENCE; Schema: gen_ai; Owner: -
--

ALTER TABLE gen_ai.prompt_library ALTER COLUMN prompt_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME gen_ai.prompt_library_prompt_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 386 (class 1259 OID 22576)
-- Name: raw_lead_generation; Type: TABLE; Schema: gen_ai; Owner: -
--

CREATE TABLE gen_ai.raw_lead_generation (
    lead_generation_id integer NOT NULL,
    org_name text,
    org_site_location text,
    org_confidence_score text,
    contact_name text,
    contact_role text,
    contact_confidence_score text,
    contact_email_address text,
    contact_email_confidence_score text,
    contact_phone text,
    contact_phone_confidence_score text,
    contact_url_source text,
    justification_rationale text,
    account_owner_name text,
    account_owner_region_list text,
    account_owner_subregion_list text,
    account_owner_industry_list text,
    account_owner_id integer,
    prompt_name text,
    prompt_id integer,
    process_time timestamp without time zone,
    execution_time timestamp without time zone,
    url text,
    run_id integer DEFAULT 0,
    fuzzy_match_key text,
    fuzzy_match_contact_key text,
    fuzzy_match_org_site_contact_key text
);


--
-- TOC entry 385 (class 1259 OID 22574)
-- Name: raw_lead_generation_lead_generation_id_seq; Type: SEQUENCE; Schema: gen_ai; Owner: -
--

ALTER TABLE gen_ai.raw_lead_generation ALTER COLUMN lead_generation_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME gen_ai.raw_lead_generation_lead_generation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 422 (class 1259 OID 24272)
-- Name: run_log; Type: TABLE; Schema: gen_ai; Owner: -
--

CREATE TABLE gen_ai.run_log (
    run_id bigint NOT NULL,
    execution_time timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    run_name text NOT NULL
);


--
-- TOC entry 421 (class 1259 OID 24270)
-- Name: run_log_run_id_seq; Type: SEQUENCE; Schema: gen_ai; Owner: -
--

CREATE SEQUENCE gen_ai.run_log_run_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 4686 (class 0 OID 0)
-- Dependencies: 421
-- Name: run_log_run_id_seq; Type: SEQUENCE OWNED BY; Schema: gen_ai; Owner: -
--

ALTER SEQUENCE gen_ai.run_log_run_id_seq OWNED BY gen_ai.run_log.run_id;


--
-- TOC entry 449 (class 1259 OID 175319)
-- Name: vw_adj_lead_generation_main; Type: VIEW; Schema: gen_ai; Owner: -
--

CREATE VIEW gen_ai.vw_adj_lead_generation_main AS
 WITH rat AS (
         SELECT adj.canonical_lead_generation_id,
            max(adj.rationale) AS adjudication_rationale,
            max(adj.verifiable_url_source) AS verifiable_url_source
           FROM gen_ai.adj_lead_generation adj
          GROUP BY adj.canonical_lead_generation_id
        )
 SELECT als.canonical_lead_generation_id_mode,
    als.target_score,
    rlg.lead_generation_id,
    rlg.org_name,
    rlg.org_site_location,
    rlg.contact_name,
    rlg.contact_role,
    rlg.contact_email_address,
    rlg.contact_phone,
    rlg.justification_rationale,
    rat.adjudication_rationale,
    rat.verifiable_url_source,
    rlg.org_confidence_score,
    rlg.contact_confidence_score,
    rlg.contact_email_confidence_score,
    rlg.contact_phone_confidence_score,
    rlg.contact_url_source,
    ao.geo_region,
    ao.geo_subregion,
    rlg.account_owner_name,
    rlg.account_owner_industry_list,
    rlg.account_owner_id,
    rlg.prompt_name,
    rlg.prompt_id,
    rlg.process_time,
    rlg.execution_time,
    rlg.url,
    rlg.run_id,
    rlg.fuzzy_match_key,
    rlg.fuzzy_match_contact_key,
    rlg.fuzzy_match_org_site_contact_key
   FROM (((gen_ai.adj_lead_score als
     JOIN gen_ai.raw_lead_generation rlg ON ((als.canonical_lead_generation_id_mode = rlg.lead_generation_id)))
     LEFT JOIN rat ON ((rlg.lead_generation_id = rat.canonical_lead_generation_id)))
     LEFT JOIN gen_ai.account_owner ao ON ((rlg.account_owner_id = ao.account_owner_id)))
  ORDER BY als.target_score DESC;


--
-- TOC entry 4539 (class 2604 OID 24275)
-- Name: run_log run_id; Type: DEFAULT; Schema: gen_ai; Owner: -
--

ALTER TABLE ONLY gen_ai.run_log ALTER COLUMN run_id SET DEFAULT nextval('gen_ai.run_log_run_id_seq'::regclass);


--
-- TOC entry 4544 (class 2606 OID 22571)
-- Name: account_owner account_owner_pk; Type: CONSTRAINT; Schema: gen_ai; Owner: -
--

ALTER TABLE ONLY gen_ai.account_owner
    ADD CONSTRAINT account_owner_pk PRIMARY KEY (account_owner_id);


--
-- TOC entry 4546 (class 2606 OID 24281)
-- Name: run_log run_log_pkey; Type: CONSTRAINT; Schema: gen_ai; Owner: -
--

ALTER TABLE ONLY gen_ai.run_log
    ADD CONSTRAINT run_log_pkey PRIMARY KEY (run_id);


--
-- TOC entry 4547 (class 2620 OID 90699)
-- Name: raw_lead_generation trg_raw_lead_generation_fuzzy_contact_key; Type: TRIGGER; Schema: gen_ai; Owner: -
--

CREATE TRIGGER trg_raw_lead_generation_fuzzy_contact_key BEFORE INSERT OR UPDATE OF org_name, org_site_location, contact_name, contact_role ON gen_ai.raw_lead_generation FOR EACH ROW EXECUTE FUNCTION gen_ai.set_fuzzy_match_contact_key();


--
-- TOC entry 4548 (class 2620 OID 90531)
-- Name: raw_lead_generation trg_raw_lead_generation_fuzzy_key; Type: TRIGGER; Schema: gen_ai; Owner: -
--

CREATE TRIGGER trg_raw_lead_generation_fuzzy_key BEFORE INSERT OR UPDATE OF org_name, org_site_location, contact_name, contact_role, contact_email_address, contact_phone ON gen_ai.raw_lead_generation FOR EACH ROW EXECUTE FUNCTION gen_ai.set_fuzzy_match_key();


--
-- TOC entry 4549 (class 2620 OID 92094)
-- Name: raw_lead_generation trg_raw_lead_generation_fuzzy_org_site_contact_key; Type: TRIGGER; Schema: gen_ai; Owner: -
--

CREATE TRIGGER trg_raw_lead_generation_fuzzy_org_site_contact_key BEFORE INSERT OR UPDATE OF org_name, org_site_location, contact_name ON gen_ai.raw_lead_generation FOR EACH ROW EXECUTE FUNCTION gen_ai.set_fuzzy_match_org_site_contact_key();


-- Completed on 2025-12-17 14:01:11 CST

--
-- PostgreSQL database dump complete
--

