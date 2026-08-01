{{
    config(
        schema='bift',
        materialized='table',
        alias='gold_npl_outlet_summary',
        pre_hook="SET LOCAL work_mem = '512MB';",
        indexes=[
          {'columns': ['tahun', 'periode'], 'type': 'btree'},
          {'columns': ['distributor_id'], 'type': 'btree'},
          {'columns': ['cust_id'], 'type': 'btree'},
          {'columns': ['pcode'], 'type': 'btree'},
          {'columns': ['subbrand_id'], 'type': 'btree'},
          {'columns': ['salesforce_id'], 'type': 'btree'},
          {'columns': ['channel_id'], 'type': 'btree'}
        ]
    )
}}

-- Unified single Gold table at Outlet + Product grain per period

SELECT
    tahun,
    periode,

    -- Sales Hierarchy
    sd_id,
    sd_nm,
    nsm_id,
    nsm_nm,
    grsm_id,
    grsm_nm,
    rsm_id,
    rsm_nm,
    ss_id,
    ss_nm,

    -- Distributor
    distributor_id,
    distributor_nm,

    -- Salesforce
    salesforce_id,
    salesforce_nm,
    gsalesforce_id,
    gsalesforce_nm,

    -- Channel
    group_channel_id,
    group_channel_nm,
    channel_id,
    channel_nm,

    -- Customer / Outlet
    cust_id,
    cust_nm,

    -- Product
    pcode,
    pcode_nm,
    subbrand_id,
    subbrand_nm,

    -- Pre-aggregated metrics at Outlet + Product grain per period
    COUNT(DISTINCT inv_no)                                          AS order_count,
    SUM(COALESCE(qty_carton, 0))                                    AS qty_carton,

    -- Pre-pivoted weekly omset
    SUM(CASE WHEN week = 1 THEN COALESCE(inv_val, 0) ELSE 0 END)    AS omset_w1,
    SUM(CASE WHEN week = 2 THEN COALESCE(inv_val, 0) ELSE 0 END)    AS omset_w2,
    SUM(CASE WHEN week = 3 THEN COALESCE(inv_val, 0) ELSE 0 END)    AS omset_w3,
    SUM(CASE WHEN week = 4 THEN COALESCE(inv_val, 0) ELSE 0 END)    AS omset_w4,
    SUM(CASE WHEN week = 5 THEN COALESCE(inv_val, 0) ELSE 0 END)    AS omset_w5,
    SUM(COALESCE(inv_val, 0))                                       AS total_omset

FROM {{ ref('silver_npl_by_hierarchy') }}
GROUP BY
    tahun,
    periode,
    sd_id,
    sd_nm,
    nsm_id,
    nsm_nm,
    grsm_id,
    grsm_nm,
    rsm_id,
    rsm_nm,
    ss_id,
    ss_nm,
    distributor_id,
    distributor_nm,
    salesforce_id,
    salesforce_nm,
    gsalesforce_id,
    gsalesforce_nm,
    group_channel_id,
    group_channel_nm,
    channel_id,
    channel_nm,
    cust_id,
    cust_nm,
    pcode,
    pcode_nm,
    subbrand_id,
    subbrand_nm
