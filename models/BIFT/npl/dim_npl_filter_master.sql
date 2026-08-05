{{
    config(
        schema='bift',
        materialized='table',
        alias='dim_npl_filter_master',
        pre_hook="SET LOCAL work_mem = '128MB';",
        indexes=[
          {'columns': ['source_schema'], 'type': 'btree'},
          {'columns': ['gdiv_id'], 'type': 'btree'},
          {'columns': ['gdiv_nm'], 'type': 'btree'},
          {'columns': ['sd_id'], 'type': 'btree'},
          {'columns': ['distributor_id'], 'type': 'btree'},
          {'columns': ['sls_id'], 'type': 'btree'},
          {'columns': ['salesforce_id'], 'type': 'btree'},
          {'columns': ['pcode'], 'type': 'btree'},
          {'columns': ['subbrand_id'], 'type': 'btree'}
        ]
    )
}}

-- Master Filter Table for NPL Dashboard
-- Unifies Sales Hierarchy (SD -> NSM -> GRSM -> RSM -> SS -> Distributor -> Salesman),
-- Salesforce Mapping (Group SF1 -> Group SF2 -> Salesforce),
-- and Product Hierarchy (pcode, subbrand, category) joined via gdiv_nm.

WITH sales_hierarchy AS (

    SELECT
        h.source_schema,
        h.gdiv_id,
        h.gdiv_nm,
        h.sd_id,
        h.sd_nm,
        h.nsm_id,
        h.nsm_nm,
        h.grsm_id,
        h.grsm_nm,
        h.rsm_id,
        h.rsm_nm,
        h.ss_id,
        h.ss_nm,
        h.distributor_id,
        h.distributor_nm,
        h.sls_id,
        h.sls_nm,
        sf.salesforce_id,
        sf.salesforce_nm,
        sf.gsalesforce1_id,
        sf.gsalesforce1_nm,
        sf.gsalesforce2_id,
        sf.gsalesforce2_nm
    FROM bift.dim_salesman_hierarchy h
    LEFT JOIN bift.dim_mapping_group_salesforce sf
           ON h.source_schema = sf.source_schema
          AND h.salesforce_id = sf.salesforce_id

),

product_hierarchy AS (

    SELECT DISTINCT
        pcode,
        pcode_nm,
        subbrand_id,
        subbrand_nm,
        gdiv_id,
        gdiv_nm,
        cat_id,
        cat_nm,
        sbu_id,
        sbu_nm
    FROM bift.dim_product
    WHERE pcode IS NOT NULL

)

SELECT DISTINCT
    sh.source_schema,
    sh.gdiv_id,
    sh.gdiv_nm,
    sh.sd_id,
    sh.sd_nm,
    sh.nsm_id,
    sh.nsm_nm,
    sh.grsm_id,
    sh.grsm_nm,
    sh.rsm_id,
    sh.rsm_nm,
    sh.ss_id,
    sh.ss_nm,
    sh.distributor_id,
    sh.distributor_nm,
    sh.sls_id,
    sh.sls_nm,

    -- Salesforce Hierarchy
    sh.gsalesforce1_id,
    sh.gsalesforce1_nm,
    sh.gsalesforce2_id,
    sh.gsalesforce2_nm,
    sh.salesforce_id,
    sh.salesforce_nm,

    -- Product Hierarchy
    p.pcode,
    p.pcode_nm,
    p.subbrand_id,
    p.subbrand_nm,
    p.cat_id,
    p.cat_nm,
    p.sbu_id,
    p.sbu_nm

FROM sales_hierarchy sh
LEFT JOIN product_hierarchy p
       ON sh.gdiv_nm = p.gdiv_nm
